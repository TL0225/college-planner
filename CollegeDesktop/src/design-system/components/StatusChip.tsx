import { cn } from "../cn";

/** Capsule meta chip — matches PathMetaChip.swift */
export function StatusChip({
  title,
  tint = "var(--color-primary)",
  filled = false,
  className,
}: {
  title: string;
  tint?: string;
  filled?: boolean;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-label",
        className,
      )}
      style={{
        color: filled ? tint : "var(--color-text-light)",
        background: filled
          ? `color-mix(in srgb, ${tint} 14%, transparent)`
          : "var(--color-surface)",
        border: "1px solid var(--color-chrome-stroke)",
      }}
    >
      {title}
    </span>
  );
}

export function LaneDot({ color, size = 8 }: { color: string; size?: number }) {
  return (
    <span
      className="shrink-0 rounded-full"
      style={{
        width: size,
        height: size,
        background: color,
        boxShadow: `0 0 0 2px color-mix(in srgb, ${color} 20%, transparent)`,
      }}
    />
  );
}
