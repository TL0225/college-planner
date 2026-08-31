import { AssistantModule } from "./AssistantModule";

/** Standalone assistant window (`/?popout=assistant`) — the minimized chat, out of the main app. */
export function AssistantPopOutView() {
  return (
    <div className="flex h-screen flex-col bg-[var(--color-content-bg)]">
      <AssistantModule page="chat" />
    </div>
  );
}
