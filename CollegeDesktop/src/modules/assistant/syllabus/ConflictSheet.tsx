import { ModalSheet } from "@/design-system";
import type { CalendarConflictEvent } from "./useSyllabusConflicts";

function formatWhen(startAt: string, endAt?: string | null, allDay?: boolean): string {
  const start = new Date(startAt);
  if (allDay) {
    return start.toLocaleDateString(undefined, {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  }
  const end = endAt ? new Date(endAt) : null;
  const startText = start.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
  if (!end) return startText;
  const endText = end.toLocaleString(undefined, { hour: "numeric", minute: "2-digit" });
  return `${startText} → ${endText}`;
}

export function ConflictSheet({
  open,
  onOpenChange,
  title,
  events,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  events: CalendarConflictEvent[];
}) {
  return (
    <ModalSheet open={open} onOpenChange={onOpenChange} title={title} width={520}>
      {events.length === 0 ? (
        <p className="text-body text-[var(--color-text-light)]">No conflicts found.</p>
      ) : (
        <ul className="max-h-[360px] space-y-2 overflow-auto">
          {events.map((event) => (
            <li
              key={event.id}
              className="rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2.5"
              style={{ background: "var(--color-content-surface)" }}
            >
              <div className="text-section-title">
                {event.title}
              </div>
              <div className="mt-1 text-caption">
                {formatWhen(event.startAt, event.endAt, event.allDay)}
              </div>
              {event.location ? (
                <div className="mt-0.5 text-caption">
                  {event.location}
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </ModalSheet>
  );
}
