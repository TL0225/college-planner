import { useMemo, useState } from "react";
import {
  AppCard,
  EmptyState,
  ListRow,
  MetricTile,
  ProgressBar,
  SegmentedPills,
  StatusChip,
} from "@/design-system";
import { PathCScreenFrame } from "@/design-system";
import {
  CashFlowBarChart,
  CategoryBarChart,
  CategoryDonutChart,
  NetWorthTrendChart,
  buildNetWorthTrend,
  totalsByCategory,
} from "./FinanceCharts";

type Tx = { id: string; postedAt: string; amount: number; category: string; payee: string; accountName: string };
type Budget = { id: string; name: string; category: string; amount: number; period: string };
type Account = { id: string; name: string; accountType: string; balance: number; currency: string };

type ReportKind = "spending" | "cashflow" | "networth" | "balances";

export function FinanceReportsScreen({
  txs,
  budgets,
  accounts,
  summary,
  money,
  spendByCategory,
}: {
  txs: Tx[];
  budgets: Budget[];
  accounts: Account[];
  summary: { transactionCount?: number; budgetCount?: number; netWorth?: number } | null;
  money: (n: number, currency?: string) => string;
  spendByCategory: Map<string, number>;
}) {
  const [reportKind, setReportKind] = useState<ReportKind>("spending");
  const [moreOpen, setMoreOpen] = useState(false);
  const now = new Date();
  const [periodStart, setPeriodStart] = useState(() => {
    const d = new Date(now);
    d.setMonth(d.getMonth() - 1);
    return d.toISOString().slice(0, 10);
  });
  const [periodEnd, setPeriodEnd] = useState(() => now.toISOString().slice(0, 10));

  const periodTxs = useMemo(
    () =>
      txs.filter((t) => {
        const d = t.postedAt.slice(0, 10);
        return d >= periodStart && d <= periodEnd;
      }),
    [txs, periodStart, periodEnd],
  );

  const categoryRows = useMemo(() => totalsByCategory(periodTxs), [periodTxs]);
  const totalSpend = periodTxs.filter((t) => t.amount < 0).reduce((s, t) => s + Math.abs(t.amount), 0);
  const totalIncome = periodTxs.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const trendPoints = useMemo(() => buildNetWorthTrend(accounts, txs, 6), [accounts, txs]);

  const balanceByType = useMemo(() => {
    const map = new Map<string, number>();
    for (const a of accounts) {
      const key = (a.accountType || "other").trim() || "other";
      map.set(key, (map.get(key) ?? 0) + a.balance);
    }
    return [...map.entries()].sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
  }, [accounts]);

  return (
    <PathCScreenFrame>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <SegmentedPills
          options={[
            { id: "spending", label: "Spending" },
            { id: "cashflow", label: "Income vs Expense" },
            { id: "networth", label: "Net Worth" },
            { id: "balances", label: "Balances" },
          ]}
          value={reportKind}
          onChange={setReportKind}
        />
        <input type="date" className="rounded-lg border border-[var(--color-chrome-stroke)] px-2 py-1 text-[12px]" value={periodStart} onChange={(e) => setPeriodStart(e.target.value)} />
        <span className="text-[var(--color-text-light)]">–</span>
        <input type="date" className="rounded-lg border border-[var(--color-chrome-stroke)] px-2 py-1 text-[12px]" value={periodEnd} onChange={(e) => setPeriodEnd(e.target.value)} />
      </div>

      <AppCard title={reportTitle(reportKind)}>
        {reportKind === "spending" ? (
          categoryRows.length === 0 ? (
            <EmptyState title="No spending data" body="Expense transactions in this period appear here." />
          ) : (
            <div className="space-y-3">
              <CategoryBarChart rows={categoryRows} money={money} />
              <CategoryDonutChart rows={categoryRows} />
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {categoryRows.map(([category, spent]) => (
                  <li key={category}>
                    <ListRow title={category} trailing={<span className="font-semibold tabular-nums text-[var(--color-error)]">{money(spent)}</span>} />
                  </li>
                ))}
              </ul>
            </div>
          )
        ) : null}

        {reportKind === "cashflow" ? (
          <div className="space-y-3">
            <CashFlowBarChart income={totalIncome} spending={totalSpend} />
            <div className="grid grid-cols-3 gap-2">
              <MetricTile label="Inflow" value={money(totalIncome)} accent="var(--color-success)" />
              <MetricTile label="Outflow" value={money(totalSpend)} accent="var(--color-error)" />
              <MetricTile label="Net" value={money(totalIncome - totalSpend)} />
            </div>
          </div>
        ) : null}

        {reportKind === "networth" ? (
          trendPoints.length > 1 ? (
            <NetWorthTrendChart points={trendPoints} />
          ) : (
            <EmptyState title="No trend data" body="Add accounts and transactions to build net worth over time." />
          )
        ) : null}

        {reportKind === "balances" ? (
          balanceByType.length === 0 ? (
            <EmptyState title="No accounts" body="Add accounts to see balances by type." />
          ) : (
            <ul className="divide-y divide-[var(--color-chrome-stroke)]">
              {balanceByType.map(([type, total]) => (
                <li key={type}>
                  <ListRow
                    title={type}
                    leading={<StatusChip title={type} filled />}
                    trailing={
                      <span className={`font-semibold tabular-nums ${total < 0 ? "text-[var(--color-error)]" : "text-[var(--color-success)]"}`}>
                        {money(total)}
                      </span>
                    }
                  />
                </li>
              ))}
            </ul>
          )
        ) : null}
      </AppCard>

      <button
        type="button"
        className="mt-4 flex w-full items-center justify-between rounded-xl border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2 text-[13px] font-semibold text-[var(--color-text-main)]"
        onClick={() => setMoreOpen((v) => !v)}
      >
        More reports
        <span className="text-[var(--color-text-light)]">{moreOpen ? "▾" : "▸"}</span>
      </button>

      {moreOpen ? (
        <div className="mt-3 grid gap-3 lg:grid-cols-2">
          <AppCard title="Budget progress">
            {budgets.length === 0 ? (
              <EmptyState title="No budgets" body="Create budgets to compare targets against actual spend." />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {budgets.map((b) => {
                  const spent = spendByCategory.get(b.category || "General") ?? 0;
                  const ratio = b.amount > 0 ? Math.min(1, spent / b.amount) : 0;
                  return (
                    <li key={b.id} className="py-2">
                      <ListRow title={b.name} subtitle={`${b.category || "General"} · ${b.period}`} trailing={<span className="font-semibold tabular-nums">{money(spent)} / {money(b.amount)}</span>} />
                      <ProgressBar value={ratio} className="mt-2" tint={ratio >= 1 ? "var(--color-success)" : "var(--color-primary)"} />
                    </li>
                  );
                })}
              </ul>
            )}
          </AppCard>
          <AppCard title="Summary">
            <div className="grid grid-cols-3 gap-2">
              <MetricTile label="Transactions" value={summary?.transactionCount ?? txs.length} />
              <MetricTile label="Budgets" value={summary?.budgetCount ?? budgets.length} />
              <MetricTile label="Net worth" value={summary?.netWorth != null ? money(summary.netWorth) : "—"} accent="var(--color-primary)" />
            </div>
          </AppCard>
        </div>
      ) : null}
    </PathCScreenFrame>
  );
}

function reportTitle(kind: ReportKind): string {
  switch (kind) {
    case "spending":
      return "Spending by category";
    case "cashflow":
      return "Income vs expense";
    case "networth":
      return "Net worth over time";
    case "balances":
      return "Account balances";
  }
}
