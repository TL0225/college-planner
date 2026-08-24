import { invoke } from "@tauri-apps/api/core";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import type { LmsExtractResult } from "@/modules/lms/lmsBridgeScript";

export type LmsCollegeWindowInput = {
  portalId: string;
  name: string;
  url: string;
};

export function lmsWindowLabel(portalId: string): string {
  return `lms-${portalId}`;
}

function portalHref(url: string): string {
  return url.startsWith("http") ? url : `https://${url}`;
}

export async function openLmsCollegeWindow(input: LmsCollegeWindowInput): Promise<WebviewWindow | null> {
  const href = portalHref(input.url.trim());
  if (!href) {
    showToast("Portal URL is missing", "error");
    return null;
  }

  const label = lmsWindowLabel(input.portalId);
  const title = `${input.name} · College LMS`;

  try {
    const existing = await WebviewWindow.getByLabel(label);
    if (existing) {
      await existing.show();
      await existing.setFocus();
      void ipc.lmsPortalInstallBridge(input.portalId).catch(() => undefined);
      return existing;
    }

    const webview = new WebviewWindow(label, {
      url: href,
      title,
      width: 1180,
      height: 820,
      center: true,
      resizable: true,
    });

    webview.once("tauri://error", (event) => {
      const message =
        typeof event.payload === "string"
          ? event.payload
          : formatIpcError(event.payload ?? event);
      showToast(message, "error");
    });

    const install = () => {
      void ipc.lmsPortalInstallBridge(input.portalId).catch(() => undefined);
    };
    webview.once("tauri://created", () => install());
    // Re-inject after navigations settle (document-start substitute).
    setTimeout(install, 1200);
    setTimeout(install, 3500);

    return webview;
  } catch (e) {
    showToast(formatIpcError(e), "error");
    return null;
  }
}

export async function extractLmsPageItems(portalId: string): Promise<LmsExtractResult | null> {
  try {
    const raw = await invoke<string>("lms_extract_portal_page", { portalId });
    if (!raw) {
      return { pageType: "", items: [] };
    }
    return JSON.parse(raw) as LmsExtractResult;
  } catch (e) {
    showToast(formatIpcError(e), "error");
    return null;
  }
}

export async function lmsWindowGoBack(portalId: string): Promise<void> {
  try {
    await invoke("lms_portal_navigate", { portalId, action: "back" });
  } catch (e) {
    showToast(formatIpcError(e), "error");
  }
}

export async function lmsWindowGoForward(portalId: string): Promise<void> {
  try {
    await invoke("lms_portal_navigate", { portalId, action: "forward" });
  } catch (e) {
    showToast(formatIpcError(e), "error");
  }
}

export async function lmsWindowReload(portalId: string): Promise<void> {
  try {
    await invoke("lms_portal_navigate", { portalId, action: "reload" });
  } catch (e) {
    showToast(formatIpcError(e), "error");
  }
}

export async function lmsWindowFind(
  portalId: string,
  query: string,
  forward = true,
): Promise<boolean> {
  try {
    const res = await invoke<{ found: boolean; matchCount: number }>("lms_portal_find", {
      portalId,
      query,
      forward,
    });
    if (!query.trim()) return false;
    if (!res.found) {
      showToast(`No match for “${query.trim()}”`, "error");
      return false;
    }
    if (res.matchCount > 1) {
      showToast(`${res.matchCount} matches — jumped to next`, "success");
    }
    return true;
  } catch (e) {
    showToast(formatIpcError(e), "error");
    return false;
  }
}
