import {
  AppCard,
  Button,
  MetricTile,
  StatusChip,
  FormField,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { navigate } from "@/lib/shellNavigate";
import { StatusNote } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsFinancePage() {
  const {
    settings,
    setPref,
    coinbaseSyncBusy,
    setCoinbaseSyncBusy,
    coinbaseSyncNote,
    setCoinbaseSyncNote,
    refresh,
    financeCategories,
    financeDue,
  } = useSettings();

  return (
    <>
      <AppCard title="Finance connections">
        <p className="mb-3 text-meta leading-relaxed">
          Store connection credentials locally for manual sync workflows.
        </p>
        <FormField label="Coinbase API key">
          <input
            className={fieldControlClass}
            type="password"
            value={settings["finance.coinbase.apiKey"] ?? ""}
            onChange={(e) => void setPref("finance.coinbase.apiKey", e.target.value)}
            placeholder="Optional — holdings sync"
          />
        </FormField>
        <FormField label="Manual sync note">
          <input
            className={fieldControlClass}
            value={settings["finance.connections.note"] ?? ""}
            onChange={(e) => void setPref("finance.connections.note", e.target.value)}
            placeholder="e.g. Import CSV weekly from bank export"
          />
        </FormField>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <Button
            size="sm"
            disabled={coinbaseSyncBusy || !settings["finance.coinbase.apiKey"]?.trim()}
            onClick={async () => {
              setCoinbaseSyncBusy(true);
              setCoinbaseSyncNote("Syncing Coinbase…");
              try {
                const res = await ipc.financeSyncCoinbase();
                const errTail = res.error ? ` · ${res.error}` : "";
                setCoinbaseSyncNote(
                  `Accounts ${res.accountsUpdated}, holdings ${res.holdingsUpdated}${errTail}`,
                );
                await refresh();
                showToast("Coinbase sync finished", "success");
              } catch (e) {
                setCoinbaseSyncNote(formatIpcError(e));
                showToast(formatIpcError(e), "error");
              } finally {
                setCoinbaseSyncBusy(false);
              }
            }}
          >
            {coinbaseSyncBusy ? "Syncing…" : "Sync Coinbase now"}
          </Button>
          {settings["finance.coinbase.lastSyncAt"] ? (
            <StatusChip
              title={`Last sync ${new Date(settings["finance.coinbase.lastSyncAt"]).toLocaleString()}`}
              tint="var(--color-primary)"
            />
          ) : (
            <StatusChip title="Never synced" />
          )}
        </div>
        {coinbaseSyncNote ? (
          <p className="mt-2 text-meta">{coinbaseSyncNote}</p>
        ) : null}
        <StatusNote>
          Linked accounts, budgets, and ledger CRUD remain fully local. Use Finance → Accounts to
          add balances or import from CSV.
        </StatusNote>
        {(financeCategories.length > 0 || financeDue.length > 0) && (
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            <MetricTile label="Categories" value={financeCategories.length} />
            <MetricTile
              label="Open IOUs"
              value={financeDue.filter((d) => !d.isPaid).length}
            />
          </div>
        )}
      </AppCard>
      <AppCard title="Finance Integrations & Storage">
        <p className="mb-3 text-meta leading-relaxed">
          Local bank accounts, budgets, and transaction records stay securely encrypted on this device.
          Market holdings and manual assets roll into your consolidated Net Worth report.
        </p>
        <div className="flex flex-wrap gap-2 pt-1">
          <Button
            size="sm"
            variant="secondary"
            onClick={() => navigate({ hub: "life", page: "money" })}
          >
            Open Finances
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => navigate({ hub: "life", page: "ledger" })}
          >
            View Transactions
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => navigate({ hub: "life", page: "budgets" })}
          >
            Manage Budgets
          </Button>
        </div>
      </AppCard>
    </>
  );
}
