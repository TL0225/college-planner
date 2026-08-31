import { cn } from "../cn";
import { spacing } from "../tokens";

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
        borderRadius: "var(--registrar-radius)",
        background: "var(--registrar-surface)",
        border: "1px solid var(--registrar-rule)",
      }}
    >
      {title && (
        <h2
          className="mb-3 flex items-center gap-2"
          style={{
            fontFamily: "var(--font-display)",
            fontWeight: 600,
            fontSize: 17,
            color: "var(--registrar-ink)",
          }}
        >
          {icon && <span style={{ color: "var(--registrar-accent)" }}>{icon}</span>}
          {title}
        </h2>
      )}
      {children}
    </section>
  );
}
