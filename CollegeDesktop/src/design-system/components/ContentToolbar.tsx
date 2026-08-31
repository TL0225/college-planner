import { cn } from "../cn";

export function ContentToolbar({
  left,
  right,
  className,
}: {
  left?: React.ReactNode;
  right?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-center gap-2 border-b border-[var(--color-chrome-stroke)] bg-[color-mix(in_srgb,var(--color-content-surface)_94%,var(--color-shell-chrome))] px-3 py-2 text-[var(--color-text-main)]",
        className,
      )}
    >
      <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2">{left}</div>
      {right ? <div className="flex shrink-0 flex-wrap items-center gap-2">{right}</div> : null}
    </div>
  );
}
