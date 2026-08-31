import { useState } from "react";
import { AppCard, Button } from "@/design-system";
import { SettingsAssistantPage } from "./SettingsAssistantPage";
import { SettingsDocumentsPage } from "./SettingsDocumentsPage";
import { SettingsAppPage } from "./SettingsAppPage";
import { SettingsShortcutsPage } from "./SettingsShortcutsPage";
import { SettingsCalendarPage } from "./SettingsCalendarPage";
import { SettingsLmsPage } from "./SettingsLmsPage";
import { SettingsFinancePage } from "./SettingsFinancePage";
import { SettingsCareerPage } from "./SettingsCareerPage";

function CollapsibleSection({
  title,
  summary,
  defaultOpen = false,
  children,
}: {
  title: string;
  summary: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <AppCard title={title}>
      <p className="mb-2 text-meta">{summary}</p>
      <Button size="sm" variant="secondary" onClick={() => setOpen((o) => !o)}>
        {open ? "Hide" : "Show"} details
      </Button>
      {open && <div className="mt-4 space-y-4">{children}</div>}
    </AppCard>
  );
}

/** Developer and power-user settings — collapsed by default. */
export function SettingsAdvancedPage() {
  return (
    <div className="space-y-4 lg:col-span-2">
      <CollapsibleSection
        title="AI assistant"
        summary="Runtime, models, and tool configuration."
      >
        <SettingsAssistantPage />
      </CollapsibleSection>
      <CollapsibleSection
        title="Files & folders"
        summary="Watched folders and import diagnostics."
      >
        <SettingsDocumentsPage />
      </CollapsibleSection>
      <CollapsibleSection
        title="Calendar OAuth (advanced)"
        summary="Paste Client IDs for Google and Outlook."
      >
        <SettingsCalendarPage />
      </CollapsibleSection>
      <CollapsibleSection title="Course portal (advanced)" summary="LMS URL and import settings.">
        <SettingsLmsPage />
      </CollapsibleSection>
      <CollapsibleSection title="Finance APIs" summary="Plaid and import configuration.">
        <SettingsFinancePage />
      </CollapsibleSection>
      <CollapsibleSection title="Career APIs" summary="Job board sync configuration.">
        <SettingsCareerPage />
      </CollapsibleSection>
      <CollapsibleSection
        title="Developer & system"
        summary="System readiness, platform info, and workspace export."
      >
        <SettingsAppPage />
      </CollapsibleSection>
      <CollapsibleSection title="Web shortcuts" summary="Sidebar links to registrar, email, LMS.">
        <SettingsShortcutsPage />
      </CollapsibleSection>
    </div>
  );
}
