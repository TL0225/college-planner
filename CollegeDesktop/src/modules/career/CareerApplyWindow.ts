import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";

export type CareerApplyWindowInput = {
  applicationId: string;
  company: string;
  roleTitle: string;
  url: string;
};

export function careerApplyWindowLabel(applicationId: string): string {
  return `career-apply-${applicationId}`;
}

function applyHref(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return "";
  return trimmed.startsWith("http") ? trimmed : `https://${trimmed}`;
}

export async function openCareerApplyWindow(input: CareerApplyWindowInput): Promise<void> {
  const href = applyHref(input.url);
  if (!href) {
    showToast("No application URL to open", "error");
    return;
  }

  const label = careerApplyWindowLabel(input.applicationId);
  const title = `${input.roleTitle} @ ${input.company}`.trim() || "Apply in College";

  try {
    const existing = await WebviewWindow.getByLabel(label);
    if (existing) {
      await existing.show();
      await existing.setFocus();
      void ipc.careerApplyInstallBridge(input.applicationId).catch(() => undefined);
      return;
    }

    const webview = new WebviewWindow(label, {
      url: href,
      title,
      width: 1100,
      height: 760,
      center: true,
      resizable: true,
    });

    const install = () => {
      void ipc.careerApplyInstallBridge(input.applicationId).catch(() => undefined);
    };
    webview.once("tauri://created", () => install());
    setTimeout(install, 1200);
    setTimeout(install, 3500);

    webview.once("tauri://error", (event) => {
      const message =
        typeof event.payload === "string"
          ? event.payload
          : formatIpcError(event.payload ?? event);
      showToast(message, "error");
    });

    webview.once("tauri://created", () => {
      window.setTimeout(() => {
        void ipc
          .careerApplyRunAutofill(input.applicationId, href)
          .then((result) => {
            if (result.filledCount > 0) {
              showToast(
                `Autofill (${result.platform}): filled ${result.filledCount} field${result.filledCount === 1 ? "" : "s"}`,
                "success",
              );
            }
          })
          .catch((err) => {
            console.warn("Career apply autofill failed:", err);
            showToast(formatIpcError(err), "error");
          });
      }, 2500);
    });
  } catch (e) {
    showToast(formatIpcError(e), "error");
  }
}
