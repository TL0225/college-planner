import { SettingsAcademicsPage } from "./SettingsAcademicsPage";
import { SettingsDiscoveryPage } from "./SettingsDiscoveryPage";

/** Academic programs and school discovery settings. */
export function SettingsSchoolWorkPage() {
  return (
    <div className="space-y-4 lg:col-span-2">
      <SettingsAcademicsPage />
      <SettingsDiscoveryPage />
    </div>
  );
}
