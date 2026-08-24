import { cn } from "../cn";
import { dateKey } from "./MonthGrid";

export type DayTimedItem = {
  id: string;
  title: string;
  startAt: string;
  endAt?: string;
  location?: string;
  kind: "event" | "task";
  color?: string;
};

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

const HOURS = Array.from({ length: 14 }, (_, i) => i + 7); // 7am–8pm

export function DayTimeline({
  day,
  items,
  onPrev,
  onNext,
  onToday,
}: {
  day: Date;
  items: DayTimedItem[];
  onPrev: () => void;
  onNext: () => void;
  onToday: () => void;
}) {
  const label = day.toLocaleDateString(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  });
  const isToday = sameDay(day, new Date());
  const dayItems = items
    .filter((i) => sameDay(new Date(i.startAt), day))
    .sort((a, b) => a.startAt.localeCompare(b.startAt));

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="mb-3 flex items-center justify-between gap-2 px-0.5">
        <button
          type="button"
          className="chrome-nav-btn"
          onClick={onPrev}
          aria-label="Previous day"
        >
          ‹
        </button>
        <div
          className="text-[var(--color-text-main)]"
          style={{ font: "var(--type-section-title)", fontSize: 15, letterSpacing: "-0.01em" }}
        >
          {label}
          {isToday ? " · Today" : ""}
        </div>
        <div className="flex items-center gap-1">
          <button type="button" className="chrome-nav-btn" onClick={onToday}>
            Today
          </button>
          <button
            type="button"
            className="chrome-nav-btn"
            onClick={onNext}
            aria-label="Next day"
          >
            ›
          </button>
        </div>
      </div>

      <div
        className="min-h-0 flex-1 overflow-auto"
        style={{
          borderRadius: 14,
          border: "1px solid var(--color-chrome-stroke)",
          boxShadow: "var(--shadow-elevated)",
        }}
      >
        {HOURS.map((hour) => {
          const slotItems = dayItems.filter((i) => new Date(i.startAt).getHours() === hour);
          return (
            <div
              key={hour}
              className="grid min-h-[52px] grid-cols-[56px_1fr] border-b border-[var(--color-chrome-stroke)] last:border-b-0"
            >
              <div
                className={cn(
                  "px-2 py-1.5 text-right text-[10px] font-semibold tabular-nums text-[var(--color-text-light)]",
                  isToday && new Date().getHours() === hour && "text-[var(--color-primary)]",
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
                    className={cn(
                      "rounded-[8px] px-2 py-1.5 text-[12px]",
                      item.kind === "event"
                        ? "bg-[var(--color-primary)]/12 text-[var(--color-primary)]"
                        : "bg-[var(--color-warning)]/15 text-[var(--color-warning)]",
                    )}
                    style={
                      item.kind === "event" && item.color
                        ? {
                            backgroundColor: `${item.color}1F`,
                            color: item.color,
                          }
                        : undefined
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
                      <div className="text-[10px] opacity-80">{item.location}</div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
        {dayItems.length === 0 && (
          <div className="p-4 text-[12px] text-[var(--color-text-light)]">
            Nothing scheduled for {dateKey(day)}.
          </div>
        )}
      </div>
    </div>
  );
}
