import type { ReactNode } from "react";
import { ChevronRight } from "lucide-react";
import {
  courseStatusState,
  plannerStatusPalette,
  type PlannerStatusState,
} from "./plannerStatus";

export function CourseDashboardSectionTitle({ children }: { children: ReactNode }) {
  return (
    <div
      className="text-[var(--color-primary)]"
      style={{ font: "var(--type-section-title)", fontSize: 14, letterSpacing: "-0.01em" }}
    >
      {children}
    </div>
  );
}

export function CourseDashboardCard({ children }: { children: ReactNode }) {
  return (
    <div className="w-full pt-0.5">
      <div className="space-y-3">{children}</div>
      <div className="mt-3 border-b border-[var(--color-chrome-stroke)]" />
    </div>
  );
}

export function CourseStatusPill({ status }: { status: string }) {
  const state = courseStatusState({ status });
  const palette = plannerStatusPalette(state);
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2 py-[3px] text-[11px] font-semibold"
      style={{ background: palette.pillBg, color: palette.pillFg }}
    >
      {palette.label}
    </span>
  );
}

export function CourseDashboardInlineMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex shrink-0 items-baseline gap-1.5 text-[13px]">
      <span className="text-[var(--color-text-light)]">{label}</span>
      <span className="font-semibold tabular-nums text-[var(--color-text-main)]">{value}</span>
    </div>
  );
}

export function CourseDashboardResourceRow({
  title,
  subtitle,
  icon,
  trailing = "chevron",
  onClick,
}: {
  title: string;
  subtitle: string;
  icon: ReactNode;
  trailing?: "chevron" | "external";
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={!onClick}
      className="flex w-full items-center gap-3 py-2 text-left transition-opacity disabled:cursor-default"
    >
      <span className="flex w-[26px] shrink-0 justify-center text-[var(--color-text-light)]">
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <div className="truncate text-[13px] font-semibold text-[var(--color-text-main)]">
          {title}
        </div>
        <div className="truncate text-[12px] font-medium text-[var(--color-text-light)]">
          {subtitle}
        </div>
      </span>
      {onClick ? (
        trailing === "external" ? (
          <span className="text-[12px] text-[var(--color-text-light)] opacity-60">↗</span>
        ) : (
          <ChevronRight className="h-4 w-4 shrink-0 text-[var(--color-text-light)] opacity-60" />
        )
      ) : null}
    </button>
  );
}

export function CourseDashboardTaskRow({
  title,
  subtitle,
  dueAt,
  isComplete,
  badge,
  badgeTint,
}: {
  title: string;
  subtitle?: string;
  dueAt?: string;
  isComplete: boolean;
  badge: string;
  badgeTint: string;
}) {
  const due = dueAt ? new Date(dueAt) : null;
  const isPast = due ? due.getTime() < Date.now() && !isComplete : false;
  const accent = isComplete
    ? "var(--color-text-light)"
    : isPast
      ? "var(--color-error)"
      : "var(--color-text-light)";

  const dateLabel = due
    ? due.toLocaleDateString(undefined, { month: "short", day: "numeric" })
    : "—";
  const weekdayLabel = due
    ? due.toLocaleDateString(undefined, { weekday: "short" })
    : "";

  return (
    <div
      className="flex overflow-hidden rounded-xl border border-[var(--color-chrome-stroke)] shadow-[0_2px_6px_rgba(0,0,0,0.02)]"
      style={{
        background: isComplete
          ? "color-mix(in srgb, var(--color-surface) 55%, var(--color-content-surface))"
          : "var(--color-content-surface)",
        opacity: isComplete ? 0.65 : 1,
      }}
    >
      <div className="min-w-0 flex-1 p-4">
        <div className="mb-1.5 flex items-start gap-2">
          <span
            className="inline-flex rounded px-2 py-1 text-[10px] font-bold uppercase tracking-[0.04em]"
            style={{
              color: badgeTint,
              background: `color-mix(in srgb, ${badgeTint} 12%, transparent)`,
            }}
          >
            {badge}
          </span>
        </div>
        <div
          className="truncate text-[15px] font-bold text-[var(--color-text-main)]"
          style={{
            textDecoration: isComplete ? "line-through" : undefined,
            opacity: isComplete ? 0.38 : 1,
          }}
        >
          {title}
        </div>
        {subtitle ? (
          <div
            className="mt-1 line-clamp-2 text-[13px] text-[var(--color-text-light)]"
            style={{ opacity: isComplete ? 0.28 : 1 }}
          >
            {subtitle}
          </div>
        ) : null}
      </div>
      <div
        className="flex w-32 shrink-0 flex-col items-center justify-center border-l border-[var(--color-chrome-stroke)] px-2 py-4"
        style={{ background: "color-mix(in srgb, var(--color-surface) 35%, transparent)" }}
      >
        <div
          className="text-[10px] font-bold uppercase tracking-[0.06em]"
          style={{ color: accent, opacity: isComplete ? 0.45 : 1 }}
        >
          {isComplete ? "Done" : isPast ? "Past" : "Due date"}
        </div>
        <div
          className="text-[18px] font-bold tabular-nums"
          style={{ color: accent, opacity: isComplete ? 0.38 : 1 }}
        >
          {dateLabel}
        </div>
        <div
          className="text-[13px] text-[var(--color-text-light)]"
          style={{ opacity: isComplete ? 0.28 : 1 }}
        >
          {weekdayLabel}
        </div>
      </div>
    </div>
  );
}

export function courseProgressPercent(status: string): string {
  const state: PlannerStatusState = courseStatusState({ status });
  if (state === "completed") return "100%";
  if (state === "in_progress") return "55%";
  if (state === "remaining") return "0%";
  return "18%";
}
