import { useEffect, useState } from "react";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { AppCard, Button, ListRow, StatusChip } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { StatusNote, insetPanelStyle } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsPrivacyPage() {
  const {
    locked,
    setLocked,
    paths,
    backupNote,
    setBackupNote,
    backups,
    setBackups,
  } = useSettings();
  const [biometricAvailable, setBiometricAvailable] = useState<boolean | null>(null);

  useEffect(() => {
    void ipc.securityBiometricAvailable().then(setBiometricAvailable).catch(() => setBiometricAvailable(false));
  }, []);

  return (
    <>
      <AppCard title="Security">
        <div className="mb-3 px-3 py-3" style={insetPanelStyle}>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-meta">Vault access</p>
            <StatusChip
              title={locked ? "Locked" : "Unlocked"}
              tint={locked ? "var(--color-warning)" : "var(--color-success)"}
              filled
            />
          </div>
        </div>
        <p className="mb-3 text-meta leading-relaxed text-[var(--color-text-light)]">
          {biometricAvailable === true
            ? "Unlock prompts Windows Hello or Touch ID when hardware is available."
            : biometricAvailable === false
              ? "Unlock clears the in-app lock (no biometric hardware detected)."
              : "Unlock clears the in-app lock when biometrics are unavailable."}
        </p>
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              await ipc.securityLock();
              setLocked(true);
            }}
          >
            Lock
          </Button>
          <Button
            size="sm"
            onClick={async () => {
              await ipc.securityUnlock("Unlock College");
              setLocked(await ipc.securityIsLocked());
            }}
          >
            Unlock
          </Button>
        </div>
      </AppCard>

      <AppCard title="Backups">
        <p className="mb-3 text-meta leading-relaxed">
          Copies `college.sqlite` into the Backups folder under Application Support. Restore
          stages a pending file and relaunches the app.
        </p>
        <div className="flex flex-wrap gap-2">
          <Button
            size="sm"
            onClick={async () => {
              setBackupNote("Creating…");
              try {
                const entry = await ipc.backupCreate();
                setBackupNote(`Saved ${entry.name}`);
                setBackups(await ipc.backupList());
              } catch (e) {
                setBackupNote(formatIpcError(e));
              }
            }}
          >
            Create backup
          </Button>
          <Button
            size="sm"
            variant="secondary"
            disabled={!paths?.backupsDir}
            onClick={async () => {
              if (!paths?.backupsDir) return;
              try {
                await revealItemInDir(paths.backupsDir);
              } catch (e) {
                setBackupNote(formatIpcError(e));
              }
            }}
          >
            Show folder
          </Button>
        </div>
        {backupNote && <StatusNote>{backupNote}</StatusNote>}
        {backups.length > 0 && (
          <ul className="mt-3 space-y-2">
            {backups.slice(0, 8).map((b) => (
              <li
                key={b.path}
                className="flex items-center gap-2 px-2.5 py-2"
                style={insetPanelStyle}
              >
                <div className="min-w-0 flex-1">
                  <ListRow
                    title={b.name}
                    subtitle={new Date(b.modifiedAt).toLocaleString()}
                    trailing={
                      <StatusChip title={`${Math.round(b.sizeBytes / 1024)} KB`} />
                    }
                  />
                </div>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    try {
                      await revealItemInDir(b.path);
                    } catch (e) {
                      setBackupNote(formatIpcError(e));
                    }
                  }}
                >
                  Reveal
                </Button>
                <Button
                  size="sm"
                  variant="danger"
                  onClick={async () => {
                    const ok = window.confirm(
                      `Restore ${b.name}?\n\nThis replaces the current database after relaunch. A safety copy is saved first.`,
                    );
                    if (!ok) return;
                    setBackupNote("Staging restore…");
                    try {
                      const res = await ipc.backupRestore(b.path);
                      setBackupNote(
                        `Restore staged${
                          res.safetyBackup ? " (safety copy saved)" : ""
                        }. Relaunching…`,
                      );
                      const { relaunch } = await import("@tauri-apps/plugin-process");
                      await relaunch();
                    } catch (e) {
                      setBackupNote(formatIpcError(e));
                    }
                  }}
                >
                  Restore
                </Button>
              </li>
            ))}
          </ul>
        )}
      </AppCard>
    </>
  );
}
