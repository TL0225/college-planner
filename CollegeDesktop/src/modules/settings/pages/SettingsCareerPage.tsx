import { AppCard, StatusChip, FormField, fieldControlClass } from "@/design-system";
import { insetPanelStyle } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsCareerPage() {
  const { settings, setPref } = useSettings();

  return (
    <>
      <AppCard title="USAJobs API">
        <p className="mb-3 text-meta leading-relaxed">
          Federal openings sync via the official Search API (free key from{" "}
          <a
            href="https://developer.usajobs.gov/"
            className="text-[var(--color-primary)] hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            developer.usajobs.gov
          </a>
          ).
        </p>
        <FormField label="API key">
          <input
            className={fieldControlClass}
            type="password"
            value={settings["jobBoard.usajobs.apiKey"] ?? ""}
            onChange={(e) => void setPref("jobBoard.usajobs.apiKey", e.target.value)}
            placeholder="Authorization-Key"
          />
        </FormField>
        <FormField label="User email">
          <input
            className={fieldControlClass}
            value={settings["jobBoard.usajobs.userEmail"] ?? ""}
            onChange={(e) => void setPref("jobBoard.usajobs.userEmail", e.target.value)}
            placeholder="you@example.edu"
          />
        </FormField>
      </AppCard>
      <AppCard title="Apply autofill">
        <p className="mb-3 text-meta leading-relaxed">
          Greenhouse, Lever, Workday, and iCIMS contact fields fill when you open Apply in College.
          Oracle and Talemetry run Tier C inventory (field scan, no writes). Add phone and LinkedIn
          under Profile. Set work-authorization answers below for Tier B screening fields.
        </p>
        <div className="mb-3 flex flex-wrap gap-2">
          <StatusChip title="Greenhouse · Lever" tint="var(--color-success)" filled />
          <StatusChip title="Workday · iCIMS (Tier B)" tint="var(--color-primary)" filled />
          <StatusChip title="Oracle · Talemetry (Tier C)" tint="var(--color-warning)" filled />
        </div>
        <div className="flex flex-col gap-2">
          {(
            [
              ["career.apply.usAuthorized", "US authorized to work"],
              ["career.apply.requiresSponsorshipNow", "Requires sponsorship now"],
              ["career.apply.requiresSponsorshipFuture", "Requires sponsorship in future"],
            ] as const
          ).map(([key, label]) => (
            <div
              key={key}
              className="flex items-center justify-between gap-3 px-2.5 py-2.5"
              style={insetPanelStyle}
            >
              <span className="text-body">{label}</span>
              <input
                type="checkbox"
                checked={settings[key] === "true"}
                onChange={(e) => void setPref(key, e.target.checked ? "true" : "false")}
              />
            </div>
          ))}
        </div>
      </AppCard>
      <AppCard title="Openings">
        <div className="flex items-center justify-between gap-3 px-2.5 py-2.5" style={insetPanelStyle}>
          <span className="text-body">Sync public job boards on module open</span>
          <input
            type="checkbox"
            checked={settings["career.openings.autoSync"] === "true"}
            onChange={(e) =>
              void setPref("career.openings.autoSync", e.target.checked ? "true" : "false")
            }
          />
        </div>
      </AppCard>
    </>
  );
}
