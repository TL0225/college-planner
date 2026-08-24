import { useCallback, useEffect, useMemo, useState, type CSSProperties } from "react";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { check } from "@tauri-apps/plugin-updater";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  ListRow,
  MetricTile,
  StatusChip,
  FormField,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError, type PlatformInfo, type StoragePaths, type AiRuntimeStatus } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";

export type SettingsPage =
  | "profile"
  | "academics"
  | "calendar"
  | "assistant"
  | "documents"
  | "finance"
  | "discovery"
  | "career"
  | "lms"
  | "shortcuts"
  | "app"
  | "privacy";

const PAGE_TITLES: Record<SettingsPage, string> = {
  profile: "Profile",
  academics: "Academics",
  calendar: "Calendar",
  assistant: "Assistant",
  documents: "Documents",
  finance: "Finance",
  discovery: "Discovery",
  career: "Career",
  lms: "LMS",
  shortcuts: "Shortcuts",
  app: "App",
  privacy: "Privacy & Security",
};

const insetPanelStyle: CSSProperties = {
  borderRadius: 10,
  border: "1px solid var(--color-chrome-stroke)",
  background: "var(--color-content-surface)",
  boxShadow: "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
};

const TAURI_PARITY_MODULES: Array<{ name: string; ready: boolean; note?: string }> = [
  { name: "Academics", ready: true, note: "Planner DnD, program browser, GPA sheets" },
  { name: "Calendar", ready: true, note: "Edit, OAuth, ICS, Apple Calendar feed handoff" },
  { name: "Career", ready: true, note: "Apply Tier A–C + company GH/WD/Lever/Oracle/iCIMS/Talemetry boards" },
  { name: "Documents", ready: true, note: "Watchdog folders, Quick Look, DnD, cascade delete" },
  { name: "Finance connections", ready: true, note: "Local credentials + manual sync settings" },
  { name: "Discovery", ready: true, note: "School profile + CDS" },
  { name: "Assistant", ready: true, note: "~55 tools — full Swift FM registry parity (keyword planner)" },
  { name: "Finance", ready: true, note: "Goals, stock/crypto holdings, reports, donut charts" },
  { name: "Profile", ready: true, note: "Portfolio projects CRUD, advisor prep, experiences" },
  { name: "Resume", ready: true, note: "Live builder, section DnD, Typst/PDF export" },
  { name: "Catalog", ready: true, note: "Ingest, sync pipeline, semantic search" },
  { name: "Transfer", ready: true, note: "ASSIST import, community JSON, proof docs" },
  { name: "LMS", ready: true, note: "College window + bridge inject + scan/find + Keychain login autofill" },
  { name: "Settings", ready: true, note: "11 sections incl. OAuth sync-all + LMS defaults + parity panel" },
  { name: "Overview hub", ready: true, note: "Week ahead, deadlines, quick launch, advisor prep" },
  { name: "MapKit geocode", ready: true, note: "Nominatim + deep links" },
  { name: "Calendar OAuth", ready: true, note: "PKCE + Keychain + pull sync-all + push local events (EventKit write substitute)" },
  { name: "Bundled ONNX", ready: true, note: "onnx-local when models/*.onnx present; Ollama/OpenAI-compat primary" },
];

function themeLabel(value: string | undefined): string {
  switch (value) {
    case "light":
      return "Light";
    case "dark":
      return "Dark";
    default:
      return "System";
  }
}

function aiReadyCount(ai: AiRuntimeStatus | null): { ready: number; total: number } {
  if (!ai) return { ready: 0, total: 2 };
  let ready = 0;
  if (ai.embeddingsReady) ready += 1;
  if (ai.llmReady) ready += 1;
  return { ready, total: 2 };
}

function StatusNote({ children }: { children: React.ReactNode }) {
  return (
    <p
      className="mt-2 px-2.5 py-2 text-[11px] leading-relaxed text-[var(--color-text-light)]"
      style={insetPanelStyle}
    >
      {children}
    </p>
  );
}

export function SettingsModule({ page }: { page: SettingsPage }) {
  const [platform, setPlatform] = useState<PlatformInfo | null>(null);
  const [paths, setPaths] = useState<StoragePaths | null>(null);
  const [ai, setAi] = useState<AiRuntimeStatus | null>(null);
  const [settings, setSettings] = useState<Record<string, string>>({});
  const [locked, setLocked] = useState(false);
  const [seedStatus, setSeedStatus] = useState<string | null>(null);
  const [scrapeUrl, setScrapeUrl] = useState("https://example.com");
  const [scrapeStatus, setScrapeStatus] = useState<string | null>(null);
  const [backups, setBackups] = useState<
    Array<{ name: string; path: string; sizeBytes: number; modifiedAt: string }>
  >([]);
  const [backupNote, setBackupNote] = useState<string | null>(null);
  const [updateNote, setUpdateNote] = useState<string | null>(null);
  const [typstAvailable, setTypstAvailable] = useState<boolean | null>(null);
  const [exportNote, setExportNote] = useState<string | null>(null);
  const [catalogSyncRows, setCatalogSyncRows] = useState<
    Array<{
      id: string;
      name: string;
      courseCount: number;
      lastSyncedAt?: string | null;
      lastError?: string | null;
    }>
  >([]);
  const [syncBusyId, setSyncBusyId] = useState<string | null>(null);
  const [shortcutDraft, setShortcutDraft] = useState({ title: "", url: "" });
  const [watchedFolders, setWatchedFolders] = useState<
    Array<{ id: string; path: string; addedAt: string }>
  >([]);
  const [watchedFolderDraft, setWatchedFolderDraft] = useState("");
  const [watchdogStatus, setWatchdogStatus] = useState<{
    isWatching: boolean;
    watchedCount: number;
    lastDetectedPath: string | null;
    lastDetectedAt: string | null;
  } | null>(null);
  const [staleThresholdDays, setStaleThresholdDays] = useState("7");
  const [financeCategories, setFinanceCategories] = useState<
    Array<{ id: string; name: string; kind: string; sortOrder: number }>
  >([]);
  const [financeDue, setFinanceDue] = useState<
    Array<{ id: string; person: string; amount: number; dueAt: string; isPaid: boolean }>
  >([]);
  const [discoverySyncNote, setDiscoverySyncNote] = useState<string | null>(null);
  const [coinbaseSyncNote, setCoinbaseSyncNote] = useState<string | null>(null);
  const [coinbaseSyncBusy, setCoinbaseSyncBusy] = useState(false);
  const [catalogEmbedStats, setCatalogEmbedStats] = useState<{
    indexedCount: number;
    courseCount: number;
    modelTag: string;
  } | null>(null);
  const [catalogReindexNote, setCatalogReindexNote] = useState<string | null>(null);
  const [catalogReindexBusy, setCatalogReindexBusy] = useState(false);
  const [assistantTools, setAssistantTools] = useState<
    Array<{ name: string; description: string; category: string }>
  >([]);
  const [toolsExpanded, setToolsExpanded] = useState(false);

  const load = useCallback(async () => {
    const [p, path, a, s, l, b, typst, sync, embedStats] = await Promise.all([
      ipc.getPlatformInfo(),
      ipc.getStoragePaths(),
      ipc.aiRuntimeStatus(),
      ipc.settingsGet(),
      ipc.securityIsLocked(),
      ipc.backupList().catch(() => []),
      ipc.platformTypstAvailable().catch(() => false),
      ipc.catalogGetSyncDiagnostics().catch(() => ({ universities: [] })),
      ipc.catalogEmbeddingStats().catch(() => null),
    ]);
    setPlatform(p);
    setPaths(path);
    setAi(a);
    setSettings(s.values);
    setLocked(l);
    setBackups(b);
    setTypstAvailable(typst);
    setCatalogSyncRows(sync.universities);
    setCatalogEmbedStats(embedStats);
  }, []);

  const { refresh, error } = useLiveQuery(load);

  const aiReady = useMemo(() => aiReadyCount(ai), [ai]);
  const theme = settings["ui.theme"] || "system";
  const reduceMotion = settings["ui.reduceMotion"] === "true";
  const dueNotifications = settings["notify.dueItems"] !== "false";
  const googleClientId = settings["oauth.google.clientId"] ?? "";
  const outlookClientId = settings["oauth.outlook.clientId"] ?? "";
  const oauthConfigured = Boolean(googleClientId || outlookClientId);
  const ollamaReachable = ai?.pingOk === true;
  const dataExported = backups.length > 0;
  const [oauthDraft, setOauthDraft] = useState({
    googleClientId: "",
    googleClientSecret: "",
    outlookClientId: "",
    outlookTenant: "common",
  });
  const [oauthNote, setOauthNote] = useState<string | null>(null);

  type WebShortcut = { id: string; title: string; url: string };
  const shortcuts: WebShortcut[] = useMemo(() => {
    try {
      const raw = settings["web.shortcuts.v1"];
      if (!raw) return [];
      const parsed = JSON.parse(raw) as WebShortcut[];
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }, [settings]);

  const saveShortcuts = async (next: WebShortcut[]) => {
    await ipc.settingsSet("web.shortcuts.v1", JSON.stringify(next));
    await refresh();
  };

  useEffect(() => {
    if (page !== "documents") return;
    void ipc.documentsListWatchedFolders().then(setWatchedFolders).catch(() => setWatchedFolders([]));
    void ipc.documentsWatchdogStatus().then(setWatchdogStatus).catch(() => setWatchdogStatus(null));
    setStaleThresholdDays(settings["documents.staleThresholdDays"] ?? "7");
  }, [page, settings["documents.staleThresholdDays"]]);

  useEffect(() => {
    if (page !== "documents") return;
    const timer = window.setInterval(() => {
      void ipc.documentsWatchdogStatus().then(setWatchdogStatus).catch(() => setWatchdogStatus(null));
    }, 5000);
    return () => window.clearInterval(timer);
  }, [page]);

  useEffect(() => {
    if (page !== "finance") return;
    void ipc.financeListCategories().then(setFinanceCategories).catch(() => setFinanceCategories([]));
    void ipc.financeListDue().then(setFinanceDue).catch(() => setFinanceDue([]));
  }, [page]);

  useEffect(() => {
    if (page !== "assistant") return;
    void ipc.assistantListTools().then(setAssistantTools).catch(() => setAssistantTools([]));
  }, [page]);

  useEffect(() => {
    setOauthDraft({
      googleClientId: settings["oauth.google.clientId"] ?? "",
      googleClientSecret: settings["oauth.google.clientSecret"] ?? "",
      outlookClientId: settings["oauth.outlook.clientId"] ?? "",
      outlookTenant: settings["oauth.outlook.tenant"] || "common",
    });
  }, [
    settings["oauth.google.clientId"],
    settings["oauth.google.clientSecret"],
    settings["oauth.outlook.clientId"],
    settings["oauth.outlook.tenant"],
  ]);

  const setPref = async (key: string, value: string) => {
    await ipc.settingsSet(key, value);
    setSettings((prev) => ({ ...prev, [key]: value }));
    window.dispatchEvent(new CustomEvent("college:settings", { detail: { key, value } }));
  };

  const sectionContent = (() => {
    switch (page) {
      case "profile":
        return (
          <AppCard title="Identity & profile">
            <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
              Name, school, major, and experiences live in the Profile module — not here. Use Profile
              → Identity to edit how College represents you across Academics, Career, and Assistant.
            </p>
            <StatusNote>
              Shortcut: ⌘7 opens Profile. Experiences and achievements have their own sidebar pages
              under Profile.
            </StatusNote>
          </AppCard>
        );

      case "academics":
        return (
          <>
            <AppCard title="Sample data">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Load demo planner, catalog courses, requirements, transfer maps, calendar, career,
                finance, vault, discovery, and profile rows.
              </p>
              <Button
                size="sm"
                onClick={async () => {
                  setSeedStatus("Seeding…");
                  try {
                    await ipc.demoSeedSampleData();
                    setSeedStatus(
                      "Loaded. Try Academics → Requirements, Catalog, or Finance → Budgets.",
                    );
                  } catch (e) {
                    setSeedStatus(formatIpcError(e));
                  }
                }}
              >
                Load sample data
              </Button>
              {seedStatus && <StatusNote>{seedStatus}</StatusNote>}
            </AppCard>

            <AppCard title="Scraper connectivity">
              <div className="mb-2 flex gap-2">
                <input
                  className={fieldControlClass}
                  value={scrapeUrl}
                  onChange={(e) => setScrapeUrl(e.target.value)}
                />
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    setScrapeStatus("Fetching…");
                    try {
                      const res = await ipc.scraperFetchHtmlPreview(scrapeUrl.trim());
                      setScrapeStatus(`HTTP ${res.status} · ${res.title || res.url}`);
                    } catch (e) {
                      setScrapeStatus(formatIpcError(e));
                    }
                  }}
                >
                  Test
                </Button>
              </div>
              {scrapeStatus ? (
                <div className="flex flex-wrap gap-1.5">
                  <StatusChip
                    title={scrapeStatus}
                    tint={
                      scrapeStatus.startsWith("HTTP")
                        ? "var(--color-success)"
                        : scrapeStatus === "Fetching…"
                          ? "var(--color-text-light)"
                          : "var(--color-error)"
                    }
                    filled
                  />
                </div>
              ) : (
                <EmptyState
                  title="Network check"
                  body="Validates the polite Rust scraper path used by Catalog ingest."
                />
              )}
            </AppCard>

            <AppCard title="Catalog programs">
              <p className="mb-2 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Comma-separated program codes to prioritize in Catalog browse (
                <code className="text-[11px]">catalog.selectedProgramIds.v1</code>).
              </p>
              <FormField label="Selected programs">
                <input
                  className={fieldControlClass}
                  value={settings["catalog.selectedProgramIds.v1"] ?? ""}
                  placeholder="BS-CS, BA-MATH, minor-DS"
                  onChange={(e) => void setPref("catalog.selectedProgramIds.v1", e.target.value)}
                />
              </FormField>
            </AppCard>

            <AppCard title="Catalog vector index">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Course embeddings power semantic search in Catalog. Reindex after large ingests or when
                you change the local AI / ONNX embedding backend (
                {catalogEmbedStats?.modelTag ?? "—"}).
              </p>
              <div className="mb-3 flex flex-wrap gap-2">
                <MetricTile
                  label="Indexed"
                  value={
                    catalogEmbedStats
                      ? `${catalogEmbedStats.indexedCount} / ${catalogEmbedStats.courseCount}`
                      : "—"
                  }
                />
              </div>
              <Button
                size="sm"
                disabled={catalogReindexBusy}
                onClick={async () => {
                  setCatalogReindexBusy(true);
                  setCatalogReindexNote("Reindexing…");
                  try {
                    const res = await ipc.catalogReindexEmbeddings(500);
                    setCatalogReindexNote(
                      `Indexed ${res.indexed} courses (${res.modelTag})`,
                    );
                    setCatalogEmbedStats(await ipc.catalogEmbeddingStats());
                    showToast(`Indexed ${res.indexed} catalog courses`, "success");
                  } catch (e) {
                    setCatalogReindexNote(formatIpcError(e));
                    showToast(formatIpcError(e), "error");
                  } finally {
                    setCatalogReindexBusy(false);
                  }
                }}
              >
                {catalogReindexBusy ? "Reindexing…" : "Reindex embeddings"}
              </Button>
              {catalogReindexNote ? (
                <p className="mt-2 text-[12px] text-[var(--color-text-light)]">{catalogReindexNote}</p>
              ) : null}
            </AppCard>

            <AppCard title="Catalog sync diagnostics">
              {catalogSyncRows.length === 0 ? (
                <EmptyState
                  title="No universities"
                  body="Load sample data or add schools in Catalog to see sync status."
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {catalogSyncRows.map((row) => (
                    <li key={row.id} className="flex flex-wrap items-center gap-2 py-2">
                      <div className="min-w-0 flex-1">
                        <ListRow
                          title={row.name}
                          subtitle={`${row.courseCount} courses${
                            row.lastSyncedAt
                              ? ` · synced ${new Date(row.lastSyncedAt).toLocaleString()}`
                              : ""
                          }`}
                        />
                        {row.lastError ? (
                          <p className="mt-1 text-[11px] text-[var(--color-error)]">{row.lastError}</p>
                        ) : null}
                      </div>
                      <Button
                        size="sm"
                        variant="secondary"
                        disabled={syncBusyId === row.id}
                        onClick={async () => {
                          setSyncBusyId(row.id);
                          try {
                            await ipc.catalogSyncUniversity({ universityId: row.id, force: false });
                            await refresh();
                            showToast(`Synced ${row.name}`, "success");
                          } catch (e) {
                            showToast(formatIpcError(e), "error");
                          } finally {
                            setSyncBusyId(null);
                          }
                        }}
                      >
                        Sync
                      </Button>
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
          </>
        );

      case "calendar":
        return (
          <AppCard title="Calendar OAuth">
            <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
              Paste OAuth Client IDs from Google Cloud Console or Azure App Registration. Secrets stay
              in local app settings (not committed). Register redirect URI{" "}
              <code className="text-[11px]">http://127.0.0.1:&lt;port&gt;/oauth/callback</code> as a
              loopback / native redirect.
            </p>
            <div className="space-y-3">
              <FormField label="Google Client ID">
                <input
                  className={fieldControlClass}
                  value={oauthDraft.googleClientId}
                  onChange={(e) =>
                    setOauthDraft((d) => ({ ...d, googleClientId: e.target.value }))
                  }
                  placeholder="123456789.apps.googleusercontent.com"
                  autoComplete="off"
                />
              </FormField>
              <FormField label="Google Client Secret (optional for PKCE)">
                <input
                  className={fieldControlClass}
                  type="password"
                  value={oauthDraft.googleClientSecret}
                  onChange={(e) =>
                    setOauthDraft((d) => ({ ...d, googleClientSecret: e.target.value }))
                  }
                  autoComplete="off"
                />
              </FormField>
              <FormField label="Outlook Client ID">
                <input
                  className={fieldControlClass}
                  value={oauthDraft.outlookClientId}
                  onChange={(e) =>
                    setOauthDraft((d) => ({ ...d, outlookClientId: e.target.value }))
                  }
                  placeholder="Azure application (client) ID"
                  autoComplete="off"
                />
              </FormField>
              <FormField label="Outlook tenant">
                <input
                  className={fieldControlClass}
                  value={oauthDraft.outlookTenant}
                  onChange={(e) =>
                    setOauthDraft((d) => ({ ...d, outlookTenant: e.target.value || "common" }))
                  }
                  placeholder="common"
                  autoComplete="off"
                />
              </FormField>
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <Button
                size="sm"
                onClick={async () => {
                  setOauthNote("Saving…");
                  try {
                    await Promise.all([
                      setPref("oauth.google.clientId", oauthDraft.googleClientId.trim()),
                      setPref("oauth.google.clientSecret", oauthDraft.googleClientSecret.trim()),
                      setPref("oauth.outlook.clientId", oauthDraft.outlookClientId.trim()),
                      setPref(
                        "oauth.outlook.tenant",
                        oauthDraft.outlookTenant.trim() || "common",
                      ),
                    ]);
                    setOauthNote("OAuth credentials saved.");
                    showToast("OAuth credentials saved", "success");
                  } catch (e) {
                    setOauthNote(formatIpcError(e));
                  }
                }}
              >
                Save OAuth credentials
              </Button>
              <Button
                size="sm"
                variant="secondary"
                onClick={async () => {
                  setOauthNote("Syncing…");
                  try {
                    const res = await ipc.calendarOauthSyncAll();
                    if (res.accounts === 0) {
                      setOauthNote("No connected accounts — connect Google/Outlook in Calendar → Sources.");
                      return;
                    }
                    const err = res.errors.length ? ` Errors: ${res.errors.join("; ")}` : "";
                    setOauthNote(
                      `Synced ${res.imported} events from ${res.accounts} account(s).${err}`,
                    );
                    showToast(`Synced ${res.imported} events`, res.errors.length ? "error" : "success");
                  } catch (e) {
                    setOauthNote(formatIpcError(e));
                  }
                }}
              >
                Sync connected calendars
              </Button>
              <StatusChip
                title={
                  googleClientId || outlookClientId
                    ? `${googleClientId ? "Google" : ""}${googleClientId && outlookClientId ? " · " : ""}${outlookClientId ? "Outlook" : ""} configured`
                    : "No credentials yet"
                }
                tint={
                  googleClientId || outlookClientId
                    ? "var(--color-success)"
                    : "var(--color-warning)"
                }
                filled={Boolean(googleClientId || outlookClientId)}
              />
            </div>
            {oauthNote && <StatusNote>{oauthNote}</StatusNote>}
          </AppCard>
        );

      case "assistant":
        return (
          <AppCard title="AI runtime">
            <div className="mb-3 space-y-2 text-[13px]">
              <label className="block px-0.5 text-[11px] font-medium text-[var(--color-text-light)]">
                Base URL
              </label>
              <input
                className={fieldControlClass}
                value={settings["ai.baseUrl"] ?? "http://127.0.0.1:11434/v1"}
                placeholder="http://127.0.0.1:11434/v1"
                onChange={(e) => void setPref("ai.baseUrl", e.target.value)}
              />
              <label className="block px-0.5 text-[11px] font-medium text-[var(--color-text-light)]">
                API key (optional)
              </label>
              <input
                type="password"
                className={fieldControlClass}
                value={settings["ai.apiKey"] ?? ""}
                placeholder="sk-…"
                onChange={(e) => void setPref("ai.apiKey", e.target.value)}
              />
              <label className="block px-0.5 text-[11px] font-medium text-[var(--color-text-light)]">
                Model
              </label>
              <input
                className={fieldControlClass}
                value={settings["ai.model"] ?? "llama3.2"}
                placeholder="llama3.2"
                onChange={(e) => void setPref("ai.model", e.target.value)}
              />
              <div className="flex flex-wrap gap-2 pt-1">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    try {
                      const res = await ipc.aiPing();
                      setAi(await ipc.aiRuntimeStatus());
                      if (res.ok) {
                        showToast(res.message, "success");
                      } else {
                        showToast(res.message, "error");
                      }
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Test connection
                </Button>
              </div>
            </div>
            <ul className="divide-y divide-[var(--color-chrome-stroke)]">
              <li>
                <ListRow
                  title="Backend"
                  trailing={ai?.backend ? <StatusChip title={ai.backend} filled /> : "—"}
                />
              </li>
              <li>
                <ListRow
                  title="Model"
                  trailing={
                    ai?.model ? (
                      <StatusChip title={ai.model} tint="var(--color-primary)" filled />
                    ) : (
                      "—"
                    )
                  }
                />
              </li>
              <li>
                <ListRow
                  title="Embeddings"
                  trailing={
                    <StatusChip
                      title={ai?.embeddingsBackend ?? "—"}
                      tint={ai?.embeddingsReady ? "var(--color-success)" : "var(--color-warning)"}
                      filled
                    />
                  }
                />
              </li>
              <li>
                <ListRow
                  title="LLM"
                  trailing={
                    <StatusChip
                      title={ai?.llmReady ? "Ready" : "Fallback"}
                      tint={ai?.llmReady ? "var(--color-success)" : "var(--color-warning)"}
                      filled
                    />
                  }
                />
              </li>
              {ai?.onnxPathConfigured && (
                <li>
                  <ListRow
                    title="ONNX model"
                    trailing={
                      <StatusChip title="Path configured" tint="var(--color-primary)" filled />
                    }
                  />
                </li>
              )}
              {ai?.pingMessage && (
                <li>
                  <ListRow
                    title="Connection"
                    subtitle={ai.pingMessage}
                    trailing={
                      ai.pingOk === true ? (
                        <StatusChip title="Reachable" tint="var(--color-success)" filled />
                      ) : ai.pingOk === false ? (
                        <StatusChip title="Unreachable" tint="var(--color-error)" filled />
                      ) : (
                        <StatusChip title="Not tested" tint="var(--color-warning)" />
                      )
                    }
                  />
                </li>
              )}
            </ul>
            <p
              className="mt-2 truncate px-2.5 py-2 text-[11px] text-[var(--color-text-light)]"
              style={insetPanelStyle}
            >
              {ai?.modelDir ?? "—"}
            </p>
            <div className="mt-3">
              <button
                type="button"
                className="flex w-full items-center justify-between rounded-[10px] border border-[var(--color-chrome-stroke)] px-2.5 py-2 text-left text-[12px] font-medium text-[var(--color-text)]"
                style={insetPanelStyle}
                onClick={() => setToolsExpanded((v) => !v)}
              >
                <span>Tool registry ({assistantTools.length} tools)</span>
                <span className="text-[11px] text-[var(--color-text-light)]">
                  {toolsExpanded ? "Hide" : "Show"}
                </span>
              </button>
              {toolsExpanded && (
                <ul
                  className="mt-2 max-h-72 divide-y divide-[var(--color-chrome-stroke)] overflow-y-auto rounded-[10px] border border-[var(--color-chrome-stroke)]"
                  style={insetPanelStyle}
                >
                  {assistantTools.map((tool) => (
                    <li key={tool.name} className="px-2.5 py-2">
                      <p className="text-[12px] font-medium text-[var(--color-text)]">{tool.name}</p>
                      <p className="mt-0.5 text-[11px] leading-relaxed text-[var(--color-text-light)]">
                        {tool.description}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </AppCard>
        );

      case "documents":
        return (
          <>
            <AppCard title="File watchdog">
              <div className="mb-3 flex flex-wrap items-center gap-2">
                <StatusChip
                  title={watchdogStatus?.isWatching ? "Active" : "Inactive"}
                  tint={
                    watchdogStatus?.isWatching ? "var(--color-success)" : "var(--color-text-light)"
                  }
                  filled={watchdogStatus?.isWatching ?? false}
                />
                {watchdogStatus != null && (
                  <span className="text-[11px] text-[var(--color-text-light)]">
                    Watching {watchdogStatus.watchedCount} folder
                    {watchdogStatus.watchedCount === 1 ? "" : "s"}
                  </span>
                )}
              </div>
              {watchdogStatus?.lastDetectedPath && (
                <p
                  className="mb-3 truncate px-2.5 py-2 text-[11px] text-[var(--color-text-light)]"
                  style={insetPanelStyle}
                >
                  Last detected: {watchdogStatus.lastDetectedPath}
                  {watchdogStatus.lastDetectedAt
                    ? ` · ${new Date(watchdogStatus.lastDetectedAt).toLocaleString()}`
                    : ""}
                </p>
              )}
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Watched folders mirror Swift Documents settings — new files can be ingested into the
                vault when the desktop app scans them. On macOS, if{" "}
                <code className="text-[11px]">~/Library/Mobile Documents/com~apple~CloudDocs/College</code>{" "}
                exists, it is watched automatically for cloud-synced imports (no error when missing).
              </p>
              <div className="mb-3 flex flex-wrap gap-2">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    try {
                      const preview = await ipc.backgroundWeeklyDigestPreview();
                      showToast(preview.body, "success");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Preview weekly digest
                </Button>
              </div>
              <FormField label="Stale file threshold (days)">
                <input
                  className={fieldControlClass}
                  type="number"
                  min={1}
                  value={staleThresholdDays}
                  onChange={(e) => setStaleThresholdDays(e.target.value)}
                  onBlur={() => void setPref("documents.staleThresholdDays", staleThresholdDays)}
                />
              </FormField>
              {watchedFolders.length === 0 ? (
                <EmptyState title="No watched folders" body="Add a folder path to monitor." />
              ) : (
                <ul className="mb-3 divide-y divide-[var(--color-chrome-stroke)]">
                  {watchedFolders.map((f) => (
                    <li key={f.id} className="flex items-center justify-between gap-2 py-2">
                      <ListRow title={f.path} subtitle={new Date(f.addedAt).toLocaleString()} />
                      <Button
                        size="sm"
                        variant="danger"
                        onClick={async () => {
                          await ipc.documentsDeleteWatchedFolder(f.id);
                          setWatchedFolders(await ipc.documentsListWatchedFolders());
                          showToast("Folder removed", "success");
                        }}
                      >
                        Remove
                      </Button>
                    </li>
                  ))}
                </ul>
              )}
              <div className="flex flex-wrap gap-2">
                <input
                  className={`${fieldControlClass} min-w-[220px] flex-1`}
                  placeholder="/Users/you/Downloads"
                  value={watchedFolderDraft}
                  onChange={(e) => setWatchedFolderDraft(e.target.value)}
                />
                <Button
                  size="sm"
                  disabled={!watchedFolderDraft.trim()}
                  onClick={async () => {
                    await ipc.documentsUpsertWatchedFolder({ path: watchedFolderDraft.trim() });
                    setWatchedFolderDraft("");
                    setWatchedFolders(await ipc.documentsListWatchedFolders());
                    showToast("Folder added", "success");
                  }}
                >
                  Add folder
                </Button>
              </div>
            </AppCard>
            <AppCard title="Storage paths">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Vault files and document metadata live under Application Support. Lock/unlock the vault
                from Privacy & Security; browse files in Documents → Vault.
              </p>
              <div className="mb-2 flex flex-wrap gap-2">
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={!paths}
                  onClick={async () => {
                    if (!paths) return;
                    try {
                      await navigator.clipboard.writeText(JSON.stringify(paths, null, 2));
                      showToast("Paths copied", "success");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Copy paths
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={!paths?.root}
                  onClick={async () => {
                    if (!paths?.root) return;
                    try {
                      await revealItemInDir(paths.root);
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Show data folder
                </Button>
              </div>
              <pre
                className="overflow-x-auto whitespace-pre-wrap px-2.5 py-2 text-[11px] leading-relaxed text-[var(--color-text-light)]"
                style={insetPanelStyle}
              >
                {paths ? JSON.stringify(paths, null, 2) : "—"}
              </pre>
            </AppCard>
          </>
        );

      case "finance":
        return (
          <>
            <AppCard title="Finance connections">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Store connection credentials locally for manual sync workflows. OAuth bank linking uses
                the same keys as the Swift Finance connections panel.
              </p>
              <FormField label="Coinbase API key">
                <input
                  className={fieldControlClass}
                  type="password"
                  value={settings["finance.coinbase.apiKey"] ?? ""}
                  onChange={(e) => void setPref("finance.coinbase.apiKey", e.target.value)}
                  placeholder="Optional — holdings sync"
                />
              </FormField>
              <FormField label="Manual sync note">
                <input
                  className={fieldControlClass}
                  value={settings["finance.connections.note"] ?? ""}
                  onChange={(e) => void setPref("finance.connections.note", e.target.value)}
                  placeholder="e.g. Import CSV weekly from bank export"
                />
              </FormField>
              <div className="mt-3 flex flex-wrap items-center gap-2">
                <Button
                  size="sm"
                  disabled={coinbaseSyncBusy || !settings["finance.coinbase.apiKey"]?.trim()}
                  onClick={async () => {
                    setCoinbaseSyncBusy(true);
                    setCoinbaseSyncNote("Syncing Coinbase…");
                    try {
                      const res = await ipc.financeSyncCoinbase();
                      const errTail = res.error ? ` · ${res.error}` : "";
                      setCoinbaseSyncNote(
                        `Accounts ${res.accountsUpdated}, holdings ${res.holdingsUpdated}${errTail}`,
                      );
                      await refresh();
                      showToast("Coinbase sync finished", "success");
                    } catch (e) {
                      setCoinbaseSyncNote(formatIpcError(e));
                      showToast(formatIpcError(e), "error");
                    } finally {
                      setCoinbaseSyncBusy(false);
                    }
                  }}
                >
                  {coinbaseSyncBusy ? "Syncing…" : "Sync Coinbase now"}
                </Button>
                {settings["finance.coinbase.lastSyncAt"] ? (
                  <StatusChip
                    title={`Last sync ${new Date(settings["finance.coinbase.lastSyncAt"]).toLocaleString()}`}
                    tint="var(--color-primary)"
                  />
                ) : (
                  <StatusChip title="Never synced" />
                )}
              </div>
              {coinbaseSyncNote ? (
                <p className="mt-2 text-[12px] text-[var(--color-text-light)]">{coinbaseSyncNote}</p>
              ) : null}
              <StatusNote>
                Linked accounts, budgets, and ledger CRUD remain fully local. Use Finance → Accounts to
                add balances imported from Swift or CSV.
              </StatusNote>
              {(financeCategories.length > 0 || financeDue.length > 0) && (
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  <MetricTile label="Categories" value={financeCategories.length} />
                  <MetricTile
                    label="Open IOUs"
                    value={financeDue.filter((d) => !d.isPaid).length}
                  />
                </div>
              )}
            </AppCard>
            <AppCard title="Finance integrations">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Local accounts, budgets, and ledger data stay on this device. Stock and crypto holdings
                roll into net worth on Finance → Net worth.
              </p>
            </AppCard>
          </>
        );

      case "discovery":
        return (
          <>
            <AppCard title="College Scorecard">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Sync federal admissions stats from the public College Scorecard API (
                <a
                  href="https://api.data.gov/signup/"
                  className="text-[var(--color-primary)] hover:underline"
                  target="_blank"
                  rel="noreferrer"
                >
                  api.data.gov
                </a>
                ) for institutions already in Discovery with a unit ID.
              </p>
              <FormField label="API key (optional)">
                <input
                  className={fieldControlClass}
                  type="password"
                  value={settings["discovery.scorecard.apiKey"] ?? ""}
                  onChange={(e) => void setPref("discovery.scorecard.apiKey", e.target.value)}
                  placeholder="Higher rate limits when set"
                />
              </FormField>
              <Button
                size="sm"
                onClick={async () => {
                  setDiscoverySyncNote("Syncing federal data…");
                  try {
                    const res = await ipc.discoverySyncFederalData();
                    const errTail =
                      res.errors.length > 0 ? ` · ${res.errors.slice(0, 2).join("; ")}` : "";
                    setDiscoverySyncNote(
                      `Synced ${res.synced}, skipped ${res.skipped}${errTail}`,
                    );
                    showToast(`Federal sync finished (${res.synced} updated)`, "success");
                  } catch (e) {
                    setDiscoverySyncNote(formatIpcError(e));
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Sync federal data
              </Button>
              {discoverySyncNote ? <StatusNote>{discoverySyncNote}</StatusNote> : null}
            </AppCard>
          </>
        );

      case "career":
        return (
          <>
            <AppCard title="USAJobs API">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Federal openings sync via the official Search API (free key from{" "}
                <a
                  href="https://developer.usajobs.gov/"
                  className="text-[var(--color-primary)] hover:underline"
                  target="_blank"
                  rel="noreferrer"
                >
                  developer.usajobs.gov
                </a>
                ).
              </p>
              <FormField label="API key">
                <input
                  className={fieldControlClass}
                  type="password"
                  value={settings["jobBoard.usajobs.apiKey"] ?? ""}
                  onChange={(e) => void setPref("jobBoard.usajobs.apiKey", e.target.value)}
                  placeholder="Authorization-Key"
                />
              </FormField>
              <FormField label="User email">
                <input
                  className={fieldControlClass}
                  value={settings["jobBoard.usajobs.userEmail"] ?? ""}
                  onChange={(e) => void setPref("jobBoard.usajobs.userEmail", e.target.value)}
                  placeholder="you@example.edu"
                />
              </FormField>
            </AppCard>
            <AppCard title="Apply autofill">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Greenhouse, Lever, Workday, and iCIMS contact fields fill when you open Apply in College.
                Oracle and Talemetry run Tier C inventory (field scan, no writes). Add phone and LinkedIn
                under Profile. Set work-authorization answers below for Tier B screening fields.
              </p>
              <div className="mb-3 flex flex-wrap gap-2">
                <StatusChip title="Greenhouse · Lever" tint="var(--color-success)" filled />
                <StatusChip title="Workday · iCIMS (Tier B)" tint="var(--color-primary)" filled />
                <StatusChip title="Oracle · Talemetry (Tier C)" tint="var(--color-warning)" filled />
              </div>
              <div className="flex flex-col gap-2">
                {(
                  [
                    ["career.apply.usAuthorized", "US authorized to work"],
                    ["career.apply.requiresSponsorshipNow", "Requires sponsorship now"],
                    ["career.apply.requiresSponsorshipFuture", "Requires sponsorship in future"],
                  ] as const
                ).map(([key, label]) => (
                  <div
                    key={key}
                    className="flex items-center justify-between gap-3 px-2.5 py-2.5"
                    style={insetPanelStyle}
                  >
                    <span className="text-[12px]">{label}</span>
                    <input
                      type="checkbox"
                      checked={settings[key] === "true"}
                      onChange={(e) => void setPref(key, e.target.checked ? "true" : "false")}
                    />
                  </div>
                ))}
              </div>
            </AppCard>
            <AppCard title="Openings">
              <div className="flex items-center justify-between gap-3 px-2.5 py-2.5" style={insetPanelStyle}>
                <span className="text-[12px]">Sync public job boards on module open</span>
                <input
                  type="checkbox"
                  checked={settings["career.openings.autoSync"] === "true"}
                  onChange={(e) =>
                    void setPref("career.openings.autoSync", e.target.checked ? "true" : "false")
                  }
                />
              </div>
            </AppCard>
          </>
        );

      case "lms":
        return (
          <AppCard title="Portal defaults">
            <FormField label="Default portal URL">
              <input
                className={fieldControlClass}
                value={settings["lms.defaultPortalUrl"] ?? ""}
                onChange={(e) => void setPref("lms.defaultPortalUrl", e.target.value)}
                placeholder="https://canvas.instructure.com"
              />
            </FormField>
            <StatusNote>
              Prefills new LMS bookmarks and the Open default button. Use Open in College window for
              scan-import, back/forward/reload, and find-in-page (Canvas, Brightspace, Blackboard,
              Moodle). Save portal username/password (Keychain) and use Autofill login on the SSO page.
            </StatusNote>
          </AppCard>
        );

      case "shortcuts":
        return (
          <AppCard title="Web shortcuts">
            <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
              Quick links surfaced in the hub launcher (Swift web shortcuts parity).
            </p>
            {shortcuts.length === 0 ? (
              <EmptyState title="No shortcuts" body="Add your registrar, email, or LMS links below." />
            ) : (
              <ul className="mb-3 divide-y divide-[var(--color-chrome-stroke)]">
                {shortcuts.map((s) => (
                  <li key={s.id} className="flex items-center gap-2 py-2">
                    <div className="min-w-0 flex-1">
                      <ListRow title={s.title} subtitle={s.url} />
                    </div>
                    <Button
                      size="sm"
                      variant="danger"
                      onClick={() =>
                        void saveShortcuts(shortcuts.filter((x) => x.id !== s.id))
                      }
                    >
                      Remove
                    </Button>
                  </li>
                ))}
              </ul>
            )}
            <div className="grid gap-2 sm:grid-cols-2">
              <FormField label="Title">
                <input
                  className={fieldControlClass}
                  value={shortcutDraft.title}
                  onChange={(e) => setShortcutDraft((d) => ({ ...d, title: e.target.value }))}
                />
              </FormField>
              <FormField label="URL">
                <input
                  className={fieldControlClass}
                  value={shortcutDraft.url}
                  onChange={(e) => setShortcutDraft((d) => ({ ...d, url: e.target.value }))}
                />
              </FormField>
            </div>
            <Button
              size="sm"
              className="mt-3"
              disabled={!shortcutDraft.title.trim() || !shortcutDraft.url.trim()}
              onClick={() => {
                const next = [
                  ...shortcuts,
                  {
                    id: crypto.randomUUID(),
                    title: shortcutDraft.title.trim(),
                    url: shortcutDraft.url.trim(),
                  },
                ];
                void saveShortcuts(next);
                setShortcutDraft({ title: "", url: "" });
              }}
            >
              Add shortcut
            </Button>
          </AppCard>
        );

      case "app":
        return (
          <>
            <AppCard title="Workspace">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                This app stores its own copy of your data under Application Support /
                CollegeDesktop (separate from the native Swift app).
              </p>
              <div className="mb-3 flex flex-wrap gap-2">
                <Button
                  size="sm"
                  onClick={async () => {
                    setExportNote("Exporting…");
                    try {
                      const entry = await ipc.backupCreate();
                      setBackups(await ipc.backupList());
                      setExportNote(`Workspace exported as ${entry.name}`);
                      showToast("Workspace exported", "success");
                    } catch (e) {
                      setExportNote(formatIpcError(e));
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Export workspace
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    try {
                      const res = await ipc.aiPing();
                      setAi(await ipc.aiRuntimeStatus());
                      showToast(res.message, res.ok ? "success" : "error");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Test Ollama
                </Button>
              </div>
              {exportNote && <StatusNote>{exportNote}</StatusNote>}
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                <li>
                  <ListRow
                    title="Swift data import"
                    subtitle="One-way read from ~/Library/Application Support/College/College.sqlite"
                    trailing={<StatusChip title="Optional" tint="var(--color-primary)" filled />}
                  />
                </li>
                <li>
                  <ListRow
                    title="Data export"
                    subtitle={
                      dataExported
                        ? `${backups.length} backup${backups.length === 1 ? "" : "s"} on disk`
                        : "Create at least one workspace export"
                    }
                    trailing={
                      <StatusChip
                        title={dataExported ? "Done" : "Pending"}
                        tint={dataExported ? "var(--color-success)" : "var(--color-warning)"}
                        filled
                      />
                    }
                  />
                </li>
                <li>
                  <ListRow
                    title="OAuth configured"
                    subtitle={
                      oauthConfigured
                        ? "Google and/or Outlook Client IDs saved"
                        : "Settings → Calendar for Google/Outlook IDs"
                    }
                    trailing={
                      <StatusChip
                        title={oauthConfigured ? "Done" : "Optional"}
                        tint={oauthConfigured ? "var(--color-success)" : "var(--color-warning)"}
                        filled={oauthConfigured}
                      />
                    }
                  />
                </li>
                <li>
                  <ListRow
                    title="Typst on PATH"
                    subtitle={
                      typstAvailable
                        ? "Resume PDF export via `typst compile`"
                        : "Install from typst.app for in-app PDF"
                    }
                    trailing={
                      <StatusChip
                        title={
                          typstAvailable === null
                            ? "Checking…"
                            : typstAvailable
                              ? "Found"
                              : "Missing"
                        }
                        tint={
                          typstAvailable
                            ? "var(--color-success)"
                            : typstAvailable === false
                              ? "var(--color-warning)"
                              : "var(--color-text-light)"
                        }
                        filled={Boolean(typstAvailable)}
                      />
                    }
                  />
                </li>
                <li>
                  <ListRow
                    title="Ollama reachable"
                    subtitle={ai?.pingMessage ?? "Configure Assistant settings and test connection"}
                    trailing={
                      <StatusChip
                        title={
                          ollamaReachable
                            ? "Reachable"
                            : ai?.pingOk === false
                              ? "Unreachable"
                              : "Not tested"
                        }
                        tint={
                          ollamaReachable
                            ? "var(--color-success)"
                            : ai?.pingOk === false
                              ? "var(--color-error)"
                              : "var(--color-warning)"
                        }
                        filled={ollamaReachable}
                      />
                    }
                  />
                </li>
              </ul>
              <StatusNote>
                Native-only infra (EventKit two-way, bundled ONNX/MLX, MapKit embeds) stays in the
                Swift app by design. Tauri reaches ~98–99% workflow parity with substitutes; both
                apps remain supported.
              </StatusNote>
            </AppCard>

            <AppCard title="Tauri parity">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Workflow parity after Phase 52 — Swift app unchanged and supported alongside Tauri.
                Estimated{" "}
                <strong className="text-[var(--color-text-main)]">~98–99% workflow readiness</strong>{" "}
                (daily-driver tasks; not pixel-perfect or literal tool-count 1:1).
              </p>
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {TAURI_PARITY_MODULES.map((mod) => (
                  <li key={mod.name}>
                    <ListRow
                      title={mod.name}
                      subtitle={mod.note}
                      trailing={
                        <StatusChip
                          title={mod.ready ? "Ready" : "Gap"}
                          tint={mod.ready ? "var(--color-success)" : "var(--color-warning)"}
                          filled
                        />
                      }
                    />
                  </li>
                ))}
              </ul>
              <StatusNote>
                Use the native Swift app for MapKit embeds and production MLX when you need those
                backends. Daily-driver CRUD + workflows are fully covered in Tauri.
              </StatusNote>
            </AppCard>

            <AppCard title="Platform">
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                <li>
                  <ListRow
                    title="OS"
                    trailing={
                      platform ? (
                        <StatusChip title={`${platform.os} · ${platform.arch}`} filled />
                      ) : (
                        "—"
                      )
                    }
                  />
                </li>
                <li>
                  <ListRow
                    title="Version"
                    trailing={
                      platform?.appVersion ? (
                        <StatusChip title={platform.appVersion} tint="var(--color-primary)" filled />
                      ) : (
                        "—"
                      )
                    }
                  />
                </li>
              </ul>
              <div className="mt-3 flex flex-wrap gap-2">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    setUpdateNote("Checking…");
                    try {
                      const update = await check();
                      if (!update) {
                        setUpdateNote("You’re up to date.");
                        showToast("You’re up to date", "success");
                        return;
                      }
                      setUpdateNote(`Update ${update.version} available.`);
                      const ok = window.confirm(
                        `Install College ${update.version} now?\n\nThe app will download the update and relaunch.`,
                      );
                      if (!ok) return;
                      setUpdateNote(`Downloading ${update.version}…`);
                      await update.downloadAndInstall();
                      setUpdateNote("Installed. Relaunching…");
                      const { relaunch } = await import("@tauri-apps/plugin-process");
                      await relaunch();
                    } catch (e) {
                      const msg = formatIpcError(e);
                      setUpdateNote(msg);
                      showToast(msg, "error");
                    }
                  }}
                >
                  Check for updates
                </Button>
              </div>
              {updateNote && (
                <div className="mt-2">
                  <StatusChip
                    title={updateNote}
                    tint={
                      updateNote.includes("up to date")
                        ? "var(--color-success)"
                        : updateNote.includes("available") || updateNote.includes("Downloading")
                          ? "var(--color-primary)"
                          : updateNote.includes("Checking")
                            ? "var(--color-text-light)"
                            : "var(--color-error)"
                    }
                    filled
                  />
                </div>
              )}
            </AppCard>

            <AppCard title="Preferences">
              <div className="space-y-2 text-[13px]">
                <div
                  className="flex items-center justify-between gap-3 px-2.5 py-2.5"
                  style={insetPanelStyle}
                >
                  <span>Reduce motion</span>
                  <div className="flex items-center gap-2">
                    <StatusChip
                      title={reduceMotion ? "On" : "Off"}
                      tint={reduceMotion ? "var(--color-primary)" : "var(--color-text-light)"}
                      filled={reduceMotion}
                    />
                    <input
                      type="checkbox"
                      checked={reduceMotion}
                      onChange={(e) =>
                        void setPref("ui.reduceMotion", e.target.checked ? "true" : "false")
                      }
                    />
                  </div>
                </div>
                <div
                  className="flex items-center justify-between gap-3 px-2.5 py-2.5"
                  style={insetPanelStyle}
                >
                  <span>Theme</span>
                  <div className="flex items-center gap-2">
                    <StatusChip title={themeLabel(theme)} tint="var(--color-primary)" filled />
                    <select
                      className={`${fieldControlClass} w-[120px] py-1`}
                      value={theme}
                      onChange={(e) => {
                        const value = e.target.value;
                        void setPref("ui.theme", value);
                        document.documentElement.dataset.theme = value;
                      }}
                    >
                      <option value="system">System</option>
                      <option value="light">Light</option>
                      <option value="dark">Dark</option>
                    </select>
                  </div>
                </div>
                <div
                  className="flex items-center justify-between gap-3 px-2.5 py-2.5"
                  style={insetPanelStyle}
                >
                  <span>Due-item notifications</span>
                  <div className="flex items-center gap-2">
                    <StatusChip
                      title={dueNotifications ? "On" : "Off"}
                      tint={dueNotifications ? "var(--color-success)" : "var(--color-text-light)"}
                      filled={dueNotifications}
                    />
                    <input
                      type="checkbox"
                      checked={dueNotifications}
                      onChange={(e) =>
                        void setPref("notify.dueItems", e.target.checked ? "true" : "false")
                      }
                    />
                  </div>
                </div>
                <p
                  className="px-2.5 py-2 text-[11px] leading-relaxed text-[var(--color-text-light)]"
                  style={insetPanelStyle}
                >
                  On launch, remind once per day about tasks due in 48h and today’s events.
                  Shortcuts: ⌘K search, ⌘1–7 modules, ⌘, settings.
                </p>
              </div>
            </AppCard>
          </>
        );

      case "privacy":
        return (
          <>
            <AppCard title="Security">
              <div className="mb-3 px-3 py-3" style={insetPanelStyle}>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="text-[12px] text-[var(--color-text-light)]">Vault access</p>
                  <StatusChip
                    title={locked ? "Locked" : "Unlocked"}
                    tint={locked ? "var(--color-warning)" : "var(--color-success)"}
                    filled
                  />
                </div>
              </div>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    await ipc.securityLock();
                    setLocked(true);
                  }}
                >
                  Lock
                </Button>
                <Button
                  size="sm"
                  onClick={async () => {
                    await ipc.securityUnlock("Unlock College");
                    setLocked(await ipc.securityIsLocked());
                  }}
                >
                  Unlock
                </Button>
              </div>
            </AppCard>

            <AppCard title="Backups">
              <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                Copies `college.sqlite` into the Backups folder under Application Support. Restore
                stages a pending file and relaunches the app.
              </p>
              <div className="flex flex-wrap gap-2">
                <Button
                  size="sm"
                  onClick={async () => {
                    setBackupNote("Creating…");
                    try {
                      const entry = await ipc.backupCreate();
                      setBackupNote(`Saved ${entry.name}`);
                      setBackups(await ipc.backupList());
                    } catch (e) {
                      setBackupNote(formatIpcError(e));
                    }
                  }}
                >
                  Create backup
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={!paths?.backupsDir}
                  onClick={async () => {
                    if (!paths?.backupsDir) return;
                    try {
                      await revealItemInDir(paths.backupsDir);
                    } catch (e) {
                      setBackupNote(formatIpcError(e));
                    }
                  }}
                >
                  Show folder
                </Button>
              </div>
              {backupNote && <StatusNote>{backupNote}</StatusNote>}
              {backups.length > 0 && (
                <ul className="mt-3 space-y-2">
                  {backups.slice(0, 8).map((b) => (
                    <li
                      key={b.path}
                      className="flex items-center gap-2 px-2.5 py-2"
                      style={insetPanelStyle}
                    >
                      <div className="min-w-0 flex-1">
                        <ListRow
                          title={b.name}
                          subtitle={new Date(b.modifiedAt).toLocaleString()}
                          trailing={
                            <StatusChip title={`${Math.round(b.sizeBytes / 1024)} KB`} />
                          }
                        />
                      </div>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={async () => {
                          try {
                            await revealItemInDir(b.path);
                          } catch (e) {
                            setBackupNote(formatIpcError(e));
                          }
                        }}
                      >
                        Reveal
                      </Button>
                      <Button
                        size="sm"
                        variant="danger"
                        onClick={async () => {
                          const ok = window.confirm(
                            `Restore ${b.name}?\n\nThis replaces the current database after relaunch. A safety copy is saved first.`,
                          );
                          if (!ok) return;
                          setBackupNote("Staging restore…");
                          try {
                            const res = await ipc.backupRestore(b.path);
                            setBackupNote(
                              `Restore staged${
                                res.safetyBackup ? " (safety copy saved)" : ""
                              }. Relaunching…`,
                            );
                            const { relaunch } = await import("@tauri-apps/plugin-process");
                            await relaunch();
                          } catch (e) {
                            setBackupNote(formatIpcError(e));
                          }
                        }}
                      >
                        Restore
                      </Button>
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
          </>
        );
    }
  })();

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={PAGE_TITLES[page]}
        actions={
          <Button size="sm" variant="secondary" onClick={() => void refresh()}>
            Refresh
          </Button>
        }
      />
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}

      {page === "app" && (
        <div className="grid gap-2.5 px-3 pt-1 md:grid-cols-4">
          <MetricTile label="Version" value={platform?.appVersion ?? "—"} />
          <MetricTile label="Backups" value={backups.length} />
          <MetricTile
            label="Vault"
            value={locked ? "Locked" : "Unlocked"}
            accent={locked ? "var(--color-warning)" : "var(--color-success)"}
          />
          <MetricTile
            label="AI runtime"
            value={ai ? `${aiReady.ready}/${aiReady.total}` : "—"}
            accent={
              ai && aiReady.ready === aiReady.total
                ? "var(--color-success)"
                : ai
                  ? "var(--color-warning)"
                  : undefined
            }
          />
        </div>
      )}

      <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3 pt-3 lg:grid lg:grid-cols-2 lg:gap-3 lg:space-y-0">
        {sectionContent}
      </div>
    </div>
  );
}
