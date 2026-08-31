import { motion } from "framer-motion";
import { cn } from "../cn";
import { useReduceMotion } from "../motion/useReduceMotion";

/** Hero block — Fraunces heading, mono eyebrow, brass accent links. */
export function RegistrarHeroBlock({
  eyebrow,
  heading,
  meta,
  action,
  reduceMotion: reduceMotionProp,
  className,
}: {
  eyebrow: string;
  heading: string;
  meta?: string | null;
  action?: { label: string; onClick: () => void } | null;
  reduceMotion?: boolean;
  className?: string;
}) {
  const reduceMotion = useReduceMotion(reduceMotionProp);
  return (
    <motion.div
      className={className}
      initial={reduceMotion ? undefined : { opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.45, ease: [0.16, 1, 0.3, 1] }}
    >
      <p
        className="text-[12px] font-semibold uppercase tracking-[0.08em]"
        style={{ fontFamily: "var(--font-mono)", color: "var(--registrar-accent)" }}
      >
        {eyebrow}
      </p>
      <h1
        className="mt-2 text-[34px] leading-[1.1] sm:text-[42px]"
        style={{ fontFamily: "var(--font-display)", fontWeight: 600, color: "var(--registrar-ink)" }}
      >
        {heading}
      </h1>
      {meta && (
        <p className="mt-2 text-body" style={{ fontFamily: "var(--font-mono)", color: "var(--color-text-light)" }}>
          {meta}
        </p>
      )}
      {action && (
        <button
          type="button"
          onClick={action.onClick}
          className="mt-4 text-body font-medium underline-offset-4 hover:underline focus-visible:underline"
          style={{ color: "var(--registrar-accent)" }}
        >
          {action.label} →
        </button>
      )}
    </motion.div>
  );
}

/** One column of the ledger strip — flat ruled stat, no card shadow. */
export function LedgerStat({
  label,
  value,
  hint,
  onClick,
  last,
  className,
}: {
  label: string;
  value: string;
  hint?: string;
  onClick?: () => void;
  last?: boolean;
  className?: string;
}) {
  const body = (
    <>
      <div className="text-[11.5px] text-[var(--color-text-light)]">{label}</div>
      <div
        className="mt-1 text-[22px] tabular-nums"
        style={{ fontFamily: "var(--font-mono)", fontWeight: 500, color: "var(--registrar-ink)" }}
      >
        {value}
      </div>
      {hint && <div className="mt-0.5 text-caption text-[var(--color-text-light)]">{hint}</div>}
    </>
  );

  const style = { borderRight: last ? "none" : "1px solid var(--registrar-rule)" };

  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        className={cn(
          "flex-1 px-0 py-4 text-left transition-colors hover:bg-[var(--color-row-hover)] focus-visible:bg-[var(--color-row-hover)] sm:px-6",
          className,
        )}
        style={style}
      >
        {body}
      </button>
    );
  }

  return (
    <div className={cn("flex-1 px-0 py-4 sm:px-6", className)} style={style}>
      {body}
    </div>
  );
}

/** Section wrapper: serif label + hairline rule, no card shadow. */
export function RegistrarSection({
  title,
  actionLabel,
  onAction,
  children,
  className,
}: {
  title: string;
  actionLabel?: string;
  onAction?: () => void;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={className}>
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2
          style={{
            fontFamily: "var(--font-display)",
            fontWeight: 600,
            fontSize: 19,
            color: "var(--registrar-ink)",
          }}
        >
          {title}
        </h2>
        {actionLabel && onAction && (
          <button
            type="button"
            onClick={onAction}
            className="text-caption font-medium underline-offset-4 hover:underline focus-visible:underline"
            style={{ color: "var(--registrar-accent)" }}
          >
            {actionLabel}
          </button>
        )}
      </div>
      {children}
    </section>
  );
}

/** Ruled navigation row — label left, hint right. */
export function JumpRow({
  label,
  hint,
  onClick,
  last,
}: {
  label: string;
  hint: string;
  onClick: () => void;
  last?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center justify-between gap-3 py-2.5 text-left transition-colors hover:bg-[var(--color-row-hover)] focus-visible:bg-[var(--color-row-hover)]"
      style={{ borderBottom: last ? "none" : "1px solid var(--registrar-rule)" }}
    >
      <span className="text-body font-medium" style={{ color: "var(--registrar-ink)" }}>
        {label}
      </span>
      <span className="text-caption text-[var(--color-text-light)]">{hint}</span>
    </button>
  );
}

/** Ruled metric row — label + value, no card chrome. */
export function RegistrarMetricRow({
  label,
  value,
  hint,
  last,
}: {
  label: string;
  value: string;
  hint?: string;
  last?: boolean;
}) {
  return (
    <div
      className="flex items-baseline justify-between gap-4 py-2.5"
      style={{ borderBottom: last ? "none" : "1px solid var(--registrar-rule)" }}
    >
      <div className="min-w-0">
        <p className="text-body font-medium" style={{ color: "var(--registrar-ink)" }}>
          {label}
        </p>
        {hint && <p className="text-caption text-[var(--color-text-light)]">{hint}</p>}
      </div>
      <span
        className="shrink-0 text-[15px] tabular-nums"
        style={{ fontFamily: "var(--font-mono)", color: "var(--registrar-ink)" }}
      >
        {value}
      </span>
    </div>
  );
}

/** Scrollable page canvas — matches Home hub layout. */
export function RegistrarPage({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex h-full min-h-0 flex-col bg-[var(--color-shell-canvas)]", className)}>
      <div className="min-h-0 flex-1 overflow-y-auto p-6">{children}</div>
    </div>
  );
}

/** Horizontal ledger strip container. */
export function RegistrarLedgerStrip({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn("flex flex-col sm:flex-row", className)}
      style={{ borderTop: "1px solid var(--registrar-rule)", borderBottom: "1px solid var(--registrar-rule)" }}
    >
      {children}
    </div>
  );
}

/** Hairline top border for ruled list content inside a section. */
export function RegistrarRuledList({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={className} style={{ borderTop: "1px solid var(--registrar-rule)" }}>
      {children}
    </div>
  );
}
