import { cn } from "../cn";
import { dateKey } from "./MonthGrid";
import type { MonthGridAnchor } from "./MonthGrid";

export type DayTimedItem = {
  id: string;
  title: string;
  startAt: string;
  endAt?: string;
  location?: string;
  kind: "event" | "task";
  color?: string;
  allDay?: boolean;
};

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function anchorFromElement(el: HTMLElement): MonthGridAnchor {
  const r = el.getBoundingClientRect();
  return { x: r.left, y: r.top, width: r.width, height: r.height };
}

const HOURS = Array.from({ length: 14 }, (_, i) => i + 7);
const accentSoft = "color-mix(in srgb, var(--registrar-accent) 14%, transparent)";

export function DayTimeline({
  day,
  items,
  onSelectSlot,
  onSelectEvent,
}: {
  day: Date;
  items: DayTimedItem[];
  onSelectSlot?: (hour: number, anchor: MonthGridAnchor) => void;
  onSelectEvent?: (eventId: string, anchor: MonthGridAnchor) => void;
}) {
  const isToday = sameDay(day, new Date());
  const dayItems = items
    .filter((i) => sameDay(new Date(i.startAt), day))
    .sort((a, b) => a.startAt.localeCompare(b.startAt));

  const allDayItems = dayItems.filter((i) => i.allDay);
  const timedItems = dayItems.filter((i) => !i.allDay);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div
        className="flex min-h-0 flex-1 flex-col overflow-hidden"
        style={{ borderTop: "1px solid var(--registrar-rule)" }}
      >
        <button
          type="button"
          className="shrink-0 border-b border-[var(--registrar-rule)] bg-[var(--color-shell-canvas)] px-3 py-2 text-left hover:bg-[var(--color-row-hover)]"
          onClick={(e) =>
            onSelectSlot?.(-1, anchorFromElement(e.currentTarget))
          }
        >
          <span className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
            All day
          </span>
          <div className="mt-1 flex flex-wrap gap-1">
            {allDayItems.length === 0 ? (
              <span className="text-caption text-[var(--color-text-light)]">Click to add</span>
            ) : (
              allDayItems.map((item) => (
                <span
                  key={item.id}
                  role="button"
                  tabIndex={0}
                  onClick={(ev) => {
                    ev.stopPropagation();
                    onSelectEvent?.(item.id, anchorFromElement(ev.currentTarget));
                  }}
                  className="rounded-[4px] px-2 py-0.5 text-caption font-medium"
                  style={
                    item.color
                      ? { backgroundColor: `${item.color}22`, color: item.color }
                      : { background: accentSoft, color: "var(--registrar-ink)" }
                  }
                >
                  {item.title}
                </span>
              ))
            )}
          </div>
        </button>

        <div className="min-h-0 flex-1 overflow-auto">
          {HOURS.map((hour) => {
            const slotItems = timedItems.filter((i) => new Date(i.startAt).getHours() === hour);
            return (
              <button
                key={hour}
                type="button"
                className="grid min-h-[52px] w-full grid-cols-[56px_1fr] border-b border-[var(--registrar-rule)] bg-[var(--color-shell-canvas)] text-left hover:bg-[var(--color-row-hover)]"
                onClick={(e) => onSelectSlot?.(hour, anchorFromElement(e.currentTarget))}
              >
                <div
                  className={cn(
                    "px-2 py-1.5 text-right text-caption font-semibold tabular-nums",
                    isToday && new Date().getHours() === hour && "text-[var(--registrar-accent)]",
                  )}
                >
                  {hour === 0
                    ? "12 AM"
                    : hour < 12
                      ? `${hour} AM`
                      : hour === 12
                        ? "12 PM"
                        : `${hour - 12} PM`}
                </div>
                <div className="space-y-1 p-1.5">
                  {slotItems.map((item) => (
                    <div
                      key={item.id}
                      role="button"
                      tabIndex={0}
                      onClick={(ev) => {
                        ev.stopPropagation();
                        onSelectEvent?.(item.id, anchorFromElement(ev.currentTarget));
                      }}
                      onKeyDown={(ev) => {
                        if (ev.key === "Enter" || ev.key === " ") {
                          ev.stopPropagation();
                          ev.preventDefault();
                          onSelectEvent?.(item.id, anchorFromElement(ev.currentTarget));
                        }
                      }}
                      className="rounded-[6px] px-2 py-1.5 text-meta transition-opacity hover:opacity-80"
                      style={
                        item.kind === "event" && item.color
                          ? {
                              backgroundColor: `${item.color}22`,
                              color: item.color,
                              borderLeft: `2px solid ${item.color}`,
                            }
                          : item.kind === "event"
                            ? {
                                background: accentSoft,
                                color: "var(--registrar-ink)",
                                borderLeft: "2px solid var(--registrar-accent)",
                              }
                            : {
                                background: "color-mix(in srgb, var(--color-warning) 15%, transparent)",
                                color: "var(--color-warning)",
                              }
                      }
                    >
                      <div className="font-semibold">
                        {new Date(item.startAt).toLocaleTimeString(undefined, {
                          hour: "numeric",
                          minute: "2-digit",
                        })}{" "}
                        · {item.title}
                      </div>
                      {item.location && (
                        <div className="text-caption opacity-80">{item.location}</div>
                      )}
                    </div>
                  ))}
                </div>
              </button>
            );
          })}
          {dayItems.length === 0 && (
            <div className="p-4 text-meta">Nothing scheduled for {dateKey(day)}.</div>
          )}
        </div>
      </div>
    </div>
  );
}
