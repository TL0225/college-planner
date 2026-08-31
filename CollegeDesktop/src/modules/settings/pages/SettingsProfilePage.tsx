import { AppCard, Button } from "@/design-system";
import { StatusNote } from "../shared";
import { navigate } from "@/lib/shellNavigate";

export function SettingsProfilePage() {
  return (
    <div className="space-y-4">
      <AppCard title="Identity & Profile">
        <p className="mb-3 text-meta leading-relaxed">
          Your student profile, university credentials, major, bio, work experiences, and achievements
          are managed in the Library Hub.
        </p>
        <div className="flex flex-wrap gap-2 pt-1">
          <Button
            size="sm"
            onClick={() => navigate({ hub: "library", page: "identity" })}
          >
            Open Student Identity
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => navigate({ hub: "library", page: "portfolio" })}
          >
            View Portfolio
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => navigate({ hub: "library", page: "advisor" })}
          >
            Advisor Checklist
          </Button>
        </div>
      </AppCard>

      <StatusNote>
        Your identity information is stored locally and used to personalize academic audits, resume generation, and AI assistant context.
      </StatusNote>
    </div>
  );
}
