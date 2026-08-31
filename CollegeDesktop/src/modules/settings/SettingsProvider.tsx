import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { ipc, type PlatformInfo, type StoragePaths, type AiRuntimeStatus } from "@/lib/ipc";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { aiReadyCount } from "./shared";
import type { SettingsPage } from "./types";
import { SettingsContext, type WebShortcut } from "./useSettings";

export function SettingsProvider({
  page,
  children,
}: {
  page: SettingsPage;
  children: ReactNode;
}) {
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
  const [oauthDraft, setOauthDraft] = useState({
    googleClientId: "",
    googleClientSecret: "",
    outlookClientId: "",
    outlookTenant: "common",
  });
  const [oauthNote, setOauthNote] = useState<string | null>(null);

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

  const { refresh, error } = useLiveQuery(load, ["settings", "vault", "catalog"]);

  const aiReady = useMemo(() => aiReadyCount(ai), [ai]);
  const theme = settings["ui.theme"] || "system";
  const reduceMotion = settings["ui.reduceMotion"] === "true";
  const density = settings["ui.density"] || "default";
  const windowStrokeSubtle = settings["ui.windowStroke"] === "subtle";
  const dueNotifications = settings["notify.dueItems"] !== "false";
  const googleClientId = settings["oauth.google.clientId"] ?? "";
  const outlookClientId = settings["oauth.outlook.clientId"] ?? "";
  const oauthConfigured = Boolean(googleClientId || outlookClientId);
  const localAiReady = ai?.embeddingsReady === true && ai?.llmReady === true;
  const dataExported = backups.length > 0;

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

  const value = {
    page,
    platform,
    paths,
    ai,
    setAi,
    settings,
    locked,
    setLocked,
    seedStatus,
    setSeedStatus,
    scrapeUrl,
    setScrapeUrl,
    scrapeStatus,
    setScrapeStatus,
    backups,
    setBackups,
    backupNote,
    setBackupNote,
    updateNote,
    setUpdateNote,
    typstAvailable,
    exportNote,
    setExportNote,
    catalogSyncRows,
    syncBusyId,
    setSyncBusyId,
    shortcutDraft,
    setShortcutDraft,
    watchedFolders,
    setWatchedFolders,
    watchedFolderDraft,
    setWatchedFolderDraft,
    watchdogStatus,
    staleThresholdDays,
    setStaleThresholdDays,
    financeCategories,
    financeDue,
    discoverySyncNote,
    setDiscoverySyncNote,
    coinbaseSyncNote,
    setCoinbaseSyncNote,
    coinbaseSyncBusy,
    setCoinbaseSyncBusy,
    catalogEmbedStats,
    setCatalogEmbedStats,
    catalogReindexNote,
    setCatalogReindexNote,
    catalogReindexBusy,
    setCatalogReindexBusy,
    assistantTools,
    toolsExpanded,
    setToolsExpanded,
    oauthDraft,
    setOauthDraft,
    oauthNote,
    setOauthNote,
    shortcuts,
    saveShortcuts,
    refresh,
    error,
    setPref,
    aiReady,
    theme,
    reduceMotion,
    density,
    windowStrokeSubtle,
    dueNotifications,
    googleClientId,
    outlookClientId,
    oauthConfigured,
    localAiReady,
    dataExported,
  };

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}
