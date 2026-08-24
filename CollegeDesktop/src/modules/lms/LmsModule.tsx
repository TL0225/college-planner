import { useCallback, useEffect, useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  ModalSheet,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";
import {
  extractLmsPageItems,
  lmsWindowGoBack,
  lmsWindowGoForward,
  lmsWindowReload,
  lmsWindowFind,
  openLmsCollegeWindow,
} from "@/modules/lms/LmsCollegeWindow";
import type { LmsExtractedItem } from "@/modules/lms/lmsBridgeScript";

type Portal = {
  id: string;
  name: string;
  url: string;
  notes: string;
  sortOrder: number;
};

function hostFromUrl(url: string): string {
  try {
    const href = url.startsWith("http") ? url : `https://${url}`;
    return new URL(href).hostname.replace(/^www\./, "");
  } catch {
    return url.replace(/^https?:\/\//, "").split("/")[0] || url;
  }
}

function portalKind(url: string, name: string): { label: string; tint: string } {
  const hay = `${url} ${name}`.toLowerCase();
  if (hay.includes("canvas")) return { label: "Canvas", tint: "#e11d48" };
  if (hay.includes("blackboard") || hay.includes("bb."))
    return { label: "Blackboard", tint: "#000000" };
  if (hay.includes("moodle")) return { label: "Moodle", tint: "#f59e0b" };
  if (hay.includes("brightspace") || hay.includes("d2l"))
    return { label: "Brightspace", tint: "#0ea5e9" };
  return { label: "Portal", tint: "var(--color-primary)" };
}

function portalHref(url: string): string {
  return url.startsWith("http") ? url : `https://${url}`;
}

export function LmsModule() {
  const [portals, setPortals] = useState<Portal[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [embedPreview, setEmbedPreview] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState({ name: "", url: "https://", notes: "" });
  const [credUser, setCredUser] = useState("");
  const [credPass, setCredPass] = useState("");
  const [credHasPassword, setCredHasPassword] = useState(false);
  const [credBusy, setCredBusy] = useState(false);
  const [autofillBusy, setAutofillBusy] = useState(false);
  const [importSheet, setImportSheet] = useState(false);
  const [importBusy, setImportBusy] = useState(false);
  const [extractBusy, setExtractBusy] = useState(false);
  const [importItems, setImportItems] = useState<LmsExtractedItem[]>([]);
  const [selectedImport, setSelectedImport] = useState<Set<number>>(new Set());
  const [findQuery, setFindQuery] = useState("");
  const [findBusy, setFindBusy] = useState(false);
  const [defaultPortalUrl, setDefaultPortalUrl] = useState("");

  const load = useCallback(async () => {
    setPortals(await ipc.lmsListPortals());
  }, []);

  const { refresh, error } = useLiveQuery(load, ["lms"]);
  const selectedPortal = portals.find((p) => p.id === selected) ?? null;

  useEffect(() => {
    void ipc.settingsGet().then((s) => {
      setDefaultPortalUrl(s.values["lms.defaultPortalUrl"]?.trim() || "");
    });
  }, []);

  useEffect(() => {
    setEmbedPreview(false);
  }, [selected]);

  const openAdd = () => {
    setEditingId(null);
    setForm({
      name: "",
      url: defaultPortalUrl || "https://",
      notes: "",
    });
    setCredUser("");
    setCredPass("");
    setCredHasPassword(false);
    setSheetOpen(true);
  };

  const openEdit = (p: Portal) => {
    setEditingId(p.id);
    setForm({ name: p.name, url: p.url, notes: p.notes });
    setCredUser("");
    setCredPass("");
    setCredHasPassword(false);
    setSheetOpen(true);
    void ipc.lmsPortalCredentialsGet(p.id).then((c) => {
      setCredUser(c.username);
      setCredHasPassword(c.hasPassword);
    });
  };

  const openPortal = async (url: string) => {
    const href = portalHref(url);
    try {
      await openUrl(href);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const openInCollegeWindow = async (portal: Portal) => {
    await openLmsCollegeWindow({
      portalId: portal.id,
      name: portal.name,
      url: portal.url,
    });
  };

  const scanPageForImport = async (portal: Portal) => {
    setExtractBusy(true);
    try {
      await openInCollegeWindow(portal);
      const result = await extractLmsPageItems(portal.id);
      if (!result) return;
      setImportItems(result.items);
      setSelectedImport(new Set(result.items.map((_, i) => i)));
      setImportSheet(true);
      if (result.items.length === 0) {
        showToast("No importable items on this page — try an assignments or announcements view", "error");
      }
    } finally {
      setExtractBusy(false);
    }
  };

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title="LMS"
        actions={
          <div className="flex gap-2">
            {defaultPortalUrl && (
              <Button
                size="sm"
                variant="secondary"
                onClick={() => void openPortal(defaultPortalUrl)}
              >
                Open default
              </Button>
            )}
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            <Button size="sm" onClick={openAdd}>
              Add portal
            </Button>
          </div>
        }
      />
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}
      <div className="min-h-0 flex-1 overflow-hidden p-3 pt-1">
        <TrailingInspector
          open={Boolean(selectedPortal)}
          main={
            <AppCard title={`Course portals · ${portals.length}`} className="h-full overflow-auto">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Save Canvas, Blackboard, or school portal links. Open in your browser for SSO, in a
                dedicated College window, or try an optional embedded preview when a portal is
                selected.
              </p>
              {portals.length === 0 ? (
                <EmptyState
                  title="No portals yet"
                  body="Add your LMS URL, or load sample data from Settings."
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {portals.map((p) => {
                    const kind = portalKind(p.url, p.name);
                    return (
                      <li key={p.id}>
                        <ListRow
                          selected={selected === p.id}
                          onClick={() => setSelected(p.id)}
                          leading={
                            <span
                              className="flex h-8 w-8 shrink-0 items-center justify-center text-[11px] font-bold tracking-wide"
                              style={{
                                borderRadius: 8,
                                border: "1px solid var(--color-chrome-stroke)",
                                background: `color-mix(in srgb, ${kind.tint} 14%, var(--color-surface))`,
                                color: kind.tint === "#000000" ? "var(--color-text-main)" : kind.tint,
                              }}
                            >
                              {kind.label.slice(0, 2).toUpperCase()}
                            </span>
                          }
                          title={p.name}
                          subtitle={hostFromUrl(p.url)}
                          trailing={<StatusChip title={kind.label} tint={kind.tint} filled />}
                        />
                      </li>
                    );
                  })}
                </ul>
              )}
            </AppCard>
          }
        >
          {selectedPortal && (
            <div className="flex h-full flex-col">
              {(() => {
                const kind = portalKind(selectedPortal.url, selectedPortal.name);
                return (
                  <>
                    <div
                      className="border-b border-[var(--color-chrome-stroke)] px-4 py-3"
                      style={{
                        background: `linear-gradient(135deg, color-mix(in srgb, ${kind.tint} 12%, transparent), transparent)`,
                      }}
                    >
                      <h3
                        className="text-[var(--color-text-main)]"
                        style={{
                          font: "var(--type-section-title)",
                          fontSize: 16,
                          letterSpacing: "-0.02em",
                        }}
                      >
                        {selectedPortal.name}
                      </h3>
                      <p className="mt-0.5 break-all text-[12px] text-[var(--color-text-light)]">
                        {selectedPortal.url}
                      </p>
                      <div className="mt-2 flex flex-wrap gap-1.5">
                        <StatusChip title={kind.label} tint={kind.tint} filled />
                        <StatusChip title={hostFromUrl(selectedPortal.url)} />
                        {embedPreview && <StatusChip title="Embedded preview" tint="var(--color-primary)" />}
                      </div>
                    </div>
                    <div className="min-h-0 flex-1 overflow-auto p-4">
                      <p className="text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                        Notes
                      </p>
                      <p className="mt-1.5 text-[12px] leading-relaxed text-[var(--color-text-main)]">
                        {selectedPortal.notes || "No notes — SSO tips or course codes can go here."}
                      </p>
                      {embedPreview && (
                        <div className="mt-4 flex min-h-[220px] flex-col gap-3">
                          <iframe
                            src={portalHref(selectedPortal.url)}
                            sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
                            title={`Preview: ${selectedPortal.name}`}
                            className="min-h-[200px] w-full flex-1 rounded-[10px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)]"
                          />
                          <EmptyState
                            title="Preview may be blank"
                            body="If blank, use Open in browser (SSO)."
                          />
                        </div>
                      )}
                    </div>
                    <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                      <Button size="sm" onClick={() => void openPortal(selectedPortal.url)}>
                        Open in browser
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => void openInCollegeWindow(selectedPortal)}
                      >
                        Open in College window
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        disabled={autofillBusy}
                        onClick={async () => {
                          setAutofillBusy(true);
                          try {
                            await openInCollegeWindow(selectedPortal);
                            const res = await ipc.lmsPortalAutofillLogin(selectedPortal.id);
                            if (!res.filledUsername && !res.filledPassword) {
                              showToast("No login fields found on this page", "error");
                            } else {
                              showToast(
                                `Filled ${[
                                  res.filledUsername ? "username" : null,
                                  res.filledPassword ? "password" : null,
                                ]
                                  .filter(Boolean)
                                  .join(" + ")}`,
                                "success",
                              );
                            }
                          } catch (e) {
                            showToast(formatIpcError(e), "error");
                          } finally {
                            setAutofillBusy(false);
                          }
                        }}
                      >
                        {autofillBusy ? "Filling…" : "Autofill login"}
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        disabled={extractBusy}
                        onClick={() => void scanPageForImport(selectedPortal)}
                      >
                        {extractBusy ? "Scanning…" : "Scan page for import"}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => void lmsWindowGoBack(selectedPortal.id)}
                      >
                        ← Back
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => void lmsWindowGoForward(selectedPortal.id)}
                      >
                        Forward →
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => void lmsWindowReload(selectedPortal.id)}
                      >
                        Reload
                      </Button>
                      <div className="flex min-w-[200px] flex-1 items-center gap-1.5">
                        <input
                          className={`${fieldControlClass} min-w-0 flex-1 py-1.5 text-[12px]`}
                          placeholder="Find in page…"
                          value={findQuery}
                          onChange={(e) => setFindQuery(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === "Enter" && selectedPortal) {
                              e.preventDefault();
                              setFindBusy(true);
                              void lmsWindowFind(selectedPortal.id, findQuery, !e.shiftKey).finally(
                                () => setFindBusy(false),
                              );
                            }
                          }}
                        />
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={findBusy || !findQuery.trim()}
                          onClick={() => {
                            if (!selectedPortal) return;
                            setFindBusy(true);
                            void lmsWindowFind(selectedPortal.id, findQuery, true).finally(() =>
                              setFindBusy(false),
                            );
                          }}
                        >
                          Find
                        </Button>
                      </div>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => setEmbedPreview((on) => !on)}
                      >
                        {embedPreview ? "Hide preview" : "Preview in app"}
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => openEdit(selectedPortal)}
                      >
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="danger"
                        onClick={async () => {
                          if (!confirmDelete(selectedPortal.name)) return;
                          try {
                            await ipc.lmsDeletePortal(selectedPortal.id);
                            setSelected(null);
                            showToast("Portal deleted", "success");
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
                  </>
                );
              })()}
            </div>
          )}
        </TrailingInspector>
      </div>

      <ModalSheet
        open={sheetOpen}
        onOpenChange={setSheetOpen}
        title={editingId ? "Edit portal" : "Add portal"}
      >
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Canvas"
            />
          </FormField>
          <FormField label="URL">
            <input
              className={fieldControlClass}
              value={form.url}
              onChange={(e) => setForm({ ...form, url: e.target.value })}
              placeholder="https://…"
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={form.notes}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
              placeholder="SSO tips, course codes…"
            />
          </FormField>
          <FormField label="Portal username (Keychain)">
            <input
              className={fieldControlClass}
              autoComplete="username"
              value={credUser}
              onChange={(e) => setCredUser(e.target.value)}
              placeholder="netid@school.edu"
            />
          </FormField>
          <FormField
            label={
              credHasPassword && !credPass
                ? "Portal password (saved — leave blank to keep)"
                : "Portal password (Keychain)"
            }
          >
            <input
              className={fieldControlClass}
              type="password"
              autoComplete="current-password"
              value={credPass}
              onChange={(e) => setCredPass(e.target.value)}
              placeholder="••••••••"
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!form.name.trim() || !form.url.trim() || credBusy}
              onClick={async () => {
                setCredBusy(true);
                try {
                  const id = await ipc.lmsUpsertPortal({
                    id: editingId ?? undefined,
                    name: form.name.trim(),
                    url: form.url.trim(),
                    notes: form.notes.trim() || undefined,
                  });
                  if (credUser.trim() || credPass) {
                    await ipc.lmsPortalCredentialsSet({
                      portalId: id,
                      username: credUser.trim(),
                      password: credPass,
                    });
                  }
                  setSheetOpen(false);
                  showToast(editingId ? "Portal updated" : "Portal saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                } finally {
                  setCredBusy(false);
                }
              }}
            >
              {credBusy ? "Saving…" : "Save"}
            </Button>
            {editingId && (credUser || credHasPassword) && (
              <Button
                variant="ghost"
                disabled={credBusy}
                onClick={async () => {
                  if (!editingId) return;
                  try {
                    await ipc.lmsPortalCredentialsClear(editingId);
                    setCredUser("");
                    setCredPass("");
                    setCredHasPassword(false);
                    showToast("Saved login cleared", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Clear login
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={importSheet}
        onOpenChange={setImportSheet}
        title="Import from LMS page"
      >
        <div className="space-y-3">
          <p className="text-[12px] text-[var(--color-text-light)]">
            Assignments become planner tasks; announcements become calendar events.
          </p>
          {importItems.length === 0 ? (
            <EmptyState title="Nothing to import" body="Navigate to assignments or announcements in the College window, then scan again." />
          ) : (
            <ul className="max-h-64 divide-y divide-[var(--color-chrome-stroke)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)]">
              {importItems.map((item, idx) => (
                <li key={`${item.lmsItemId ?? item.title}-${idx}`}>
                  <label className="flex cursor-pointer items-start gap-2 px-3 py-2">
                    <input
                      type="checkbox"
                      checked={selectedImport.has(idx)}
                      onChange={(e) => {
                        setSelectedImport((prev) => {
                          const next = new Set(prev);
                          if (e.target.checked) next.add(idx);
                          else next.delete(idx);
                          return next;
                        });
                      }}
                      className="mt-1"
                    />
                    <span>
                      <span className="block text-[13px] font-medium text-[var(--color-text-main)]">
                        {item.title}
                      </span>
                      <span className="text-[11px] text-[var(--color-text-light)]">
                        {item.kind}
                        {item.courseCode ? ` · ${item.courseCode}` : ""}
                        {item.dueAt ? ` · due ${new Date(item.dueAt).toLocaleDateString()}` : ""}
                      </span>
                    </span>
                  </label>
                </li>
              ))}
            </ul>
          )}
          <Button
            disabled={importBusy || selectedImport.size === 0}
            onClick={async () => {
              setImportBusy(true);
              try {
                const payload = importItems
                  .filter((_, idx) => selectedImport.has(idx))
                  .map((item) => ({
                    kind: item.kind,
                    title: item.title,
                    dueAt: item.dueAt ?? undefined,
                    courseCode: item.courseCode ?? undefined,
                    notes: item.notes ?? undefined,
                    lmsItemId: item.lmsItemId ?? undefined,
                    portalId: selectedPortal?.id,
                  }));
                const res = await ipc.lmsImportItems(payload);
                setImportSheet(false);
                showToast(
                  `Imported ${res.tasksCreated} task(s), ${res.eventsCreated} event(s)`,
                  "success",
                );
              } catch (e) {
                showToast(formatIpcError(e), "error");
              } finally {
                setImportBusy(false);
              }
            }}
          >
            {importBusy ? "Importing…" : `Import ${selectedImport.size} item(s)`}
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}
