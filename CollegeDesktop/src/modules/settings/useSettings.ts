import { createContext, useContext, type Dispatch, type SetStateAction } from "react";
import type { PlatformInfo, StoragePaths, AiRuntimeStatus } from "@/lib/ipc";
import type { SettingsPage } from "./types";

export type WebShortcut = { id: string; title: string; url: string };

export type SettingsContextValue = {
  page: SettingsPage;
  platform: PlatformInfo | null;
  paths: StoragePaths | null;
  ai: AiRuntimeStatus | null;
  setAi: (ai: AiRuntimeStatus | null) => void;
  settings: Record<string, string>;
  locked: boolean;
  setLocked: (locked: boolean) => void;
  seedStatus: string | null;
  setSeedStatus: (status: string | null) => void;
  scrapeUrl: string;
  setScrapeUrl: (url: string) => void;
  scrapeStatus: string | null;
  setScrapeStatus: (status: string | null) => void;
  backups: Array<{ name: string; path: string; sizeBytes: number; modifiedAt: string }>;
  setBackups: (
    backups: Array<{ name: string; path: string; sizeBytes: number; modifiedAt: string }>,
  ) => void;
  backupNote: string | null;
  setBackupNote: (note: string | null) => void;
  updateNote: string | null;
  setUpdateNote: (note: string | null) => void;
  typstAvailable: boolean | null;
  exportNote: string | null;
  setExportNote: (note: string | null) => void;
  catalogSyncRows: Array<{
    id: string;
    name: string;
    courseCount: number;
    lastSyncedAt?: string | null;
    lastError?: string | null;
  }>;
  syncBusyId: string | null;
  setSyncBusyId: (id: string | null) => void;
  shortcutDraft: { title: string; url: string };
  setShortcutDraft: Dispatch<SetStateAction<{ title: string; url: string }>>;
  watchedFolders: Array<{ id: string; path: string; addedAt: string }>;
  setWatchedFolders: (
    folders: Array<{ id: string; path: string; addedAt: string }>,
  ) => void;
  watchedFolderDraft: string;
  setWatchedFolderDraft: (draft: string) => void;
  watchdogStatus: {
    isWatching: boolean;
    watchedCount: number;
    lastDetectedPath: string | null;
    lastDetectedAt: string | null;
  } | null;
  staleThresholdDays: string;
  setStaleThresholdDays: (days: string) => void;
  financeCategories: Array<{ id: string; name: string; kind: string; sortOrder: number }>;
  financeDue: Array<{ id: string; person: string; amount: number; dueAt: string; isPaid: boolean }>;
  discoverySyncNote: string | null;
  setDiscoverySyncNote: (note: string | null) => void;
  coinbaseSyncNote: string | null;
  setCoinbaseSyncNote: (note: string | null) => void;
  coinbaseSyncBusy: boolean;
  setCoinbaseSyncBusy: (busy: boolean) => void;
  catalogEmbedStats: { indexedCount: number; courseCount: number; modelTag: string } | null;
  setCatalogEmbedStats: (
    stats: { indexedCount: number; courseCount: number; modelTag: string } | null,
  ) => void;
  catalogReindexNote: string | null;
  setCatalogReindexNote: (note: string | null) => void;
  catalogReindexBusy: boolean;
  setCatalogReindexBusy: (busy: boolean) => void;
  assistantTools: Array<{ name: string; description: string; category: string }>;
  toolsExpanded: boolean;
  setToolsExpanded: Dispatch<SetStateAction<boolean>>;
  oauthDraft: {
    googleClientId: string;
    googleClientSecret: string;
    outlookClientId: string;
    outlookTenant: string;
  };
  setOauthDraft: Dispatch<
    SetStateAction<{
      googleClientId: string;
      googleClientSecret: string;
      outlookClientId: string;
      outlookTenant: string;
    }>
  >;
  oauthNote: string | null;
  setOauthNote: (note: string | null) => void;
  shortcuts: WebShortcut[];
  saveShortcuts: (next: WebShortcut[]) => Promise<void>;
  refresh: () => Promise<void>;
  error: string | null;
  setPref: (key: string, value: string) => Promise<void>;
  aiReady: { ready: number; total: number };
  theme: string;
  reduceMotion: boolean;
  density: string;
  windowStrokeSubtle: boolean;
  dueNotifications: boolean;
  googleClientId: string;
  outlookClientId: string;
  oauthConfigured: boolean;
  localAiReady: boolean;
  dataExported: boolean;
};

export const SettingsContext = createContext<SettingsContextValue | null>(null);

export function useSettings(): SettingsContextValue {
  const ctx = useContext(SettingsContext);
  if (!ctx) {
    throw new Error("useSettings must be used within SettingsProvider");
  }
  return ctx;
}
