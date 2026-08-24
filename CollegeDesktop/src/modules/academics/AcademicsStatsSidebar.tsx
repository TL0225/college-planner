import { MetricTile, ProgressBar, StatusChip } from "@/design-system";
import type { AuditSummary, GpaSummary } from "@/lib/ipc";

const LEGEND = [
  { label: "Completed", tint: "var(--color-success)" },
  { label: "In progress", tint: "var(--color-warning)" },
  { label: "Planned", tint: "var(--color-primary)" },
  { label: "Missing", tint: "var(--color-error)" },
] as const;

export function AcademicsStatsSidebar({
  summary,
  gpa,
  auditProgress,
  className,
}: {
  summary: AuditSummary | null;
  gpa: GpaSummary | null;
  auditProgress?: number | null;
  className?: string;
}) {
  const completed = summary?.completedCredits ?? 0;
  const planned = summary?.plannedCredits ?? 0;
  const totalTracked = completed + Math.max(0, planned - completed);
  const completedRatio = totalTracked > 0 ? completed / totalTracked : 0;

  return (
    <aside
      className={className}
      style={{
        borderRadius: 12,
        border: "1px solid var(--color-chrome-stroke)",
        background: "var(--color-surface)",
        boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
      }}
    >
      <div className="border-b border-[var(--color-chrome-stroke)] px-3 py-2.5">
        <div className="text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
          Planner stats
        </div>
      </div>

      <div className="space-y-3 p-3">
        <MetricTile
          label="Cumulative GPA"
          value={gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"}
          accent="var(--color-warning)"
        />

        <div className="grid grid-cols-2 gap-2">
          <MetricTile
            label="Completed"
            value={completed.toFixed(1)}
            accent="var(--color-success)"
          />
          <MetricTile label="Planned" value={planned.toFixed(1)} accent="var(--color-primary)" />
        </div>

        <div>
          <div className="mb-1.5 flex items-center justify-between text-[11px] text-[var(--color-text-light)]">
            <span className="font-semibold uppercase tracking-[0.04em]">Credit progress</span>
            <span className="tabular-nums">{Math.round(completedRatio * 100)}%</span>
          </div>
          <ProgressBar value={completedRatio} height={7} tint="var(--color-success)" />
        </div>

        {auditProgress != null ? (
          <div>
            <div className="mb-1.5 flex items-center justify-between text-[11px] text-[var(--color-text-light)]">
              <span className="font-semibold uppercase tracking-[0.04em]">Degree progress</span>
              <span className="tabular-nums">{Math.round(auditProgress * 100)}%</span>
            </div>
            <ProgressBar value={auditProgress} height={7} />
          </div>
        ) : null}

        <div>
          <div className="mb-2 text-[11px] font-semibold uppercase tracking-[0.04em] text-[var(--color-text-light)]">
            Legend
          </div>
          <ul className="space-y-1.5">
            {LEGEND.map((row) => (
              <li key={row.label} className="flex items-center gap-2 text-[12px]">
                <span
                  className="inline-block h-2 w-2 shrink-0 rounded-full"
                  style={{ background: row.tint }}
                />
                <span className="text-[var(--color-text-main)]">{row.label}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="flex flex-wrap gap-1.5 pt-1">
          <StatusChip
            title={`${summary?.semesterCount ?? 0} terms`}
            tint="var(--color-text-light)"
          />
          <StatusChip
            title={`${summary?.courseCount ?? 0} courses`}
            tint="var(--color-text-light)"
          />
          {gpa?.gradedCourses ? (
            <StatusChip
              title={`${gpa.gradedCourses} graded`}
              tint="var(--color-warning)"
              filled
            />
          ) : null}
        </div>
      </div>
    </aside>
  );
}
