import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  SegmentedPills,
  StatusChip,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError, type ProfileIdentity } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { SimpleMarkdown } from "@/modules/assistant/simpleMarkdown";
import {
  buildResumeMarkdown,
  DEFAULT_RESUME_SECTION_ORDER,
  type ResumeDraftAchievement,
  type ResumeDraftBragEntry,
  type ResumeDraftExperience,
  type ResumeDraftProject,
  type ResumeExportSection,
  type ResumeProfileTailoring,
} from "./buildResumeMarkdown";
import { buildResumeTypst, compileResumeTypstToPdf, compileResumeTypstPdfPreview } from "./buildResumeTypst";

const SETTINGS_KEY = "career.resumeLiveDraft";

export type ResumeBuilderSection =
  | "header"
  | "experience"
  | "education"
  | "skills"
  | "projects"
  | "brag";

type CenterMode = "fields" | "markdown" | "typst";
type PreviewMode = "markdown" | "typst" | "pdf";

export type ResumeLiveDraft = {
  identity: ProfileIdentity;
  experiences: ResumeDraftExperience[];
  achievements: ResumeDraftAchievement[];
  skills: string[];
  projects: ResumeDraftProject[];
  bragEntries: ResumeDraftBragEntry[];
  includeBragBook: boolean;
  tailoring: ResumeProfileTailoring | null;
  /** Sidebar + export section order (header stays first in sidebar; omitted from export). */
  sectionOrder?: ResumeBuilderSection[];
};

function defaultSectionOrder(includeBrag: boolean): ResumeBuilderSection[] {
  return [
    "header",
    ...DEFAULT_RESUME_SECTION_ORDER.filter((section) => includeBrag || section !== "brag"),
  ];
}

function normalizeSectionOrder(
  order: ResumeBuilderSection[] | undefined,
  includeBrag: boolean,
): ResumeBuilderSection[] {
  const allowed = new Set(defaultSectionOrder(includeBrag));
  const seen = new Set<ResumeBuilderSection>();
  const normalized: ResumeBuilderSection[] = [];
  for (const section of order ?? defaultSectionOrder(includeBrag)) {
    if (!allowed.has(section) || seen.has(section)) continue;
    seen.add(section);
    normalized.push(section);
  }
  for (const section of defaultSectionOrder(includeBrag)) {
    if (!seen.has(section)) normalized.push(section);
  }
  return normalized;
}

function exportSectionOrder(draft: ResumeLiveDraft): ResumeExportSection[] {
  return normalizeSectionOrder(draft.sectionOrder, draft.includeBragBook).filter(
    (section): section is ResumeExportSection => section !== "header",
  );
}

function emptyIdentity(): ProfileIdentity {
  return {
    fullName: "",
    email: "",
    universityName: "",
    major: "",
    graduationYear: null,
  };
}

function emptyDraft(includeBragBook = true): ResumeLiveDraft {
  return {
    identity: emptyIdentity(),
    experiences: [],
    achievements: [],
    skills: [],
    projects: [],
    bragEntries: [],
    includeBragBook,
    tailoring: null,
    sectionOrder: defaultSectionOrder(includeBragBook),
  };
}

function draftIsPopulated(draft: ResumeLiveDraft): boolean {
  if (draft.identity.fullName.trim()) return true;
  if (draft.experiences.length > 0) return true;
  if (draft.skills.length > 0) return true;
  if (draft.projects.length > 0) return true;
  if (draft.achievements.length > 0) return true;
  if (draft.bragEntries.length > 0) return true;
  if (draft.identity.universityName.trim() || draft.identity.major.trim()) return true;
  return false;
}

function sectionItems(includeBrag: boolean): Array<{ id: ResumeBuilderSection; label: string }> {
  const items: Array<{ id: ResumeBuilderSection; label: string }> = [
    { id: "header", label: "Header" },
    { id: "experience", label: "Experience" },
    { id: "education", label: "Education" },
    { id: "skills", label: "Skills" },
    { id: "projects", label: "Projects" },
  ];
  if (includeBrag) items.push({ id: "brag", label: "Brag" });
  return items;
}

function sectionCount(draft: ResumeLiveDraft, id: ResumeBuilderSection): number {
  switch (id) {
    case "header":
      return draft.identity.fullName.trim() ? 1 : 0;
    case "experience":
      return draft.experiences.length;
    case "education":
      return draft.identity.universityName.trim() ||
        draft.identity.major.trim() ||
        draft.identity.graduationYear != null
        ? 1
        : 0;
    case "skills":
      return draft.skills.length + draft.achievements.length;
    case "projects":
      return draft.projects.length;
    case "brag":
      return draft.bragEntries.length;
  }
}

function parsePersistedDraft(raw: string | undefined): ResumeLiveDraft | null {
  if (!raw?.trim()) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<ResumeLiveDraft>;
    if (!parsed || typeof parsed !== "object") return null;
    const base = emptyDraft(parsed.includeBragBook !== false);
    return {
      ...base,
      identity: { ...emptyIdentity(), ...(parsed.identity ?? {}) },
      experiences: Array.isArray(parsed.experiences) ? parsed.experiences : [],
      achievements: Array.isArray(parsed.achievements) ? parsed.achievements : [],
      skills: Array.isArray(parsed.skills) ? parsed.skills.map(String) : [],
      projects: Array.isArray(parsed.projects) ? parsed.projects : [],
      bragEntries: Array.isArray(parsed.bragEntries) ? parsed.bragEntries : [],
      includeBragBook: parsed.includeBragBook !== false,
      tailoring: parsed.tailoring ?? null,
      sectionOrder: normalizeSectionOrder(
        Array.isArray(parsed.sectionOrder)
          ? parsed.sectionOrder.filter((section): section is ResumeBuilderSection =>
              typeof section === "string",
            )
          : undefined,
        parsed.includeBragBook !== false,
      ),
    };
  } catch {
    return null;
  }
}

export type ResumeLiveBuilderProps = {
  /** Increment to force reload from profile (header “New draft”). */
  loadNonce?: number;
  includeBragBook?: boolean;
  onIncludeBragBookChange?: (value: boolean) => void;
  tailoring?: ResumeProfileTailoring | null;
  onDraftOutputsChange?: (outputs: { markdown: string; typst: string; hasDraft: boolean }) => void;
  onOpenSourceSheet?: () => void;
};

export function ResumeLiveBuilder({
  loadNonce = 0,
  includeBragBook = true,
  onIncludeBragBookChange,
  tailoring = null,
  onDraftOutputsChange,
  onOpenSourceSheet,
}: ResumeLiveBuilderProps) {
  const [draft, setDraft] = useState<ResumeLiveDraft>(() => emptyDraft(includeBragBook));
  const [section, setSection] = useState<ResumeBuilderSection>("header");
  const [centerMode, setCenterMode] = useState<CenterMode>("fields");
  const [previewMode, setPreviewMode] = useState<PreviewMode>("markdown");
  const [loadBusy, setLoadBusy] = useState(false);
  const [saveBusy, setSaveBusy] = useState(false);
  const [compileBusy, setCompileBusy] = useState(false);
  const [pdfPreviewUrl, setPdfPreviewUrl] = useState<string | null>(null);
  const [pdfPreviewBusy, setPdfPreviewBusy] = useState(false);
  const [hydrated, setHydrated] = useState(false);
  const [skillsText, setSkillsText] = useState("");
  const [dragSection, setDragSection] = useState<ResumeBuilderSection | null>(null);

  const applyDraft = useCallback((next: ResumeLiveDraft) => {
    setDraft(next);
    setSkillsText(next.skills.join(", "));
  }, []);

  const loadFromProfile = useCallback(
    async (opts?: { silent?: boolean; preferPersisted?: boolean }) => {
      setLoadBusy(true);
      try {
        if (opts?.preferPersisted) {
          const settings = await ipc.settingsGet().catch(() => ({ values: {} as Record<string, string> }));
          const persisted = parsePersistedDraft(settings.values[SETTINGS_KEY]);
          if (persisted && draftIsPopulated(persisted)) {
            applyDraft({
              ...persisted,
              includeBragBook: includeBragBook,
              tailoring: tailoring ?? persisted.tailoring,
            });
            if (!opts.silent) showToast("Restored saved draft", "success");
            return;
          }
        }

        const [identity, experiences, achievements, brag, skills] = await Promise.all([
          ipc.profileGetIdentity(),
          ipc.profileListExperiences(),
          ipc.profileListAchievements(),
          includeBragBook
            ? ipc.careerListBragEntries().catch(() => [] as ResumeDraftBragEntry[])
            : Promise.resolve([] as ResumeDraftBragEntry[]),
          ipc.careerListSkills().catch(() => [] as Array<{ name: string }>),
        ]);

        const next: ResumeLiveDraft = {
          identity: {
            fullName: identity.fullName ?? "",
            email: identity.email ?? "",
            universityName: identity.universityName ?? "",
            major: identity.major ?? "",
            graduationYear: identity.graduationYear ?? null,
            id: identity.id,
          },
          experiences: experiences.map((e) => ({
            title: e.title,
            organization: e.organization,
            startDate: e.startDate ?? null,
            endDate: e.endDate ?? null,
            summary: e.summary,
          })),
          achievements: achievements.map((a) => ({
            title: a.title,
            issuer: a.issuer,
            notes: a.notes,
          })),
          skills: skills.map((s) => s.name).filter(Boolean),
          projects: [],
          bragEntries: brag.map((b) => ({
            title: b.title,
            occurredAt: b.occurredAt ?? null,
            summary: b.summary,
            evidenceNote: b.evidenceNote,
          })),
          includeBragBook,
          tailoring,
        };
        applyDraft(next);
        if (!opts?.silent) showToast("Loaded from profile", "success");
      } catch (e) {
        showToast(formatIpcError(e), "error");
      } finally {
        setLoadBusy(false);
      }
    },
    [applyDraft, includeBragBook, tailoring],
  );

  useEffect(() => {
    void (async () => {
      await loadFromProfile({ silent: true, preferPersisted: true });
      setHydrated(true);
    })();
    // initial hydrate only
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!hydrated || loadNonce <= 0) return;
    void loadFromProfile({ silent: false, preferPersisted: false });
  }, [loadNonce, hydrated, loadFromProfile]);

  useEffect(() => {
    setDraft((prev) => ({
      ...prev,
      includeBragBook,
      tailoring: tailoring ?? prev.tailoring,
      sectionOrder: normalizeSectionOrder(prev.sectionOrder, includeBragBook),
    }));
  }, [includeBragBook, tailoring]);

  useEffect(() => {
    if (section === "brag" && !includeBragBook) setSection("header");
  }, [includeBragBook, section]);

  const buildInput = useMemo(
    () => ({
      identity: draft.identity,
      experiences: draft.experiences,
      achievements: draft.achievements,
      skills: draft.skills,
      projects: draft.projects,
      bragEntries: draft.bragEntries,
      includeBragBook: draft.includeBragBook,
      tailoring: draft.tailoring,
      sectionOrder: exportSectionOrder(draft),
    }),
    [draft],
  );

  const markdown = useMemo(() => buildResumeMarkdown(buildInput), [buildInput]);
  const typst = useMemo(() => buildResumeTypst(buildInput), [buildInput]);
  const hasDraft = draftIsPopulated(draft);

  const outputsRef = useRef(onDraftOutputsChange);
  outputsRef.current = onDraftOutputsChange;
  useEffect(() => {
    outputsRef.current?.({ markdown, typst, hasDraft });
  }, [markdown, typst, hasDraft]);

  const persistDraft = useCallback(async () => {
    setSaveBusy(true);
    try {
      await ipc.settingsSet(SETTINGS_KEY, JSON.stringify(draft));
      showToast("Draft saved", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setSaveBusy(false);
    }
  }, [draft]);

  const exportText = useCallback(async (kind: "markdown" | "typst") => {
    const content = kind === "markdown" ? markdown : typst;
    if (!content.trim()) return;
    try {
      const picked = await save({
        title: "Save resume draft",
        defaultPath: kind === "markdown" ? "resume-draft.md" : "resume-draft.typ",
        filters:
          kind === "markdown"
            ? [{ name: "Markdown", extensions: ["md"] }]
            : [{ name: "Typst", extensions: ["typ"] }],
      });
      if (!picked) return;
      await writeTextFile(picked, content);
      showToast("Resume draft saved", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  }, [markdown, typst]);

  const copyText = useCallback(async (kind: "markdown" | "typst") => {
    const content = kind === "markdown" ? markdown : typst;
    try {
      await navigator.clipboard.writeText(content);
      showToast(kind === "markdown" ? "Copied Markdown" : "Copied Typst", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  }, [markdown, typst]);

  const compilePdf = useCallback(async () => {
    if (!typst.trim()) return;
    setCompileBusy(true);
    try {
      const result = await compileResumeTypstToPdf(typst);
      if (result === "ok") showToast("PDF compiled", "success");
    } catch (e) {
      const message = e instanceof Error ? e.message : formatIpcError(e);
      if (message.includes("typst not found")) {
        showToast("Install Typst from https://typst.app if missing", "error");
      } else {
        showToast(message, "error");
      }
    } finally {
      setCompileBusy(false);
    }
  }, [typst]);

  const previewPdf = useCallback(async () => {
    if (!typst.trim()) return;
    setPdfPreviewBusy(true);
    try {
      const url = await compileResumeTypstPdfPreview(typst);
      setPdfPreviewUrl(url);
      setPreviewMode("pdf");
    } catch (e) {
      const message = e instanceof Error ? e.message : formatIpcError(e);
      if (message.includes("typst not found")) {
        showToast("Install Typst from https://typst.app if missing", "error");
      } else {
        showToast(message, "error");
      }
    } finally {
      setPdfPreviewBusy(false);
    }
  }, [typst]);

  const updateIdentity = <K extends keyof ProfileIdentity>(key: K, value: ProfileIdentity[K]) => {
    setDraft((prev) => ({
      ...prev,
      identity: { ...prev.identity, [key]: value },
    }));
  };

  const updateExperience = (index: number, patch: Partial<ResumeDraftExperience>) => {
    setDraft((prev) => {
      const experiences = prev.experiences.map((exp, i) =>
        i === index ? { ...exp, ...patch } : exp,
      );
      return { ...prev, experiences };
    });
  };

  const updateProject = (index: number, patch: Partial<ResumeDraftProject>) => {
    setDraft((prev) => {
      const projects = prev.projects.map((p, i) => (i === index ? { ...p, ...patch } : p));
      return { ...prev, projects };
    });
  };

  const updateAchievement = (index: number, patch: Partial<ResumeDraftAchievement>) => {
    setDraft((prev) => {
      const achievements = prev.achievements.map((a, i) =>
        i === index ? { ...a, ...patch } : a,
      );
      return { ...prev, achievements };
    });
  };

  const updateBrag = (index: number, patch: Partial<ResumeDraftBragEntry>) => {
    setDraft((prev) => {
      const bragEntries = prev.bragEntries.map((b, i) => (i === index ? { ...b, ...patch } : b));
      return { ...prev, bragEntries };
    });
  };

  const commitSkillsText = (value: string) => {
    setSkillsText(value);
    const skills = value
      .split(/[,;\n]/)
      .map((s) => s.trim())
      .filter(Boolean);
    setDraft((prev) => ({ ...prev, skills }));
  };

  const sidebar = useMemo(() => {
    const order = normalizeSectionOrder(draft.sectionOrder, draft.includeBragBook);
    const labels = sectionItems(draft.includeBragBook);
    return order
      .map((id) => labels.find((item) => item.id === id))
      .filter((item): item is { id: ResumeBuilderSection; label: string } => Boolean(item));
  }, [draft.includeBragBook, draft.sectionOrder]);

  const reorderSections = (from: ResumeBuilderSection, to: ResumeBuilderSection) => {
    if (from === to) return;
    setDraft((prev) => {
      const order = normalizeSectionOrder(prev.sectionOrder, prev.includeBragBook);
      const fromIdx = order.indexOf(from);
      const toIdx = order.indexOf(to);
      if (fromIdx < 0 || toIdx < 0) return prev;
      const next = [...order];
      next.splice(fromIdx, 1);
      next.splice(toIdx, 0, from);
      return { ...prev, sectionOrder: next };
    });
  };

  return (
    <AppCard title="Live resume builder">
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <Button size="sm" disabled={loadBusy} onClick={() => void loadFromProfile()}>
          {loadBusy ? "Loading…" : "Load from profile"}
        </Button>
        <label className="flex items-center gap-2 text-[12px] text-[var(--color-text-main)]">
          <input
            type="checkbox"
            checked={includeBragBook}
            onChange={(e) => onIncludeBragBookChange?.(e.target.checked)}
          />
          Include brag book
        </label>
        <Button size="sm" variant="secondary" disabled={saveBusy || !hasDraft} onClick={() => void persistDraft()}>
          {saveBusy ? "Saving…" : "Save draft"}
        </Button>
        <Button size="sm" variant="secondary" disabled={!hasDraft} onClick={() => void exportText("markdown")}>
          Export MD
        </Button>
        <Button size="sm" variant="secondary" disabled={!hasDraft} onClick={() => void exportText("typst")}>
          Export Typst
        </Button>
        <Button size="sm" variant="secondary" disabled={!typst.trim() || compileBusy} onClick={() => void compilePdf()}>
          {compileBusy ? "Compiling…" : "Compile PDF"}
        </Button>
        {onOpenSourceSheet && (
          <Button size="sm" variant="ghost" onClick={onOpenSourceSheet}>
            Open source sheet
          </Button>
        )}
        {hasDraft ? (
          <StatusChip title="Live" tint="var(--color-success)" filled />
        ) : (
          <StatusChip title="Empty" tint="var(--color-text-light)" />
        )}
      </div>

      {!hasDraft ? (
        <EmptyState
          title="No draft yet"
          body="Load from profile to populate editable sections and a live Markdown/Typst preview."
        />
      ) : (
        <div className="grid min-h-[420px] gap-3 lg:grid-cols-[148px_minmax(0,1.1fr)_minmax(0,1fr)]">
          <aside
            className="space-y-1 rounded-[10px] border border-[var(--color-chrome-stroke)] p-1.5"
            style={{ background: "var(--color-sidebar-section)" }}
          >
            <p className="px-2 pb-1 pt-0.5 text-[10px] font-semibold uppercase tracking-[0.07em] text-[var(--color-text-light)]">
              Sections
            </p>
            <p className="px-2 pb-1 text-[10px] text-[var(--color-text-light)]">
              Drag to reorder export sections
            </p>
            {sidebar.map((item) => {
              const selected = section === item.id;
              const count = sectionCount(draft, item.id);
              const dragging = dragSection === item.id;
              return (
                <button
                  key={item.id}
                  type="button"
                  draggable
                  onDragStart={(e) => {
                    e.dataTransfer.effectAllowed = "move";
                    e.dataTransfer.setData("text/plain", item.id);
                    setDragSection(item.id);
                  }}
                  onDragOver={(e) => {
                    e.preventDefault();
                    e.dataTransfer.dropEffect = "move";
                  }}
                  onDrop={(e) => {
                    e.preventDefault();
                    const from =
                      dragSection ??
                      (e.dataTransfer.getData("text/plain") as ResumeBuilderSection);
                    if (from) reorderSections(from, item.id);
                    setDragSection(null);
                  }}
                  onDragEnd={() => setDragSection(null)}
                  onClick={() => {
                    setSection(item.id);
                    setCenterMode("fields");
                  }}
                  className={
                    selected
                      ? "flex w-full items-center justify-between rounded-[8px] px-2.5 py-2 text-left text-[12px] font-semibold text-[var(--color-text-main)]"
                      : "flex w-full items-center justify-between rounded-[8px] px-2.5 py-2 text-left text-[12px] font-medium text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)] hover:text-[var(--color-text-main)]"
                  }
                  style={
                    selected
                      ? {
                          background: "var(--color-shell-selection)",
                          boxShadow: "var(--shadow-pill)",
                          cursor: "grab",
                          opacity: dragging ? 0.55 : 1,
                        }
                      : {
                          cursor: "grab",
                          opacity: dragging ? 0.55 : 1,
                        }
                  }
                >
                  <span>{item.label}</span>
                  <span className="tabular-nums text-[10px] text-[var(--color-text-light)]">
                    {count}
                  </span>
                </button>
              );
            })}
          </aside>

          <div className="min-w-0 space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <SegmentedPills<CenterMode>
                options={[
                  { id: "fields", label: "Fields" },
                  { id: "markdown", label: "Markdown" },
                  { id: "typst", label: "Typst" },
                ]}
                value={centerMode}
                onChange={setCenterMode}
              />
              <div className="flex gap-1.5">
                <Button size="sm" variant="ghost" disabled={!hasDraft} onClick={() => void copyText(centerMode === "typst" ? "typst" : "markdown")}>
                  Copy
                </Button>
              </div>
            </div>

            {centerMode === "markdown" ? (
              <FormField label="Markdown (generated)">
                <textarea
                  className={fieldControlClass}
                  rows={18}
                  readOnly
                  value={markdown}
                  onFocus={(e) => e.currentTarget.select()}
                />
              </FormField>
            ) : centerMode === "typst" ? (
              <FormField label="Typst (generated)">
                <textarea
                  className={fieldControlClass}
                  rows={18}
                  readOnly
                  value={typst}
                  onFocus={(e) => e.currentTarget.select()}
                />
              </FormField>
            ) : (
              <div className="max-h-[440px] space-y-3 overflow-auto rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-3">
                {section === "header" && (
                  <>
                    <FormField label="Full name">
                      <input
                        className={fieldControlClass}
                        value={draft.identity.fullName}
                        onChange={(e) => updateIdentity("fullName", e.target.value)}
                        placeholder="Your name"
                      />
                    </FormField>
                    <FormField label="Email">
                      <input
                        className={fieldControlClass}
                        value={draft.identity.email}
                        onChange={(e) => updateIdentity("email", e.target.value)}
                        placeholder="you@school.edu"
                      />
                    </FormField>
                    <FormField label="Target role">
                      <input
                        className={fieldControlClass}
                        value={draft.tailoring?.targetRole ?? ""}
                        onChange={(e) =>
                          setDraft((prev) => ({
                            ...prev,
                            tailoring: {
                              targetRole: e.target.value,
                              targetCompany: prev.tailoring?.targetCompany ?? "",
                              notes: prev.tailoring?.notes ?? "",
                            },
                          }))
                        }
                        placeholder="Software Engineer Intern"
                      />
                    </FormField>
                    <FormField label="Target company">
                      <input
                        className={fieldControlClass}
                        value={draft.tailoring?.targetCompany ?? ""}
                        onChange={(e) =>
                          setDraft((prev) => ({
                            ...prev,
                            tailoring: {
                              targetRole: prev.tailoring?.targetRole ?? "",
                              targetCompany: e.target.value,
                              notes: prev.tailoring?.notes ?? "",
                            },
                          }))
                        }
                        placeholder="Acme Corp"
                      />
                    </FormField>
                    <FormField label="Tailoring notes">
                      <textarea
                        className={fieldControlClass}
                        rows={3}
                        value={draft.tailoring?.notes ?? ""}
                        onChange={(e) =>
                          setDraft((prev) => ({
                            ...prev,
                            tailoring: {
                              targetRole: prev.tailoring?.targetRole ?? "",
                              targetCompany: prev.tailoring?.targetCompany ?? "",
                              notes: e.target.value,
                            },
                          }))
                        }
                        placeholder="Emphasize ML project…"
                      />
                    </FormField>
                  </>
                )}

                {section === "education" && (
                  <>
                    <FormField label="University">
                      <input
                        className={fieldControlClass}
                        value={draft.identity.universityName}
                        onChange={(e) => updateIdentity("universityName", e.target.value)}
                      />
                    </FormField>
                    <FormField label="Major">
                      <input
                        className={fieldControlClass}
                        value={draft.identity.major}
                        onChange={(e) => updateIdentity("major", e.target.value)}
                      />
                    </FormField>
                    <FormField label="Graduation year">
                      <input
                        className={fieldControlClass}
                        type="number"
                        value={draft.identity.graduationYear ?? ""}
                        onChange={(e) =>
                          updateIdentity(
                            "graduationYear",
                            e.target.value ? Number(e.target.value) : null,
                          )
                        }
                      />
                    </FormField>
                  </>
                )}

                {section === "experience" && (
                  <div className="space-y-3">
                    {draft.experiences.length === 0 ? (
                      <p className="text-[12px] text-[var(--color-text-light)]">
                        No experience entries — add some in Profile, or create one here.
                      </p>
                    ) : (
                      draft.experiences.map((exp, index) => (
                        <div
                          key={index}
                          className="space-y-2 rounded-[8px] border border-[var(--color-chrome-stroke)] p-2.5"
                        >
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                              Entry {index + 1}
                            </span>
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() =>
                                setDraft((prev) => ({
                                  ...prev,
                                  experiences: prev.experiences.filter((_, i) => i !== index),
                                }))
                              }
                            >
                              Remove
                            </Button>
                          </div>
                          <FormField label="Title">
                            <input
                              className={fieldControlClass}
                              value={exp.title}
                              onChange={(e) => updateExperience(index, { title: e.target.value })}
                            />
                          </FormField>
                          <FormField label="Organization">
                            <input
                              className={fieldControlClass}
                              value={exp.organization}
                              onChange={(e) =>
                                updateExperience(index, { organization: e.target.value })
                              }
                            />
                          </FormField>
                          <FormField label="Bullets (one per line)">
                            <textarea
                              className={fieldControlClass}
                              rows={4}
                              value={exp.summary}
                              onChange={(e) => updateExperience(index, { summary: e.target.value })}
                            />
                          </FormField>
                        </div>
                      ))
                    )}
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        setDraft((prev) => ({
                          ...prev,
                          experiences: [
                            ...prev.experiences,
                            { title: "", organization: "", summary: "", startDate: null, endDate: null },
                          ],
                        }))
                      }
                    >
                      Add experience
                    </Button>
                  </div>
                )}

                {section === "skills" && (
                  <div className="space-y-3">
                    <FormField label="Skills (comma-separated)">
                      <textarea
                        className={fieldControlClass}
                        rows={4}
                        value={skillsText}
                        onChange={(e) => commitSkillsText(e.target.value)}
                        placeholder="TypeScript, React, SQL, systems design"
                      />
                    </FormField>
                    <p className="text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                      Achievements
                    </p>
                    {draft.achievements.length === 0 ? (
                      <p className="text-[12px] text-[var(--color-text-light)]">
                        No achievements loaded from profile.
                      </p>
                    ) : (
                      draft.achievements.map((ach, index) => (
                        <div
                          key={index}
                          className="space-y-2 rounded-[8px] border border-[var(--color-chrome-stroke)] p-2.5"
                        >
                          <FormField label="Title">
                            <input
                              className={fieldControlClass}
                              value={ach.title}
                              onChange={(e) => updateAchievement(index, { title: e.target.value })}
                            />
                          </FormField>
                          <FormField label="Issuer">
                            <input
                              className={fieldControlClass}
                              value={ach.issuer}
                              onChange={(e) => updateAchievement(index, { issuer: e.target.value })}
                            />
                          </FormField>
                          <FormField label="Notes">
                            <input
                              className={fieldControlClass}
                              value={ach.notes}
                              onChange={(e) => updateAchievement(index, { notes: e.target.value })}
                            />
                          </FormField>
                        </div>
                      ))
                    )}
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        setDraft((prev) => ({
                          ...prev,
                          achievements: [
                            ...prev.achievements,
                            { title: "", issuer: "", notes: "" },
                          ],
                        }))
                      }
                    >
                      Add achievement
                    </Button>
                  </div>
                )}

                {section === "projects" && (
                  <div className="space-y-3">
                    {draft.projects.length === 0 ? (
                      <p className="text-[12px] text-[var(--color-text-light)]">
                        No projects yet — add one to include a Projects section in the export.
                      </p>
                    ) : (
                      draft.projects.map((project, index) => (
                        <div
                          key={index}
                          className="space-y-2 rounded-[8px] border border-[var(--color-chrome-stroke)] p-2.5"
                        >
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                              Project {index + 1}
                            </span>
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() =>
                                setDraft((prev) => ({
                                  ...prev,
                                  projects: prev.projects.filter((_, i) => i !== index),
                                }))
                              }
                            >
                              Remove
                            </Button>
                          </div>
                          <FormField label="Title">
                            <input
                              className={fieldControlClass}
                              value={project.title}
                              onChange={(e) => updateProject(index, { title: e.target.value })}
                            />
                          </FormField>
                          <FormField label="Link">
                            <input
                              className={fieldControlClass}
                              value={project.link ?? ""}
                              onChange={(e) => updateProject(index, { link: e.target.value })}
                              placeholder="https://"
                            />
                          </FormField>
                          <FormField label="Bullets (one per line)">
                            <textarea
                              className={fieldControlClass}
                              rows={3}
                              value={project.summary}
                              onChange={(e) => updateProject(index, { summary: e.target.value })}
                            />
                          </FormField>
                        </div>
                      ))
                    )}
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        setDraft((prev) => ({
                          ...prev,
                          projects: [...prev.projects, { title: "", summary: "", link: "" }],
                        }))
                      }
                    >
                      Add project
                    </Button>
                  </div>
                )}

                {section === "brag" && (
                  <div className="space-y-3">
                    {draft.bragEntries.length === 0 ? (
                      <p className="text-[12px] text-[var(--color-text-light)]">
                        No brag book entries — add wins under Career → Brag Book, then reload.
                      </p>
                    ) : (
                      draft.bragEntries.map((entry, index) => (
                        <div
                          key={index}
                          className="space-y-2 rounded-[8px] border border-[var(--color-chrome-stroke)] p-2.5"
                        >
                          <FormField label="Title">
                            <input
                              className={fieldControlClass}
                              value={entry.title}
                              onChange={(e) => updateBrag(index, { title: e.target.value })}
                            />
                          </FormField>
                          <FormField label="Summary (one bullet per line)">
                            <textarea
                              className={fieldControlClass}
                              rows={3}
                              value={entry.summary}
                              onChange={(e) => updateBrag(index, { summary: e.target.value })}
                            />
                          </FormField>
                          <FormField label="Evidence">
                            <input
                              className={fieldControlClass}
                              value={entry.evidenceNote}
                              onChange={(e) => updateBrag(index, { evidenceNote: e.target.value })}
                            />
                          </FormField>
                        </div>
                      ))
                    )}
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="min-w-0 space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <SegmentedPills<PreviewMode>
                options={[
                  { id: "markdown", label: "MD preview" },
                  { id: "typst", label: "Typst" },
                  { id: "pdf", label: "PDF" },
                ]}
                value={previewMode}
                onChange={setPreviewMode}
              />
              {previewMode === "typst" && (
                <Button size="sm" variant="secondary" disabled={!typst.trim() || compileBusy} onClick={() => void compilePdf()}>
                  {compileBusy ? "Compiling…" : "Save PDF"}
                </Button>
              )}
              {previewMode === "pdf" && (
                <Button size="sm" variant="secondary" disabled={!typst.trim() || pdfPreviewBusy} onClick={() => void previewPdf()}>
                  {pdfPreviewBusy ? "Rendering…" : "Render PDF"}
                </Button>
              )}
            </div>
            <div className="max-h-[440px] min-h-[280px] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-3 text-[13px]">
              {previewMode === "markdown" ? (
                markdown.trim() ? (
                  <SimpleMarkdown content={markdown} />
                ) : (
                  <p className="text-[12px] text-[var(--color-text-light)]">Nothing to preview yet.</p>
                )
              ) : previewMode === "pdf" ? (
                pdfPreviewUrl ? (
                  <iframe
                    title="Resume PDF preview"
                    src={pdfPreviewUrl}
                    className="h-[400px] w-full rounded border-0 bg-white"
                  />
                ) : (
                  <p className="text-[12px] text-[var(--color-text-light)]">
                    Click Render PDF to compile Typst in-pane (requires local typst CLI).
                  </p>
                )
              ) : typst.trim() ? (
                <>
                  <p className="mb-2 text-[11px] text-[var(--color-text-light)]">
                    Formatted Typst source — compile PDF for print layout.
                  </p>
                  <pre className="font-mono text-[11px] leading-relaxed whitespace-pre-wrap text-[var(--color-text-main)]">
                    {typst}
                  </pre>
                </>
              ) : (
                <p className="text-[12px] text-[var(--color-text-light)]">Nothing to preview yet.</p>
              )}
            </div>
          </div>
        </div>
      )}
    </AppCard>
  );
}
