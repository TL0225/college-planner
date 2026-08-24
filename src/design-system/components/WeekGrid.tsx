import { cn } from "../cn";
import { dateKey } from "./MonthGrid";

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

export type WeekEventChip = {
  id: string;
  title: string;
  startAt: string;
  color?: string;
};

export function WeekGrid({
  anchor,
  selected,
  eventsByDay,
  onSelectDay,
  onAnchorChange,
}: {
  anchor: Date;
  selected: Date | null;
  eventsByDay: Map<string, WeekEventChip[]>;
  onSelectDay: (day: Date) => void;
  onAnchorChange: (next: Date) => void;
}) {
  const weekStart = startOfWeek(anchor);
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart);
    d.setDate(weekStart.getDate() + i);
    return d;
  });
  const rangeLabel = `${days[0]!.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  })} – ${days[6]!.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  })}`;

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="mb-3 flex items-center justify-between gap-2 px-0.5">
        <button
          type="button"
          className="chrome-nav-btn"
          onClick={() => {
            const prev = new Date(weekStart);
            prev.setDate(prev.getDate() - 7);
            onAnchorChange(prev);
          }}
          aria-label="Previous week"
        >
          ‹
        </button>
        <div
          className="text-[var(--color-text-main)]"
          style={{ font: "var(--type-section-title)", fontSize: 15, letterSpacing: "-0.01em" }}
        >
          {rangeLabel}
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            className="chrome-nav-btn"
            onClick={() => {
              const now = new Date();
              onAnchorChange(now);
              onSelectDay(new Date(now.getFullYear(), now.getMonth(), now.getDate()));
            }}
          >
            Today
          </button>
          <button
            type="button"
            className="chrome-nav-btn"
            onClick={() => {
              const next = new Date(weekStart);
              next.setDate(next.getDate() + 7);
              onAnchorChange(next);
            }}
            aria-label="Next week"
          >
            ›
          </button>
        </div>
      </div>

      <div
        className="grid min-h-0 flex-1 grid-cols-7 gap-px overflow-hidden"
        style={{
          borderRadius: 14,
          border: "1px solid var(--color-chrome-stroke)",
          background: "var(--color-chrome-stroke)",
          boxShadow: "var(--shadow-elevated)",
        }}
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
              onClick={() => onSelectDay(new Date(day.getFullYear(), day.getMonth(), day.getDate()))}
              className={cn(
                "flex min-h-0 flex-col bg-[var(--color-content-surface)] p-2 text-left transition-colors hover:bg-[var(--color-row-hover)]",
                isSelected && "bg-[var(--color-primary-soft)] ring-1 ring-inset ring-[var(--color-primary)]/30",
              )}
            >
              <div className="mb-1.5 flex items-center justify-between gap-1">
                <span className="text-[10px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                  {day.toLocaleDateString(undefined, { weekday: "short" })}
                </span>
                <span
                  className={cn(
                    "inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1 text-[12px] font-semibold tabular-nums",
                    isToday
                      ? "bg-[var(--color-primary)] text-white shadow-[var(--shadow-pill)]"
                      : "text-[var(--color-text-main)]",
                  )}
                >
                  {day.getDate()}
                </span>
              </div>
              <div className="min-h-0 flex-1 space-y-1 overflow-y-auto">
                {chips.slice(0, 6).map((e) => (
                  <div
                    key={e.id}
                    className="truncate rounded-[6px] bg-[var(--color-primary-soft)] px-1.5 py-1 text-[10px] font-medium leading-snug text-[var(--color-primary)]"
                    style={
                      e.color
                        ? {
                            backgroundColor: `${e.color}1F`,
                            color: e.color,
                          }
                        : undefined
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
                {chips.length > 6 && (
                  <div className="px-1 text-[10px] text-[var(--color-text-light)]">
                    +{chips.length - 6} more
                  </div>
                )}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
