import { AppCard, Button, FormField, fieldControlClass } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { StatusNote } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsDiscoveryPage() {
  const { settings, setPref, discoverySyncNote, setDiscoverySyncNote } = useSettings();

  return (
    <AppCard title="College Scorecard">
      <p className="mb-3 text-meta leading-relaxed">
        Sync federal admissions stats from the public College Scorecard API (
        <a
          href="https://api.data.gov/signup/"
          className="text-[var(--color-primary)] hover:underline"
          target="_blank"
          rel="noreferrer"
        >
          api.data.gov
        </a>
        ) for institutions already in Discovery with a unit ID.
      </p>
      <FormField label="API key (optional)">
        <input
          className={fieldControlClass}
          type="password"
          value={settings["discovery.scorecard.apiKey"] ?? ""}
          onChange={(e) => void setPref("discovery.scorecard.apiKey", e.target.value)}
          placeholder="Higher rate limits when set"
        />
      </FormField>
      <Button
        size="sm"
        onClick={async () => {
          setDiscoverySyncNote("Syncing federal data…");
          try {
            const res = await ipc.discoverySyncFederalData();
            const errTail =
              res.errors.length > 0 ? ` · ${res.errors.slice(0, 2).join("; ")}` : "";
            setDiscoverySyncNote(
              `Synced ${res.synced}, skipped ${res.skipped}${errTail}`,
            );
            showToast(`Federal sync finished (${res.synced} updated)`, "success");
          } catch (e) {
            setDiscoverySyncNote(formatIpcError(e));
            showToast(formatIpcError(e), "error");
          }
        }}
      >
        Sync federal data
      </Button>
      {discoverySyncNote ? <StatusNote>{discoverySyncNote}</StatusNote> : null}
    </AppCard>
  );
}
