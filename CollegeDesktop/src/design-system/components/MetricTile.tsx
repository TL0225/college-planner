import { motion } from "framer-motion";
import { cn } from "../cn";
import { radius } from "../tokens";
import { pillSpring, standardSpring, withReduceMotion } from "../motion/springPresets";

export function MetricTile({
  label,
  value,
  accent,
  className,
}: {
  label: string;
  value: string | number;
  accent?: string;
  className?: string;
}) {
  return (
    <div
      className={cn("w-full", className)}
      style={{
        padding: "14px 14px 12px",
        borderRadius: radius.lg,
        background: "var(--color-surface)",
        border: "1px solid var(--color-chrome-stroke)",
        boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
      }}
    >
      <div className="text-[11px] font-medium uppercase tracking-[0.05em] text-[var(--color-text-light)]">
        {label}
      </div>
      <p
        className="mt-1.5 text-[28px] font-semibold tracking-[-0.03em] tabular-nums text-[var(--color-text-main)]"
        style={accent ? { color: accent } : undefined}
      >
        {value}
      </p>
    </div>
  );
}

export function SegmentedPills<T extends string>({
  options,
  value,
  onChange,
  reduceMotion = false,
}: {
  options: Array<{ id: T; label: string }>;
  value: T;
  onChange: (id: T) => void;
  reduceMotion?: boolean;
}) {
  return (
    <div
      className="relative inline-flex items-center gap-0.5 p-0.5"
      style={{
        borderRadius: 999,
        background: "var(--color-shell-chrome)",
        border: "1px solid var(--color-chrome-stroke)",
      }}
    >
      {options.map((opt) => {
        const selected = opt.id === value;
        return (
          <button
            key={opt.id}
            type="button"
            onClick={() => onChange(opt.id)}
            className={cn(
              "relative rounded-full px-2.5 py-1 text-[11px] transition-colors",
              selected
                ? "font-semibold text-[var(--color-text-main)]"
                : "font-medium text-[var(--color-text-light)] hover:text-[var(--color-text-main)]",
            )}
          >
            {selected && (
              <motion.span
                layoutId="segmentedPillSelection"
                className="absolute inset-0 bg-[var(--color-shell-selection)] shadow-[var(--shadow-pill)]"
                style={{ borderRadius: 999 }}
                transition={withReduceMotion(reduceMotion, pillSpring)}
              />
            )}
            <span className="relative z-10">{opt.label}</span>
          </button>
        );
      })}
    </div>
  );
}

export function ListRow({
  title,
  subtitle,
  trailing,
  onClick,
  onDoubleClick,
  leading,
  selected,
  interactive = true,
  reduceMotion = false,
}: {
  title: string;
  subtitle?: React.ReactNode;
  trailing?: React.ReactNode;
  leading?: React.ReactNode;
  onClick?: () => void;
  onDoubleClick?: () => void;
  selected?: boolean;
  /** Subtle press/hover scale (matches InteractiveSurface). Default on when `onClick` is set. */
  interactive?: boolean;
  reduceMotion?: boolean;
}) {
  const className = cn(
    "flex w-full items-center gap-3 px-2 py-2.5 text-left transition-colors",
    onClick && interactive && "origin-center",
    onClick && "hover:bg-[var(--color-row-hover)]",
    selected && "bg-[var(--color-primary-soft)]",
  );
  const style = { borderRadius: radius.md };
  const body = (
    <>
      {leading}
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13px] font-medium tracking-[-0.01em] text-[var(--color-text-main)]">
          {title}
        </div>
        {subtitle != null && subtitle !== "" && (
          <div className="mt-0.5 text-[11px] text-[var(--color-text-light)]">{subtitle}</div>
        )}
      </div>
      {trailing && <div className="shrink-0 text-[11px] text-[var(--color-text-light)]">{trailing}</div>}
    </>
  );
  if (onClick) {
    if (interactive) {
      return (
        <motion.button
          type="button"
          onClick={onClick}
          onDoubleClick={onDoubleClick}
          className={className}
          style={style}
          whileHover={reduceMotion ? undefined : { scale: 1.01 }}
          whileTap={reduceMotion ? undefined : { scale: 0.97 }}
          transition={withReduceMotion(reduceMotion, standardSpring)}
        >
          {body}
        </motion.button>
      );
    }
    return (
      <button type="button" onClick={onClick} onDoubleClick={onDoubleClick} className={className} style={style}>
        {body}
      </button>
    );
  }
  return (
    <div className={className} style={style}>
      {body}
    </div>
  );
}
