import type { DragEvent, ReactNode } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  KanbanLaneHeader,
  LaneDot,
  ListRow,
  MetricTile,
  StatusChip,
  TrailingInspector,
  colors,
  fieldControlClass,
} from "@/design-system";
import type { PipelineMetrics } from "@/lib/ipc";
import { CareerBoardAppPopover } from "./CareerBoardAppPopover";

export type CareerAppRow = {
  id: string;
  company: string;
  roleTitle: string;
  status: string;
  location: string;
  url: string;
  appliedAt?: string;
};

export const laneColor: Record<string, string> = {
  interested: colors.careerLaneInterested,
  applied: colors.careerLaneApplied,
  interviewing: colors.careerLaneInterviewing,
  offer: colors.careerLaneOffer,
  rejected: colors.careerLaneRejected,
  accepted: colors.careerLaneAccepted,
};

export const statuses = [
  "interested",
  "applied",
  "interviewing",
  "offer",
  "rejected",
  "accepted",
] as const;

export const statusLabels: Record<(typeof statuses)[number], string> = {
  interested: "Interested",
  applied: "Applied",
  interviewing: "Interviewing",
  offer: "Offer",
  rejected: "Rejected",
  accepted: "Accepted",
};

export const CAREER_APP_DRAG = "application/x-college-career-app";

export type CareerPipelineViewProps = {
  metrics: PipelineMetrics | null;
  apps: CareerAppRow[];
  effectiveLayout: "board" | "list";
  byStatus: Map<string, CareerAppRow[]>;
  selected: string | null;
  selectedApp: CareerAppRow | null;
  dropTargetStatus: string | null;
  lastApplySessionId: string | null;
  interviewTimeline: ReactNode;
  onSelectApp: (id: string) => void;
  onClearSelection: () => void;
  onLaneDragOver: (e: DragEvent, status: string) => void;
  onLaneDragLeave: (status: string) => void;
  onLaneDrop: (e: DragEvent, status: string, beforeAppId?: string) => void;
  onStatusChange: (appId: string, status: string) => void | Promise<void>;
  onApplyInCollege: (app: CareerAppRow) => void;
  onMarkApplied: (appId: string) => void;
  onOpenInBrowser: (url: string) => void;
  onEditApp: (app: CareerAppRow) => void;
  onDeleteApp: (app: CareerAppRow) => void;
};

export function CareerPipelineView({
  metrics,
  apps,
  effectiveLayout,
  byStatus,
  selected,
  selectedApp,
  dropTargetStatus,
  lastApplySessionId,
  interviewTimeline,
  onSelectApp,
  onClearSelection,
  onLaneDragOver,
  onLaneDragLeave,
  onLaneDrop,
  onStatusChange,
  onApplyInCollege,
  onMarkApplied,
  onOpenInBrowser,
  onEditApp,
  onDeleteApp,
}: CareerPipelineViewProps) {
  return (
    <>
      <div className="grid gap-2.5 px-3 pt-1 sm:grid-cols-3 lg:grid-cols-6">
        {(
          [
            ["Interested", metrics?.interested, colors.careerLaneInterested],
            ["Applied", metrics?.applied, colors.careerLaneApplied],
            ["Interviewing", metrics?.interviewing, colors.careerLaneInterviewing],
            ["Offer", metrics?.offer, colors.careerLaneOffer],
            ["Rejected", metrics?.rejected, colors.careerLaneRejected],
            ["Accepted", metrics?.accepted, colors.careerLaneAccepted],
          ] as const
        ).map(([label, value, accent]) => (
          <MetricTile key={label} label={label} value={value ?? 0} accent={accent} />
        ))}
      </div>
      <div className="min-h-0 flex-1 p-3 pt-3">
        {effectiveLayout === "board" ? (
          <div className="flex h-full gap-2.5 overflow-x-auto pb-1">
            {statuses.map((status) => {
              const lane = byStatus.get(status) ?? [];
              const isDropTarget = dropTargetStatus === status;
              return (
                <div
                  key={status}
                  className="flex w-[232px] shrink-0 flex-col overflow-hidden"
                  style={{
                    borderRadius: 14,
                    border: isDropTarget
                      ? "1px solid color-mix(in srgb, var(--color-primary) 55%, var(--color-chrome-stroke))"
                      : "1px solid var(--color-chrome-stroke)",
                    background: isDropTarget
                      ? "color-mix(in srgb, var(--color-primary) 8%, var(--color-surface))"
                      : "var(--color-surface)",
                    boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
                  }}
                  onDragOver={(e) => onLaneDragOver(e, status)}
                  onDragLeave={() => onLaneDragLeave(status)}
                  onDrop={(e) => void onLaneDrop(e, status)}
                >
                  <KanbanLaneHeader
                    title={statusLabels[status]}
                    count={lane.length}
                    tint={laneColor[status]!}
                  />
                  <div className="min-h-0 flex-1 space-y-2 overflow-y-auto p-2">
                    {lane.length === 0 ? (
                      <p className="px-1 py-3 text-center text-caption">
                        Empty lane
                      </p>
                    ) : (
                      lane.map((a) => (
                        <button
                          key={a.id}
                          type="button"
                          draggable
                          onDragStart={(e) => {
                            e.dataTransfer.effectAllowed = "move";
                            e.dataTransfer.setData(CAREER_APP_DRAG, a.id);
                            e.dataTransfer.setData("text/plain", a.roleTitle);
                          }}
                          onDragOver={(e) => {
                            e.preventDefault();
                            e.stopPropagation();
                          }}
                          onDrop={(e) => {
                            e.stopPropagation();
                            void onLaneDrop(e, status, a.id);
                          }}
                          onClick={() => onSelectApp(a.id)}
                          className={`w-full px-2.5 py-2.5 text-left transition-colors ${
                            selected === a.id
                              ? "bg-[var(--color-primary-soft)]"
                              : "bg-[var(--color-content-surface)] hover:bg-[var(--color-row-hover)]"
                          }`}
                          style={{
                            borderRadius: 10,
                            border:
                              selected === a.id
                                ? "1px solid color-mix(in srgb, var(--color-primary) 40%, var(--color-chrome-stroke))"
                                : "1px solid var(--color-chrome-stroke)",
                            boxShadow:
                              selected === a.id
                                ? "var(--shadow-pill)"
                                : "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
                            cursor: "grab",
                          }}
                        >
                          <div className="truncate text-body font-semibold tracking-[-0.01em] text-[var(--color-text-main)]">
                            {a.roleTitle}
                          </div>
                          <div className="mt-0.5 truncate text-caption">
                            {a.company}
                          </div>
                          {a.location ? (
                            <div className="mt-1.5">
                              <StatusChip title={a.location} />
                            </div>
                          ) : null}
                        </button>
                      ))
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <TrailingInspector
            open={!!selectedApp}
            storageKey="career.inspectorWidth"
            main={
              <AppCard title="Pipeline">
                {apps.length === 0 ? (
                  <EmptyState
                    title="No applications yet"
                    body="Track roles here, or load sample data from Settings."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {apps.map((a) => (
                      <li key={a.id}>
                        <ListRow
                          selected={selected === a.id}
                          onClick={() => onSelectApp(a.id)}
                          leading={
                            <LaneDot
                              color={laneColor[a.status] ?? colors.careerLaneInterested}
                              size={9}
                            />
                          }
                          title={a.roleTitle || "Untitled role"}
                          subtitle={`${a.company}${a.location ? ` · ${a.location}` : ""}`}
                          trailing={
                            <StatusChip
                              title={statusLabels[a.status as (typeof statuses)[number]] ?? a.status}
                              tint={laneColor[a.status] ?? colors.careerLaneInterested}
                              filled
                            />
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
            }
          >
            {selectedApp && (
              <div className="flex h-full flex-col">
                <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
                  <h3
                    className="text-[var(--color-text-main)]"
                    style={{
                      font: "var(--type-section-title)",
                      fontSize: 16,
                      letterSpacing: "-0.02em",
                    }}
                  >
                    {selectedApp.roleTitle}
                  </h3>
                  <p className="mt-0.5 text-meta">
                    {selectedApp.company}
                  </p>
                  <div className="mt-2">
                    <StatusChip
                      title={
                        statusLabels[selectedApp.status as (typeof statuses)[number]] ??
                        selectedApp.status
                      }
                      tint={laneColor[selectedApp.status] ?? colors.careerLaneInterested}
                      filled
                    />
                  </div>
                </div>
                <div className="min-h-0 flex-1 space-y-3 overflow-auto p-4">
                  <FormField label="Status">
                    <select
                      className={fieldControlClass}
                      value={selectedApp.status}
                      onChange={(e) => void onStatusChange(selectedApp.id, e.target.value)}
                    >
                      {statuses.map((s) => (
                        <option key={s} value={s}>
                          {statusLabels[s]}
                        </option>
                      ))}
                    </select>
                  </FormField>
                  {selectedApp.location && (
                    <p className="text-meta">
                      {selectedApp.location}
                    </p>
                  )}
                  {selectedApp.url.trim() ? (
                    <p className="break-all text-caption">
                      {selectedApp.url}
                    </p>
                  ) : null}
                  {interviewTimeline}
                </div>
                <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                  {selectedApp.url.trim() ? (
                    <>
                      <Button size="sm" onClick={() => void onApplyInCollege(selectedApp)}>
                        Apply in College
                      </Button>
                      {lastApplySessionId === selectedApp.id ? (
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => void onMarkApplied(selectedApp.id)}
                        >
                          Mark applied
                        </Button>
                      ) : null}
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => void onOpenInBrowser(selectedApp.url)}
                      >
                        Open in browser
                      </Button>
                    </>
                  ) : null}
                  <Button size="sm" variant="secondary" onClick={() => onEditApp(selectedApp)}>
                    Edit
                  </Button>
                  <Button size="sm" variant="ghost" onClick={onClearSelection}>
                    Close
                  </Button>
                  <Button
                    size="sm"
                    variant="danger"
                    onClick={() => void onDeleteApp(selectedApp)}
                  >
                    Delete
                  </Button>
                </div>
              </div>
            )}
          </TrailingInspector>
        )}
      </div>
      {effectiveLayout === "board" && selectedApp ? (
        <CareerBoardAppPopover
          app={selectedApp}
          interviewTimeline={interviewTimeline}
          lastApplySessionId={lastApplySessionId}
          onStatusChange={onStatusChange}
          onApplyInCollege={onApplyInCollege}
          onMarkApplied={onMarkApplied}
          onOpenInBrowser={onOpenInBrowser}
          onClose={onClearSelection}
          onDelete={onDeleteApp}
        />
      ) : null}
    </>
  );
}
