import { cn } from "../cn";
import { radius } from "../tokens";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

export type MonthDayLabel = {
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

export function MonthGrid({
  cursor,
  selected,
  countsByDay,
  labelsByDay,
  onSelectDay,
  onCursorChange,
}: {
  cursor: Date;
  selected: Date | null;
  countsByDay: Map<string, number>;
  labelsByDay?: Map<string, MonthDayLabel[]>;
  onSelectDay: (day: Date) => void;
  onCursorChange: (next: Date) => void;
}) {
  const year = cursor.getFullYear();
  const month = cursor.getMonth();
  const first = new Date(year, month, 1);
  const startPad = first.getDay();
  const today = startOfDay(new Date());
  const label = cursor.toLocaleString(undefined, { month: "long", year: "numeric" });

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
      labels: labelsByDay?.get(key)?.slice(0, 2),
    });
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="mb-3 flex items-center justify-between gap-2 px-0.5">
        <button
          type="button"
          className="chrome-nav-btn"
          onClick={() => onCursorChange(new Date(year, month - 1, 1))}
          aria-label="Previous month"
        >
          ‹
        </button>
        <div
          className="text-[var(--color-text-main)]"
          style={{ font: "var(--type-section-title)", letterSpacing: "-0.01em", fontSize: 15 }}
        >
          {label}
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            className="chrome-nav-btn"
            onClick={() => {
              const now = new Date();
              onCursorChange(new Date(now.getFullYear(), now.getMonth(), 1));
              onSelectDay(startOfDay(now));
            }}
          >
            Today
          </button>
          <button
            type="button"
            className="chrome-nav-btn"
            onClick={() => onCursorChange(new Date(year, month + 1, 1))}
            aria-label="Next month"
          >
            ›
          </button>
        </div>
      </div>

      <div className="mb-1.5 grid grid-cols-7 gap-px">
        {WEEKDAYS.map((d) => (
          <div
            key={d}
            className="py-1 text-center text-[10px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]"
          >
            {d}
          </div>
        ))}
      </div>

      <div
        className="grid min-h-0 flex-1 grid-cols-7 grid-rows-6 gap-px overflow-hidden"
        style={{
          borderRadius: radius.lg,
          background: "var(--color-chrome-stroke)",
          border: "1px solid var(--color-chrome-stroke)",
          boxShadow: "var(--shadow-elevated)",
        }}
      >
        {cells.map((cell) => {
          const key = dateKey(cell.date);
          return (
            <button
              key={key + String(cell.inMonth)}
              type="button"
              onClick={() => onSelectDay(startOfDay(cell.date))}
              className={cn(
                "relative flex min-h-[64px] flex-col items-start gap-1 bg-[var(--color-content-surface)] p-1.5 text-left transition-colors",
                "hover:bg-[var(--color-row-hover)]",
                !cell.inMonth && "opacity-35",
                cell.isSelected && "ring-1 ring-inset ring-[var(--color-primary)]/35",
                cell.isSelected && "bg-[var(--color-primary-soft)]",
              )}
            >
              <span
                className={cn(
                  "inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1 text-[12px] font-semibold tabular-nums",
                  cell.isToday
                    ? "bg-[var(--color-primary)] text-white shadow-[var(--shadow-pill)]"
                    : "text-[var(--color-text-main)]",
                )}
              >
                {cell.date.getDate()}
              </span>
              {cell.labels && cell.labels.length > 0 ? (
                <div className="mt-auto w-full space-y-0.5 pb-0.5">
                  {cell.labels.map((item, i) => (
                    <div
                      key={i}
                      className="truncate rounded-[5px] bg-[var(--color-primary-soft)] px-1 py-px text-[9px] font-medium leading-tight text-[var(--color-primary)]"
                      style={
                        item.color
                          ? {
                              backgroundColor: `${item.color}1F`,
                              color: item.color,
                            }
                          : undefined
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
                        className="h-1.5 w-1.5 rounded-full bg-[var(--color-primary)]"
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
