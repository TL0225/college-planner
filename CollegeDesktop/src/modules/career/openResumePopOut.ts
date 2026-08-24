import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

const LABEL = "resume-builder-popout";

export async function openResumePopOutWindow() {
  const existing = await WebviewWindow.getByLabel(LABEL);
  if (existing) {
    await existing.setFocus();
    return;
  }
  new WebviewWindow(LABEL, {
    url: "/?popout=resume",
    title: "Resume Builder",
    width: 1180,
    height: 820,
    minWidth: 720,
    minHeight: 520,
  });
}
