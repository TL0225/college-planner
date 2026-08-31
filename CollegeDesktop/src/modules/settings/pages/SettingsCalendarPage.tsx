import { AppCard, Button, StatusChip, FormField, fieldControlClass } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { StatusNote } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsCalendarPage() {
  const {
    oauthDraft,
    setOauthDraft,
    setPref,
    googleClientId,
    outlookClientId,
    oauthNote,
    setOauthNote,
  } = useSettings();

  return (
    <AppCard title="Calendar OAuth">
      <p className="mb-3 text-meta leading-relaxed">
        Paste OAuth Client IDs from Google Cloud Console or Azure App Registration. Secrets stay
        in local app settings (not committed). Register redirect URI{" "}
        <code className="text-caption">http://127.0.0.1:&lt;port&gt;/oauth/callback</code> as a
        loopback / native redirect.
      </p>
      <div className="space-y-3">
        <FormField label="Google Client ID">
          <input
            className={fieldControlClass}
            value={oauthDraft.googleClientId}
            onChange={(e) =>
              setOauthDraft((d) => ({ ...d, googleClientId: e.target.value }))
            }
            placeholder="123456789.apps.googleusercontent.com"
            autoComplete="off"
          />
        </FormField>
        <FormField label="Google Client Secret (optional for PKCE)">
          <input
            className={fieldControlClass}
            type="password"
            value={oauthDraft.googleClientSecret}
            onChange={(e) =>
              setOauthDraft((d) => ({ ...d, googleClientSecret: e.target.value }))
            }
            autoComplete="off"
          />
        </FormField>
        <FormField label="Outlook Client ID">
          <input
            className={fieldControlClass}
            value={oauthDraft.outlookClientId}
            onChange={(e) =>
              setOauthDraft((d) => ({ ...d, outlookClientId: e.target.value }))
            }
            placeholder="Azure application (client) ID"
            autoComplete="off"
          />
        </FormField>
        <FormField label="Outlook tenant">
          <input
            className={fieldControlClass}
            value={oauthDraft.outlookTenant}
            onChange={(e) =>
              setOauthDraft((d) => ({ ...d, outlookTenant: e.target.value || "common" }))
            }
            placeholder="common"
            autoComplete="off"
          />
        </FormField>
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Button
          size="sm"
          onClick={async () => {
            setOauthNote("Saving…");
            try {
              await Promise.all([
                setPref("oauth.google.clientId", oauthDraft.googleClientId.trim()),
                setPref("oauth.google.clientSecret", oauthDraft.googleClientSecret.trim()),
                setPref("oauth.outlook.clientId", oauthDraft.outlookClientId.trim()),
                setPref(
                  "oauth.outlook.tenant",
                  oauthDraft.outlookTenant.trim() || "common",
                ),
              ]);
              setOauthNote("OAuth credentials saved.");
              showToast("OAuth credentials saved", "success");
            } catch (e) {
              setOauthNote(formatIpcError(e));
            }
          }}
        >
          Save OAuth credentials
        </Button>
        <Button
          size="sm"
          variant="secondary"
          onClick={async () => {
            setOauthNote("Syncing…");
            try {
              const res = await ipc.calendarOauthSyncAll();
              if (res.accounts === 0) {
                setOauthNote("No connected accounts — connect Google/Outlook in Calendar → Sources.");
                return;
              }
              const err = res.errors.length ? ` Errors: ${res.errors.join("; ")}` : "";
              setOauthNote(
                `Synced ${res.imported} events from ${res.accounts} account(s).${err}`,
              );
              showToast(`Synced ${res.imported} events`, res.errors.length ? "error" : "success");
            } catch (e) {
              setOauthNote(formatIpcError(e));
            }
          }}
        >
          Sync connected calendars
        </Button>
        <StatusChip
          title={
            googleClientId || outlookClientId
              ? `${googleClientId ? "Google" : ""}${googleClientId && outlookClientId ? " · " : ""}${outlookClientId ? "Outlook" : ""} configured`
              : "No credentials yet"
          }
          tint={
            googleClientId || outlookClientId
              ? "var(--color-success)"
              : "var(--color-warning)"
          }
          filled={Boolean(googleClientId || outlookClientId)}
        />
      </div>
      {oauthNote && <StatusNote>{oauthNote}</StatusNote>}
    </AppCard>
  );
}
