import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from "@tauri-apps/plugin-notification";
import { ipc } from "./ipc";

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

/** Notify about due-soon tasks / today's events (at most once per local day). */
export async function maybeNotifyDueItems(): Promise<void> {
  try {
    const settings = await ipc.settingsGet();
    if (settings.values["notify.dueItems"] === "false") return;

    const todayKey = new Date().toISOString().slice(0, 10);
    if (settings.values["notify.dueItems.last"] === todayKey) return;

    let granted = await isPermissionGranted();
    if (!granted) {
      const perm = await requestPermission();
      granted = perm === "granted";
    }
    if (!granted) return;

    const [tasks, events] = await Promise.all([
      ipc.calendarListTasks().catch(() => []),
      ipc.calendarListEvents().catch(() => []),
    ]);
    const now = new Date();
    const inTwoDays = new Date(now.getTime() + 86400000 * 2);
    const dueSoon = tasks.filter((t) => {
      if (t.isComplete || !t.dueAt) return false;
      const d = new Date(t.dueAt);
      return d >= now && d <= inTwoDays;
    });
    const todayEvents = events.filter((e) => sameDay(new Date(e.startAt), now));

    const parts: string[] = [];
    if (dueSoon.length) {
      parts.push(
        `${dueSoon.length} task${dueSoon.length === 1 ? "" : "s"} due soon` +
          (dueSoon[0] ? `: ${dueSoon[0].title}` : ""),
      );
    }
    if (todayEvents.length) {
      parts.push(
        `${todayEvents.length} event${todayEvents.length === 1 ? "" : "s"} today` +
          (todayEvents[0] ? `: ${todayEvents[0].title}` : ""),
      );
    }
    if (!parts.length) {
      await ipc.settingsSet("notify.dueItems.last", todayKey);
      return;
    }

    sendNotification({
      title: "College",
      body: parts.join(" · "),
    });
    await ipc.settingsSet("notify.dueItems.last", todayKey);
  } catch {
    // Notifications are best-effort; ignore permission / plugin failures.
  }
}
