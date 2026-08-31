import { revealItemInDir } from "@tauri-apps/plugin-opener";
import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  StatusChip,
  FormField,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { insetPanelStyle } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsDocumentsPage() {
  const {
    watchdogStatus,
    watchedFolders,
    setWatchedFolders,
    staleThresholdDays,
    setStaleThresholdDays,
    setPref,
    watchedFolderDraft,
    setWatchedFolderDraft,
    paths,
  } = useSettings();

  return (
    <>
      <AppCard title="File watchdog">
        <div className="mb-3 flex flex-wrap items-center gap-2">
          <StatusChip
            title={watchdogStatus?.isWatching ? "Active" : "Inactive"}
            tint={
              watchdogStatus?.isWatching ? "var(--color-success)" : "var(--color-text-light)"
            }
            filled={watchdogStatus?.isWatching ?? false}
          />
          {watchdogStatus != null && (
            <span className="text-caption">
              Watching {watchdogStatus.watchedCount} folder
              {watchdogStatus.watchedCount === 1 ? "" : "s"}
            </span>
          )}
        </div>
        {watchdogStatus?.lastDetectedPath && (
          <p
            className="mb-3 truncate px-2.5 py-2 text-caption"
            style={insetPanelStyle}
          >
            Last detected: {watchdogStatus.lastDetectedPath}
            {watchdogStatus.lastDetectedAt
              ? ` · ${new Date(watchdogStatus.lastDetectedAt).toLocaleString()}`
              : ""}
          </p>
        )}
        <p className="mb-3 text-meta leading-relaxed">
          Watched folders enable automated file ingestion into the vault when the desktop app scans them.
          Cloud-synced folders (such as iCloud Drive, OneDrive, or local drop folders) are watched automatically when configured.
        </p>
        <div className="mb-3 flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              try {
                const preview = await ipc.backgroundWeeklyDigestPreview();
                showToast(preview.body, "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Preview weekly digest
          </Button>
        </div>
        <FormField label="Stale file threshold (days)">
          <input
            className={fieldControlClass}
            type="number"
            min={1}
            value={staleThresholdDays}
            onChange={(e) => setStaleThresholdDays(e.target.value)}
            onBlur={() => void setPref("documents.staleThresholdDays", staleThresholdDays)}
          />
        </FormField>
        {watchedFolders.length === 0 ? (
          <EmptyState title="No watched folders" body="Add a folder path to monitor." />
        ) : (
          <ul className="mb-3 divide-y divide-[var(--color-chrome-stroke)]">
            {watchedFolders.map((f) => (
              <li key={f.id} className="flex items-center justify-between gap-2 py-2">
                <ListRow title={f.path} subtitle={new Date(f.addedAt).toLocaleString()} />
                <Button
                  size="sm"
                  variant="danger"
                  onClick={async () => {
                    await ipc.documentsDeleteWatchedFolder(f.id);
                    setWatchedFolders(await ipc.documentsListWatchedFolders());
                    showToast("Folder removed", "success");
                  }}
                >
                  Remove
                </Button>
              </li>
            ))}
          </ul>
        )}
        <div className="flex flex-wrap gap-2">
          <input
            className={`${fieldControlClass} min-w-[220px] flex-1`}
            placeholder="/Users/you/Downloads"
            value={watchedFolderDraft}
            onChange={(e) => setWatchedFolderDraft(e.target.value)}
          />
          <Button
            size="sm"
            disabled={!watchedFolderDraft.trim()}
            onClick={async () => {
              await ipc.documentsUpsertWatchedFolder({ path: watchedFolderDraft.trim() });
              setWatchedFolderDraft("");
              setWatchedFolders(await ipc.documentsListWatchedFolders());
              showToast("Folder added", "success");
            }}
          >
            Add folder
          </Button>
        </div>
      </AppCard>
      <AppCard title="Storage paths">
        <p className="mb-3 text-meta leading-relaxed">
          Vault files and document metadata live under Application Support. Lock/unlock the vault
          from Privacy & Security; browse files in Documents → Vault.
        </p>
        <div className="mb-2 flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="secondary"
            disabled={!paths}
            onClick={async () => {
              if (!paths) return;
              try {
                await navigator.clipboard.writeText(JSON.stringify(paths, null, 2));
                showToast("Paths copied", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Copy paths
          </Button>
          <Button
            size="sm"
            variant="secondary"
            disabled={!paths?.root}
            onClick={async () => {
              if (!paths?.root) return;
              try {
                await revealItemInDir(paths.root);
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Show data folder
          </Button>
        </div>
        <pre
          className="overflow-x-auto whitespace-pre-wrap px-2.5 py-2 text-caption leading-relaxed"
          style={insetPanelStyle}
        >
          {paths ? JSON.stringify(paths, null, 2) : "—"}
        </pre>
      </AppCard>
    </>
  );
}
