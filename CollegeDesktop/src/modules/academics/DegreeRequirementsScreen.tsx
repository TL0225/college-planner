import type { DragEvent, ReactNode } from "react";
import {
  GuidedEmptyState,
  HumanStatusChip,
  MetricTile,
  ProgressBar,
} from "@/design-system";
import { FlatSectionTitle, PathCScreenFrame } from "@/design-system";
import type { AuditSummary, GpaSummary } from "@/lib/ipc";
import { ProgramBrowser } from "./ProgramBrowser";
import type { PlannerDragPayload } from "./plannerDrag";

export type AuditItem = {
  id: string;
  sectionTitle: string;
  creditsRequired?: number | null;
  creditsEarned: number;
  status: string;
  matchedCodes: string[];
  missingCodes: string[];
};

export function DegreeRequirementsScreen({
  audit,
  summary,
  gpaSummary,
  highlightSectionId,
  dropTargetCategoryId,
  onDropTargetChange,
  onRequirementDrop,
  readRequirementDropPayload,
  onCreditsClick,
  onGpaClick,
  onProgramChanged,
  courseCreditsByCode,
  requirementDragChip,
}: {
  audit: {
    items: AuditItem[];
    satisfiedCount: number;
    totalCount: number;
    progressRatio: number;
  } | null;
  summary: AuditSummary | null;
  gpaSummary: GpaSummary | null;
  highlightSectionId?: string;
  dropTargetCategoryId: string | null;
  onDropTargetChange: (id: string | null) => void;
  onRequirementDrop: (categoryId: string, payload: PlannerDragPayload) => void;
  readRequirementDropPayload: (e: DragEvent) => PlannerDragPayload | null;
  onCreditsClick: () => void;
  onGpaClick: () => void;
  onProgramChanged: () => void;
  courseCreditsByCode?: Map<string, number>;
  requirementDragChip: (payload: PlannerDragPayload) => ReactNode;
}) {
  return (
    <PathCScreenFrame>
      <ProgramBrowser onActiveChanged={onProgramChanged} />

      <div className="mt-3 grid gap-2.5 md:grid-cols-4">
        <MetricTile label="Satisfied" value={`${audit?.satisfiedCount ?? 0}/${audit?.totalCount ?? 0}`} accent="var(--color-success)" />
        <MetricTile label="Progress" value={`${Math.round((audit?.progressRatio ?? 0) * 100)}%`} accent="var(--color-primary)" />
        <button type="button" className="text-left" onClick={onCreditsClick}>
          <MetricTile label="Completed credits" value={summary?.completedCredits.toFixed(1) ?? "—"} />
        </button>
        <button type="button" className="text-left" onClick={onGpaClick}>
          <MetricTile label="GPA" value={gpaSummary?.gpa != null ? gpaSummary.gpa.toFixed(2) : "—"} accent="var(--color-warning)" />
        </button>
      </div>

      {audit && audit.totalCount > 0 ? (
        <div
          className="mt-3 px-1"
          style={{
            padding: "12px 14px",
            borderRadius: 12,
            border: "1px solid var(--color-chrome-stroke)",
            background: "var(--color-surface)",
            boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
          }}
        >
          <div className="mb-2 flex items-center justify-between text-caption">
            <FlatSectionTitle accent="var(--color-text-light)">Degree progress</FlatSectionTitle>
            <span className="tabular-nums">
              {audit.satisfiedCount}/{audit.totalCount} sections
            </span>
          </div>
          <ProgressBar value={audit.progressRatio} height={8} />
        </div>
      ) : null}

      <div className="mt-4">
        <FlatSectionTitle>Requirements breakdown</FlatSectionTitle>
        {!audit || audit.items.length === 0 ? (
          <div className="mt-3">
            <GuidedEmptyState
              title="No requirements loaded"
              subtitle="Try demo data to see a sample degree audit, or add your program from the catalog."
              showDemoSeed
            />
          </div>
        ) : (
          <ul className="mt-3 space-y-2">
            {audit.items.map((item) => {
              const ratio =
                item.creditsRequired != null && item.creditsRequired > 0
                  ? item.creditsEarned / item.creditsRequired
                  : item.status === "satisfied"
                    ? 1
                    : item.status === "in_progress"
                      ? 0.5
                      : 0;
              const tint = requirementStatusTint(item.status);
              const acceptsFulfillment = item.status !== "satisfied" || item.missingCodes.length > 0;
              const isDropTarget = dropTargetCategoryId === item.id;
              return (
                <li
                  key={item.id}
                  id={`req-section-${item.id}`}
                  className="px-3 py-2.5 transition-colors"
                  onDragOver={(e) => {
                    if (!acceptsFulfillment) return;
                    e.preventDefault();
                    e.dataTransfer.dropEffect = "copy";
                    onDropTargetChange(item.id);
                  }}
                  onDragLeave={() => onDropTargetChange(null)}
                  onDrop={(e) => {
                    e.preventDefault();
                    onDropTargetChange(null);
                    if (!acceptsFulfillment) return;
                    const payload = readRequirementDropPayload(e);
                    if (!payload) return;
                    onRequirementDrop(item.id, payload);
                  }}
                  style={{
                    borderRadius: 10,
                    border: isDropTarget
                      ? "1px solid color-mix(in srgb, var(--color-primary) 55%, var(--color-chrome-stroke))"
                      : highlightSectionId === item.id
                        ? "1px solid color-mix(in srgb, var(--color-primary) 45%, var(--color-chrome-stroke))"
                        : "1px solid var(--color-chrome-stroke)",
                    background: isDropTarget
                      ? "color-mix(in srgb, var(--color-primary) 10%, var(--color-content-surface))"
                      : highlightSectionId === item.id
                        ? "color-mix(in srgb, var(--color-primary) 6%, var(--color-content-surface))"
                        : "var(--color-content-surface)",
                  }}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="text-section-title tracking-[-0.01em]">
                        {item.sectionTitle}
                      </div>
                      <div className="mt-0.5 text-caption">
                        {item.matchedCodes.length > 0 && <span>Matched {item.matchedCodes.join(", ")}. </span>}
                        {item.missingCodes.length > 0 && <span>Missing {item.missingCodes.join(", ")}. </span>}
                        {item.creditsRequired != null && (
                          <span>
                            {item.creditsEarned.toFixed(1)} / {item.creditsRequired.toFixed(1)} cr
                          </span>
                        )}
                      </div>
                    </div>
                    <HumanStatusChip value={item.status} tint={tint} filled />
                  </div>
                  <ProgressBar value={ratio} tint={tint} className="mt-2.5" />
                  {acceptsFulfillment ? (
                    <p className="mt-2 text-label">
                      Drop a course code here to manually fulfill this section.
                    </p>
                  ) : null}
                  {item.missingCodes.length > 0 ? (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {item.missingCodes.map((code) =>
                        requirementDragChip({
                          code,
                          title: code,
                          credits:
                            courseCreditsByCode?.get(code.trim().toUpperCase()) ??
                            (item.creditsRequired != null &&
                            item.creditsRequired > 0 &&
                            item.missingCodes.length > 0
                              ? item.creditsRequired / item.missingCodes.length
                              : 3),
                          source: "requirement",
                        }),
                      )}
                    </div>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {audit && audit.totalCount > 0 ? (
        <div
          className="sticky bottom-0 mt-4 border-t border-[var(--color-chrome-stroke)] pt-3"
          style={{ background: "color-mix(in srgb, var(--color-content-surface) 92%, transparent)" }}
        >
          <div className="flex flex-wrap gap-2">
            {audit.items.slice(0, 6).map((item) => (
              <button
                key={item.id}
                type="button"
                className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-caption font-medium"
                onClick={() => document.getElementById(`req-section-${item.id}`)?.scrollIntoView({ behavior: "smooth", block: "center" })}
              >
                {item.sectionTitle}
              </button>
            ))}
          </div>
        </div>
      ) : null}
    </PathCScreenFrame>
  );
}

function requirementStatusTint(status: string): string {
  switch (status) {
    case "satisfied":
      return "var(--color-success)";
    case "in_progress":
      return "var(--color-warning)";
    case "open":
      return "var(--color-primary)";
    default:
      return "var(--color-error)";
  }
}
