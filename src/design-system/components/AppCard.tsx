import { cn } from "../cn";
import { radius, spacing } from "../tokens";

export function AppCard({
  children,
  className,
  title,
  icon,
}: {
  children: React.ReactNode;
  className?: string;
  title?: string;
  icon?: React.ReactNode;
}) {
  return (
    <section
      className={cn("frame-card w-full", className)}
      style={{
        padding: spacing.md,
        borderRadius: radius.lg,
        background: "var(--color-surface)",
        border: "1px solid var(--color-chrome-stroke)",
        boxShadow: "inset 0 1px 0 color-mix(in srgb, white 40%, transparent)",
      }}
    >
      {title && (
        <h2
          className="mb-2 flex items-center gap-2 text-[var(--color-text-main)]"
          style={{ marginBottom: spacing.sm, font: "var(--type-section-title)" }}
        >
          {icon && <span className="text-[var(--color-primary)]">{icon}</span>}
          {title}
        </h2>
      )}
      {children}
    </section>
  );
}
