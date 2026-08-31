import { AppCard, Button, MetricTile } from "@/design-system";
import type { PipelineMetrics } from "@/lib/ipc";
import { navigate } from "@/lib/shellNavigate";

export function CareerStatsView({
  metrics,
  appCount,
}: {
  metrics: PipelineMetrics | null;
  appCount: number;
}) {
  return (
    <div className="min-h-0 flex-1 overflow-auto p-3">
      <AppCard title="Pipeline stats">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <MetricTile label="Total" value={metrics?.total ?? appCount} accent="var(--color-primary)" />
          <MetricTile label="Applied" value={metrics?.applied ?? "—"} />
          <MetricTile
            label="Interviewing"
            value={metrics?.interviewing ?? "—"}
            accent="var(--color-success)"
          />
          <MetricTile label="Offers" value={metrics?.offer ?? "—"} accent="var(--color-success)" />
        </div>
        <Button
          size="sm"
          variant="secondary"
          className="mt-3"
          onClick={() => navigate({ hub: "career", page: "pipeline" })}
        >
          Open pipeline
        </Button>
      </AppCard>
    </div>
  );
}
