import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

export const ASSISTANT_POPOUT_LABEL = "assistant-popout";

/** Opens the assistant in a small, separate OS window (Claude/ChatGPT-style "minimize"). */
export async function openAssistantPopOut(): Promise<void> {
  const existing = await WebviewWindow.getByLabel(ASSISTANT_POPOUT_LABEL);
  if (existing) {
    await existing.show();
    await existing.setFocus();
    return;
  }
  new WebviewWindow(ASSISTANT_POPOUT_LABEL, {
    url: "/?popout=assistant",
    title: "Assistant",
    width: 400,
    height: 620,
    minWidth: 340,
    minHeight: 420,
    resizable: true,
    alwaysOnTop: false,
  });
}
