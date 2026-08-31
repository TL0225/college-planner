import { Button, PathTimeline } from "@/design-system";
import { formatEventWhen } from "../format";
import { eventKindColor, eventKindLabels, eventKinds } from "../CareerModals";

export type CareerEventRow = {
  id: string;
  applicationId?: string | null;
  title: string;
  occursAt: string;
  kind: string;
  notes: string;
};

export function CareerInterviewTimeline({
  events,
  onAdd,
  onEdit,
}: {
  events: CareerEventRow[];
  onAdd: () => void;
  onEdit: (event: CareerEventRow) => void;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <p className="text-label font-semibold uppercase tracking-[0.06em]">
          Interview timeline
        </p>
        <Button size="sm" variant="secondary" onClick={onAdd}>
          Add event
        </Button>
      </div>
      {events.length === 0 ? (
        <p className="text-meta">No events yet.</p>
      ) : (
        <PathTimeline
          items={events.map((event) => {
            const kind = eventKinds.includes(event.kind as (typeof eventKinds)[number])
              ? (event.kind as (typeof eventKinds)[number])
              : "other";
            return {
              id: event.id,
              title: event.title,
              subtitle: eventKindLabels[kind],
              meta: formatEventWhen(event.occursAt),
              color: eventKindColor[kind],
              onClick: () => onEdit(event),
            };
          })}
        />
      )}
    </div>
  );
}
