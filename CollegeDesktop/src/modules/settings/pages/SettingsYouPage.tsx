import { SettingsProfilePage } from "./SettingsProfilePage";
import { SettingsPrivacyPage } from "./SettingsPrivacyPage";

/** Profile, privacy, and backups — student-facing settings. */
export function SettingsYouPage() {
  return (
    <div className="space-y-4 lg:col-span-2">
      <SettingsProfilePage />
      <SettingsPrivacyPage />
    </div>
  );
}
