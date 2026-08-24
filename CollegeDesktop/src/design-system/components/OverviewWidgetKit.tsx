import type { ReactNode } from "react";
import { cn } from "../cn";
import { radius, spacing } from "../tokens";

/** Mirrors Swift `WidgetCategory.accentColor`. */
export const overviewCategoryAccent = {
  academic: "var(--color-primary)",
  productivity: "#ff9f0a",
  media: "#ff375f",
  information: "#64d2ff",
  custom: "#5e5ce6",
} as const;

export type OverviewCategory = keyof typeof overviewCategoryAccent;

/** Scrollable card shell — Swift `OverviewCard` / `.cardSurface()`. */
export function OverviewWidgetCard({
  children,
  className,
  widgetId,
  title,
}: {
  children: ReactNode;
  className?: string;
  widgetId?: string;
  title?: string;
}) {
  return (
    <section
      className={cn("frame-card flex h-full min-h-[150px] w-full flex-col", className)}
      data-overview-widget={widgetId}
      aria-label={title}
      style={{
        padding: spacing.md,
        borderRadius: radius.lg,
        background: "var(--color-surface)",
        border: "1px solid var(--color-chrome-stroke)",
        boxShadow: "inset 0 1px 0 color-mix(in srgb, white 40%, transparent)",
      }}
    >
      {children}
    </section>
  );
}

/** Swift `OverviewWidgetHeader`. */
export function OverviewWidgetHeader({
  title,
  accent,
  icon,
  trailing,
}: {
  title: string;
  accent: string;
  icon: ReactNode;
  trailing?: ReactNode;
}) {
  return (
    <div className="flex items-center gap-2.5">
      <span
        className="flex h-[30px] w-[30px] shrink-0 items-center justify-center rounded-full"
        style={{ background: `color-mix(in srgb, ${accent} 12%, transparent)`, color: accent }}
      >
        {icon}
      </span>
      <h2
        className="min-w-0 flex-1 truncate text-[var(--color-text-main)]"
        style={{ font: "var(--type-section-title)", fontWeight: 700 }}
      >
        {title}
      </h2>
      {trailing}
    </div>
  );
}

/** Swift `OverviewWidgetEmptyState`. */
export function OverviewWidgetEmpty({
  title,
  message,
  accent = "var(--color-text-light)",
  icon,
}: {
  title: string;
  message?: string;
  accent?: string;
  icon: ReactNode;
}) {
  return (
    <div className="flex w-full flex-col items-center gap-2 py-5 text-center">
      <span
        className="flex h-[42px] w-[42px] items-center justify-center rounded-full"
        style={{ background: `color-mix(in srgb, ${accent} 10%, transparent)`, color: accent }}
      >
        {icon}
      </span>
      <p className="text-[13px] font-semibold text-[var(--color-text-main)]">{title}</p>
      {message ? (
        <p className="max-w-[28ch] text-[11px] font-medium text-[var(--color-text-light)]">{message}</p>
      ) : null}
    </div>
  );
}

/** Swift `OverviewWidgetRowSurface`. */
export function OverviewWidgetRow({
  accent,
  children,
  className,
}: {
  accent: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn("px-3 py-2.5", className)}
      style={{
        borderRadius: radius.lg,
        background: `color-mix(in srgb, ${accent} 7%, transparent)`,
        border: `1px solid color-mix(in srgb, ${accent} 14%, transparent)`,
      }}
    >
      {children}
    </div>
  );
}

/** Swift `OverviewWidgetBadge`. */
export function OverviewWidgetBadge({ text, color }: { text: string; color: string }) {
  return (
    <span
      className="shrink-0 rounded-full px-[7px] py-[3px] text-[9px] font-extrabold tracking-wide uppercase"
      style={{
        color,
        background: `color-mix(in srgb, ${color} 12%, transparent)`,
      }}
    >
      {text}
    </span>
  );
}

/** Swift Overview `LazyVGrid` adaptive ~340 / spacing 24. */
export function OverviewWidgetGridLayout({ children }: { children: ReactNode }) {
  return (
    <div
      className="grid w-full"
      style={{
        gap: 24,
        gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))",
      }}
    >
      {children}
    </div>
  );
}

/** Swift AcademicsWidget credit ring. */
export function CreditRing({
  fraction,
  color,
  size = 100,
}: {
  fraction: number;
  color: string;
  size?: number;
}) {
  const f = Math.max(0, Math.min(1, fraction));
  const stroke = 7;
  const r = (size - stroke) / 2;
  const c = size / 2;
  const circumference = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} className="mx-auto" role="img" aria-label={`${Math.round(f * 100)}% complete`}>
      <circle
        cx={c}
        cy={c}
        r={r}
        fill="none"
        stroke="var(--color-chrome-stroke)"
        strokeWidth={stroke}
      />
      <circle
        cx={c}
        cy={c}
        r={r}
        fill="none"
        stroke={color}
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={circumference * (1 - f)}
        transform={`rotate(-90 ${c} ${c})`}
      />
      <text
        x={c}
        y={c + 5}
        textAnchor="middle"
        className="fill-[var(--color-text-main)] text-[15px] font-bold"
      >
        {Math.round(f * 100)}%
      </text>
    </svg>
  );
}
