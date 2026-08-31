import { useMemo } from "react";
import { AppCard, Button, EmptyState } from "@/design-system";

type BragEntry = {
  id: string;
  title: string;
  occurredAt?: string | null;
  summary: string;
};

type Props = {
  bragEntries: BragEntry[];
  onOpenBragBook: () => void;
};

export function PathingStoriesPanel({ bragEntries, onOpenBragBook }: Props) {
  const topEntries = useMemo(() => {
    return [...bragEntries]
      .sort((a, b) => {
        const aTime = a.occurredAt ? new Date(a.occurredAt).getTime() : 0;
        const bTime = b.occurredAt ? new Date(b.occurredAt).getTime() : 0;
        return bTime - aTime;
      })
      .slice(0, 3);
  }, [bragEntries]);

  return (
    <div className="space-y-3">
      <AppCard title="Stories from Brag Book">
        <p className="mb-3 text-meta">
          Accomplishment stories live in Brag Book — link wins here when building interview-ready
          narratives.
        </p>
        <div className="mb-3 flex items-center justify-between gap-2 rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2">
          <span className="text-meta">Total brag entries</span>
          <span
            className="text-section-title font-semibold tabular-nums text-[var(--color-primary)]"
            style={{ fontSize: 18 }}
          >
            {bragEntries.length}
          </span>
        </div>
        {topEntries.length === 0 ? (
          <EmptyState
            title="No stories yet"
            body="Add wins under Career → Brag Book, then return here."
          />
        ) : (
          <ul className="space-y-2">
            {topEntries.map((entry) => (
              <li
                key={entry.id}
                className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
              >
                <div className="text-body font-medium">
                  {entry.title}
                </div>
                {entry.occurredAt ? (
                  <p className="mt-0.5 text-caption">
                    {new Date(entry.occurredAt).toLocaleDateString()}
                  </p>
                ) : null}
                {entry.summary.trim() ? (
                  <p className="mt-1 text-meta leading-relaxed">
                    {entry.summary}
                  </p>
                ) : null}
              </li>
            ))}
          </ul>
        )}
        <div className="mt-3">
          <Button size="sm" variant="secondary" onClick={onOpenBragBook}>
            Open Brag Book
          </Button>
        </div>
      </AppCard>
    </div>
  );
}
