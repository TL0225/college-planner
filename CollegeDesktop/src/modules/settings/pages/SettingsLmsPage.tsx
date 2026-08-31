import { useCallback, useEffect, useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { AppCard, Button, FormField, fieldControlClass } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { StatusNote } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsLmsPage() {
  const { settings, setPref } = useSettings();
  const [canvasBaseUrl, setCanvasBaseUrl] = useState("");
  const [canvasToken, setCanvasToken] = useState("");
  const [canvasConnected, setCanvasConnected] = useState(false);
  const [canvasAuthMethod, setCanvasAuthMethod] = useState<string | null>(null);
  const [canvasBusy, setCanvasBusy] = useState(false);
  const [syncBusy, setSyncBusy] = useState(false);
  const [oauthClientId, setOauthClientId] = useState(settings["lms.canvas.clientId"] ?? "");
  const [oauthClientSecret, setOauthClientSecret] = useState("");
  const [oauthBusy, setOauthBusy] = useState(false);

  const loadCanvas = useCallback(async () => {
    const config = await ipc.lmsCanvasGetConfig();
    setCanvasBaseUrl(config.baseUrl || settings["lms.defaultPortalUrl"] || "");
    setCanvasConnected(config.connected);
    setCanvasAuthMethod(config.authMethod ?? null);
    setCanvasToken("");
  }, [settings]);

  useEffect(() => {
    void loadCanvas();
  }, [loadCanvas]);

  const connectCanvasOAuth = async () => {
    if (!canvasBaseUrl.trim()) {
      showToast("Enter your Canvas base URL first", "error");
      return;
    }
    setOauthBusy(true);
    try {
      await ipc.lmsCanvasOAuthSetCredentials({
        clientId: oauthClientId.trim(),
        clientSecret: oauthClientSecret,
      });
      const begin = await ipc.lmsCanvasOAuthBegin(canvasBaseUrl.trim());
      await openUrl(begin.authUrl);
      const result = await ipc.lmsCanvasOAuthComplete(begin.state);
      setCanvasConnected(result.connected);
      setCanvasAuthMethod(result.authMethod ?? "oauth");
      setOauthClientSecret("");
      showToast("Canvas connected via OAuth", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setOauthBusy(false);
    }
  };

  return (
    <>
      <AppCard title="Portal defaults">
        <FormField label="Default portal URL">
          <input
            className={fieldControlClass}
            value={settings["lms.defaultPortalUrl"] ?? ""}
            onChange={(e) => void setPref("lms.defaultPortalUrl", e.target.value)}
            placeholder="https://canvas.instructure.com"
          />
        </FormField>
        <StatusNote>
          Prefills new LMS bookmarks and the Open default button. Use Open in College window for
          scan-import, back/forward/reload, and find-in-page (Canvas, Brightspace, Blackboard,
          Moodle). Save portal username/password (Keychain) and use Autofill login on the SSO page.
        </StatusNote>
      </AppCard>

      <AppCard title="Canvas API sync" className="mt-4">
        <p className="mb-3 text-meta leading-relaxed">
          Connect with OAuth (institution developer key) or a personal access token. Assignments from
          active courses import as planner tasks.
        </p>
        <FormField label="Canvas base URL">
          <input
            className={fieldControlClass}
            value={canvasBaseUrl}
            onChange={(e) => setCanvasBaseUrl(e.target.value)}
            placeholder="https://yourschool.instructure.com"
          />
        </FormField>

        <div className="mt-4 space-y-3 rounded-[10px] border border-[var(--color-chrome-stroke)] p-3">
          <p className="text-caption font-medium">OAuth (recommended)</p>
          <p className="text-meta">
            Create a developer key in Canvas Admin → Developer Keys. Redirect URI must match the
            loopback URL shown when you connect (127.0.0.1).
          </p>
          <FormField label="Client ID">
            <input
              className={fieldControlClass}
              value={oauthClientId}
              onChange={(e) => setOauthClientId(e.target.value)}
              placeholder="Canvas developer key client ID"
            />
          </FormField>
          <FormField label="Client secret">
            <input
              className={fieldControlClass}
              type="password"
              autoComplete="off"
              value={oauthClientSecret}
              onChange={(e) => setOauthClientSecret(e.target.value)}
              placeholder="Leave blank to keep saved secret"
            />
          </FormField>
          <Button
            variant="secondary"
            disabled={oauthBusy || !canvasBaseUrl.trim() || !oauthClientId.trim()}
            onClick={() => void connectCanvasOAuth()}
          >
            {oauthBusy ? "Connecting…" : "Connect with Canvas OAuth"}
          </Button>
        </div>

        <div className="mt-4 space-y-3">
          <p className="text-caption font-medium">Personal access token</p>
          <FormField
            label={
              canvasConnected && canvasAuthMethod === "token"
                ? "Token (leave blank to keep saved)"
                : "Token"
            }
          >
            <input
              className={fieldControlClass}
              type="password"
              autoComplete="off"
              value={canvasToken}
              onChange={(e) => setCanvasToken(e.target.value)}
              placeholder="Canvas → Settings → Approved Integrations"
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              variant="secondary"
              disabled={canvasBusy || !canvasBaseUrl.trim()}
              onClick={async () => {
                setCanvasBusy(true);
                try {
                  await ipc.lmsCanvasSetConfig({
                    baseUrl: canvasBaseUrl.trim(),
                    accessToken: canvasToken,
                  });
                  await loadCanvas();
                  showToast("Canvas token saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                } finally {
                  setCanvasBusy(false);
                }
              }}
            >
              {canvasBusy ? "Saving…" : "Save token"}
            </Button>
            <Button
              disabled={syncBusy || !canvasConnected}
              onClick={async () => {
                setSyncBusy(true);
                try {
                  const result = await ipc.lmsCanvasSync();
                  showToast(
                    `Canvas sync: ${result.tasksCreated} task${result.tasksCreated === 1 ? "" : "s"} from ${result.coursesFetched} course${result.coursesFetched === 1 ? "" : "s"}${
                      result.skipped > 0 ? ` (${result.skipped} skipped)` : ""
                    }`,
                    "success",
                  );
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                } finally {
                  setSyncBusy(false);
                }
              }}
            >
              {syncBusy ? "Syncing…" : "Sync assignments"}
            </Button>
          </div>
        </div>

        {canvasConnected && (
          <p className="mt-2 text-meta text-[var(--color-success)]">
            Connected via {canvasAuthMethod === "oauth" ? "OAuth" : "personal access token"}
          </p>
        )}
      </AppCard>
    </>
  );
}
