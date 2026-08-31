import { motion, LayoutGroup } from "framer-motion";
import { useId } from "react";
import { cn } from "../cn";
import { pillSpring, standardSpring, withReduceMotion } from "../motion/springPresets";
import { useReduceMotion } from "../motion/useReduceMotion";

export function MetricTile({
  label,
  value,
  accent,
  hint,
  icon,
  className,
}: {
  label: string;
  value: string | number;
  accent?: string;
  hint?: string;
  icon?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn("w-full", className)}
      style={{
        padding: "14px 16px",
        borderRadius: "var(--registrar-radius)",
        background: "var(--registrar-surface)",
        border: "1px solid var(--registrar-rule)",
      }}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11.5px] text-[var(--color-text-light)]">{label}</span>
        {icon && <span className="text-[var(--color-text-light)] opacity-75">{icon}</span>}
      </div>
      <p
        className="mt-1 text-[22px] tabular-nums"
        style={{
          fontFamily: "var(--font-mono)",
          fontWeight: 500,
          color: accent ?? "var(--registrar-ink)",
        }}
      >
        {value}
      </p>
      {hint && (
        <p className="mt-0.5 truncate text-caption text-[var(--color-text-light)]">{hint}</p>
      )}
    </div>
  );
}

export function SegmentedPills<T extends string>({
  options,
  value,
  onChange,
  reduceMotion,
}: {
  options: Array<{ id: T; label: string }>;
  value: T;
  onChange: (id: T) => void;
  reduceMotion?: boolean;
}) {
  const groupId = useId();
  const motionOff = useReduceMotion(reduceMotion);
  return (
    <LayoutGroup id={groupId}>
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
                "relative rounded-full px-2.5 py-1 text-label transition-colors",
                selected
                  ? "font-semibold text-[var(--color-text-main)]"
                  : "font-medium text-[var(--color-text-light)] hover:text-[var(--color-text-main)]",
              )}
            >
              {selected && (
                <motion.span
                  layoutId={`${groupId}-selection`}
                  className="absolute inset-0 bg-[var(--color-shell-selection)] shadow-[var(--shadow-pill)]"
                  style={{ borderRadius: 999 }}
                  transition={withReduceMotion(motionOff, pillSpring)}
                />
              )}
              <span className="relative z-10">{opt.label}</span>
            </button>
          );
        })}
      </div>
    </LayoutGroup>
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
  reduceMotion,
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
  const motionOff = useReduceMotion(reduceMotion);
  const className = cn(
    "flex w-full items-center gap-3 px-2 py-2.5 text-left transition-colors",
    onClick && interactive && "origin-center",
    onClick && "hover:bg-[var(--color-row-hover)]",
    selected && "bg-[color-mix(in_srgb,var(--registrar-accent)_10%,transparent)]",
  );
  const style = {
    borderBottom: "1px solid var(--registrar-rule)",
    borderRadius: 0,
  };
  const body = (
    <>
      {leading}
      <div className="min-w-0 flex-1">
        <div
          className="truncate text-body font-medium tracking-[-0.01em]"
          style={{ color: "var(--registrar-ink)" }}
        >
          {title}
        </div>
        {subtitle != null && subtitle !== "" && (
          <div className="mt-0.5 text-caption">{subtitle}</div>
        )}
      </div>
      {trailing && <div className="shrink-0 text-caption">{trailing}</div>}
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
          whileHover={motionOff ? undefined : { scale: 1.01 }}
          whileTap={motionOff ? undefined : { scale: 0.97 }}
          transition={withReduceMotion(motionOff, standardSpring)}
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
