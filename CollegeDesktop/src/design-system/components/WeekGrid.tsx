import { cn } from "../cn";
import { dateKey } from "./MonthGrid";
import type { MonthGridAnchor } from "./MonthGrid";

function startOfWeek(d: Date): Date {
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  day.setDate(day.getDate() - day.getDay());
  return day;
}

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

export type WeekEventChip = {
  id: string;
  title: string;
  startAt: string;
  color?: string;
};

const accentSoft = "color-mix(in srgb, var(--registrar-accent) 14%, transparent)";

export function WeekGrid({
  anchor,
  selected,
  eventsByDay,
  onSelectDay,
  onSelectEvent,
}: {
  anchor: Date;
  selected: Date | null;
  eventsByDay: Map<string, WeekEventChip[]>;
  onSelectDay: (day: Date, anchor: MonthGridAnchor) => void;
  onSelectEvent?: (eventId: string, anchor: MonthGridAnchor) => void;
}) {
  const weekStart = startOfWeek(anchor);
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart);
    d.setDate(weekStart.getDate() + i);
    return d;
  });

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div
        className="grid min-h-0 flex-1 grid-cols-7 overflow-hidden"
        style={{ borderTop: "1px solid var(--registrar-rule)" }}
      >
        {days.map((day) => {
          const key = dateKey(day);
          const chips = eventsByDay.get(key) ?? [];
          const isToday = sameDay(day, today);
          const isSelected = selected ? sameDay(day, selected) : false;
          return (
            <button
              key={key}
              type="button"
              onClick={(e) =>
                onSelectDay(
                  new Date(day.getFullYear(), day.getMonth(), day.getDate()),
                  anchorFromElement(e.currentTarget),
                )
              }
              className={cn(
                "flex min-h-0 flex-col border-b border-r border-[var(--registrar-rule)] bg-[var(--color-shell-canvas)] p-2 text-left transition-colors hover:bg-[var(--color-row-hover)]",
                isSelected && "bg-[color-mix(in_srgb,var(--registrar-accent)_8%,var(--color-shell-canvas))]",
              )}
            >
              <div className="mb-1.5 flex items-center justify-between gap-1">
                <span className="text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                  {day.toLocaleDateString(undefined, { weekday: "short" })}
                </span>
                <span
                  className={cn(
                    "inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1 text-meta font-semibold tabular-nums",
                    isToday ? "text-white" : "text-[var(--registrar-ink)]",
                  )}
                  style={isToday ? { background: "var(--registrar-accent)" } : undefined}
                >
                  {day.getDate()}
                </span>
              </div>
              <div className="min-h-0 flex-1 space-y-1 overflow-y-auto">
                {chips.slice(0, 8).map((e) => (
                  <div
                    key={e.id}
                    role="button"
                    tabIndex={0}
                    onClick={(ev) => {
                      ev.stopPropagation();
                      onSelectEvent?.(e.id, anchorFromElement(ev.currentTarget));
                    }}
                    onKeyDown={(ev) => {
                      if (ev.key === "Enter" || ev.key === " ") {
                        ev.stopPropagation();
                        ev.preventDefault();
                        onSelectEvent?.(e.id, anchorFromElement(ev.currentTarget));
                      }
                    }}
                    className="truncate rounded-[4px] px-1.5 py-1 text-[10px] font-medium leading-snug transition-opacity hover:opacity-80"
                    style={
                      e.color
                        ? {
                            backgroundColor: `${e.color}22`,
                            color: e.color,
                            borderLeft: `2px solid ${e.color}`,
                          }
                        : {
                            background: accentSoft,
                            color: "var(--registrar-ink)",
                            borderLeft: "2px solid var(--registrar-accent)",
                          }
                    }
                    title={e.title}
                  >
                    {new Date(e.startAt).toLocaleTimeString(undefined, {
                      hour: "numeric",
                      minute: "2-digit",
                    })}{" "}
                    {e.title}
                  </div>
                ))}
                {chips.length > 8 && (
                  <div className="px-1 text-caption">+{chips.length - 8} more</div>
                )}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
