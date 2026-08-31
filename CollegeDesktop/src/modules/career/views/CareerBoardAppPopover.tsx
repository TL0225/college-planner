import type { ReactNode } from "react";
import { Button, FormField, StatusChip, colors, fieldControlClass } from "@/design-system";
import {
  laneColor,
  statuses,
  statusLabels,
  type CareerAppRow,
} from "./CareerPipelineView";

export function CareerBoardAppPopover({
  app,
  interviewTimeline,
  lastApplySessionId,
  onStatusChange,
  onApplyInCollege,
  onMarkApplied,
  onOpenInBrowser,
  onClose,
  onDelete,
}: {
  app: CareerAppRow;
  interviewTimeline: ReactNode;
  lastApplySessionId: string | null;
  onStatusChange: (appId: string, status: string) => void | Promise<void>;
  onApplyInCollege: (app: CareerAppRow) => void;
  onMarkApplied: (appId: string) => void;
  onOpenInBrowser: (url: string) => void;
  onClose: () => void;
  onDelete: (app: CareerAppRow) => void;
}) {
  return (
    <div
      className="absolute bottom-4 right-4 z-20 w-[320px] overflow-hidden"
      style={{
        borderRadius: 14,
        border: "1px solid var(--color-chrome-stroke)",
        background: "var(--color-content-surface)",
        boxShadow:
          "0 12px 40px rgba(0,0,0,0.14), inset 0 1px 0 color-mix(in srgb, white 40%, transparent)",
      }}
    >
      <div
        className="border-b border-[var(--color-chrome-stroke)] px-4 py-3"
        style={{
          background: `linear-gradient(90deg, color-mix(in srgb, ${laneColor[app.status] ?? colors.careerLaneInterested} 14%, transparent), transparent)`,
        }}
      >
        <h3
          className="text-[var(--color-text-main)]"
          style={{ font: "var(--type-section-title)", fontSize: 15, letterSpacing: "-0.02em" }}
        >
          {app.roleTitle}
        </h3>
        <p className="mt-0.5 text-meta">{app.company}</p>
        <div className="mt-2">
          <StatusChip
            title={statusLabels[app.status as (typeof statuses)[number]] ?? app.status}
            tint={laneColor[app.status] ?? colors.careerLaneInterested}
            filled
          />
        </div>
      </div>
      <div className="space-y-3 p-4">
        <FormField label="Move to">
          <select
            className={fieldControlClass}
            value={app.status}
            onChange={(e) => void onStatusChange(app.id, e.target.value)}
          >
            {statuses.map((s) => (
              <option key={s} value={s}>
                {statusLabels[s]}
              </option>
            ))}
          </select>
        </FormField>
        {interviewTimeline}
        {app.url.trim() ? (
          <p className="break-all text-caption">{app.url}</p>
        ) : null}
        <div className="flex flex-wrap gap-2">
          {app.url.trim() ? (
            <>
              <Button size="sm" onClick={() => void onApplyInCollege(app)}>
                Apply in College
              </Button>
              {lastApplySessionId === app.id ? (
                <Button size="sm" variant="secondary" onClick={() => void onMarkApplied(app.id)}>
                  Mark applied
                </Button>
              ) : null}
              <Button
                size="sm"
                variant="secondary"
                onClick={() => void onOpenInBrowser(app.url)}
              >
                Open in browser
              </Button>
            </>
          ) : null}
          <Button size="sm" variant="ghost" onClick={onClose}>
            Close
          </Button>
          <Button size="sm" variant="danger" onClick={() => void onDelete(app)}>
            Delete
          </Button>
        </div>
      </div>
    </div>
  );
}
