import { AppCard, Button } from "@/design-system";
import { navigate } from "@/lib/shellNavigate";

export function CareerApplyView() {
  return (
    <div className="min-h-0 flex-1 overflow-auto p-3">
      <AppCard title="Apply profile">
        <p className="mb-3 text-meta leading-relaxed">
          Default autofill payload for Tier A–C apply flows. Edit identity in Library, then run
          autofill from an application row.
        </p>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => navigate({ hub: "library", page: "identity" })}>
            Edit identity
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => navigate({ hub: "career", page: "pipeline" })}
          >
            Open applications
          </Button>
        </div>
      </AppCard>
    </div>
  );
}
