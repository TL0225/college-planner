import { cn } from "../cn";
import { LaneDot } from "./StatusChip";

export type PathTimelineItem = {
  id: string;
  title: string;
  subtitle?: string;
  meta?: string;
  color: string;
  onClick?: () => void;
  selected?: boolean;
};

/** Vertical spine timeline — simplified PathingTimelinePrimitives */
export function PathTimeline({
  items,
  className,
}: {
  items: PathTimelineItem[];
  className?: string;
}) {
  if (items.length === 0) return null;
  return (
    <ol className={cn("relative ml-1 space-y-0 pl-5", className)}>
      <span
        className="absolute bottom-2 left-[7px] top-2 w-px"
        style={{
          background:
            "linear-gradient(180deg, var(--color-chrome-stroke), color-mix(in srgb, var(--color-primary) 35%, var(--color-chrome-stroke)))",
        }}
        aria-hidden
      />
      {items.map((item, idx) => (
        <li key={item.id} className="relative pb-4 last:pb-0">
          <span className="absolute -left-[17px] top-2 z-10">
            <LaneDot color={item.color} size={10} />
          </span>
          <button
            type="button"
            onClick={item.onClick}
            className={cn(
              "w-full rounded-[10px] px-2.5 py-2 text-left transition-colors",
              item.onClick && "hover:bg-[var(--color-row-hover)]",
              item.selected && "bg-[var(--color-primary-soft)] ring-1 ring-[var(--color-primary)]/25",
            )}
          >
            <div className="text-section-title tracking-[-0.01em]">
              {item.title}
            </div>
            {(item.subtitle || item.meta) && (
              <div className="mt-0.5 text-caption">
                {[item.subtitle, item.meta].filter(Boolean).join(" · ")}
                {idx === 0 && items.length > 1 ? " · latest" : ""}
              </div>
            )}
          </button>
        </li>
      ))}
    </ol>
  );
}
