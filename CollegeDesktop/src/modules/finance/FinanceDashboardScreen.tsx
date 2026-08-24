import { useMemo, useState } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  SegmentedPills,
} from "@/design-system";
import {
  buildNetWorthTrend,
  CashFlowBarChart,
  FinanceSectionHero,
  monthCashFlow,
  NetWorthTrendChart,
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
  postedAt: string;
  amount: number;
  payee: string;
};

export function FinanceDashboardScreen({
  netWorth,
  accounts,
  txs,
  money,
  onSelectAccount,
  onViewAllAccounts,
  onViewAllTransactions,
  onAddAccount,
}: {
  netWorth: number;
  accounts: Account[];
  txs: Tx[];
  money: (n: number, currency?: string) => string;
  onSelectAccount: (id: string) => void;
  onViewAllAccounts: () => void;
  onViewAllTransactions: () => void;
  onAddAccount: () => void;
}) {
  const [trendMonths, setTrendMonths] = useState<"3" | "6" | "12">("6");

  const trendPoints = useMemo(
    () => buildNetWorthTrend(accounts, txs, Number(trendMonths)),
    [accounts, txs, trendMonths],
  );

  const netWorthDelta = useMemo(() => {
    if (trendPoints.length < 2) return 0;
    return trendPoints[trendPoints.length - 1].value - trendPoints[trendPoints.length - 2].value;
  }, [trendPoints]);

  const deltaText =
    netWorthDelta !== 0
      ? `${netWorthDelta > 0 ? "↑" : "↓"} ${money(Math.abs(netWorthDelta))} vs last month`
      : undefined;

  const { income, spending } = useMemo(() => monthCashFlow(txs), [txs]);
  const recentTxs = useMemo(
    () =>
      [...txs]
        .sort((a, b) => new Date(b.postedAt).getTime() - new Date(a.postedAt).getTime())
        .slice(0, 4),
    [txs],
  );

  if (accounts.length === 0) {
    return (
      <div className="min-h-0 flex-1 overflow-auto p-3 pt-1">
        <AppCard title="Configure accounts">
          <EmptyState
            title="No accounts yet"
            body="Add a checking or savings account to see net worth, trends, and cash flow."
            action={
              <Button size="sm" onClick={onAddAccount}>
                Add account
              </Button>
            }
          />
        </AppCard>
      </div>
    );
  }

  const leftColumn = (
    <div className="flex flex-col gap-3">
      <FinanceSectionHero
        title="Net worth"
        value={money(netWorth)}
        deltaText={deltaText}
        deltaValue={netWorthDelta}
      />

      <AppCard title="Net worth trend">
        <SegmentedPills
          options={[
            { id: "3", label: "3 mo" },
            { id: "6", label: "6 mo" },
            { id: "12", label: "12 mo" },
          ]}
          value={trendMonths}
          onChange={setTrendMonths}
        />
        <div className="mt-3">
          {trendPoints.length > 1 ? (
            <NetWorthTrendChart points={trendPoints} />
          ) : (
            <EmptyState
              title="No trend data"
              body="Add transactions over time to build a net worth trend."
            />
          )}
        </div>
      </AppCard>

      <AppCard title="Cash flow this month">
        <div className="flex flex-wrap gap-6">
          <div>
            <p className="text-[11px] text-[var(--color-text-light)]">Income</p>
            <p className="text-[18px] font-semibold tabular-nums text-[var(--color-success)]">
              {money(income)}
            </p>
          </div>
          <div>
            <p className="text-[11px] text-[var(--color-text-light)]">Spending</p>
            <p className="text-[18px] font-semibold tabular-nums text-[var(--color-error)]">
              {money(spending)}
            </p>
          </div>
        </div>
        <div className="mt-3">
          <CashFlowBarChart income={income} spending={spending} />
        </div>
      </AppCard>
    </div>
  );

  const rightColumn = (
    <div className="flex flex-col gap-3">
      <AppCard title="Accounts">
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {accounts.map((a) => (
            <li key={a.id}>
              <button
                type="button"
                onClick={() => onSelectAccount(a.id)}
                className="flex w-full items-center justify-between gap-3 py-2 text-left transition hover:bg-[var(--color-row-hover)]"
              >
                <div className="min-w-0">
                  <p className="truncate text-[13px] font-medium text-[var(--color-text-main)]">
                    {a.name}
                  </p>
                  <p className="text-[11px] capitalize text-[var(--color-text-light)]">
                    {a.accountType.replace(/_/g, " ")}
                  </p>
                </div>
                <span
                  className={`shrink-0 text-[13px] font-semibold tabular-nums ${
                    a.balance < 0 ? "text-[var(--color-error)]" : "text-[var(--color-text-main)]"
                  }`}
                >
                  {money(a.balance, a.currency || "USD")}
                </span>
              </button>
            </li>
          ))}
        </ul>
        <Button size="sm" variant="secondary" className="mt-2" onClick={onViewAllAccounts}>
          View all accounts
        </Button>
      </AppCard>

      <AppCard title="Recent">
        {recentTxs.length === 0 ? (
          <EmptyState title="No transactions yet" body="Import a CSV or add a transaction." />
        ) : (
          <>
            <ul className="divide-y divide-[var(--color-chrome-stroke)]">
              {recentTxs.map((t) => (
                <li key={t.id} className="flex items-center justify-between gap-3 py-2">
                  <div className="min-w-0">
                    <p className="truncate text-[13px] text-[var(--color-text-main)]">
                      {t.payee || "Untitled"}
                    </p>
                    <p className="text-[11px] text-[var(--color-text-light)]">
                      {new Date(t.postedAt).toLocaleDateString()}
                    </p>
                  </div>
                  <span
                    className={`shrink-0 text-[13px] font-semibold tabular-nums ${
                      t.amount < 0 ? "text-[var(--color-error)]" : "text-[var(--color-success)]"
                    }`}
                  >
                    {money(t.amount)}
                  </span>
                </li>
              ))}
            </ul>
            <Button size="sm" variant="secondary" className="mt-2" onClick={onViewAllTransactions}>
              View all transactions
            </Button>
          </>
        )}
      </AppCard>
    </div>
  );

  return (
    <div className="min-h-0 flex-1 overflow-auto p-3 pt-1">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:gap-6">
        <div className="min-w-0 flex-1">{leftColumn}</div>
        <div className="w-full shrink-0 lg:w-[340px]">{rightColumn}</div>
      </div>
    </div>
  );
}
