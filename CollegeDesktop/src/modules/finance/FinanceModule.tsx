import { useCallback, useEffect, useMemo, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  MetricTile,
  ModalSheet,
  ProgressBar,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError, type FinanceDashboardSummary, type FinanceHolding } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { shellNavigate } from "@/lib/shellNavigate";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { FinanceDashboardScreen } from "./FinanceDashboardScreen";
import { FinanceAccountDetailScreen } from "./FinanceAccountDetailScreen";
import { FinanceReportsScreen } from "./FinanceReportsScreen";

type Account = {
  id: string;
  name: string;
  institution: string;
  accountType: string;
  balance: number;
  currency: string;
};

type Tx = {
  id: string;
  accountId: string;
  accountName: string;
  postedAt: string;
  amount: number;
  payee: string;
  category: string;
  memo: string;
};

type Budget = {
  id: string;
  name: string;
  category: string;
  amount: number;
  period: string;
};

type Goal = {
  id: string;
  name: string;
  targetAmount: number;
  currentAmount: number;
  deadline?: string | null;
  notes: string;
  sortOrder: number;
};

type InventoryItem = {
  id: string;
  name: string;
  category: string;
  purchaseDate?: string | null;
  value: number;
  notes: string;
  sortOrder: number;
};

type Receipt = {
  id: string;
  title: string;
  merchant: string;
  amount: number;
  purchasedAt?: string | null;
  category: string;
  notes: string;
  vaultDocId?: string | null;
  sortOrder: number;
};

type Recurring = {
  id: string;
  accountId?: string | null;
  accountName: string;
  title: string;
  amount: number;
  cadence: string;
  nextDue?: string | null;
  category: string;
};

function parseAccountIdFromPage(page: string): string | null {
  if (!page.startsWith("account-")) return null;
  const id = page.slice("account-".length);
  return id.length > 0 ? id : null;
}

export function FinanceModule({ page = "dashboard" }: { page?: string }) {
  const accountIdFromPage = parseAccountIdFromPage(page);
  const view =
    page === "accounts" || accountIdFromPage
      ? "accounts"
      : page === "ledger"
        ? "ledger"
        : page === "budgets"
          ? "budgets"
          : page === "goals"
            ? "goals"
            : page === "inventory"
              ? "inventory"
              : page === "receipts"
                ? "receipts"
                : page === "reports"
                  ? "reports"
            : page === "net-worth"
              ? "net-worth"
              : "dashboard";
  const [summary, setSummary] = useState<FinanceDashboardSummary | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [txs, setTxs] = useState<Tx[]>([]);
  const [budgets, setBudgets] = useState<Budget[]>([]);
  const [goals, setGoals] = useState<Goal[]>([]);
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [recurring, setRecurring] = useState<Recurring[]>([]);
  const [holdings, setHoldings] = useState<FinanceHolding[]>([]);
  const [recurringSheet, setRecurringSheet] = useState(false);
  const [editingRecurringId, setEditingRecurringId] = useState<string | null>(null);
  const [recurringForm, setRecurringForm] = useState({
    accountId: "",
    title: "",
    amount: -25,
    cadence: "monthly",
    nextDue: new Date().toISOString().slice(0, 10),
    category: "General",
  });
  const [holdingSheet, setHoldingSheet] = useState(false);
  const [editingHoldingId, setEditingHoldingId] = useState<string | null>(null);
  const [holdingForm, setHoldingForm] = useState({
    assetType: "stock",
    symbol: "",
    name: "",
    quantity: 1,
    pricePerUnit: 0,
  });
  const [accountSheet, setAccountSheet] = useState(false);
  const [editingAccountId, setEditingAccountId] = useState<string | null>(null);
  const [txSheet, setTxSheet] = useState(false);
  const [budgetSheet, setBudgetSheet] = useState(false);
  const [goalSheet, setGoalSheet] = useState(false);
  const [editingGoalId, setEditingGoalId] = useState<string | null>(null);
  const [inventorySheet, setInventorySheet] = useState(false);
  const [editingInventoryId, setEditingInventoryId] = useState<string | null>(null);
  const [receiptSheet, setReceiptSheet] = useState(false);
  const [editingReceiptId, setEditingReceiptId] = useState<string | null>(null);
  const [csvSheet, setCsvSheet] = useState(false);
  const [csvForm, setCsvForm] = useState({ accountId: "", csvText: "" });
  const [csvNote, setCsvNote] = useState<string | null>(null);
  const [form, setForm] = useState({
    name: "",
    institution: "",
    accountType: "checking",
    balance: 0,
  });
  const [txForm, setTxForm] = useState({
    accountId: "",
    amount: -10,
    payee: "",
    category: "General",
    postedAt: new Date().toISOString().slice(0, 10),
  });
  const [budgetForm, setBudgetForm] = useState({
    name: "",
    category: "General",
    amount: 100,
    period: "monthly",
  });
  const [goalForm, setGoalForm] = useState({
    name: "",
    targetAmount: 1000,
    currentAmount: 0,
    deadline: "",
    notes: "",
  });
  const [inventoryForm, setInventoryForm] = useState({
    name: "",
    category: "General",
    purchaseDate: "",
    value: 0,
    notes: "",
  });
  const [receiptForm, setReceiptForm] = useState({
    title: "",
    merchant: "",
    amount: 0,
    purchasedAt: new Date().toISOString().slice(0, 10),
    category: "General",
    notes: "",
    vaultDocId: "",
  });
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(accountIdFromPage);

  useEffect(() => {
    setSelectedAccountId(accountIdFromPage);
  }, [accountIdFromPage]);

  useEffect(() => {
    if (
      accountIdFromPage &&
      accounts.length > 0 &&
      !accounts.some((a) => a.id === accountIdFromPage)
    ) {
      setSelectedAccountId(null);
      shellNavigate("finance", "accounts");
    }
  }, [accountIdFromPage, accounts]);

  const load = useCallback(async () => {
    const [s, a, t, b, g, inv, rec, hold, recurringRows] = await Promise.all([
      ipc.financeDashboardSummary(),
      ipc.financeListAccounts(),
      ipc.financeListTransactions(undefined, 500),
      ipc.financeListBudgets(),
      ipc.financeListGoals(),
      ipc.financeListInventoryItems(),
      ipc.financeListReceipts(),
      ipc.financeListHoldings(),
      ipc.financeListRecurring().catch(() => []),
    ]);
    setSummary(s);
    setAccounts(a);
    setTxs(t);
    setBudgets(b);
    setGoals(g);
    setInventory(inv);
    setReceipts(rec);
    setHoldings(hold);
    setRecurring(recurringRows);
    setTxForm((prev) =>
      prev.accountId || !a[0] ? prev : { ...prev, accountId: a[0].id },
    );
    setCsvForm((prev) =>
      prev.accountId || !a[0] ? prev : { ...prev, accountId: a[0].id },
    );
    setRecurringForm((prev) =>
      prev.accountId || !a[0] ? prev : { ...prev, accountId: a[0].id },
    );
  }, []);

  const { refresh, error } = useLiveQuery(load, ["finance"]);

  const money = (n: number, currency = "USD") =>
    n.toLocaleString(undefined, { style: "currency", currency });

  const spendByCategory = (() => {
    const map = new Map<string, number>();
    for (const t of txs) {
      if (t.amount >= 0) continue;
      const key = (t.category || "General").trim() || "General";
      map.set(key, (map.get(key) ?? 0) + Math.abs(t.amount));
    }
    return map;
  })();

  const balanceByType = (() => {
    const map = new Map<string, number>();
    for (const a of accounts) {
      const key = (a.accountType || "other").trim() || "other";
      map.set(key, (map.get(key) ?? 0) + a.balance);
    }
    return [...map.entries()].sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
  })();

  const goalProgress = goals.reduce((sum, g) => sum + g.currentAmount, 0);
  const goalTargets = goals.reduce((sum, g) => sum + g.targetAmount, 0);
  const inventoryTotal = inventory.reduce((sum, item) => sum + item.value, 0);

  const selectedAccount = useMemo(
    () => accounts.find((a) => a.id === selectedAccountId) ?? null,
    [accounts, selectedAccountId],
  );

  const selectAccount = (id: string) => {
    setSelectedAccountId(id);
    shellNavigate("finance", `account-${id}`);
  };

  const closeAccountInspector = () => {
    setSelectedAccountId(null);
    shellNavigate("finance", "accounts");
  };

  const openAccountEditor = (account: Account) => {
    setEditingAccountId(account.id);
    setForm({
      name: account.name,
      institution: account.institution || "",
      accountType: account.accountType || "checking",
      balance: account.balance,
    });
    setAccountSheet(true);
  };

  const goalStatus = (g: Goal) => {
    const ratio = g.targetAmount > 0 ? g.currentAmount / g.targetAmount : 0;
    if (ratio >= 1) return { label: "Complete", filled: true };
    if (g.deadline) {
      const due = new Date(g.deadline);
      if (!Number.isNaN(due.getTime()) && due < new Date()) {
        return { label: "Overdue", filled: false };
      }
    }
    return { label: "In progress", filled: false };
  };

  const title =
    view === "accounts"
      ? "Accounts"
      : view === "ledger"
        ? "Ledger"
        : view === "budgets"
          ? "Budgets"
          : view === "goals"
            ? "Goals"
            : view === "inventory"
              ? "Inventory"
              : view === "receipts"
                ? "Receipts"
                : view === "reports"
                  ? "Reports"
            : view === "net-worth"
              ? "Net worth"
              : "Dashboard";

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={title}
        actions={
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            {view === "ledger" ? (
              <>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    try {
                      const picked = await save({
                        title: "Export transactions",
                        defaultPath: "college-transactions.csv",
                        filters: [{ name: "CSV", extensions: ["csv"] }],
                      });
                      if (!picked) return;
                      const res = await ipc.financeExportTransactionsCsvPath(picked);
                      showToast(`Exported ${res.rowCount} rows`, "success");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                  disabled={txs.length === 0}
                >
                  Export CSV
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => setCsvSheet(true)}
                  disabled={accounts.length === 0}
                >
                  Import CSV
                </Button>
                <Button size="sm" onClick={() => setTxSheet(true)} disabled={accounts.length === 0}>
                  Add transaction
                </Button>
              </>
            ) : view === "budgets" ? (
              <Button size="sm" onClick={() => setBudgetSheet(true)}>
                Add budget
              </Button>
            ) : view === "goals" ? (
              <Button
                size="sm"
                onClick={() => {
                  setEditingGoalId(null);
                  setGoalForm({
                    name: "",
                    targetAmount: 1000,
                    currentAmount: 0,
                    deadline: "",
                    notes: "",
                  });
                  setGoalSheet(true);
                }}
              >
                Add goal
              </Button>
            ) : view === "inventory" ? (
              <Button
                size="sm"
                onClick={() => {
                  setEditingInventoryId(null);
                  setInventoryForm({
                    name: "",
                    category: "General",
                    purchaseDate: "",
                    value: 0,
                    notes: "",
                  });
                  setInventorySheet(true);
                }}
              >
                Add item
              </Button>
            ) : view === "receipts" ? (
              <Button
                size="sm"
                onClick={() => {
                  setEditingReceiptId(null);
                  setReceiptForm({
                    title: "",
                    merchant: "",
                    amount: 0,
                    purchasedAt: new Date().toISOString().slice(0, 10),
                    category: "General",
                    notes: "",
                    vaultDocId: "",
                  });
                  setReceiptSheet(true);
                }}
              >
                Add receipt
              </Button>
            ) : view === "reports" || view === "net-worth" ? null : (
              <Button
                size="sm"
                onClick={() => {
                  setEditingAccountId(null);
                  setForm({ name: "", institution: "", accountType: "checking", balance: 0 });
                  setAccountSheet(true);
                }}
              >
                Add account
              </Button>
            )}
          </div>
        }
      />
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}

      {view === "dashboard" && (
        <FinanceDashboardScreen
          netWorth={summary?.netWorth ?? 0}
          accounts={accounts}
          txs={txs}
          money={money}
          onSelectAccount={selectAccount}
          onViewAllAccounts={() => shellNavigate("finance", "accounts")}
          onViewAllTransactions={() => shellNavigate("finance", "accounts")}
          onAddAccount={() => {
            setEditingAccountId(null);
            setForm({ name: "", institution: "", accountType: "checking", balance: 0 });
            setAccountSheet(true);
          }}
        />
      )}

      {view === "accounts" && (
        <div className="min-h-0 flex-1 space-y-3 p-3 pt-1">
          <TrailingInspector
            open={!!selectedAccount}
            main={
              <AppCard title={`Bank accounts · ${accounts.length}`}>
                {accounts.length === 0 ? (
                  <EmptyState
                    title="No accounts yet"
                    body="Add a checking or savings account, or load sample data from Settings."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {accounts.map((a) => (
                      <li key={a.id}>
                        <ListRow
                          title={a.name}
                          subtitle={`${a.institution || "—"} · ${a.accountType}`}
                          leading={<StatusChip title={a.accountType} filled />}
                          selected={selectedAccountId === a.id}
                          onClick={() => selectAccount(a.id)}
                          trailing={
                            <span className="font-semibold tabular-nums text-[var(--color-text-main)]">
                              {money(a.balance, a.currency || "USD")}
                            </span>
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
            }
          >
            {selectedAccount && (
              <FinanceAccountDetailScreen
                account={selectedAccount}
                txs={txs}
                money={money}
                onEdit={() => openAccountEditor(selectedAccount)}
                onDelete={async () => {
                  if (!confirmDelete(selectedAccount.name)) return;
                  try {
                    await ipc.financeDeleteAccount(selectedAccount.id);
                    closeAccountInspector();
                    showToast("Account deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
                onClose={closeAccountInspector}
              />
            )}
          </TrailingInspector>

          <AppCard title={`Recurring · ${recurring.length}`}>
            <div className="mb-3 flex flex-wrap justify-end gap-2">
              <Button
                size="sm"
                variant="secondary"
                disabled={recurring.length === 0}
                onClick={async () => {
                  try {
                    const res = await ipc.financeRunRecurringDue();
                    showToast(
                      `Created ${res.created} transaction${res.created === 1 ? "" : "s"}`,
                      "success",
                    );
                    await refresh();
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Run due
              </Button>
              <Button
                size="sm"
                disabled={accounts.length === 0}
                onClick={() => {
                  setEditingRecurringId(null);
                  setRecurringForm({
                    accountId: accounts[0]?.id ?? "",
                    title: "",
                    amount: -25,
                    cadence: "monthly",
                    nextDue: new Date().toISOString().slice(0, 10),
                    category: "General",
                  });
                  setRecurringSheet(true);
                }}
              >
                Add recurring
              </Button>
            </div>
            {recurring.length === 0 ? (
              <EmptyState
                title="No recurring charges"
                body="Track rent, subscriptions, or allowances with a linked account."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {recurring.map((r) => (
                  <li key={r.id} className="flex items-center gap-2">
                    <div className="min-w-0 flex-1">
                      <ListRow
                        title={r.title}
                        subtitle={`${r.accountName || "No account"} · ${r.cadence}${
                          r.nextDue ? ` · next ${new Date(r.nextDue).toLocaleDateString()}` : ""
                        }`}
                        leading={<StatusChip title={r.category || "General"} />}
                        trailing={
                          <span
                            className={`font-semibold tabular-nums ${
                              r.amount < 0
                                ? "text-[var(--color-error)]"
                                : "text-[var(--color-success)]"
                            }`}
                          >
                            {money(r.amount)}
                          </span>
                        }
                      />
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setEditingRecurringId(r.id);
                        setRecurringForm({
                          accountId: r.accountId ?? "",
                          title: r.title,
                          amount: r.amount,
                          cadence: r.cadence,
                          nextDue: r.nextDue?.slice(0, 10) ?? "",
                          category: r.category || "General",
                        });
                        setRecurringSheet(true);
                      }}
                    >
                      Edit
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {view === "ledger" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          <AppCard title="Transactions">
            {txs.length === 0 ? (
              <EmptyState
                title="Ledger is empty"
                body="Add a transaction, import a CSV, or reload sample data from Settings."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {txs.map((t) => (
                  <li key={t.id} className="flex items-center gap-2">
                    <div className="min-w-0 flex-1">
                      <ListRow
                        title={t.payee || "Untitled"}
                        subtitle={`${new Date(t.postedAt).toLocaleDateString()} · ${t.accountName}`}
                        leading={
                          t.category ? <StatusChip title={t.category} /> : undefined
                        }
                        trailing={
                          <span
                            className={`font-semibold tabular-nums ${
                              t.amount < 0
                                ? "text-[var(--color-error)]"
                                : "text-[var(--color-success)]"
                            }`}
                          >
                            {money(t.amount)}
                          </span>
                        }
                      />
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        if (!confirmDelete(t.payee || "transaction")) return;
                        void ipc
                          .financeDeleteTransaction(t.id)
                          .then(() => showToast("Transaction deleted", "success"))
                          .catch((e) => showToast(formatIpcError(e), "error"));
                      }}
                    >
                      Delete
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {view === "budgets" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          <AppCard title="Monthly budgets">
            {budgets.length === 0 ? (
              <EmptyState
                title="No budgets"
                body="Set category spending targets, or load sample data from Settings."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {budgets.map((b) => {
                  const spent = spendByCategory.get(b.category || "General") ?? 0;
                  const ratio = b.amount > 0 ? Math.min(1, spent / b.amount) : 0;
                  return (
                    <li key={b.id} className="py-2">
                      <div className="flex items-center gap-2">
                        <div className="min-w-0 flex-1">
                          <ListRow
                            title={b.name}
                            subtitle={`${b.category || "General"} · ${b.period}`}
                            trailing={
                              <span className="font-semibold tabular-nums text-[var(--color-text-main)]">
                                {money(spent)} / {money(b.amount)}
                              </span>
                            }
                          />
                        </div>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => {
                            if (!confirmDelete(b.name)) return;
                            void ipc
                              .financeDeleteBudget(b.id)
                              .then(() => showToast("Budget deleted", "success"))
                              .catch((e) => showToast(formatIpcError(e), "error"));
                          }}
                        >
                          Delete
                        </Button>
                      </div>
                      <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-[var(--color-chrome-stroke)]">
                        <div
                          className="h-full rounded-full bg-[var(--color-primary)]"
                          style={{ width: `${ratio * 100}%` }}
                        />
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {view === "goals" && (
        <>
          <div className="grid gap-2.5 px-3 pt-1 md:grid-cols-3">
            <MetricTile label="Goals" value={goals.length || "—"} />
            <MetricTile
              label="Saved"
              value={goals.length ? money(goalProgress) : "—"}
              accent="var(--color-success)"
            />
            <MetricTile
              label="Target total"
              value={goals.length ? money(goalTargets) : "—"}
            />
          </div>
          <div className="min-h-0 flex-1 overflow-auto p-3 pt-3">
            <AppCard title="Savings goals">
              {goals.length === 0 ? (
                <EmptyState
                  title="No goals yet"
                  body="Track emergency funds, tuition, or other savings targets."
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {goals.map((g) => {
                    const ratio =
                      g.targetAmount > 0
                        ? Math.min(1, g.currentAmount / g.targetAmount)
                        : 0;
                    const status = goalStatus(g);
                    return (
                      <li key={g.id} className="py-3">
                        <div className="flex items-start gap-2">
                          <div className="min-w-0 flex-1">
                            <ListRow
                              title={g.name}
                              subtitle={
                                g.deadline
                                  ? `Due ${new Date(g.deadline).toLocaleDateString()}`
                                  : g.notes || undefined
                              }
                              leading={
                                <StatusChip title={status.label} filled={status.filled} />
                              }
                              trailing={
                                <span className="text-[13px] font-semibold tracking-[-0.02em] tabular-nums text-[var(--color-text-main)]">
                                  {money(g.currentAmount)} / {money(g.targetAmount)}
                                </span>
                              }
                            />
                          </div>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => {
                              setEditingGoalId(g.id);
                              setGoalForm({
                                name: g.name,
                                targetAmount: g.targetAmount,
                                currentAmount: g.currentAmount,
                                deadline: g.deadline?.slice(0, 10) ?? "",
                                notes: g.notes,
                              });
                              setGoalSheet(true);
                            }}
                          >
                            Edit
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => {
                              if (!confirmDelete(g.name)) return;
                              void ipc
                                .financeDeleteGoal(g.id)
                                .then(() => showToast("Goal deleted", "success"))
                                .catch((e) => showToast(formatIpcError(e), "error"));
                            }}
                          >
                            Delete
                          </Button>
                        </div>
                        <ProgressBar
                          value={ratio}
                          tint={
                            status.label === "Complete"
                              ? "var(--color-success)"
                              : status.label === "Overdue"
                                ? "var(--color-error)"
                                : "var(--color-primary)"
                          }
                          className="mt-2.5"
                        />
                      </li>
                    );
                  })}
                </ul>
              )}
            </AppCard>
          </div>
        </>
      )}

      {view === "inventory" && (
        <>
          <div className="grid gap-2.5 px-3 pt-1 md:grid-cols-3">
            <MetricTile label="Items" value={inventory.length || "—"} />
            <MetricTile
              label="Total value"
              value={inventory.length ? money(inventoryTotal) : "—"}
              accent="var(--color-primary)"
            />
            <MetricTile
              label="Categories"
              value={
                inventory.length
                  ? new Set(inventory.map((i) => i.category || "General")).size
                  : "—"
              }
            />
          </div>
          <div className="min-h-0 flex-1 overflow-auto p-3 pt-3">
            <AppCard title="Tracked items">
              {inventory.length === 0 ? (
                <EmptyState
                  title="No inventory yet"
                  body="Track laptops, textbooks, furniture, and other valuables."
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {inventory.map((item) => (
                    <li key={item.id} className="flex items-center gap-2">
                      <div className="min-w-0 flex-1">
                        <ListRow
                          title={item.name}
                          subtitle={
                            item.purchaseDate
                              ? `Purchased ${new Date(item.purchaseDate).toLocaleDateString()}`
                              : item.notes || undefined
                          }
                          leading={
                            <StatusChip
                              title={(item.category || "General").trim() || "General"}
                              filled
                            />
                          }
                          trailing={
                            <span className="text-[13px] font-semibold tracking-[-0.02em] tabular-nums text-[var(--color-text-main)]">
                              {money(item.value)}
                            </span>
                          }
                        />
                      </div>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => {
                          setEditingInventoryId(item.id);
                          setInventoryForm({
                            name: item.name,
                            category: item.category || "General",
                            purchaseDate: item.purchaseDate?.slice(0, 10) ?? "",
                            value: item.value,
                            notes: item.notes,
                          });
                          setInventorySheet(true);
                        }}
                      >
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => {
                          if (!confirmDelete(item.name)) return;
                          void ipc
                            .financeDeleteInventoryItem(item.id)
                            .then(() => showToast("Item deleted", "success"))
                            .catch((e) => showToast(formatIpcError(e), "error"));
                        }}
                      >
                        Delete
                      </Button>
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
          </div>
        </>
      )}

      {view === "receipts" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          <AppCard title="Saved receipts">
            {receipts.length === 0 ? (
              <EmptyState
                title="No receipts yet"
                body="Log purchases and optionally link a vault document."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {receipts.map((r) => (
                  <li key={r.id} className="flex items-center gap-2">
                    <div className="min-w-0 flex-1">
                      <ListRow
                        title={r.title}
                        subtitle={
                          [
                            r.merchant || undefined,
                            r.purchasedAt
                              ? new Date(r.purchasedAt).toLocaleDateString()
                              : undefined,
                            r.vaultDocId ? "Linked to vault document" : undefined,
                          ]
                            .filter(Boolean)
                            .join(" · ") || undefined
                        }
                        leading={
                          r.category ? (
                            <StatusChip title={r.category} />
                          ) : undefined
                        }
                        trailing={
                          <span className="font-semibold tabular-nums text-[var(--color-text-main)]">
                            {money(r.amount)}
                          </span>
                        }
                      />
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setEditingReceiptId(r.id);
                        setReceiptForm({
                          title: r.title,
                          merchant: r.merchant || "",
                          amount: r.amount,
                          purchasedAt: r.purchasedAt?.slice(0, 10) ?? "",
                          category: r.category || "General",
                          notes: r.notes,
                          vaultDocId: r.vaultDocId ?? "",
                        });
                        setReceiptSheet(true);
                      }}
                    >
                      Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        if (!confirmDelete(r.title)) return;
                        void ipc
                          .financeDeleteReceipt(r.id)
                          .then(() => showToast("Receipt deleted", "success"))
                          .catch((e) => showToast(formatIpcError(e), "error"));
                      }}
                    >
                      Delete
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {view === "reports" && (
        <FinanceReportsScreen
          txs={txs}
          budgets={budgets}
          accounts={accounts}
          summary={summary}
          money={money}
          spendByCategory={spendByCategory}
        />
      )}

      {view === "net-worth" && (
        <>
          <div className="grid gap-2.5 px-3 pt-1 md:grid-cols-4">
            <MetricTile
              label="Net worth"
              value={summary ? money(summary.netWorth) : "—"}
              accent={
                !summary
                  ? undefined
                  : summary.netWorth < 0
                    ? "var(--color-error)"
                    : "var(--color-success)"
              }
            />
            <MetricTile
              label="Cash accounts"
              value={summary ? money(summary.accountBalanceTotal) : "—"}
            />
            <MetricTile
              label="Holdings"
              value={summary ? money(summary.holdingsValue) : "—"}
              accent="var(--color-primary)"
            />
            <MetricTile label="Accounts" value={summary?.accountCount ?? "—"} />
          </div>
          <div className="min-h-0 flex-1 overflow-auto p-3 pt-3">
            <div className="grid gap-3 lg:grid-cols-2">
              <AppCard title="By account type">
                {balanceByType.length === 0 ? (
                  <EmptyState
                    title="No accounts"
                    body="Add accounts to see your net worth breakdown."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {balanceByType.map(([type, total]) => (
                      <li key={type}>
                        <ListRow
                          title={type}
                          leading={<StatusChip title={type} filled />}
                          trailing={
                            <span
                              className={`text-[13px] font-semibold tracking-[-0.02em] tabular-nums ${
                                total < 0
                                  ? "text-[var(--color-error)]"
                                  : "text-[var(--color-success)]"
                              }`}
                            >
                              {money(total)}
                            </span>
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
              <AppCard title={`Holdings · ${holdings.length}`}>
                <p className="mb-3 text-[12px] text-[var(--color-text-light)]">
                  Stocks and crypto included in net worth.
                </p>
                <div className="mb-3 flex justify-end">
                  <Button
                    size="sm"
                    onClick={() => {
                      setEditingHoldingId(null);
                      setHoldingForm({
                        assetType: "stock",
                        symbol: "",
                        name: "",
                        quantity: 1,
                        pricePerUnit: 0,
                      });
                      setHoldingSheet(true);
                    }}
                  >
                    Add holding
                  </Button>
                </div>
                {holdings.length === 0 ? (
                  <EmptyState
                    title="No holdings"
                    body="Track stocks or crypto with quantity and price per unit."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {holdings.map((h) => (
                      <li key={h.id} className="flex items-center gap-2 py-1">
                        <ListRow
                          title={`${h.symbol} · ${h.name || h.assetType}`}
                          subtitle={`${h.quantity} × ${money(h.pricePerUnit)}`}
                          leading={
                            <StatusChip
                              title={h.assetType}
                              tint={
                                h.assetType === "crypto"
                                  ? "var(--color-warning)"
                                  : "var(--color-primary)"
                              }
                              filled
                            />
                          }
                          trailing={
                            <span className="text-[13px] font-semibold tabular-nums">
                              {money(h.marketValue)}
                            </span>
                          }
                          onClick={() => {
                            setEditingHoldingId(h.id);
                            setHoldingForm({
                              assetType: h.assetType,
                              symbol: h.symbol,
                              name: h.name,
                              quantity: h.quantity,
                              pricePerUnit: h.pricePerUnit,
                            });
                            setHoldingSheet(true);
                          }}
                        />
                        <Button
                          size="sm"
                          variant="danger"
                          onClick={() => {
                            if (!confirmDelete(`${h.symbol} holding`)) return;
                            void ipc.financeDeleteHolding(h.id).then(refresh);
                          }}
                        >
                          Delete
                        </Button>
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
              <AppCard title="All accounts">
                {accounts.length === 0 ? (
                  <EmptyState
                    title="No accounts yet"
                    body="Add a checking or savings account, or load sample data from Settings."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {accounts.map((a) => (
                      <li key={a.id}>
                        <ListRow
                          title={a.name}
                          subtitle={a.institution || undefined}
                          leading={<StatusChip title={a.accountType} filled />}
                          trailing={
                            <span
                              className={`text-[13px] font-semibold tracking-[-0.02em] tabular-nums ${
                                a.balance < 0
                                  ? "text-[var(--color-error)]"
                                  : "text-[var(--color-text-main)]"
                              }`}
                            >
                              {money(a.balance, a.currency || "USD")}
                            </span>
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
            </div>
          </div>
        </>
      )}

      <ModalSheet
        open={accountSheet}
        onOpenChange={setAccountSheet}
        title={editingAccountId ? "Edit account" : "Add account"}
      >
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
          </FormField>
          <FormField label="Institution">
            <input
              className={fieldControlClass}
              value={form.institution}
              onChange={(e) => setForm({ ...form, institution: e.target.value })}
            />
          </FormField>
          <FormField label="Type">
            <select
              className={fieldControlClass}
              value={form.accountType}
              onChange={(e) => setForm({ ...form, accountType: e.target.value })}
            >
              {["checking", "savings", "credit", "investment", "real_estate"].map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Balance">
            <input
              className={fieldControlClass}
              type="number"
              value={form.balance}
              onChange={(e) => setForm({ ...form, balance: Number(e.target.value) })}
            />
          </FormField>
          <Button
            disabled={!form.name.trim()}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingAccountId);
                await ipc.financeUpsertAccount({
                  id: editingAccountId ?? undefined,
                  name: form.name.trim(),
                  institution: form.institution.trim() || undefined,
                  accountType: form.accountType,
                  balance: form.balance,
                });
                setAccountSheet(false);
                setEditingAccountId(null);
                setForm({ name: "", institution: "", accountType: "checking", balance: 0 });
                showToast(wasEdit ? "Account updated" : "Account saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save account
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={txSheet} onOpenChange={setTxSheet} title="Add transaction">
        <div className="space-y-3">
          <FormField label="Account">
            <select
              className={fieldControlClass}
              value={txForm.accountId}
              onChange={(e) => setTxForm({ ...txForm, accountId: e.target.value })}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Payee">
            <input
              className={fieldControlClass}
              value={txForm.payee}
              onChange={(e) => setTxForm({ ...txForm, payee: e.target.value })}
            />
          </FormField>
          <FormField label="Amount (negative = expense)">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              value={txForm.amount}
              onChange={(e) => setTxForm({ ...txForm, amount: Number(e.target.value) })}
            />
          </FormField>
          <FormField label="Category">
            <input
              className={fieldControlClass}
              value={txForm.category}
              onChange={(e) => setTxForm({ ...txForm, category: e.target.value })}
            />
          </FormField>
          <FormField label="Date">
            <input
              className={fieldControlClass}
              type="date"
              value={txForm.postedAt}
              onChange={(e) => setTxForm({ ...txForm, postedAt: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!txForm.accountId || !txForm.payee.trim()}
            onClick={async () => {
              await ipc.financeUpsertTransaction({
                accountId: txForm.accountId,
                amount: txForm.amount,
                payee: txForm.payee.trim(),
                category: txForm.category.trim() || undefined,
                postedAt: new Date(txForm.postedAt + "T12:00:00").toISOString(),
              });
              setTxSheet(false);
              setTxForm((prev) => ({ ...prev, payee: "", amount: -10 }));
            }}
          >
            Save transaction
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={budgetSheet} onOpenChange={setBudgetSheet} title="Add budget">
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={budgetForm.name}
              onChange={(e) => setBudgetForm({ ...budgetForm, name: e.target.value })}
            />
          </FormField>
          <FormField label="Category">
            <input
              className={fieldControlClass}
              value={budgetForm.category}
              onChange={(e) => setBudgetForm({ ...budgetForm, category: e.target.value })}
            />
          </FormField>
          <FormField label="Amount">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              value={budgetForm.amount}
              onChange={(e) => setBudgetForm({ ...budgetForm, amount: Number(e.target.value) })}
            />
          </FormField>
          <FormField label="Period">
            <select
              className={fieldControlClass}
              value={budgetForm.period}
              onChange={(e) => setBudgetForm({ ...budgetForm, period: e.target.value })}
            >
              {["monthly", "weekly", "yearly"].map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </FormField>
          <Button
            disabled={!budgetForm.name.trim() || !(budgetForm.amount > 0)}
            onClick={async () => {
              await ipc.financeUpsertBudget({
                name: budgetForm.name.trim(),
                category: budgetForm.category.trim() || undefined,
                amount: budgetForm.amount,
                period: budgetForm.period,
              });
              setBudgetSheet(false);
              setBudgetForm({ name: "", category: "General", amount: 100, period: "monthly" });
            }}
          >
            Save budget
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={goalSheet}
        onOpenChange={setGoalSheet}
        title={editingGoalId ? "Edit goal" : "Add goal"}
      >
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={goalForm.name}
              onChange={(e) => setGoalForm({ ...goalForm, name: e.target.value })}
            />
          </FormField>
          <FormField label="Target amount">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              min={0}
              value={goalForm.targetAmount}
              onChange={(e) =>
                setGoalForm({ ...goalForm, targetAmount: Number(e.target.value) })
              }
            />
          </FormField>
          <FormField label="Current amount">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              min={0}
              value={goalForm.currentAmount}
              onChange={(e) =>
                setGoalForm({ ...goalForm, currentAmount: Number(e.target.value) })
              }
            />
          </FormField>
          <FormField label="Deadline (optional)">
            <input
              className={fieldControlClass}
              type="date"
              value={goalForm.deadline}
              onChange={(e) => setGoalForm({ ...goalForm, deadline: e.target.value })}
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={goalForm.notes}
              onChange={(e) => setGoalForm({ ...goalForm, notes: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!goalForm.name.trim() || !(goalForm.targetAmount > 0)}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingGoalId);
                await ipc.financeUpsertGoal({
                  id: editingGoalId ?? undefined,
                  name: goalForm.name.trim(),
                  targetAmount: goalForm.targetAmount,
                  currentAmount: goalForm.currentAmount,
                  deadline: goalForm.deadline
                    ? new Date(goalForm.deadline + "T12:00:00").toISOString()
                    : null,
                  notes: goalForm.notes.trim() || undefined,
                });
                setGoalSheet(false);
                setEditingGoalId(null);
                setGoalForm({
                  name: "",
                  targetAmount: 1000,
                  currentAmount: 0,
                  deadline: "",
                  notes: "",
                });
                showToast(wasEdit ? "Goal updated" : "Goal saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save goal
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={inventorySheet}
        onOpenChange={setInventorySheet}
        title={editingInventoryId ? "Edit item" : "Add item"}
      >
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={inventoryForm.name}
              onChange={(e) => setInventoryForm({ ...inventoryForm, name: e.target.value })}
            />
          </FormField>
          <FormField label="Category">
            <input
              className={fieldControlClass}
              value={inventoryForm.category}
              onChange={(e) => setInventoryForm({ ...inventoryForm, category: e.target.value })}
            />
          </FormField>
          <FormField label="Purchase date (optional)">
            <input
              className={fieldControlClass}
              type="date"
              value={inventoryForm.purchaseDate}
              onChange={(e) =>
                setInventoryForm({ ...inventoryForm, purchaseDate: e.target.value })
              }
            />
          </FormField>
          <FormField label="Value">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              min={0}
              value={inventoryForm.value}
              onChange={(e) =>
                setInventoryForm({ ...inventoryForm, value: Number(e.target.value) })
              }
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={inventoryForm.notes}
              onChange={(e) => setInventoryForm({ ...inventoryForm, notes: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!inventoryForm.name.trim()}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingInventoryId);
                await ipc.financeUpsertInventoryItem({
                  id: editingInventoryId ?? undefined,
                  name: inventoryForm.name.trim(),
                  category: inventoryForm.category.trim() || undefined,
                  purchaseDate: inventoryForm.purchaseDate
                    ? new Date(inventoryForm.purchaseDate + "T12:00:00").toISOString()
                    : null,
                  value: inventoryForm.value,
                  notes: inventoryForm.notes.trim() || undefined,
                });
                setInventorySheet(false);
                setEditingInventoryId(null);
                setInventoryForm({
                  name: "",
                  category: "General",
                  purchaseDate: "",
                  value: 0,
                  notes: "",
                });
                showToast(wasEdit ? "Item updated" : "Item saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save item
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={receiptSheet}
        onOpenChange={setReceiptSheet}
        title={editingReceiptId ? "Edit receipt" : "Add receipt"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={receiptForm.title}
              onChange={(e) => setReceiptForm({ ...receiptForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Merchant">
            <input
              className={fieldControlClass}
              value={receiptForm.merchant}
              onChange={(e) => setReceiptForm({ ...receiptForm, merchant: e.target.value })}
            />
          </FormField>
          <FormField label="Amount">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              min={0}
              value={receiptForm.amount}
              onChange={(e) =>
                setReceiptForm({ ...receiptForm, amount: Number(e.target.value) })
              }
            />
          </FormField>
          <FormField label="Purchase date (optional)">
            <input
              className={fieldControlClass}
              type="date"
              value={receiptForm.purchasedAt}
              onChange={(e) =>
                setReceiptForm({ ...receiptForm, purchasedAt: e.target.value })
              }
            />
          </FormField>
          <FormField label="Category">
            <input
              className={fieldControlClass}
              value={receiptForm.category}
              onChange={(e) => setReceiptForm({ ...receiptForm, category: e.target.value })}
            />
          </FormField>
          <FormField label="Vault document ID (optional)">
            <input
              className={fieldControlClass}
              placeholder="Link to a vault document"
              value={receiptForm.vaultDocId}
              onChange={(e) => setReceiptForm({ ...receiptForm, vaultDocId: e.target.value })}
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={receiptForm.notes}
              onChange={(e) => setReceiptForm({ ...receiptForm, notes: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!receiptForm.title.trim()}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingReceiptId);
                await ipc.financeUpsertReceipt({
                  id: editingReceiptId ?? undefined,
                  title: receiptForm.title.trim(),
                  merchant: receiptForm.merchant.trim() || undefined,
                  amount: receiptForm.amount,
                  purchasedAt: receiptForm.purchasedAt
                    ? new Date(receiptForm.purchasedAt + "T12:00:00").toISOString()
                    : null,
                  category: receiptForm.category.trim() || undefined,
                  notes: receiptForm.notes.trim() || undefined,
                  vaultDocId: receiptForm.vaultDocId.trim() || null,
                });
                setReceiptSheet(false);
                setEditingReceiptId(null);
                setReceiptForm({
                  title: "",
                  merchant: "",
                  amount: 0,
                  purchasedAt: new Date().toISOString().slice(0, 10),
                  category: "General",
                  notes: "",
                  vaultDocId: "",
                });
                showToast(wasEdit ? "Receipt updated" : "Receipt saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save receipt
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={holdingSheet}
        onOpenChange={setHoldingSheet}
        title={editingHoldingId ? "Edit holding" : "Add holding"}
      >
        <div className="space-y-3">
          <FormField label="Asset type">
            <select
              className={fieldControlClass}
              value={holdingForm.assetType}
              onChange={(e) => setHoldingForm((f) => ({ ...f, assetType: e.target.value }))}
            >
              <option value="stock">Stock / ETF</option>
              <option value="crypto">Crypto</option>
            </select>
          </FormField>
          <FormField label="Symbol">
            <input
              className={fieldControlClass}
              value={holdingForm.symbol}
              onChange={(e) => setHoldingForm((f) => ({ ...f, symbol: e.target.value.toUpperCase() }))}
            />
          </FormField>
          <FormField label="Name (optional)">
            <input
              className={fieldControlClass}
              value={holdingForm.name}
              onChange={(e) => setHoldingForm((f) => ({ ...f, name: e.target.value }))}
            />
          </FormField>
          <FormField label="Quantity">
            <input
              type="number"
              className={fieldControlClass}
              value={holdingForm.quantity}
              onChange={(e) =>
                setHoldingForm((f) => ({ ...f, quantity: Number(e.target.value) || 0 }))
              }
            />
          </FormField>
          <FormField label="Price per unit">
            <input
              type="number"
              className={fieldControlClass}
              value={holdingForm.pricePerUnit}
              onChange={(e) =>
                setHoldingForm((f) => ({ ...f, pricePerUnit: Number(e.target.value) || 0 }))
              }
            />
          </FormField>
          <Button
            onClick={async () => {
              try {
                await ipc.financeUpsertHolding({
                  id: editingHoldingId ?? undefined,
                  assetType: holdingForm.assetType,
                  symbol: holdingForm.symbol.trim(),
                  name: holdingForm.name.trim() || undefined,
                  quantity: holdingForm.quantity,
                  pricePerUnit: holdingForm.pricePerUnit,
                });
                setHoldingSheet(false);
                await refresh();
                showToast(editingHoldingId ? "Holding updated" : "Holding added", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save holding
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={csvSheet} onOpenChange={setCsvSheet} title="Import transactions CSV">
        <div className="space-y-3">
          <p className="text-[12px] text-[var(--color-text-light)]">
            Columns: date, amount, payee, category (optional). One row per line — or choose a `.csv`
            file.
          </p>
          <FormField label="Account">
            <select
              className={fieldControlClass}
              value={csvForm.accountId}
              onChange={(e) => setCsvForm({ ...csvForm, accountId: e.target.value })}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </FormField>
          <Button
            size="sm"
            variant="secondary"
            disabled={!csvForm.accountId}
            onClick={async () => {
              try {
                const picked = await open({
                  multiple: false,
                  directory: false,
                  title: "Import transactions",
                  filters: [{ name: "CSV", extensions: ["csv", "txt"] }],
                });
                if (!picked || typeof picked !== "string") return;
                const count = await ipc.financeImportTransactionsCsvPath(
                  csvForm.accountId,
                  picked,
                );
                setCsvNote(`Imported ${count} transaction${count === 1 ? "" : "s"} from file.`);
                showToast(`Imported ${count} transactions`, "success");
              } catch (e) {
                setCsvNote(formatIpcError(e));
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Choose .csv file…
          </Button>
          <FormField label="Or paste CSV text">
            <textarea
              className={fieldControlClass}
              rows={8}
              placeholder={"2026-01-15,-12.50,Campus Cafe,Food\n2026-01-16,500.00,Refund,Income"}
              value={csvForm.csvText}
              onChange={(e) => setCsvForm({ ...csvForm, csvText: e.target.value })}
            />
          </FormField>
          {csvNote && <p className="text-[12px] text-[var(--color-success)]">{csvNote}</p>}
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!csvForm.accountId || !csvForm.csvText.trim()}
              onClick={async () => {
                try {
                  const count = await ipc.financeImportTransactionsCsv({
                    accountId: csvForm.accountId,
                    csvText: csvForm.csvText,
                  });
                  setCsvNote(`Imported ${count} transaction${count === 1 ? "" : "s"}.`);
                  setCsvForm((prev) => ({ ...prev, csvText: "" }));
                  showToast(`Imported ${count} transactions`, "success");
                } catch (e) {
                  setCsvNote(formatIpcError(e));
                }
              }}
            >
              Import pasted text
            </Button>
            <Button
              size="sm"
              variant="secondary"
              disabled={txs.length === 0}
              onClick={async () => {
                try {
                  const csv = await ipc.financeExportTransactionsCsv();
                  await navigator.clipboard.writeText(csv);
                  showToast("Copied CSV to clipboard", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Copy export
            </Button>
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={recurringSheet}
        onOpenChange={setRecurringSheet}
        title={editingRecurringId ? "Edit recurring" : "Add recurring"}
      >
        <div className="space-y-3">
          <FormField label="Account">
            <select
              className={fieldControlClass}
              value={recurringForm.accountId}
              onChange={(e) => setRecurringForm({ ...recurringForm, accountId: e.target.value })}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={recurringForm.title}
              onChange={(e) => setRecurringForm({ ...recurringForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Amount (negative = expense)">
            <input
              className={fieldControlClass}
              type="number"
              step="0.01"
              value={recurringForm.amount}
              onChange={(e) =>
                setRecurringForm({ ...recurringForm, amount: Number(e.target.value) })
              }
            />
          </FormField>
          <FormField label="Cadence">
            <select
              className={fieldControlClass}
              value={recurringForm.cadence}
              onChange={(e) => setRecurringForm({ ...recurringForm, cadence: e.target.value })}
            >
              {["monthly", "weekly", "yearly"].map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Next due">
            <input
              className={fieldControlClass}
              type="date"
              value={recurringForm.nextDue}
              onChange={(e) => setRecurringForm({ ...recurringForm, nextDue: e.target.value })}
            />
          </FormField>
          <FormField label="Category">
            <input
              className={fieldControlClass}
              value={recurringForm.category}
              onChange={(e) => setRecurringForm({ ...recurringForm, category: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!recurringForm.accountId || !recurringForm.title.trim()}
            onClick={async () => {
              try {
                await ipc.financeUpsertRecurring({
                  id: editingRecurringId ?? undefined,
                  accountId: recurringForm.accountId,
                  title: recurringForm.title.trim(),
                  amount: recurringForm.amount,
                  cadence: recurringForm.cadence,
                  nextDue: recurringForm.nextDue
                    ? new Date(recurringForm.nextDue + "T12:00:00").toISOString()
                    : null,
                  category: recurringForm.category.trim() || undefined,
                });
                setRecurringSheet(false);
                setEditingRecurringId(null);
                await refresh();
                showToast(editingRecurringId ? "Recurring updated" : "Recurring saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save recurring
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}
