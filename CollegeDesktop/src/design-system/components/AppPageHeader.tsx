import { cn } from "../cn";
import { spacing } from "../tokens";

/** Canonical in-content page header — matches AppPageHeader.swift */
export function AppPageHeader({
  title,
  subtitle,
  leading,
  actions,
  className,
  showsTitle = true,
}: {
  title: string;
  subtitle?: string;
  leading?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
  showsTitle?: boolean;
}) {
  return (
    <header
      className={cn(
        "flex w-full items-center gap-3 border-b border-[var(--color-chrome-stroke)]",
        className,
      )}
      style={{
        paddingLeft: spacing.md,
        paddingRight: spacing.md,
        paddingTop: spacing.sm,
        paddingBottom: spacing.sm,
        background:
          "linear-gradient(180deg, color-mix(in srgb, var(--color-content-surface) 92%, var(--color-shell-chrome)), var(--color-content-surface))",
      }}
    >
      <div className="flex min-w-0 flex-1 items-center gap-3">
        {leading}
        {showsTitle && title && (
          <div className="min-w-0">
            <h1
              className="truncate text-[var(--color-text-main)]"
              style={{ font: "var(--type-page-title)", letterSpacing: "-0.022em" }}
            >
              {title}
            </h1>
            {subtitle && (
              <p className="mt-0.5 truncate text-[12px] text-[var(--color-text-light)]">{subtitle}</p>
            )}
          </div>
        )}
      </div>
      {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
    </header>
  );
}
