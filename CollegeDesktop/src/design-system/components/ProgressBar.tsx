import { cn } from "../cn";

/** Thin filled track — degree audit / credit progress */
export function ProgressBar({
  value,
  tint = "var(--color-primary)",
  className,
  height = 6,
}: {
  /** 0–1 */
  value: number;
  tint?: string;
  className?: string;
  height?: number;
}) {
  const clamped = Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0));
  return (
    <div
      className={cn("w-full overflow-hidden", className)}
      style={{
        height,
        borderRadius: 999,
        background: "var(--color-shell-chrome)",
        border: "1px solid var(--color-chrome-stroke)",
      }}
      role="progressbar"
      aria-valuenow={Math.round(clamped * 100)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div
        className="h-full transition-[width] duration-300 ease-out"
        style={{
          width: `${clamped * 100}%`,
          borderRadius: 999,
          background: `linear-gradient(90deg, ${tint}, color-mix(in srgb, ${tint} 70%, white))`,
          boxShadow: `0 0 0 1px color-mix(in srgb, ${tint} 25%, transparent)`,
        }}
      />
    </div>
  );
}
