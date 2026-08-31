import { cn } from "../cn";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

export type MonthGridAnchor = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type MonthDayLabel = {
  id: string;
  title: string;
  color?: string;
};

export type MonthDayCell = {
  date: Date;
  inMonth: boolean;
  isToday: boolean;
  isSelected: boolean;
  dotCount: number;
  labels?: MonthDayLabel[];
};

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

/** YYYY-MM-DD in local time */
export function dateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function anchorFromElement(el: HTMLElement): MonthGridAnchor {
  const r = el.getBoundingClientRect();
  return { x: r.left, y: r.top, width: r.width, height: r.height };
}

const accentSoft = "color-mix(in srgb, var(--registrar-accent) 14%, transparent)";

export function MonthGrid({
  cursor,
  selected,
  countsByDay,
  labelsByDay,
  onSelectDay,
  onSelectEvent,
}: {
  cursor: Date;
  selected: Date | null;
  countsByDay: Map<string, number>;
  labelsByDay?: Map<string, MonthDayLabel[]>;
  onSelectDay: (day: Date, anchor: MonthGridAnchor) => void;
  onSelectEvent?: (eventId: string, anchor: MonthGridAnchor) => void;
}) {
  const year = cursor.getFullYear();
  const month = cursor.getMonth();
  const first = new Date(year, month, 1);
  const startPad = first.getDay();
  const today = startOfDay(new Date());

  const cells: MonthDayCell[] = [];
  for (let i = 0; i < 42; i++) {
    const day = new Date(year, month, i - startPad + 1);
    const key = dateKey(day);
    cells.push({
      date: day,
      inMonth: day.getMonth() === month,
      isToday: sameDay(day, today),
      isSelected: selected ? sameDay(day, selected) : false,
      dotCount: Math.min(3, countsByDay.get(key) ?? 0),
      labels: labelsByDay?.get(key)?.slice(0, 3),
    });
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="mb-1.5 grid grid-cols-7">
        {WEEKDAYS.map((d) => (
          <div
            key={d}
            className="py-1 text-center text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]"
          >
            {d}
          </div>
        ))}
      </div>

      <div
        className="grid min-h-0 flex-1 grid-cols-7 grid-rows-6 overflow-hidden"
        style={{ borderTop: "1px solid var(--registrar-rule)" }}
      >
        {cells.map((cell) => {
          const key = dateKey(cell.date);
          return (
            <button
              key={key + String(cell.inMonth)}
              type="button"
              onClick={(e) => onSelectDay(startOfDay(cell.date), anchorFromElement(e.currentTarget))}
              className={cn(
                "relative flex min-h-[64px] flex-col items-start gap-0.5 border-b border-r border-[var(--registrar-rule)] bg-[var(--color-shell-canvas)] p-1.5 text-left transition-colors",
                "hover:bg-[var(--color-row-hover)]",
                !cell.inMonth && "opacity-40",
                cell.isSelected && "bg-[color-mix(in_srgb,var(--registrar-accent)_8%,var(--color-shell-canvas))]",
              )}
            >
              <span
                className={cn(
                  "inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1 text-meta font-semibold tabular-nums",
                  cell.isToday
                    ? "text-white"
                    : "text-[var(--registrar-ink)]",
                )}
                style={
                  cell.isToday
                    ? { background: "var(--registrar-accent)" }
                    : undefined
                }
              >
                {cell.date.getDate()}
              </span>
              {cell.labels && cell.labels.length > 0 ? (
                <div className="mt-auto w-full space-y-0.5 pb-0.5">
                  {cell.labels.map((item) => (
                    <div
                      key={item.id}
                      role="button"
                      tabIndex={0}
                      onClick={(e) => {
                        e.stopPropagation();
                        if (onSelectEvent) {
                          onSelectEvent(item.id, anchorFromElement(e.currentTarget));
                        }
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.stopPropagation();
                          e.preventDefault();
                          if (onSelectEvent) {
                            onSelectEvent(item.id, anchorFromElement(e.currentTarget));
                          }
                        }
                      }}
                      className="truncate rounded-[4px] px-1 py-px text-[9px] font-medium leading-tight transition-opacity hover:opacity-80"
                      style={
                        item.color
                          ? {
                              backgroundColor: `${item.color}22`,
                              color: item.color,
                              borderLeft: `2px solid ${item.color}`,
                            }
                          : {
                              background: accentSoft,
                              color: "var(--registrar-ink)",
                              borderLeft: "2px solid var(--registrar-accent)",
                            }
                      }
                    >
                      {item.title}
                    </div>
                  ))}
                </div>
              ) : (
                cell.dotCount > 0 && (
                  <span className="mt-auto flex gap-0.5 px-0.5 pb-0.5">
                    {Array.from({ length: cell.dotCount }).map((_, i) => (
                      <span
                        key={i}
                        className="h-1.5 w-1.5 rounded-full"
                        style={{ background: "var(--registrar-accent)" }}
                      />
                    ))}
                  </span>
                )
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
