import { cn } from "../cn";
import { spacing } from "../tokens";

/** In-content page header — registrar typography, flat ruled chrome. */
export function AppPageHeader({
  title,
  subtitle,
  eyebrow,
  leading,
  center,
  actions,
  className,
  showsTitle = true,
}: {
  title: string;
  subtitle?: string;
  eyebrow?: string;
  leading?: React.ReactNode;
  center?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
  showsTitle?: boolean;
}) {
  return (
    <header
      className={cn(
        "grid w-full items-center gap-3 border-b border-[var(--registrar-rule)] bg-[var(--color-shell-canvas)]",
        center ? "grid-cols-[1fr_auto_1fr]" : "grid-cols-[1fr_auto]",
        className,
      )}
      style={{
        paddingLeft: spacing.lg,
        paddingRight: spacing.lg,
        paddingTop: spacing.md,
        paddingBottom: spacing.md,
      }}
    >
      <div className="flex min-w-0 items-center gap-3">
        {leading}
        {showsTitle && title && (
          <div className="min-w-0">
            {eyebrow && (
              <p
                className="text-[12px] font-semibold uppercase tracking-[0.08em]"
                style={{ fontFamily: "var(--font-mono)", color: "var(--registrar-accent)" }}
              >
                {eyebrow}
              </p>
            )}
            <h1
              className="truncate"
              style={{
                fontFamily: "var(--font-display)",
                fontWeight: 600,
                fontSize: eyebrow ? 28 : 30,
                lineHeight: 1.15,
                color: "var(--registrar-ink)",
              }}
            >
              {title}
            </h1>
            {subtitle && (
              <p
                className="mt-0.5 truncate text-meta"
                style={{ fontFamily: "var(--font-mono)", color: "var(--color-text-light)" }}
              >
                {subtitle}
              </p>
            )}
          </div>
        )}
      </div>
      {center ? <div className="flex justify-center">{center}</div> : null}
      {actions ? (
        <div className={cn("flex items-center gap-2", center && "justify-self-end")}>
          {actions}
        </div>
      ) : center ? (
        <div />
      ) : null}
    </header>
  );
}
