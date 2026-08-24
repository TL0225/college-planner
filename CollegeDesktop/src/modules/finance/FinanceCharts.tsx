/** Swift Charts substitutes — FinanceDashboardView layout parity (Path C). */

export type TrendPoint = { date: Date; value: number };

export function NetWorthTrendChart({ points }: { points: TrendPoint[] }) {
  if (points.length === 0) return null;
  const w = 560;
  const h = 180;
  const pad = { top: 8, right: 12, bottom: 24, left: 44 };
  const innerW = w - pad.left - pad.right;
  const innerH = h - pad.top - pad.bottom;
  const minY = Math.min(...points.map((p) => p.value));
  const maxY = Math.max(...points.map((p) => p.value));
  const spanY = maxY - minY || 1;
  const minX = points[0].date.getTime();
  const maxX = points[points.length - 1].date.getTime();
  const spanX = maxX - minX || 1;

  const coords = points.map((p) => {
    const x = pad.left + ((p.date.getTime() - minX) / spanX) * innerW;
    const y = pad.top + innerH - ((p.value - minY) / spanY) * innerH;
    return { x, y };
  });

  const linePath = coords.map((c, i) => `${i === 0 ? "M" : "L"} ${c.x} ${c.y}`).join(" ");
  const areaPath = `${linePath} L ${coords[coords.length - 1].x} ${pad.top + innerH} L ${coords[0].x} ${pad.top + innerH} Z`;

  const yTicks = [minY, minY + spanY / 2, maxY];

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label="Net worth trend">
      {yTicks.map((tick, i) => {
        const y = pad.top + innerH - ((tick - minY) / spanY) * innerH;
        return (
          <g key={i}>
            <line
              x1={pad.left}
              y1={y}
              x2={w - pad.right}
              y2={y}
              stroke="var(--color-chrome-stroke)"
              strokeWidth={0.5}
              opacity={0.6}
            />
            <text
              x={pad.left - 6}
              y={y + 3}
              textAnchor="end"
              className="fill-[var(--color-text-light)] text-[9px] tabular-nums"
            >
              {formatCompactMoney(tick)}
            </text>
          </g>
        );
      })}
      <path d={areaPath} fill="var(--color-primary)" opacity={0.12} />
      <path
        d={linePath}
        fill="none"
        stroke="var(--color-primary)"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function CashFlowBarChart({ income, spending }: { income: number; spending: number }) {
  const w = 280;
  const h = 80;
  const pad = 16;
  const max = Math.max(income, spending, 1);
  const barW = 56;
  const gap = 48;
  const x1 = w / 2 - gap / 2 - barW;
  const x2 = w / 2 + gap / 2;

  const bar = (x: number, value: number, color: string) => {
    const barH = (value / max) * (h - pad * 2);
    const y = h - pad - barH;
    return (
      <rect x={x} y={y} width={barW} height={Math.max(2, barH)} rx={4} fill={color} opacity={0.9} />
    );
  };

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label="Cash flow">
      {bar(x1, income, "var(--color-success)")}
      {bar(x2, spending, "var(--color-error)")}
      <text x={x1 + barW / 2} y={h - 4} textAnchor="middle" className="fill-[var(--color-text-light)] text-[9px]">
        Income
      </text>
      <text x={x2 + barW / 2} y={h - 4} textAnchor="middle" className="fill-[var(--color-text-light)] text-[9px]">
        Spending
      </text>
    </svg>
  );
}

export function FinanceSectionHero({
  title,
  value,
  deltaText,
  deltaValue = 0,
}: {
  title: string;
  value: string;
  deltaText?: string;
  deltaValue?: number;
}) {
  const deltaColor =
    deltaValue > 0
      ? "var(--color-success)"
      : deltaValue < 0
        ? "var(--color-error)"
        : "var(--color-text-light)";

  return (
    <div className="w-full">
      <p className="text-[11px] text-[var(--color-text-light)]">{title}</p>
      <p
        className="mt-1 text-[34px] font-semibold tracking-[-0.04em] tabular-nums text-[var(--color-text-main)]"
        style={{ fontFamily: "var(--font-rounded)" }}
      >
        {value}
      </p>
      {deltaText ? (
        <p className="mt-1 text-[11px] font-semibold tabular-nums" style={{ color: deltaColor }}>
          {deltaText}
        </p>
      ) : null}
    </div>
  );
}

function formatCompactMoney(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `$${(n / 1_000).toFixed(0)}k`;
  return `$${Math.round(n)}`;
}

export function buildNetWorthTrend(
  accounts: Array<{ balance: number }>,
  txs: Array<{ postedAt: string; amount: number }>,
  months: number,
): TrendPoint[] {
  const current = accounts.reduce((s, a) => s + a.balance, 0);
  const now = new Date();
  const points: TrendPoint[] = [];
  for (let i = months; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const after = txs
      .filter((t) => new Date(t.postedAt) >= d)
      .reduce((s, t) => s + t.amount, 0);
    points.push({ date: d, value: current - after });
  }
  return points;
}

export function monthCashFlow(txs: Array<{ postedAt: string; amount: number }>) {
  const start = new Date();
  start.setDate(1);
  start.setHours(0, 0, 0, 0);
  const monthTxs = txs.filter((t) => new Date(t.postedAt) >= start);
  const income = monthTxs.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const spending = monthTxs.filter((t) => t.amount < 0).reduce((s, t) => s + Math.abs(t.amount), 0);
  return { income, spending };
}

const DONUT_COLORS = [
  "var(--color-primary)",
  "var(--color-warning)",
  "var(--color-success)",
  "var(--color-error)",
  "#0ea5e9",
  "#a855f7",
  "#f97316",
];

export function CategoryDonutChart({ rows }: { rows: Array<[string, number]> }) {
  const total = rows.reduce((s, [, v]) => s + v, 0);
  if (total <= 0) return null;
  const size = 140;
  const r = 52;
  const c = 2 * Math.PI * r;
  let offset = 0;
  return (
    <div className="flex flex-wrap items-center gap-4">
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label="Spend by category">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--color-chrome-stroke)" strokeWidth={16} />
        {rows.slice(0, 7).map(([label, value], i) => {
          const len = (value / total) * c;
          const el = (
            <circle
              key={label}
              cx={size / 2}
              cy={size / 2}
              r={r}
              fill="none"
              stroke={DONUT_COLORS[i % DONUT_COLORS.length]}
              strokeWidth={16}
              strokeDasharray={`${len} ${c - len}`}
              strokeDashoffset={-offset}
              transform={`rotate(-90 ${size / 2} ${size / 2})`}
              opacity={0.9}
            />
          );
          offset += len;
          return el;
        })}
      </svg>
      <div className="min-w-0 flex-1 space-y-1">
        {rows.slice(0, 5).map(([label, value], i) => (
          <div key={label} className="flex items-center gap-2 text-[11px]">
            <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: DONUT_COLORS[i % DONUT_COLORS.length] }} />
            <span className="min-w-0 flex-1 truncate text-[var(--color-text-light)]">{label}</span>
            <span className="tabular-nums text-[var(--color-text-main)]">{((value / total) * 100).toFixed(0)}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function BalanceSparkline({ points }: { points: number[] }) {
  const w = 560;
  const h = 140;
  const pad = 4;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min || 1;
  const coords = points
    .map((v, i) => {
      const x = pad + (i / Math.max(1, points.length - 1)) * (w - pad * 2);
      const y = pad + (1 - (v - min) / span) * (h - pad * 2);
      return `${x},${y}`;
    })
    .join(" ");
  const last = points[points.length - 1] ?? 0;
  const first = points[0] ?? 0;
  const tint = last >= first ? "#2563eb" : "var(--color-error)";

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label="Balance trend">
      <polyline fill="none" stroke={tint} strokeWidth="2" strokeLinecap="round" points={coords} />
    </svg>
  );
}

export function SpendingBarChart({ txs }: { txs: Array<{ amount: number }> }) {
  if (txs.length === 0) return null;
  const w = 560;
  const h = 140;
  const pad = 8;
  const maxAbs = Math.max(...txs.map((t) => Math.abs(t.amount)), 1);
  const barW = (w - pad * 2) / txs.length;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label="Recent amounts">
      {txs.map((t, i) => {
        const barH = (Math.abs(t.amount) / maxAbs) * (h - pad * 2);
        const x = pad + i * barW + barW * 0.12;
        const bw = barW * 0.76;
        const y = h - pad - barH;
        return (
          <rect
            key={i}
            x={x}
            y={y}
            width={bw}
            height={Math.max(2, barH)}
            rx={2}
            fill={t.amount < 0 ? "var(--color-error)" : "var(--color-success)"}
            opacity={0.85}
          />
        );
      })}
    </svg>
  );
}

export function balanceSparklinePoints(accountBalance: number, txs: Array<{ postedAt: string; amount: number }>, limit = 12) {
  const recent = [...txs].sort((a, b) => new Date(a.postedAt).getTime() - new Date(b.postedAt).getTime()).slice(-limit);
  let running = accountBalance;
  const points = [running];
  for (let i = recent.length - 1; i >= 0; i--) {
    running -= recent[i].amount;
    points.unshift(running);
  }
  return points.length > 1 ? points : [accountBalance, accountBalance];
}

export function totalsByCategory(txs: Array<{ amount: number; category?: string }>) {
  const map = new Map<string, number>();
  for (const t of txs) {
    if (t.amount >= 0) continue;
    const key = (t.category || "General").trim() || "General";
    map.set(key, (map.get(key) ?? 0) + Math.abs(t.amount));
  }
  return [...map.entries()].sort((a, b) => b[1] - a[1]);
}

export function CategoryBarChart({ rows, money }: { rows: Array<[string, number]>; money: (n: number) => string }) {
  if (rows.length === 0) return null;
  const w = 560;
  const h = 220;
  const pad = { l: 8, r: 8, t: 8, b: 28 };
  const max = Math.max(...rows.map(([, v]) => v), 1);
  const barW = (w - pad.l - pad.r) / Math.min(rows.length, 8);
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label="Spending by category">
      {rows.slice(0, 8).map(([label, value], i) => {
        const barH = (value / max) * (h - pad.t - pad.b);
        const x = pad.l + i * barW + barW * 0.15;
        const bw = barW * 0.7;
        const y = h - pad.b - barH;
        return (
          <g key={label}>
            <rect x={x} y={y} width={bw} height={Math.max(2, barH)} rx={3} fill="var(--color-primary)" opacity={0.85} />
            <text x={x + bw / 2} y={h - 6} textAnchor="middle" className="fill-[var(--color-text-light)] text-[8px]">
              {label.slice(0, 8)}
            </text>
            <title>{`${label}: ${money(value)}`}</title>
          </g>
        );
      })}
    </svg>
  );
}
