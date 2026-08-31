import { motion } from "framer-motion";
import { cn } from "../cn";
import { withReduceMotion, standardSpring } from "../motion/springPresets";
import { useReduceMotion } from "../motion/useReduceMotion";
import { radius, spacing } from "../tokens";

type Variant = "primary" | "secondary" | "ghost" | "danger";

const variants: Record<Variant, string> = {
  primary:
    "bg-[var(--color-primary)] text-white shadow-[0_1px_3px_rgba(99,102,241,0.4)] hover:brightness-[1.08] active:brightness-95",
  secondary:
    "bg-[var(--color-surface-elevated)] text-[var(--color-text-main)] border border-[var(--color-chrome-stroke)] shadow-[var(--shadow-pill)] hover:bg-[var(--color-row-hover)] hover:border-[var(--color-text-light)]",
  ghost:
    "bg-transparent text-[var(--color-text-main)] hover:bg-[var(--color-row-hover)]",
  danger:
    "bg-[var(--color-error)] text-white shadow-sm hover:brightness-[1.06]",
};

export function Button({
  children,
  variant = "primary",
  className,
  reduceMotion,
  onClick,
  disabled,
  type = "button",
  size = "md",
}: {
  children: React.ReactNode;
  variant?: Variant;
  className?: string;
  reduceMotion?: boolean;
  onClick?: () => void;
  disabled?: boolean;
  type?: "button" | "submit" | "reset";
  size?: "sm" | "md";
}) {
  const motionOff = useReduceMotion(reduceMotion);
  return (
    <motion.button
      type={type}
      disabled={disabled}
      onClick={onClick}
      whileHover={motionOff || disabled ? undefined : { scale: 1.02 }}
      whileTap={motionOff || disabled ? undefined : { scale: 0.97 }}
      transition={withReduceMotion(motionOff, standardSpring)}
      className={cn(
        "inline-flex items-center justify-center gap-1.5 font-medium transition-[filter,background-color,color] disabled:pointer-events-none disabled:opacity-45",
        size === "sm" ? "rounded-[8px] px-2.5 py-1 text-chrome" : "rounded-[10px] px-3.5 py-1.5 text-body",
        variants[variant],
        className,
      )}
      style={{ borderRadius: size === "sm" ? radius.sm : radius.md }}
    >
      {children}
    </motion.button>
  );
}

export function FormField({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block text-body">
      <span className="mb-1 block text-meta font-medium">
        {label}
      </span>
      {children}
    </label>
  );
}

export const fieldControlClass =
  "w-full rounded-[10px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-3 py-2 text-body outline-none transition-shadow placeholder:text-[var(--color-text-light)] focus:border-[color-mix(in_srgb,var(--color-primary)_55%,var(--color-chrome-stroke))] focus:ring-2 focus:ring-[color-mix(in_srgb,var(--color-primary)_25%,transparent)]";

export function EmptyState({
  title,
  body,
  action,
}: {
  title: string;
  body?: string;
  action?: React.ReactNode;
}) {
  return (
    <div
      className="flex flex-col items-start justify-center"
      style={{ gap: spacing.sm, padding: `${spacing.lg}px 0` }}
    >
      <h3
        className="text-section-title font-semibold tracking-tight text-[var(--color-text-main)]"
        style={{ fontSize: 15 }}
      >
        {title}
      </h3>
      {body && (
        <p className="max-w-md text-body leading-relaxed text-[var(--color-text-light)]">{body}</p>
      )}
      {action && <div className="pt-1">{action}</div>}
    </div>
  );
}
