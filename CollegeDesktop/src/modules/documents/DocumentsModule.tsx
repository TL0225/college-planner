import { useCallback, useEffect, useMemo, useState, type CSSProperties, type DragEvent } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { openPath, revealItemInDir } from "@tauri-apps/plugin-opener";
import { ChevronRight, Folder, Star } from "lucide-react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  ModalSheet,
  SegmentedPills,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDelete, confirmFolderCascadeDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { onAssistantOpenDocument } from "@/lib/events";
import { useLiveQuery } from "@/lib/useLiveQuery";

type Doc = {
  id: string;
  title: string;
  category: string;
  mimeType: string;
  fileSize: number;
  updatedAt: string;
  relativePath: string;
  hasFile: boolean;
  isStarred: boolean;
  parentFolderId: string | null;
  isFolder: boolean;
};

const CATEGORIES = ["general", "syllabus", "transcript", "resume", "receipt"] as const;

const RECENT_MS = 14 * 24 * 60 * 60 * 1000;
const VAULT_DRAG_MIME = "application/x-college-vault-item";
const VAULT_ROOT_DROP = "__vault_root__";

type LayoutMode = "list" | "grid";

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function mimeLabel(mime: string, hasFile: boolean, isFolder: boolean): string {
  if (isFolder) return "Folder";
  if (!hasFile) return "Note";
  const m = mime.toLowerCase();
  if (m.includes("pdf")) return "PDF";
  if (m.includes("image")) return "Image";
  if (m.includes("word") || m.includes("msword") || m.includes("officedocument.word")) return "Doc";
  if (m.includes("sheet") || m.includes("excel")) return "Sheet";
  if (m.includes("text")) return "Text";
  if (m) return mime.split("/").pop()?.toUpperCase() || "File";
  return "File";
}

function categoryTint(category: string): string {
  switch (category) {
    case "syllabus":
      return "var(--color-primary)";
    case "transcript":
      return "var(--color-success)";
    case "resume":
      return "var(--color-warning)";
    case "receipt":
      return "#0ea5e9";
    default:
      return "var(--color-text-light)";
  }
}

function pageCategory(page: string): string | null {
  if (page.startsWith("cat-")) return page.slice(4);
  return null;
}

function pageCourseId(page: string): string | null {
  if (page.startsWith("course-")) return page.slice(7);
  return null;
}

function pageFolderId(page: string): string | null {
  if (page.startsWith("folder-")) return page.slice(7);
  return null;
}

function pageTitle(page: string, docs: Doc[]): string {
  switch (page) {
    case "all":
      return "All files";
    case "recent":
      return "Recent";
    case "starred":
      return "Starred";
    case "needs-review":
      return "Needs review";
    default: {
      const cat = pageCategory(page);
      if (cat) return cat[0]!.toUpperCase() + cat.slice(1);
      if (pageCourseId(page)) return "Course folder";
      const folderId = pageFolderId(page);
      if (folderId) {
        const folder = docs.find((d) => d.id === folderId && d.isFolder);
        return folder?.title || "Folder";
      }
      return "Documents";
    }
  }
}

function filterByPage(docs: Doc[], page: string, courseCode?: string | null): Doc[] {
  switch (page) {
    case "all":
      return docs;
    case "recent": {
      const cutoff = Date.now() - RECENT_MS;
      return docs
        .filter((d) => !d.isFolder && new Date(d.updatedAt).getTime() >= cutoff)
        .sort(
          (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
        );
    }
    case "starred":
      return docs.filter((d) => d.isStarred);
    case "needs-review":
      return docs.filter((d) => !d.isFolder && (!d.hasFile || d.category === "needs_review"));
    default: {
      const folderId = pageFolderId(page);
      if (folderId) {
        return docs.filter((d) => (d.parentFolderId ?? null) === folderId);
      }
      const courseId = pageCourseId(page);
      if (courseId && courseCode) {
        const needle = courseCode.toLowerCase();
        return docs.filter(
          (d) =>
            !d.isFolder &&
            (d.title.toLowerCase().includes(needle) ||
              d.relativePath.toLowerCase().includes(needle) ||
              (d.category === "syllabus" && d.title.toLowerCase().includes(needle.split(" ")[0] ?? needle))),
        );
      }
      const cat = pageCategory(page);
      if (cat) return docs.filter((d) => !d.isFolder && d.category === cat);
      return docs;
    }
  }
}

function folderContents(docs: Doc[], folderId: string | null): Doc[] {
  return docs
    .filter((d) => (d.parentFolderId ?? null) === folderId)
    .sort((a, b) => {
      if (a.isFolder !== b.isFolder) return a.isFolder ? -1 : 1;
      return a.title.localeCompare(b.title, undefined, { sensitivity: "base" });
    });
}

function buildBreadcrumb(docs: Doc[], folderId: string | null): Array<{ id: string | null; title: string }> {
  const trail: Array<{ id: string | null; title: string }> = [{ id: null, title: "Vault" }];
  if (!folderId) return trail;
  const byId = new Map(docs.map((d) => [d.id, d]));
  const chain: Doc[] = [];
  let current: string | null = folderId;
  while (current) {
    const doc = byId.get(current);
    if (!doc?.isFolder) break;
    chain.unshift(doc);
    current = doc.parentFolderId;
  }
  for (const folder of chain) {
    trail.push({ id: folder.id, title: folder.title });
  }
  return trail;
}

function collectDescendantIds(docs: Doc[], rootId: string): Set<string> {
  const blocked = new Set<string>([rootId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const doc of docs) {
      if (doc.parentFolderId && blocked.has(doc.parentFolderId) && !blocked.has(doc.id)) {
        blocked.add(doc.id);
        changed = true;
      }
    }
  }
  return blocked;
}

function emptyStateForPage(page: string, inFolder: boolean): { title: string; body: string } {
  if (inFolder) {
    return {
      title: "Folder is empty",
      body: "Import files or create subfolders to organize this folder.",
    };
  }
  switch (page) {
    case "recent":
      return {
        title: "Nothing recent",
        body: "Files updated in the last 14 days appear here.",
      };
    case "starred":
      return {
        title: "No starred files",
        body: "Star documents from the inspector to collect them here.",
      };
    case "needs-review":
      return {
        title: "Nothing needs review",
        body: "Metadata-only notes and items marked for review show up here.",
      };
    default: {
      const cat = pageCategory(page);
      if (cat) {
        return {
          title: `No ${cat} files`,
          body: `Import or add notes in the ${cat} category to see them here.`,
        };
      }
      return {
        title: "No documents",
        body: "Import a PDF or file, create a folder, or load sample data from Settings.",
      };
    }
  }
}

function buildFolderTreeNodes(docs: Doc[], parentId: string | null): Doc[] {
  return docs
    .filter((d) => d.isFolder && (d.parentFolderId ?? null) === parentId)
    .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }));
}

function VaultFolderTree({
  docs,
  currentFolderId,
  onSelect,
}: {
  docs: Doc[];
  currentFolderId: string | null;
  onSelect: (folderId: string | null) => void;
}) {
  const renderNode = (folder: Doc, depth: number) => {
    const children = buildFolderTreeNodes(docs, folder.id);
    const selected = currentFolderId === folder.id;
    return (
      <div key={folder.id}>
        <button
          type="button"
          onClick={() => onSelect(folder.id)}
          className="flex w-full items-center gap-1 rounded px-1.5 py-1 text-left text-[12px] hover:bg-[var(--color-surface-elevated)]"
          style={{
            paddingLeft: 8 + depth * 14,
            color: selected ? "var(--color-primary)" : "var(--color-text-main)",
            fontWeight: selected ? 600 : 400,
          }}
        >
          <Folder size={13} strokeWidth={2} className="shrink-0 opacity-80" />
          <span className="truncate">{folder.title || "Folder"}</span>
        </button>
        {children.map((child) => renderNode(child, depth + 1))}
      </div>
    );
  };

  const roots = buildFolderTreeNodes(docs, null);
  if (roots.length === 0) return null;

  return (
    <div className="hidden w-[200px] shrink-0 flex-col border-r border-[var(--color-chrome-stroke)] pr-2 lg:flex">
      <div className="mb-1 px-1.5 text-[10px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
        Folders
      </div>
      <button
        type="button"
        onClick={() => onSelect(null)}
        className="rounded px-1.5 py-1 text-left text-[12px] hover:bg-[var(--color-surface-elevated)]"
        style={{
          color: currentFolderId === null ? "var(--color-primary)" : "var(--color-text-main)",
          fontWeight: currentFolderId === null ? 600 : 400,
        }}
      >
        Vault root
      </button>
      <div className="min-h-0 flex-1 overflow-auto">{roots.map((f) => renderNode(f, 0))}</div>
    </div>
  );
}

type PreviewState = {
  mimeType: string;
  base64Preview?: string | null;
  tempPath?: string | null;
  isEncrypted: boolean;
};

function DocumentPreviewPanel({ docId }: { docId: string }) {
  const [preview, setPreview] = useState<PreviewState | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setPreview(null);
    setError(null);
    void ipc
      .documentsQuickLookPreview(docId)
      .then((result) => {
        if (!cancelled) setPreview(result);
      })
      .catch((e) => {
        if (!cancelled) setError(formatIpcError(e));
      });
    return () => {
      cancelled = true;
    };
  }, [docId]);

  if (error) {
    return <p className="text-[12px] text-[var(--color-error)]">{error}</p>;
  }
  if (!preview) {
    return <p className="text-[12px] text-[var(--color-text-light)]">Loading preview…</p>;
  }
  if (preview.isEncrypted && !preview.tempPath && !preview.base64Preview) {
    return (
      <p className="text-[12px] text-[var(--color-warning)]">
        Encrypted file — unlock College in Settings → Privacy to preview.
      </p>
    );
  }

  const mime = preview.mimeType.toLowerCase();
  if (preview.base64Preview) {
    const decoded = atob(preview.base64Preview);
    return (
      <pre className="max-h-64 overflow-auto whitespace-pre-wrap rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-surface-elevated)] p-2 text-[11px] text-[var(--color-text-main)]">
        {decoded}
      </pre>
    );
  }
  if (preview.tempPath && mime.includes("pdf")) {
    return (
      <iframe
        title="Document preview"
        src={convertFileSrc(preview.tempPath)}
        className="h-64 w-full rounded-lg border border-[var(--color-chrome-stroke)]"
      />
    );
  }
  if (preview.tempPath && mime.includes("image")) {
    return (
      <img
        src={convertFileSrc(preview.tempPath)}
        alt="Document preview"
        className="max-h-64 w-full rounded-lg border border-[var(--color-chrome-stroke)] object-contain"
      />
    );
  }
  return (
    <p className="text-[12px] text-[var(--color-text-light)]">
      No in-pane preview for this file type. Use Quick Look or Open.
    </p>
  );
}

function importCategoryForPage(page: string): string {
  const cat = pageCategory(page);
  if (cat && CATEGORIES.includes(cat as (typeof CATEGORIES)[number])) return cat;
  return "general";
}

type DocumentsModuleProps = {
  page: string;
};

export function DocumentsModule({ page }: DocumentsModuleProps) {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [currentFolderId, setCurrentFolderId] = useState<string | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [editSheet, setEditSheet] = useState(false);
  const [folderSheet, setFolderSheet] = useState(false);
  const [moveSheet, setMoveSheet] = useState(false);
  const [busy, setBusy] = useState(false);
  const [layout, setLayout] = useState<LayoutMode>("list");
  const [form, setForm] = useState({ title: "", category: "general" });
  const [editForm, setEditForm] = useState({ title: "", category: "general" });
  const [folderName, setFolderName] = useState("");
  const [moveTargetId, setMoveTargetId] = useState<string>("");
  const [search, setSearch] = useState("");
  const [semanticHits, setSemanticHits] = useState<string[] | null>(null);
  const [dropTargetFolderId, setDropTargetFolderId] = useState<string | null>(null);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [courseById, setCourseById] = useState<Map<string, { code: string; title: string }>>(
    new Map(),
  );

  const load = useCallback(async () => {
    const [vault, courses] = await Promise.all([
      ipc.documentsListVault(),
      ipc.academicsListCourses().catch(() => []),
    ]);
    setDocs(vault);
    setCourseById(new Map(courses.map((c) => [c.id, { code: c.code, title: c.title }])));
  }, []);

  const { refresh, error } = useLiveQuery(load, ["vault"]);
  const selectedDoc = docs.find((d) => d.id === selected) ?? null;

  const activeCourseId = pageCourseId(page);
  const sidebarFolderId = pageFolderId(page);
  const activeCourse = activeCourseId ? courseById.get(activeCourseId) : null;

  const usesFolderBrowser =
    (page === "all" || sidebarFolderId != null) &&
    !search.trim() &&
    !semanticHits &&
    !activeCourseId;

  useEffect(() => {
    setCurrentFolderId(sidebarFolderId);
    setSelected(null);
  }, [page, sidebarFolderId]);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void onAssistantOpenDocument(({ documentId }) => {
      setSelected(documentId);
      showToast("Document selected from Assistant", "success");
    }).then((fn) => {
      unlisten = fn;
    });
    return () => {
      unlisten?.();
    };
  }, []);

  const pageFiltered = useMemo(
    () => filterByPage(docs, page, activeCourse?.code ?? null),
    [docs, page, activeCourse?.code],
  );

  const filtered = useMemo(() => {
    let list = pageFiltered;
    if (usesFolderBrowser) {
      list = folderContents(list, currentFolderId);
    }
    if (semanticHits) {
      const order = new Map(semanticHits.map((id, i) => [id, i]));
      list = list
        .filter((d) => order.has(d.id))
        .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0));
    } else if (search.trim()) {
      const q = search.trim().toLowerCase();
      list = list.filter(
        (d) =>
          d.title.toLowerCase().includes(q) ||
          d.category.toLowerCase().includes(q) ||
          d.mimeType.toLowerCase().includes(q),
      );
    }
    return list;
  }, [pageFiltered, search, semanticHits, usesFolderBrowser, currentFolderId]);

  const breadcrumb = useMemo(
    () => (usesFolderBrowser ? buildBreadcrumb(docs, currentFolderId) : []),
    [docs, currentFolderId, usesFolderBrowser],
  );

  const moveFolderOptions = useMemo(() => {
    if (!selectedDoc) return [];
    const blocked = collectDescendantIds(docs, selectedDoc.id);
    return docs
      .filter((d) => d.isFolder && !blocked.has(d.id))
      .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }));
  }, [docs, selectedDoc]);

  const emptyState = emptyStateForPage(page, usesFolderBrowser && currentFolderId !== null);
  const defaultCategory = importCategoryForPage(page);
  const importParentFolderId = usesFolderBrowser ? currentFolderId : null;

  const readVaultDragId = (e: DragEvent): string | null =>
    e.dataTransfer.getData(VAULT_DRAG_MIME) || null;

  const canMoveToFolder = useCallback(
    (itemId: string, targetFolderId: string | null): boolean => {
      const item = docs.find((d) => d.id === itemId);
      if (!item) return false;
      if (itemId === targetFolderId) return false;
      if (targetFolderId && collectDescendantIds(docs, itemId).has(targetFolderId)) return false;
      if ((item.parentFolderId ?? null) === targetFolderId) return false;
      return true;
    },
    [docs],
  );

  const moveVaultItem = useCallback(
    async (itemId: string, targetFolderId: string | null) => {
      if (!canMoveToFolder(itemId, targetFolderId)) return;
      try {
        await ipc.documentsMoveVaultItem(itemId, targetFolderId);
        showToast("Item moved", "success");
      } catch (e) {
        showToast(formatIpcError(e), "error");
      }
    },
    [canMoveToFolder],
  );

  const handleVaultDragStart = (e: DragEvent, id: string) => {
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData(VAULT_DRAG_MIME, id);
    setDraggingId(id);
  };

  const handleVaultDragEnd = () => {
    setDraggingId(null);
    setDropTargetFolderId(null);
  };

  const handleFolderDragOver = (e: DragEvent, folderId: string | null) => {
    if (!usesFolderBrowser) return;
    const dragId = readVaultDragId(e);
    if (!dragId || !canMoveToFolder(dragId, folderId)) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    setDropTargetFolderId(folderId ?? VAULT_ROOT_DROP);
  };

  const handleFolderDrop = (e: DragEvent, folderId: string | null) => {
    e.preventDefault();
    setDropTargetFolderId(null);
    const dragId = readVaultDragId(e);
    if (!dragId) return;
    void moveVaultItem(dragId, folderId);
    setDraggingId(null);
  };

  const folderDropStyle = (folderId: string | null): CSSProperties | undefined => {
    const key = folderId ?? VAULT_ROOT_DROP;
    if (dropTargetFolderId !== key) return undefined;
    return {
      outline: "2px solid color-mix(in srgb, var(--color-primary) 55%, transparent)",
      outlineOffset: -2,
      background: "color-mix(in srgb, var(--color-primary) 8%, var(--color-surface))",
    };
  };

  const quickLook = useCallback(async (id: string) => {
    try {
      const result = await ipc.documentsQuickLook(id);
      if (!result.opened && result.path) {
        await openPath(result.path);
      }
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  }, []);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.code !== "Space" || e.repeat) return;
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.tagName === "SELECT" ||
          target.isContentEditable)
      ) {
        return;
      }
      if (!selectedDoc || selectedDoc.isFolder || !selectedDoc.hasFile) return;
      e.preventDefault();
      void quickLook(selectedDoc.id);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [selectedDoc, quickLook]);

  const importFile = async () => {
    const picked = await open({
      multiple: false,
      directory: false,
      title: "Import into Vault",
    });
    if (!picked || typeof picked !== "string") return;
    setBusy(true);
    try {
      await ipc.documentsImportFile({
        sourcePath: picked,
        category: defaultCategory,
        parentFolderId: importParentFolderId,
      });
      showToast("File imported", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const openDoc = async (id: string) => {
    const path = await ipc.documentsResolvePath(id);
    if (!path) return;
    await openPath(path);
  };

  const revealDoc = async (id: string) => {
    const path = await ipc.documentsResolvePath(id);
    if (!path) return;
    await revealItemInDir(path);
  };

  const toggleStar = async (doc: Doc) => {
    try {
      await ipc.documentsUpdateVaultDoc({
        id: doc.id,
        isStarred: !doc.isStarred,
      });
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const enterFolder = (folderId: string) => {
    setCurrentFolderId(folderId);
    setSelected(null);
  };

  const goUp = () => {
    if (!currentFolderId) return;
    const current = docs.find((d) => d.id === currentFolderId);
    setCurrentFolderId(current?.parentFolderId ?? null);
    setSelected(null);
  };

  const isRecentHighlight = (updatedAt: string) =>
    page === "all" && Date.now() - new Date(updatedAt).getTime() <= RECENT_MS;

  const leadingIcon = (d: Doc) => {
    if (d.isFolder) {
      return (
        <span
          className="flex h-8 w-8 shrink-0 items-center justify-center"
          style={{
            borderRadius: 8,
            border: "1px solid var(--color-chrome-stroke)",
            background: "color-mix(in srgb, var(--color-primary) 10%, var(--color-surface))",
            color: "var(--color-primary)",
          }}
        >
          <Folder size={16} strokeWidth={2} />
        </span>
      );
    }
    return (
      <span
        className="flex h-8 w-8 shrink-0 items-center justify-center text-[10px] font-bold tracking-wide"
        style={{
          borderRadius: 8,
          border: "1px solid var(--color-chrome-stroke)",
          background: `color-mix(in srgb, ${categoryTint(d.category)} 12%, var(--color-surface))`,
          color: categoryTint(d.category),
        }}
      >
        {mimeLabel(d.mimeType, d.hasFile, d.isFolder).slice(0, 4)}
      </span>
    );
  };

  const docRow = (d: Doc, onActivate?: () => void) => {
    const row = (
      <ListRow
        selected={selected === d.id}
        onClick={() => setSelected(d.id)}
        onDoubleClick={() => {
          if (d.isFolder) {
            enterFolder(d.id);
            return;
          }
          onActivate?.();
        }}
        leading={leadingIcon(d)}
        title={d.title || "Untitled"}
        subtitle={
          d.isFolder
            ? "Folder"
            : d.hasFile
              ? `${formatBytes(d.fileSize)} · ${new Date(d.updatedAt).toLocaleDateString()}`
              : "Metadata only"
        }
        trailing={
          <div className="flex items-center gap-1">
            {d.isStarred && (
              <Star size={12} fill="currentColor" className="text-[var(--color-warning)]" />
            )}
            {!d.isFolder && isRecentHighlight(d.updatedAt) && (
              <StatusChip title="Recent" tint="var(--color-primary)" />
            )}
            {!d.isFolder && (
              <StatusChip title={d.category} tint={categoryTint(d.category)} filled />
            )}
          </div>
        }
      />
    );

    if (!usesFolderBrowser) return row;

    const dropHandlers = d.isFolder
      ? {
          onDragOver: (e: DragEvent) => handleFolderDragOver(e, d.id),
          onDragLeave: () =>
            setDropTargetFolderId((prev) => (prev === d.id ? null : prev)),
          onDrop: (e: DragEvent) => handleFolderDrop(e, d.id),
        }
      : {};

    return (
      <div
        draggable
        onDragStart={(e) => handleVaultDragStart(e, d.id)}
        onDragEnd={handleVaultDragEnd}
        style={{
          cursor: "grab",
          opacity: draggingId === d.id ? 0.55 : 1,
          borderRadius: 8,
          ...folderDropStyle(d.isFolder ? d.id : null),
        }}
        {...dropHandlers}
      >
        {row}
      </div>
    );
  };

  const docCard = (d: Doc) => {
    const card = (
      <button
        type="button"
        onClick={() => setSelected(d.id)}
        onDoubleClick={() => {
          if (d.isFolder) enterFolder(d.id);
        }}
        className="flex w-full flex-col rounded-[10px] border p-3 text-left transition-colors"
        style={{
          borderColor:
            selected === d.id ? "var(--color-primary)" : "var(--color-chrome-stroke)",
          background:
            selected === d.id
              ? "color-mix(in srgb, var(--color-primary) 8%, var(--color-surface))"
              : "var(--color-surface)",
        }}
      >
        <div className="flex items-start justify-between gap-2">
          {d.isFolder ? (
            <span
              className="flex h-10 w-10 shrink-0 items-center justify-center"
              style={{
                borderRadius: 8,
                border: "1px solid var(--color-chrome-stroke)",
                background: "color-mix(in srgb, var(--color-primary) 10%, var(--color-surface))",
                color: "var(--color-primary)",
              }}
            >
              <Folder size={18} strokeWidth={2} />
            </span>
          ) : (
            <span
              className="flex h-10 w-10 shrink-0 items-center justify-center text-[11px] font-bold tracking-wide"
              style={{
                borderRadius: 8,
                border: "1px solid var(--color-chrome-stroke)",
                background: `color-mix(in srgb, ${categoryTint(d.category)} 12%, var(--color-surface))`,
                color: categoryTint(d.category),
              }}
            >
              {mimeLabel(d.mimeType, d.hasFile, d.isFolder).slice(0, 4)}
            </span>
          )}
          {d.isStarred && (
            <Star size={14} fill="currentColor" className="text-[var(--color-warning)]" />
          )}
        </div>
        <p
          className="mt-2 line-clamp-2 text-[13px] font-medium text-[var(--color-text-main)]"
          style={{ letterSpacing: "-0.02em" }}
        >
          {d.title || "Untitled"}
        </p>
        <p className="mt-0.5 text-[11px] text-[var(--color-text-light)]">
          {d.isFolder
            ? "Folder"
            : d.hasFile
              ? `${formatBytes(d.fileSize)} · ${new Date(d.updatedAt).toLocaleDateString()}`
              : "Metadata only"}
        </p>
        {!d.isFolder && (
          <div className="mt-2 flex flex-wrap gap-1">
            <StatusChip title={d.category} tint={categoryTint(d.category)} filled />
            {!d.hasFile && <StatusChip title="No file" tint="var(--color-warning)" />}
          </div>
        )}
      </button>
    );

    if (!usesFolderBrowser) {
      return (
        <div key={d.id}>
          {card}
        </div>
      );
    }

    const dropHandlers = d.isFolder
      ? {
          onDragOver: (e: DragEvent) => handleFolderDragOver(e, d.id),
          onDragLeave: () =>
            setDropTargetFolderId((prev) => (prev === d.id ? null : prev)),
          onDrop: (e: DragEvent) => handleFolderDrop(e, d.id),
        }
      : {};

    return (
      <div
        key={d.id}
        draggable
        onDragStart={(e) => handleVaultDragStart(e, d.id)}
        onDragEnd={handleVaultDragEnd}
        style={{
          cursor: "grab",
          opacity: draggingId === d.id ? 0.55 : 1,
          borderRadius: 10,
          ...folderDropStyle(d.isFolder ? d.id : null),
        }}
        {...dropHandlers}
      >
        {card}
      </div>
    );
  };

  const parentRow =
    usesFolderBrowser && currentFolderId ? (
      <ListRow
        leading={
          <span
            className="flex h-8 w-8 shrink-0 items-center justify-center text-[13px] font-semibold text-[var(--color-text-light)]"
            style={{
              borderRadius: 8,
              border: "1px solid var(--color-chrome-stroke)",
              background: "var(--color-surface)",
            }}
          >
            ..
          </span>
        }
        title="Parent folder"
        subtitle="Go up one level"
        onClick={goUp}
        onDoubleClick={goUp}
      />
    ) : null;

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={activeCourse ? `${activeCourse.code} · ${activeCourse.title}` : pageTitle(page, docs)}
        subtitle={
          activeCourse
            ? "Course folder — syllabus and related files"
            : usesFolderBrowser && breadcrumb.length > 1
              ? breadcrumb.map((b) => b.title).join(" / ")
              : undefined
        }
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <SegmentedPills
              value={layout}
              onChange={(v) => setLayout(v as LayoutMode)}
              options={[
                { id: "list", label: "List" },
                { id: "grid", label: "Grid" },
              ]}
            />
            <input
              className={fieldControlClass}
              style={{ width: 180, paddingTop: 6, paddingBottom: 6 }}
              placeholder="Search vault…"
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setSemanticHits(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") void refresh();
              }}
            />
            <Button
              size="sm"
              variant="secondary"
              disabled={!search.trim()}
              onClick={async () => {
                const hits = await ipc.aiSemanticSearchVault(search.trim(), 40);
                setSemanticHits(hits.map((h) => h.id));
              }}
            >
              Semantic
            </Button>
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            {usesFolderBrowser && (
              <Button
                size="sm"
                variant="secondary"
                onClick={() => {
                  setFolderName("");
                  setFolderSheet(true);
                }}
              >
                New folder
              </Button>
            )}
            <Button size="sm" variant="secondary" disabled={busy} onClick={() => void importFile()}>
              {usesFolderBrowser ? "Import here" : "Import file"}
            </Button>
            <Button
              size="sm"
              onClick={() => {
                setForm({ title: "", category: defaultCategory });
                setSheetOpen(true);
              }}
            >
              Add note
            </Button>
          </div>
        }
      />
      {usesFolderBrowser && breadcrumb.length > 1 && (
        <nav
          className="flex flex-wrap items-center gap-1 px-3 pb-1 text-[12px] text-[var(--color-text-light)]"
          aria-label="Folder breadcrumb"
        >
          {breadcrumb.map((crumb, index) => (
            <span key={crumb.id ?? "root"} className="flex items-center gap-1">
              {index > 0 && <ChevronRight size={12} className="opacity-60" />}
              <button
                type="button"
                className="rounded px-1 py-0.5 hover:bg-[var(--color-surface-elevated)] hover:text-[var(--color-text-main)]"
                style={folderDropStyle(crumb.id)}
                onClick={() => {
                  setCurrentFolderId(crumb.id);
                  setSelected(null);
                }}
                onDragOver={(e) => handleFolderDragOver(e, crumb.id)}
                onDragLeave={() =>
                  setDropTargetFolderId((prev) =>
                    prev === (crumb.id ?? VAULT_ROOT_DROP) ? null : prev,
                  )
                }
                onDrop={(e) => handleFolderDrop(e, crumb.id)}
              >
                {crumb.title}
              </button>
            </span>
          ))}
        </nav>
      )}
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}
      <div className="min-h-0 flex-1 p-3 pt-1">
        <TrailingInspector
          open={!!selectedDoc}
          main={
            <AppCard className="flex min-h-0 flex-1 flex-col">
              <div className="flex min-h-0 flex-1">
                {usesFolderBrowser && layout === "list" ? (
                  <VaultFolderTree
                    docs={docs}
                    currentFolderId={currentFolderId}
                    onSelect={(folderId) => {
                      setCurrentFolderId(folderId);
                      setSelected(null);
                    }}
                  />
                ) : null}
                <div className="min-h-0 min-w-0 flex-1">
              {filtered.length === 0 && !parentRow ? (
                <EmptyState title={emptyState.title} body={emptyState.body} />
              ) : layout === "grid" ? (
                <div className="grid grid-cols-2 gap-2 p-2 sm:grid-cols-3 lg:grid-cols-4">
                  {parentRow && (
                    <button
                      type="button"
                      onClick={goUp}
                      className="flex flex-col rounded-[10px] border p-3 text-left"
                      style={{
                        borderColor: "var(--color-chrome-stroke)",
                        background: "var(--color-surface)",
                      }}
                    >
                      <span className="text-[13px] font-medium">..</span>
                      <span className="text-[11px] text-[var(--color-text-light)]">Parent folder</span>
                    </button>
                  )}
                  {filtered.map((d) => docCard(d))}
                </div>
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {parentRow && <li>{parentRow}</li>}
                  {filtered.map((d) => (
                    <li key={d.id}>
                      {docRow(d, () => {
                        if (!d.isFolder && d.hasFile) void openDoc(d.id);
                      })}
                    </li>
                  ))}
                </ul>
              )}
                </div>
              </div>
            </AppCard>
          }
        >
          {selectedDoc && (
            <div className="flex h-full flex-col">
              <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
                <div className="flex items-start justify-between gap-2">
                  <h3
                    className="text-[var(--color-text-main)]"
                    style={{
                      font: "var(--type-section-title)",
                      fontSize: 16,
                      letterSpacing: "-0.02em",
                    }}
                  >
                    {selectedDoc.title}
                  </h3>
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label={selectedDoc.isStarred ? "Remove star" : "Star document"}
                    onClick={() => void toggleStar(selectedDoc)}
                  >
                    <Star
                      size={16}
                      fill={selectedDoc.isStarred ? "currentColor" : "none"}
                      className={
                        selectedDoc.isStarred ? "text-[var(--color-warning)]" : undefined
                      }
                    />
                  </Button>
                </div>
                <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
                  {selectedDoc.isFolder
                    ? "Folder"
                    : `Updated ${new Date(selectedDoc.updatedAt).toLocaleString()}`}
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {selectedDoc.isFolder ? (
                    <StatusChip title="Folder" tint="var(--color-primary)" filled />
                  ) : (
                    <>
                      <StatusChip
                        title={selectedDoc.category}
                        tint={categoryTint(selectedDoc.category)}
                        filled
                      />
                      <StatusChip
                        title={mimeLabel(selectedDoc.mimeType, selectedDoc.hasFile, false)}
                      />
                      {selectedDoc.hasFile ? (
                        <StatusChip title={formatBytes(selectedDoc.fileSize)} />
                      ) : (
                        <StatusChip title="No file" tint="var(--color-warning)" filled />
                      )}
                    </>
                  )}
                  {selectedDoc.isStarred && (
                    <StatusChip title="Starred" tint="var(--color-warning)" filled />
                  )}
                </div>
              </div>
              <div className="min-h-0 flex-1 space-y-2 overflow-auto p-4">
                {!selectedDoc.isFolder && selectedDoc.hasFile ? (
                  <DocumentPreviewPanel docId={selectedDoc.id} />
                ) : null}
                <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
                  {selectedDoc.isFolder
                    ? "Double-click to open this folder in the vault browser."
                    : selectedDoc.hasFile
                      ? selectedDoc.relativePath
                      : "No file on disk — metadata placeholder."}
                </p>
              </div>
              <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                {selectedDoc.isFolder ? (
                  <Button size="sm" onClick={() => enterFolder(selectedDoc.id)}>
                    Open folder
                  </Button>
                ) : (
                  <>
                    <Button
                      size="sm"
                      disabled={!selectedDoc.hasFile}
                      onClick={() => void quickLook(selectedDoc.id)}
                    >
                      Quick Look
                    </Button>
                    <Button
                      size="sm"
                      disabled={!selectedDoc.hasFile}
                      onClick={() => void openDoc(selectedDoc.id)}
                    >
                      Open
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={!selectedDoc.hasFile}
                      onClick={() => void revealDoc(selectedDoc.id)}
                    >
                      Reveal
                    </Button>
                  </>
                )}
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => {
                    setEditForm({ title: selectedDoc.title, category: selectedDoc.category });
                    setEditSheet(true);
                  }}
                >
                  Rename
                </Button>
                {usesFolderBrowser && (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => {
                      setMoveTargetId("");
                      setMoveSheet(true);
                    }}
                  >
                    Move…
                  </Button>
                )}
                <Button
                  size="sm"
                  variant="danger"
                  onClick={async () => {
                    if (!selectedDoc) return;
                    const descendantCount = selectedDoc.isFolder
                      ? collectDescendantIds(docs, selectedDoc.id).size - 1
                      : 0;
                    if (selectedDoc.isFolder && descendantCount > 0) {
                      if (!confirmFolderCascadeDelete(selectedDoc.title, descendantCount)) return;
                    } else if (!confirmDelete(selectedDoc.title || "item")) {
                      return;
                    }
                    try {
                      await ipc.documentsDeleteVaultDoc(
                        selectedDoc.id,
                        selectedDoc.isFolder && descendantCount > 0,
                      );
                      if (selectedDoc.isFolder && currentFolderId === selectedDoc.id) {
                        setCurrentFolderId(selectedDoc.parentFolderId ?? null);
                      }
                      setSelected(null);
                      showToast(
                        descendantCount > 0
                          ? `Deleted folder and ${descendantCount} item${descendantCount === 1 ? "" : "s"}`
                          : "Deleted",
                        "success",
                      );
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Delete
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setSelected(null)}>
                  Close
                </Button>
              </div>
            </div>
          )}
        </TrailingInspector>
      </div>

      <ModalSheet open={sheetOpen} onOpenChange={setSheetOpen} title="Add vault note">
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={form.title}
              onChange={(e) => setForm({ ...form, title: e.target.value })}
            />
          </FormField>
          <FormField label="Category">
            <select
              className={fieldControlClass}
              value={form.category}
              onChange={(e) => setForm({ ...form, category: e.target.value })}
            >
              {CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </FormField>
          <Button
            disabled={!form.title.trim()}
            onClick={async () => {
              await ipc.documentsUpsertVaultDoc({
                title: form.title.trim(),
                category: form.category,
                parentFolderId: importParentFolderId,
              });
              setSheetOpen(false);
              setForm({ title: "", category: defaultCategory });
            }}
          >
            Save
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={editSheet} onOpenChange={setEditSheet} title="Rename item">
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={editForm.title}
              onChange={(e) => setEditForm({ ...editForm, title: e.target.value })}
            />
          </FormField>
          {!selectedDoc?.isFolder && (
            <FormField label="Category">
              <select
                className={fieldControlClass}
                value={editForm.category}
                onChange={(e) => setEditForm({ ...editForm, category: e.target.value })}
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </FormField>
          )}
          <Button
            disabled={!editForm.title.trim() || !selected}
            onClick={async () => {
              if (!selected) return;
              try {
                await ipc.documentsRenameVaultItem(selected, editForm.title.trim());
                if (!selectedDoc?.isFolder) {
                  await ipc.documentsUpdateVaultDoc({
                    id: selected,
                    category: editForm.category,
                  });
                }
                setEditSheet(false);
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save changes
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={folderSheet} onOpenChange={setFolderSheet} title="New folder">
        <div className="space-y-3">
          <FormField label="Folder name">
            <input
              className={fieldControlClass}
              value={folderName}
              onChange={(e) => setFolderName(e.target.value)}
              placeholder="e.g. Fall 2025"
              autoFocus
            />
          </FormField>
          <Button
            disabled={!folderName.trim()}
            onClick={async () => {
              try {
                await ipc.documentsCreateFolder(folderName.trim(), currentFolderId);
                setFolderSheet(false);
                setFolderName("");
                showToast("Folder created", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Create folder
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={moveSheet} onOpenChange={setMoveSheet} title="Move item">
        <div className="space-y-3">
          <FormField label="Destination folder">
            <select
              className={fieldControlClass}
              value={moveTargetId}
              onChange={(e) => setMoveTargetId(e.target.value)}
            >
              <option value="">Vault root</option>
              {moveFolderOptions.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.title}
                </option>
              ))}
            </select>
          </FormField>
          <Button
            disabled={!selected}
            onClick={async () => {
              if (!selected) return;
              try {
                await ipc.documentsMoveVaultItem(
                  selected,
                  moveTargetId ? moveTargetId : null,
                );
                setMoveSheet(false);
                setSelected(null);
                showToast("Item moved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Move here
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}
