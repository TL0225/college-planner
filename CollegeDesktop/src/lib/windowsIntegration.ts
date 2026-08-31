import { ipc } from "@/lib/ipc";

export type WindowsCapabilities = {
  os: string;
  dwmMica: boolean;
  taskbarProgress: boolean;
  uriProtocol: boolean;
  widgetsBoard: boolean;
  focusSessions: boolean;
  directml: boolean;
  copilotNpu: boolean;
  xamlIslands: boolean;
  dpapi: boolean;
  ecoQos: boolean;
};

export type WindowsPersonalization = {
  accentColor?: string | null;
  textScalePercent: number;
  highContrast: boolean;
};

export type TaskbarProgressState =
  | "none"
  | "indeterminate"
  | "normal"
  | "error"
  | "paused";

export function isWindowsPlatform(): boolean {
  if (typeof navigator === "undefined") return false;
  return navigator.userAgent.includes("Windows");
}

export async function loadWindowsCapabilities(): Promise<WindowsCapabilities | null> {
  if (!isWindowsPlatform()) return null;
  try {
    return await ipc.windowsGetCapabilities();
  } catch {
    return null;
  }
}

export async function applyWindowsPersonalization(): Promise<WindowsPersonalization | null> {
  if (!isWindowsPlatform()) return null;
  try {
    const p = await ipc.windowsGetPersonalization();
    const root = document.documentElement;
    if (p.accentColor) {
      root.style.setProperty("--color-primary", p.accentColor);
      root.style.setProperty("--color-accent", p.accentColor);
    }
    const scale = Math.min(2.25, Math.max(1, p.textScalePercent / 100));
    root.style.setProperty("--ui-scale", String(scale));
    if (p.highContrast) {
      root.dataset.highContrast = "true";
    } else {
      delete root.dataset.highContrast;
    }
    return p;
  } catch {
    return null;
  }
}

export async function syncWindowsTheme(dark: boolean): Promise<void> {
  if (!isWindowsPlatform()) return;
  try {
    await ipc.windowsSyncTheme(dark);
  } catch {
    /* non-fatal */
  }
}

export async function setWindowsTaskbarProgress(
  completed: number,
  total: number,
  state: TaskbarProgressState = "normal",
): Promise<void> {
  if (!isWindowsPlatform()) return;
  try {
    if (state === "none") {
      await ipc.windowsClearTaskbarProgress();
      return;
    }
    await ipc.windowsSetTaskbarProgress({ completed, total, state });
  } catch {
    /* non-fatal */
  }
}

export async function refreshWindowsWidgetFeeds(input: {
  agenda?: Record<string, unknown>;
  gpa?: Record<string, unknown>;
  pipeline?: Record<string, unknown>;
}): Promise<void> {
  if (!isWindowsPlatform()) return;
  try {
    await ipc.windowsBuildWidgetFeeds({
      agenda: input.agenda ?? null,
      gpa: input.gpa ?? null,
      pipeline: input.pipeline ?? null,
    });
  } catch {
    /* non-fatal */
  }
}

export async function syncWindowsSearchIndex(
  entries: Array<{
    id: string;
    title: string;
    path: string;
    category?: string;
    updatedAt?: string;
  }>,
): Promise<void> {
  if (!isWindowsPlatform()) return;
  try {
    await ipc.windowsSyncSearchIndex(entries);
  } catch {
    /* non-fatal */
  }
}
