import { forwardRef } from "react";
import { cn } from "../cn";

/** Flat content stage — matches SuperAppContentSurface.swift */
export const SuperAppContentSurface = forwardRef<
  HTMLDivElement,
  { children: React.ReactNode; className?: string }
>(function SuperAppContentSurface({ children, className }, ref) {
  return (
    <div
      ref={ref}
      className={cn(
        "content-stage flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-[var(--color-shell-canvas)]",
        className,
      )}
    >
      {children}
    </div>
  );
});
