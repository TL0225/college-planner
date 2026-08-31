import { useMemo, useState } from "react";
import { Button, ListRow, SegmentedPills, StatusChip } from "@/design-system";
import { FormAmountHero, InsetChartCard } from "@/design-system";
import {
  BalanceSparkline,
  CashFlowMeter,
  CategoryDonutChart,
  balanceSparklinePoints,
  monthCashFlow,
  periodCashFlow,
  totalsByCategory,
} from "./FinanceCharts";

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
  postedAt: string;
  amount: number;
  payee: string;
  category: string;
};

type ChartLayer = "balance" | "spending" | "income";

export function FinanceAccountDetailScreen({
  account,
  txs,
  money,
  onEdit,
  onDelete,
  onClose,
}: {
  account: Account;
  txs: Tx[];
  money: (n: number, currency?: string) => string;
  onEdit: () => void;
  onDelete: () => void;
  onClose: () => void;
}) {
  const [chartLayout, setChartLayout] = useState<"trend" | "categories">("trend");
  const [chartMonths, setChartMonths] = useState<"1" | "3" | "6">("3");
  const [layers, setLayers] = useState<Set<ChartLayer>>(() => new Set(["balance", "spending"]));

  const accountTxs = useMemo(
    () => txs.filter((t) => t.accountId === account.id).sort((a, b) => new Date(b.postedAt).getTime() - new Date(a.postedAt).getTime()),
    [account.id, txs],
  );

  const chartTxs = useMemo(() => {
    const months = Number(chartMonths);
    const start = new Date();
    start.setMonth(start.getMonth() - months);
    return accountTxs.filter((t) => new Date(t.postedAt) >= start);
  }, [accountTxs, chartMonths]);

  const sparkPoints = useMemo(
    () => balanceSparklinePoints(account.balance, accountTxs),
    [account.balance, accountTxs],
  );

  const categoryRows = useMemo(() => totalsByCategory(chartTxs), [chartTxs]);
  const monthly = useMemo(() => monthCashFlow(accountTxs), [accountTxs]);
  const periodFlow = useMemo(() => periodCashFlow(chartTxs), [chartTxs]);

  const toggleLayer = (layer: ChartLayer) => {
    setLayers((prev) => {
      const next = new Set(prev);
      if (next.has(layer)) {
        if (next.size > 1) next.delete(layer);
      } else {
        next.add(layer);
      }
      return next;
    });
  };

  const layerMeta: Record<ChartLayer, { label: string; color: string }> = {
    balance: { label: "Balance", color: "#2563eb" },
    spending: { label: "Spending", color: "var(--color-error)" },
    income: { label: "Income", color: "var(--color-success)" },
  };

  return (
    <div className="flex h-full flex-col">
      <header className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
        <div className="flex flex-wrap items-center gap-1.5">
          <StatusChip title={account.accountType} filled />
          {account.institution ? <StatusChip title={account.institution} /> : null}
        </div>
        <h3
          className="mt-2 text-section-title font-semibold tracking-[-0.02em] text-[var(--color-text-main)]"
          style={{ fontSize: 18 }}
        >
          {account.name}
        </h3>
        <FormAmountHero
          label="Current balance"
          value={money(account.balance, account.currency || "USD")}
          negative={account.balance < 0}
        />
      </header>

      <div className="min-h-0 flex-1 space-y-4 overflow-auto p-4">
        <InsetChartCard
          title={chartLayout === "trend" ? "Balance history" : "Categories"}
          headerRight={
            <>
              <SegmentedPills
                options={[
                  { id: "trend", label: "Trend" },
                  { id: "categories", label: "Categories" },
                ]}
                value={chartLayout}
                onChange={setChartLayout}
              />
              <SegmentedPills
                options={[
                  { id: "1", label: "1 mo" },
                  { id: "3", label: "3 mo" },
                  { id: "6", label: "6 mo" },
                ]}
                value={chartMonths}
                onChange={setChartMonths}
              />
            </>
          }
        >
          {chartLayout === "trend" ? (
            <>
              <div className="mb-2 flex flex-wrap gap-1.5">
                {(Object.keys(layerMeta) as ChartLayer[]).map((layer) => {
                  const on = layers.has(layer);
                  const meta = layerMeta[layer];
                  return (
                    <button
                      key={layer}
                      type="button"
                      onClick={() => toggleLayer(layer)}
                      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-label"
                      style={{
                        border: `1px solid ${on ? meta.color : "var(--color-chrome-stroke)"}`,
                        background: on ? `color-mix(in srgb, ${meta.color} 14%, transparent)` : "var(--color-surface)",
                        color: on ? "var(--color-text-main)" : "var(--color-text-light)",
                      }}
                    >
                      <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: meta.color }} />
                      {meta.label}
                    </button>
                  );
                })}
              </div>
              {layers.has("balance") ? <BalanceSparkline points={sparkPoints} /> : null}
              {(layers.has("spending") || layers.has("income")) && (
                <div className={layers.has("balance") ? "mt-3 border-t border-[var(--registrar-rule)] pt-3" : ""}>
                  <CashFlowMeter
                    income={layers.has("income") ? periodFlow.income : 0}
                    spending={layers.has("spending") ? periodFlow.spending : 0}
                  />
                </div>
              )}
            </>
          ) : categoryRows.length === 0 ? (
            <p className="text-meta">
              Add transactions with categories to see a breakdown.
            </p>
          ) : (
            <CategoryDonutChart rows={categoryRows} />
          )}
        </InsetChartCard>

        <div className="grid grid-cols-2 gap-3">
          <div className="rounded-xl border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] p-3">
            <p className="text-caption">Deposits this month</p>
            <p
              className="mt-1 text-section-title font-semibold tabular-nums text-[var(--color-success)]"
              style={{ fontSize: 20 }}
            >
              {money(monthly.income)}
            </p>
          </div>
          <div className="rounded-xl border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] p-3">
            <p className="text-caption">Withdrawals this month</p>
            <p
              className="mt-1 text-section-title font-semibold tabular-nums text-[var(--color-error)]"
              style={{ fontSize: 20 }}
            >
              {money(monthly.spending)}
            </p>
          </div>
        </div>

        <div>
          <p className="mb-2 text-label font-semibold uppercase tracking-[0.05em]">
            Recent transactions
          </p>
          <ul className="divide-y divide-[var(--color-chrome-stroke)] rounded-[10px] border border-[var(--color-chrome-stroke)]">
            {accountTxs.slice(0, 10).map((t) => (
              <li key={t.id}>
                <ListRow
                  title={t.payee || "Untitled"}
                  subtitle={new Date(t.postedAt).toLocaleDateString()}
                  leading={t.category ? <StatusChip title={t.category} /> : undefined}
                  trailing={
                    <span
                      className={`text-meta font-semibold tabular-nums ${
                        t.amount < 0 ? "text-[var(--color-error)]" : "text-[var(--color-success)]"
                      }`}
                    >
                      {money(t.amount)}
                    </span>
                  }
                  interactive={false}
                />
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
        <Button size="sm" onClick={onEdit}>
          Edit
        </Button>
        <Button size="sm" variant="danger" onClick={onDelete}>
          Delete
        </Button>
        <Button size="sm" variant="ghost" onClick={onClose}>
          Close
        </Button>
      </div>
    </div>
  );
}
