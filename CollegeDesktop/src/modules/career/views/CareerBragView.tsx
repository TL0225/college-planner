import { AppCard, EmptyState, StatusChip } from "@/design-system";
import { formatDateLabel } from "../format";
import type { BragEntryRow } from "../growthTypes";

export function CareerBragView({
  entries,
  onOpenEntry,
}: {
  entries: BragEntryRow[];
  onOpenEntry: (entry: BragEntryRow) => void;
}) {
  return (
    <div className="min-h-0 flex-1 overflow-auto p-3">
      {entries.length === 0 ? (
        <AppCard title="Brag Book">
          <EmptyState
            title="No wins logged yet"
            body="Capture accomplishments, metrics, and evidence for interviews and performance reviews."
          />
        </AppCard>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {entries.map((entry) => (
            <button
              key={entry.id}
              type="button"
              onClick={() => onOpenEntry(entry)}
              className="text-left transition-colors hover:bg-[var(--color-row-hover)]"
              style={{
                borderRadius: 12,
                border: "1px solid var(--color-chrome-stroke)",
                background: "var(--color-content-surface)",
                boxShadow: "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
                padding: "14px 16px",
              }}
            >
              <div className="flex items-start justify-between gap-2">
                <h3
                  className="text-[var(--color-text-main)]"
                  style={{ font: "var(--type-section-title)", fontSize: 14 }}
                >
                  {entry.title}
                </h3>
                <StatusChip title={formatDateLabel(entry.occurredAt)} filled />
              </div>
              {entry.summary.trim() ? (
                <p className="mt-2 line-clamp-3 text-meta leading-relaxed">
                  {entry.summary}
                </p>
              ) : (
                <p className="mt-2 text-meta">No summary</p>
              )}
              {entry.evidenceNote.trim() ? (
                <p className="mt-2 text-caption">
                  Evidence: {entry.evidenceNote}
                </p>
              ) : null}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
