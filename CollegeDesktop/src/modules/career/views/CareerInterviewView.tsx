import { AppCard, EmptyState, ListRow, StatusChip } from "@/design-system";
import { formatEventWhen } from "../format";
import {
  interviewStatuses,
  interviewStatusColor,
  interviewStatusLabels,
  type CareerAppLink,
  type InterviewPrepRow,
} from "../growthTypes";

export function CareerInterviewView({
  prepRows,
  apps,
  onOpenPrep,
}: {
  prepRows: InterviewPrepRow[];
  apps: CareerAppLink[];
  onOpenPrep: (prep: InterviewPrepRow) => void;
}) {
  return (
    <div className="min-h-0 flex-1 overflow-auto p-3">
      <AppCard title="Interview prep">
        {prepRows.length === 0 ? (
          <EmptyState
            title="No interviews scheduled"
            body="Plan questions, notes, and status for upcoming screens and onsite loops."
          />
        ) : (
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {prepRows.map((prep) => {
              const linkedApp = prep.applicationId
                ? apps.find((a) => a.id === prep.applicationId)
                : null;
              const status = interviewStatuses.includes(
                prep.status as (typeof interviewStatuses)[number],
              )
                ? (prep.status as (typeof interviewStatuses)[number])
                : "upcoming";
              return (
                <li key={prep.id}>
                  <ListRow
                    onClick={() => onOpenPrep(prep)}
                    title={prep.roleTitle || "Untitled role"}
                    subtitle={[
                      prep.company,
                      prep.scheduledAt ? formatEventWhen(prep.scheduledAt) : null,
                      linkedApp ? `App: ${linkedApp.roleTitle} @ ${linkedApp.company}` : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                    trailing={
                      <StatusChip
                        title={interviewStatusLabels[status]}
                        tint={interviewStatusColor[status]}
                        filled
                      />
                    }
                  />
                </li>
              );
            })}
          </ul>
        )}
      </AppCard>
    </div>
  );
}
