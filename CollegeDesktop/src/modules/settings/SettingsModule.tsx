import { AppPageHeader, Button } from "@/design-system";
import { SettingsProvider } from "./SettingsProvider";
import { SettingsYouPage } from "./pages/SettingsYouPage";
import { SettingsAppearancePage } from "./pages/SettingsAppearancePage";
import { SettingsConnectionsPage } from "./pages/SettingsConnectionsPage";
import { SettingsSchoolWorkPage } from "./pages/SettingsSchoolWorkPage";
import { SettingsAdvancedPage } from "./pages/SettingsAdvancedPage";
import { SettingsCalendarPage } from "./pages/SettingsCalendarPage";
import { SettingsLmsPage } from "./pages/SettingsLmsPage";
import { SettingsFinancePage } from "./pages/SettingsFinancePage";
import { SettingsCareerPage } from "./pages/SettingsCareerPage";
import { SettingsShortcutsPage } from "./pages/SettingsShortcutsPage";
import { PAGE_TITLES, type SettingsPage } from "./types";
import { useSettings } from "./useSettings";

export type { SettingsPage } from "./types";

function SettingsModuleContent({ page }: { page: SettingsPage }) {
  const { refresh, error } = useSettings();

  const sectionContent = (() => {
    switch (page) {
      case "you":
        return <SettingsYouPage />;
      case "appearance":
        return <SettingsAppearancePage />;
      case "connections":
        return <SettingsConnectionsPage />;
      case "school-work":
        return <SettingsSchoolWorkPage />;
      case "advanced":
        return <SettingsAdvancedPage />;
      case "calendar":
        return <SettingsCalendarPage />;
      case "lms":
        return <SettingsLmsPage />;
      case "finance":
        return <SettingsFinancePage />;
      case "career":
        return <SettingsCareerPage />;
      case "shortcuts":
        return <SettingsShortcutsPage />;
      case "profile":
      case "privacy":
      case "academics":
      case "assistant":
      case "documents":
      case "app":
      case "discovery":
        return <SettingsAdvancedPage />;
    }
  })();

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={PAGE_TITLES[page]}
        actions={
          <Button size="sm" variant="secondary" onClick={() => void refresh()}>
            Refresh
          </Button>
        }
      />
      {error && <p className="px-3 text-meta text-[var(--color-error)]">{error}</p>}
      <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3 pt-3 lg:grid lg:grid-cols-2 lg:gap-3 lg:space-y-0">
        {sectionContent}
      </div>
    </div>
  );
}

export function SettingsModule({ page }: { page: SettingsPage }) {
  return (
    <SettingsProvider page={page}>
      <SettingsModuleContent page={page} />
    </SettingsProvider>
  );
}
