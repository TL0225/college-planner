import { cn } from "../cn";

/** Flat content stage — matches SuperAppContentSurface.swift */
export function SuperAppContentSurface({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-[var(--color-content-surface)]",
        className,
      )}
      style={{
        boxShadow: "inset 1px 0 0 color-mix(in srgb, white 30%, transparent)",
      }}
    >
      {children}
    </div>
  );
}
