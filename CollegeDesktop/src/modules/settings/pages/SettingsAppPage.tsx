import { useEffect, useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { check } from "@tauri-apps/plugin-updater";
import {
  AppCard,
  Button,
  ListRow,
  StatusChip,
  fieldControlClass,
  usePlatform,
  useTheme,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { TAURI_PARITY_MODULES } from "../constants";
import { StatusNote, insetPanelStyle } from "../shared";
import { useSettings } from "../useSettings";
import { isWindowsPlatform } from "@/lib/windowsIntegration";
import type { WindowsCapabilities } from "@/lib/windowsIntegration";

export function SettingsAppPage() {
  const { modKey } = usePlatform();
  const { theme: activeTheme, resolvedTheme, setTheme: updateTheme } = useTheme();
  const [winCaps, setWinCaps] = useState<WindowsCapabilities | null>(null);
  const [importNote, setImportNote] = useState<string | null>(null);
  const [importBusy, setImportBusy] = useState(false);
  useEffect(() => {
    if (!isWindowsPlatform()) return;
    void ipc.windowsGetCapabilities().then(setWinCaps).catch(() => setWinCaps(null));
  }, []);
  const {
    platform,
    ai,
    backups,
    exportNote,
    setExportNote,
    setBackups,
    setAi,
    dataExported,
    oauthConfigured,
    typstAvailable,
    localAiReady,
    updateNote,
    setUpdateNote,
    reduceMotion,
    windowStrokeSubtle,
    density,
    dueNotifications,
    setPref,
  } = useSettings();

  return (
    <>
      <AppCard title="Workspace">
        <p className="mb-3 text-meta leading-relaxed">
          This app stores your workspace data locally in your system application data directory.
        </p>
        <div className="mb-3 flex flex-wrap gap-2">
          <Button
            size="sm"
            onClick={async () => {
              setExportNote("Exporting…");
              try {
                const entry = await ipc.backupCreate();
                setBackups(await ipc.backupList());
                setExportNote(`Workspace exported as ${entry.name}`);
                showToast("Workspace exported", "success");
              } catch (e) {
                setExportNote(formatIpcError(e));
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Export workspace
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              try {
                const res = await ipc.aiPing();
                setAi(await ipc.aiRuntimeStatus());
                showToast(res.message, res.ok ? "success" : "error");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Test Ollama
          </Button>
        </div>
        {exportNote && <StatusNote>{exportNote}</StatusNote>}
        {importNote && <StatusNote>{importNote}</StatusNote>}
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          <li>
            <ListRow
              title="Legacy SQLite import"
              subtitle="One-way database read from College.sqlite backup file"
              trailing={
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={importBusy}
                  onClick={async () => {
                    const picked = await open({
                      multiple: false,
                      filters: [{ name: "SQLite", extensions: ["sqlite", "db"] }],
                    });
                    if (typeof picked !== "string") return;
                    setImportBusy(true);
                    setImportNote("Importing…");
                    try {
                      const report = await ipc.platformImportSwiftWorkspace({
                        swiftCollegeDb: picked,
                      });
                      if (report.skippedReason) {
                        setImportNote(report.skippedReason);
                        showToast(report.skippedReason, "error");
                      } else {
                        setImportNote(
                          `Imported ${report.totalRows} rows from ${report.sourceSchema}`,
                        );
                        showToast(`Imported ${report.totalRows} rows`, "success");
                      }
                    } catch (e) {
                      const msg = formatIpcError(e);
                      setImportNote(msg);
                      showToast(msg, "error");
                    } finally {
                      setImportBusy(false);
                    }
                  }}
                >
                  {importBusy ? "Importing…" : "Import…"}
                </Button>
              }
            />
          </li>
          <li>
            <ListRow
              title="Data export"
              subtitle={
                dataExported
                  ? `${backups.length} backup${backups.length === 1 ? "" : "s"} on disk`
                  : "Create at least one workspace export"
              }
              trailing={
                <StatusChip
                  title={dataExported ? "Done" : "Pending"}
                  tint={dataExported ? "var(--color-success)" : "var(--color-warning)"}
                  filled
                />
              }
            />
          </li>
          <li>
            <ListRow
              title="OAuth configured"
              subtitle={
                oauthConfigured
                  ? "Google and/or Outlook Client IDs saved"
                  : "Settings → Calendar for Google/Outlook IDs"
              }
              trailing={
                <StatusChip
                  title={oauthConfigured ? "Done" : "Optional"}
                  tint={oauthConfigured ? "var(--color-success)" : "var(--color-warning)"}
                  filled={oauthConfigured}
                />
              }
            />
          </li>
          <li>
            <ListRow
              title="Typst on PATH"
              subtitle={
                typstAvailable
                  ? "Resume PDF export via `typst compile`"
                  : "Install from typst.app for in-app PDF"
              }
              trailing={
                <StatusChip
                  title={
                    typstAvailable === null ? "Checking…" : typstAvailable ? "Found" : "Missing"
                  }
                  tint={
                    typstAvailable
                      ? "var(--color-success)"
                      : typstAvailable === false
                        ? "var(--color-warning)"
                        : "var(--color-text-light)"
                  }
                  filled={Boolean(typstAvailable)}
                />
              }
            />
          </li>
          <li>
            <ListRow
              title="On-device AI"
              subtitle={ai?.pingMessage ?? "Bundled embed + parse models (offline, DirectML / MLX)"}
              trailing={
                <StatusChip
                  title={
                    localAiReady
                      ? (ai?.device?.toUpperCase() ?? "Ready")
                      : ai?.pingOk === false
                        ? "Missing"
                        : "Checking…"
                  }
                  tint={
                    localAiReady
                      ? "var(--color-success)"
                      : ai?.pingOk === false
                        ? "var(--color-error)"
                        : "var(--color-warning)"
                  }
                  filled={localAiReady}
                />
              }
            />
          </li>
        </ul>
        <StatusNote>
          AI runs fully offline from bundled local models with cross-platform desktop support.
        </StatusNote>
      </AppCard>

      <AppCard title="System Readiness">
        <p className="mb-3 text-meta leading-relaxed">
          Comprehensive feature coverage for daily-driver tasks across all academic, life, career, and library workflows.
        </p>
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {TAURI_PARITY_MODULES.map((mod) => (
            <li key={mod.name}>
              <ListRow
                title={mod.name}
                subtitle={mod.note}
                trailing={
                  <StatusChip
                    title={mod.ready ? "Ready" : "Gap"}
                    tint={mod.ready ? "var(--color-success)" : "var(--color-warning)"}
                    filled
                  />
                }
              />
            </li>
          ))}
        </ul>
        <StatusNote>
          All hub features, database CRUD operations, and on-device AI tools are active and supported on your system.
        </StatusNote>
      </AppCard>

      <AppCard title="Platform">
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          <li>
            <ListRow
              title="OS"
              trailing={
                platform ? (
                  <StatusChip title={`${platform.os} · ${platform.arch}`} filled />
                ) : (
                  "—"
                )
              }
            />
          </li>
          <li>
            <ListRow
              title="Version"
              trailing={
                platform?.appVersion ? (
                  <StatusChip title={platform.appVersion} tint="var(--color-primary)" filled />
                ) : (
                  "—"
                )
              }
            />
          </li>
        </ul>
        <div className="mt-3 flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              setUpdateNote("Checking…");
              try {
                const update = await check();
                if (!update) {
                  setUpdateNote("You’re up to date.");
                  showToast("You’re up to date", "success");
                  return;
                }
                setUpdateNote(`Update ${update.version} available.`);
                const ok = window.confirm(
                  `Install College ${update.version} now?\n\nThe app will download the update and relaunch.`,
                );
                if (!ok) return;
                setUpdateNote(`Downloading ${update.version}…`);
                await update.downloadAndInstall();
                setUpdateNote("Installed. Relaunching…");
                const { relaunch } = await import("@tauri-apps/plugin-process");
                await relaunch();
              } catch (e) {
                const msg = formatIpcError(e);
                setUpdateNote(msg);
                showToast(msg, "error");
              }
            }}
          >
            Check for updates
          </Button>
        </div>
        {updateNote && (
          <div className="mt-2">
            <StatusChip
              title={updateNote}
              tint={
                updateNote.includes("up to date")
                  ? "var(--color-success)"
                  : updateNote.includes("available") || updateNote.includes("Downloading")
                    ? "var(--color-primary)"
                    : updateNote.includes("Checking")
                      ? "var(--color-text-light)"
                      : "var(--color-error)"
              }
              filled
            />
          </div>
        )}
      </AppCard>

      <AppCard title="Preferences">
        <div className="space-y-2 text-body">
          <div
            className="flex items-center justify-between gap-3 px-2.5 py-2.5"
            style={insetPanelStyle}
          >
            <span>Reduce motion</span>
            <div className="flex items-center gap-2">
              <StatusChip
                title={reduceMotion ? "On" : "Off"}
                tint={reduceMotion ? "var(--color-primary)" : "var(--color-text-light)"}
                filled={reduceMotion}
              />
              <input
                type="checkbox"
                checked={reduceMotion}
                onChange={(e) => void setPref("ui.reduceMotion", e.target.checked ? "true" : "false")}
              />
            </div>
          </div>
          <div
            className="flex items-center justify-between gap-3 px-2.5 py-2.5"
            style={insetPanelStyle}
          >
            <span>Window border</span>
            <div className="flex items-center gap-2">
              <StatusChip title={windowStrokeSubtle ? "Subtle" : "None"} tint="var(--color-primary)" filled />
              <select
                className={`${fieldControlClass} w-[120px] py-1`}
                value={windowStrokeSubtle ? "subtle" : "none"}
                onChange={(e) =>
                  void setPref("ui.windowStroke", e.target.value === "subtle" ? "subtle" : "none")
                }
              >
                <option value="none">None</option>
                <option value="subtle">Subtle</option>
              </select>
            </div>
          </div>
          <div
            className="flex items-center justify-between gap-3 px-2.5 py-2.5"
            style={insetPanelStyle}
          >
            <div>
              <div className="font-medium">Theme</div>
              <div className="text-caption text-[var(--color-text-light)]">
                {activeTheme === "system"
                  ? `Following OS preference (currently ${resolvedTheme})`
                  : activeTheme === "dark"
                    ? "Forced dark interface"
                    : "Forced light interface"}
              </div>
            </div>
            <div className="flex items-center gap-2">
              <StatusChip
                title={
                  activeTheme === "system"
                    ? `System (${resolvedTheme === "dark" ? "Dark" : "Light"})`
                    : activeTheme === "dark"
                      ? "Dark"
                      : "Light"
                }
                tint="var(--color-primary)"
                filled
              />
              <select
                className={`${fieldControlClass} w-[130px] py-1`}
                value={activeTheme}
                onChange={(e) => {
                  const val = e.target.value as "system" | "light" | "dark";
                  void updateTheme(val);
                }}
              >
                <option value="system">System (Auto)</option>
                <option value="light">Light</option>
                <option value="dark">Dark</option>
              </select>
            </div>
          </div>
          <div
            className="flex items-center justify-between gap-3 px-2.5 py-2.5"
            style={insetPanelStyle}
          >
            <span>Display density</span>
            <div className="flex items-center gap-2">
              <StatusChip
                title={density === "auto" ? "Auto" : density}
                tint="var(--color-primary)"
                filled
              />
              <select
                className={`${fieldControlClass} w-[120px] py-1`}
                value={density}
                onChange={(e) => {
                  const value = e.target.value;
                  if (
                    value === "compact" ||
                    value === "default" ||
                    value === "comfortable" ||
                    value === "auto"
                  ) {
                    void setPref("ui.density", value);
                  }
                }}
              >
                <option value="auto">Auto</option>
                <option value="compact">Compact</option>
                <option value="default">Default</option>
                <option value="comfortable">Comfortable</option>
              </select>
            </div>
          </div>
          <div
            className="flex items-center justify-between gap-3 px-2.5 py-2.5"
            style={insetPanelStyle}
          >
            <span>Due-item notifications</span>
            <div className="flex items-center gap-2">
              <StatusChip
                title={dueNotifications ? "On" : "Off"}
                tint={dueNotifications ? "var(--color-success)" : "var(--color-text-light)"}
                filled={dueNotifications}
              />
              <input
                type="checkbox"
                checked={dueNotifications}
                onChange={(e) =>
                  void setPref("notify.dueItems", e.target.checked ? "true" : "false")
                }
              />
            </div>
          </div>
          <p
            className="px-2.5 py-2 text-caption leading-relaxed"
            style={insetPanelStyle}
          >
            On launch, remind once per day about tasks due in 48h and today’s events. Shortcuts: {modKey}+K
            search, {modKey}+1–5 hubs, {modKey}+J assistant, {modKey}+, settings.
          </p>
        </div>
      </AppCard>

      {winCaps && (
        <AppCard title="Windows 11 integration">
          <p className="mb-3 text-meta leading-relaxed">
            Theme sync, taskbar progress, jump lists, and EcoQoS efficiency mode run automatically.
            Widget feeds export to your data folder; focus sessions prevent system sleep during study
            mode. A separate WinUI widget package is required for Win+W board tiles.
          </p>
          <div className="grid gap-2 sm:grid-cols-2">
            <StatusChip
              title={winCaps.dwmMica ? "Mica backdrop" : "DWM"}
              tint="var(--color-primary)"
              filled={winCaps.dwmMica}
            />
            <StatusChip
              title={winCaps.directml ? "DirectML GPU" : "CPU AI"}
              tint="var(--color-primary)"
              filled={winCaps.directml}
            />
            <StatusChip
              title={winCaps.copilotNpu ? "Copilot+ NPU" : "No NPU"}
              tint="var(--color-primary)"
              filled={winCaps.copilotNpu}
            />
            <StatusChip
              title={winCaps.uriProtocol ? "college:// links" : "URI"}
              tint="var(--color-primary)"
              filled={winCaps.uriProtocol}
            />
            <StatusChip
              title={winCaps.widgetsBoard ? "Widget feeds exported" : "Widgets"}
              tint="var(--color-primary)"
              filled={winCaps.widgetsBoard}
            />
            <StatusChip
              title={winCaps.focusSessions ? "Focus session (sleep blocked)" : "Focus session"}
              tint="var(--color-primary)"
              filled={winCaps.focusSessions}
            />
          </div>
          <div className="mt-3">
            <Button
              size="sm"
              variant="secondary"
              onClick={() => void ipc.windowsRefreshShellIntegration().then(() => showToast("Shell integration refreshed", "success")).catch((e) => showToast(formatIpcError(e), "error"))}
            >
              Refresh shell integration
            </Button>
          </div>
        </AppCard>
      )}
    </>
  );
}
