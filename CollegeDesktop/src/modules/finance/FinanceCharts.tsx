import { useId } from "react";

/** Fluid finance charts — compact fixed-height frames, no non-uniform SVG stretch. */

export type TrendPoint = { date: Date; value: number };

const SVG_ASPECT = "xMidYMid meet" as const;

function ChartFrame({
  height,
  children,
}: {
  height: number;
  children: React.ReactNode;
}) {
  return (
    <div className="w-full overflow-hidden" style={{ height }}>
      {children}
    </div>
  );
}

/** Pad flat or tight domains so lines aren't glued to an edge. */
function paddedValueDomain(min: number, max: number): [number, number] {
  if (min === max) {
    const pad = Math.max(Math.abs(min) * 0.06, 100);
    return [min - pad, max + pad];
  }
  const pad = (max - min) * 0.1;
  return [min - pad, max + pad];
}

function buildYTicks(domainMin: number, domainMax: number): number[] {
  const span = domainMax - domainMin;
  const candidates = [domainMin, domainMin + span / 2, domainMax];
  const out: number[] = [];
  for (const tick of candidates) {
    if (!out.some((t) => Math.abs(t - tick) < span * 0.02)) out.push(tick);
  }
  return out;
}

/** Catmull-Rom → cubic Bezier smoothing for a fluid curve through points. */
function smoothPath(points: Array<{ x: number; y: number }>): string {
  if (points.length === 0) return "";
  if (points.length === 1) return `M ${points[0].x} ${points[0].y}`;
  if (points.length === 2) {
    return `M ${points[0].x} ${points[0].y} L ${points[1].x} ${points[1].y}`;
  }
  let d = `M ${points[0].x} ${points[0].y}`;
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[i === 0 ? i : i - 1];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[i + 2 < points.length ? i + 2 : i + 1];
    const cp1x = p1.x + (p2.x - p0.x) / 6;
    const cp1y = p1.y + (p2.y - p0.y) / 6;
    const cp2x = p2.x - (p3.x - p1.x) / 6;
    const cp2y = p2.y - (p3.y - p1.y) / 6;
    d += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2.x} ${p2.y}`;
  }
  return d;
}

function monthLabel(d: Date): string {
  return d.toLocaleDateString(undefined, { month: "short" });
}

export function NetWorthTrendChart({ points }: { points: TrendPoint[] }) {
  const uid = useId();
  if (points.length === 0) return null;

  const w = 400;
  const h = 112;
  const pad = { top: 10, right: 8, bottom: 22, left: 42 };
  const innerW = w - pad.left - pad.right;
  const innerH = h - pad.top - pad.bottom;

  const rawMin = Math.min(...points.map((p) => p.value));
  const rawMax = Math.max(...points.map((p) => p.value));
  const [domainMin, domainMax] = paddedValueDomain(rawMin, rawMax);
  const spanY = domainMax - domainMin || 1;

  const minX = points[0].date.getTime();
  const maxX = points[points.length - 1].date.getTime();
  const spanX = maxX - minX || 1;

  const coords = points.map((p) => ({
    x: pad.left + ((p.date.getTime() - minX) / spanX) * innerW,
    y: pad.top + innerH - ((p.value - domainMin) / spanY) * innerH,
  }));

  const linePath = smoothPath(coords);
  const last = coords[coords.length - 1];
  const areaPath = `${linePath} L ${last.x} ${pad.top + innerH} L ${coords[0].x} ${pad.top + innerH} Z`;
  const yTicks = buildYTicks(domainMin, domainMax);
  const gradId = `nw-grad-${uid}`;
  const rising = points[points.length - 1].value >= points[0].value;
  const tint = rising ? "var(--color-primary)" : "var(--color-error)";

  const xLabels = points.length <= 6
    ? points
    : [points[0], points[Math.floor(points.length / 2)], points[points.length - 1]];

  return (
    <ChartFrame height={h}>
      <svg
        className="h-full w-full"
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio={SVG_ASPECT}
        role="img"
        aria-label="Net worth trend"
      >
        <defs>
          <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={tint} stopOpacity={0.22} />
            <stop offset="100%" stopColor={tint} stopOpacity={0} />
          </linearGradient>
        </defs>
        {yTicks.map((tick, i) => {
          const y = pad.top + innerH - ((tick - domainMin) / spanY) * innerH;
          return (
            <g key={i}>
              <line
                x1={pad.left}
                y1={y}
                x2={w - pad.right}
                y2={y}
                stroke="var(--color-chrome-stroke)"
                strokeWidth={0.5}
                strokeDasharray="2 3"
                opacity={0.45}
              />
              <text
                x={pad.left - 4}
                y={y + 3}
                textAnchor="end"
                fontSize={9}
                className="fill-[var(--color-text-light)] tabular-nums"
              >
                {formatCompactMoney(tick)}
              </text>
            </g>
          );
        })}
        {xLabels.map((p, i) => {
          const x = pad.left + ((p.date.getTime() - minX) / spanX) * innerW;
          return (
            <text
              key={i}
              x={x}
              y={h - 4}
              textAnchor="middle"
              fontSize={9}
              className="fill-[var(--color-text-light)]"
            >
              {monthLabel(p.date)}
            </text>
          );
        })}
        <path d={areaPath} fill={`url(#${gradId})`} />
        <path
          d={linePath}
          fill="none"
          stroke={tint}
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          vectorEffect="non-scaling-stroke"
        />
        <circle
          cx={last.x}
          cy={last.y}
          r={3.5}
          fill="var(--color-shell-canvas)"
          stroke={tint}
          strokeWidth={2}
          vectorEffect="non-scaling-stroke"
        />
      </svg>
    </ChartFrame>
  );
}

/** Horizontal fluid meter — income vs. spending as proportional rounded pills. */
export function CashFlowMeter({ income, spending }: { income: number; spending: number }) {
  const max = Math.max(income, spending, 1);
  const rows: Array<{ label: string; value: number; color: string }> = [
    { label: "Income", value: income, color: "var(--color-success)" },
    { label: "Spending", value: spending, color: "var(--color-error)" },
  ];
  return (
    <div className="flex flex-col gap-2">
      {rows.map((row) => {
        const pct = row.value <= 0 ? 0 : Math.max(3, Math.min(100, (row.value / max) * 100));
        return (
          <div key={row.label} className="flex items-center gap-2.5">
            <span className="w-14 shrink-0 text-label text-[var(--color-text-light)]">{row.label}</span>
            <div className="h-2 min-w-0 flex-1 overflow-hidden rounded-full bg-[color-mix(in_srgb,var(--color-chrome-stroke)_55%,transparent)]">
              <div
                className="h-full rounded-full"
                style={{
                  width: `${pct}%`,
                  background: `linear-gradient(90deg, color-mix(in srgb, ${row.color} 70%, transparent), ${row.color})`,
                }}
              />
            </div>
          </div>
        );
      })}
    </div>
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
      <p className="text-caption">{title}</p>
      <p
        className="mt-1 text-page-title font-semibold tracking-[-0.04em] tabular-nums text-[var(--color-text-main)]"
        style={{ fontSize: 34, fontFamily: "var(--font-rounded)" }}
      >
        {value}
      </p>
      {deltaText ? (
        <p className="mt-1 text-label font-semibold tabular-nums" style={{ color: deltaColor }}>
          {deltaText}
        </p>
      ) : null}
    </div>
  );
}

function formatCompactMoney(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `$${(n / 1_000).toFixed(1)}k`;
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

export function periodCashFlow(txs: Array<{ amount: number }>) {
  const income = txs.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const spending = txs.filter((t) => t.amount < 0).reduce((s, t) => s + Math.abs(t.amount), 0);
  return { income, spending };
}

const CATEGORY_COLORS = [
  "#6d7ef7",
  "#f6a24b",
  "#3fbf8f",
  "#f2647a",
  "#3fb6d8",
  "#b17ce8",
  "#f2c14e",
  "#8a97ab",
];

/** Ring chart — rounded segment caps and small gaps. */
export function CategoryDonutChart({ rows }: { rows: Array<[string, number]> }) {
  const total = rows.reduce((s, [, v]) => s + v, 0);
  if (total <= 0) return null;
  const size = 108;
  const r = 40;
  const strokeW = 12;
  const c = 2 * Math.PI * r;
  const gap = 5;
  const top = rows.slice(0, 7);
  let offset = 0;

  return (
    <div className="flex flex-wrap items-center gap-4">
      <div className="relative shrink-0" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label="Spend by category">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke="color-mix(in srgb, var(--color-chrome-stroke) 70%, transparent)"
            strokeWidth={strokeW}
          />
          {top.map(([label, value], i) => {
            const len = Math.max(0, (value / total) * c - gap);
            const el = (
              <circle
                key={label}
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={CATEGORY_COLORS[i % CATEGORY_COLORS.length]}
                strokeWidth={strokeW}
                strokeLinecap="round"
                strokeDasharray={`${len} ${c - len}`}
                strokeDashoffset={-offset}
                transform={`rotate(-90 ${size / 2} ${size / 2})`}
              />
            );
            offset += (value / total) * c;
            return el;
          })}
        </svg>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-caption text-[var(--color-text-light)]">Total</span>
          <span className="text-body font-semibold tabular-nums text-[var(--color-text-main)]">
            {formatCompactMoney(total)}
          </span>
        </div>
      </div>
      <div className="min-w-0 flex-1 space-y-1">
        {top.slice(0, 5).map(([label, value], i) => (
          <div key={label} className="flex items-center gap-2 text-caption">
            <span
              className="h-1.5 w-1.5 shrink-0 rounded-full"
              style={{ background: CATEGORY_COLORS[i % CATEGORY_COLORS.length] }}
            />
            <span className="min-w-0 flex-1 truncate text-[var(--color-text-light)]">{label}</span>
            <span className="tabular-nums text-[var(--color-text-main)]">
              {((value / total) * 100).toFixed(0)}%
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/** Horizontal proportional bars — compact list-native chart. */
export function CategorySpendRows({
  rows,
  money,
}: {
  rows: Array<[string, number]>;
  money: (n: number) => string;
}) {
  if (rows.length === 0) return null;
  const top = rows.slice(0, 6);
  const max = Math.max(...top.map(([, v]) => v), 1);
  return (
    <div className="flex flex-col gap-2">
      {top.map(([label, value], i) => {
        const pct = Math.max(3, (value / max) * 100);
        const color = CATEGORY_COLORS[i % CATEGORY_COLORS.length];
        return (
          <div key={label} className="flex items-center gap-2">
            <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: color }} />
            <span className="w-20 shrink-0 truncate text-caption text-[var(--color-text-main)]">{label}</span>
            <div className="h-1.5 min-w-0 flex-1 overflow-hidden rounded-full bg-[color-mix(in_srgb,var(--color-chrome-stroke)_55%,transparent)]">
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
            </div>
            <span className="w-14 shrink-0 text-right text-caption font-medium tabular-nums text-[var(--color-text-main)]">
              {money(value)}
            </span>
          </div>
        );
      })}
    </div>
  );
}

/** Smooth area sparkline for balance history. */
export function BalanceSparkline({ points }: { points: number[] }) {
  const uid = useId();
  if (points.length === 0) return null;

  const w = 400;
  const h = 72;
  const pad = { top: 6, right: 6, bottom: 6, left: 6 };
  const innerW = w - pad.left - pad.right;
  const innerH = h - pad.top - pad.bottom;

  const rawMin = Math.min(...points);
  const rawMax = Math.max(...points);
  const [domainMin, domainMax] = paddedValueDomain(rawMin, rawMax);
  const span = domainMax - domainMin || 1;

  const coords = points.map((v, i) => ({
    x: pad.left + (i / Math.max(1, points.length - 1)) * innerW,
    y: pad.top + innerH - ((v - domainMin) / span) * innerH,
  }));

  const last = points[points.length - 1] ?? 0;
  const first = points[0] ?? 0;
  const tint = last >= first ? "var(--color-primary)" : "var(--color-error)";
  const linePath = smoothPath(coords);
  const lastPt = coords[coords.length - 1];
  const areaPath = `${linePath} L ${lastPt.x} ${pad.top + innerH} L ${coords[0].x} ${pad.top + innerH} Z`;
  const gradId = `bal-grad-${uid}`;

  return (
    <ChartFrame height={h}>
      <svg
        className="h-full w-full"
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio={SVG_ASPECT}
        role="img"
        aria-label="Balance trend"
      >
        <defs>
          <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={tint} stopOpacity={0.2} />
            <stop offset="100%" stopColor={tint} stopOpacity={0} />
          </linearGradient>
        </defs>
        <path d={areaPath} fill={`url(#${gradId})`} />
        <path
          d={linePath}
          fill="none"
          stroke={tint}
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          vectorEffect="non-scaling-stroke"
        />
        <circle
          cx={lastPt.x}
          cy={lastPt.y}
          r={3}
          fill="var(--color-shell-canvas)"
          stroke={tint}
          strokeWidth={1.75}
          vectorEffect="non-scaling-stroke"
        />
      </svg>
    </ChartFrame>
  );
}

export function balanceSparklinePoints(
  accountBalance: number,
  txs: Array<{ postedAt: string; amount: number }>,
  limit = 12,
) {
  const recent = [...txs]
    .sort((a, b) => new Date(a.postedAt).getTime() - new Date(b.postedAt).getTime())
    .slice(-limit);
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
