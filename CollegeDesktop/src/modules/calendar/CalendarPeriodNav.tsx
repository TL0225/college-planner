function startOfWeek(d: Date): Date {
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  day.setDate(day.getDate() - day.getDay());
  return day;
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function CalendarPeriodNav({
  view,
  cursor,
  weekAnchor,
  dayCursor,
  onMonthChange,
  onWeekChange,
  onDayChange,
  onSelectToday,
}: {
  view: "month" | "week" | "day";
  cursor: Date;
  weekAnchor: Date;
  dayCursor: Date;
  onMonthChange: (next: Date) => void;
  onWeekChange: (next: Date) => void;
  onDayChange: (next: Date) => void;
  onSelectToday: () => void;
}) {
  const label =
    view === "month"
      ? cursor.toLocaleString(undefined, { month: "long", year: "numeric" })
      : view === "week"
        ? (() => {
            const weekStart = startOfWeek(weekAnchor);
            const days = Array.from({ length: 7 }, (_, i) => {
              const d = new Date(weekStart);
              d.setDate(weekStart.getDate() + i);
              return d;
            });
            return `${days[0]!.toLocaleDateString(undefined, {
              month: "short",
              day: "numeric",
            })} – ${days[6]!.toLocaleDateString(undefined, {
              month: "short",
              day: "numeric",
              year: "numeric",
            })}`;
          })()
        : (() => {
            const isToday = startOfDay(dayCursor).getTime() === startOfDay(new Date()).getTime();
            const text = dayCursor.toLocaleDateString(undefined, {
              weekday: "long",
              month: "long",
              day: "numeric",
              year: "numeric",
            });
            return isToday ? `${text} · Today` : text;
          })();

  const onPrev = () => {
    if (view === "month") {
      onMonthChange(new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1));
    } else if (view === "week") {
      const prev = startOfWeek(weekAnchor);
      prev.setDate(prev.getDate() - 7);
      onWeekChange(prev);
    } else {
      const d = new Date(dayCursor);
      d.setDate(d.getDate() - 1);
      onDayChange(d);
    }
  };

  const onNext = () => {
    if (view === "month") {
      onMonthChange(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1));
    } else if (view === "week") {
      const next = startOfWeek(weekAnchor);
      next.setDate(next.getDate() + 7);
      onWeekChange(next);
    } else {
      const d = new Date(dayCursor);
      d.setDate(d.getDate() + 1);
      onDayChange(d);
    }
  };

  return (
    <div className="flex items-center gap-1">
      <button type="button" className="chrome-nav-btn" onClick={onPrev} aria-label="Previous period">
        ‹
      </button>
      <div
        className="min-w-[10rem] truncate px-1 text-center"
        style={{
          fontFamily: "var(--font-display)",
          fontWeight: 600,
          fontSize: 15,
          color: "var(--registrar-ink)",
        }}
      >
        {label}
      </div>
      <button type="button" className="chrome-nav-btn" onClick={onSelectToday}>
        Today
      </button>
      <button type="button" className="chrome-nav-btn" onClick={onNext} aria-label="Next period">
        ›
      </button>
    </div>
  );
}
