import type { CSSProperties, ReactNode } from "react";

/** Shared Path C visual primitives — Swift composition without stock System Settings chrome. */

export function FlatSectionTitle({
  children,
  accent = "var(--color-primary)",
}: {
  children: ReactNode;
  accent?: string;
}) {
  return (
    <div
      className="font-bold tracking-[-0.01em]"
      style={{ color: accent, font: "var(--type-section-title)", fontSize: 14 }}
    >
      {children}
    </div>
  );
}

export function FormAmountHero({
  label,
  value,
  hint,
  negative,
}: {
  label: string;
  value: string;
  hint?: string;
  negative?: boolean;
}) {
  return (
    <div className="w-full">
      <p className="text-[11px] font-medium text-[var(--color-text-light)]">{label}</p>
      <p
        className={`mt-1 text-[32px] font-semibold tracking-[-0.04em] tabular-nums ${
          negative ? "text-[var(--color-error)]" : "text-[var(--color-text-main)]"
        }`}
        style={{ fontFamily: "var(--font-rounded)" }}
      >
        {value}
      </p>
      {hint ? <p className="mt-1 text-[11px] text-[var(--color-text-light)]">{hint}</p> : null}
    </div>
  );
}

export function InsetChartCard({
  title,
  headerRight,
  children,
  className,
}: {
  title: string;
  headerRight?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={className}
      style={{
        borderRadius: 10,
        border: "1px solid color-mix(in srgb, var(--color-text-main) 8%, var(--color-chrome-stroke))",
        background: "color-mix(in srgb, var(--color-text-main) 2%, transparent)",
        padding: "12px 14px",
      }}
    >
      <div className="mb-2.5 flex flex-wrap items-center gap-2">
        <span className="text-[12px] font-semibold text-[var(--color-text-light)]">{title}</span>
        <span className="ml-auto flex flex-wrap items-center gap-2">{headerRight}</span>
      </div>
      {children}
    </div>
  );
}

export function FinderToolbarRow({
  left,
  right,
}: {
  left: ReactNode;
  right?: ReactNode;
}) {
  return (
    <div
      className="flex flex-wrap items-center gap-2 border-b border-[var(--color-chrome-stroke)] px-3 py-2"
      style={{
        background: "color-mix(in srgb, var(--color-surface) 92%, transparent)",
        boxShadow: "inset 0 -1px 0 color-mix(in srgb, white 25%, transparent)",
      }}
    >
      <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2">{left}</div>
      {right ? <div className="flex shrink-0 flex-wrap items-center gap-2">{right}</div> : null}
    </div>
  );
}

export function KanbanLaneHeader({
  title,
  count,
  tint,
}: {
  title: string;
  count: number;
  tint: string;
}) {
  return (
    <div
      className="flex items-center gap-2 rounded-t-xl px-3 py-2"
      style={{
        background: `linear-gradient(90deg, color-mix(in srgb, ${tint} 12%, transparent), transparent)`,
        borderBottom: "1px solid var(--color-chrome-stroke)",
      }}
    >
      <span className="inline-block h-2 w-2 rounded-full" style={{ background: tint }} />
      <span className="text-[12px] font-semibold text-[var(--color-text-main)]">{title}</span>
      <span className="ml-auto rounded-full bg-black/5 px-2 py-0.5 text-[10px] font-bold tabular-nums text-[var(--color-text-light)]">
        {count}
      </span>
    </div>
  );
}

export function SettingsPaneShell({
  sidebar,
  children,
}: {
  sidebar: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="flex min-h-0 flex-1 overflow-hidden">
      <aside
        className="w-[220px] shrink-0 overflow-y-auto border-r border-[var(--color-chrome-stroke)] p-2"
        style={{ background: "var(--color-surface)" }}
      >
        {sidebar}
      </aside>
      <div className="min-h-0 min-w-0 flex-1 overflow-y-auto p-3">{children}</div>
    </div>
  );
}

export function HubModuleTile({
  icon,
  title,
  subtitle,
  onClick,
}: {
  icon: ReactNode;
  title: string;
  subtitle?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="group flex flex-col items-start gap-2 rounded-[14px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-4 text-left transition-transform hover:-translate-y-0.5 hover:bg-[var(--color-row-hover)]"
      style={{
        boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
      }}
    >
      <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-[color-mix(in_srgb,var(--color-primary)_12%,transparent)] text-[var(--color-primary)]">
        {icon}
      </span>
      <span className="text-[14px] font-semibold text-[var(--color-text-main)]">{title}</span>
      {subtitle ? (
        <span className="text-[11px] leading-snug text-[var(--color-text-light)]">{subtitle}</span>
      ) : null}
    </button>
  );
}

export function PathCScreenFrame({
  children,
  style,
}: {
  children: ReactNode;
  style?: CSSProperties;
}) {
  return (
    <div className="min-h-0 flex-1 overflow-auto px-3 pb-4 pt-1" style={style}>
      {children}
    </div>
  );
}
