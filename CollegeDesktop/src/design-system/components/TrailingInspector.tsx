import { useState } from "react";
import { cn } from "../cn";
import { inspectorMetrics } from "../tokens";

export function TrailingInspector({
  open,
  children,
  main,
  className,
}: {
  open: boolean;
  children: React.ReactNode;
  main: React.ReactNode;
  className?: string;
}) {
  const [width, setWidth] = useState<number>(inspectorMetrics.widthDefault);

  return (
    <div className={cn("flex h-full min-h-0 w-full", className)}>
      <div className="min-w-0 flex-1 overflow-auto">{main}</div>
      {open && (
        <aside
          className="shrink-0 overflow-auto border-l border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)]"
          style={{
            width: Math.min(
              inspectorMetrics.widthMax,
              Math.max(inspectorMetrics.widthMin, width),
            ),
          }}
          onMouseDown={(e) => {
            if ((e.target as HTMLElement).dataset.resize !== "true") return;
            const startX = e.clientX;
            const startW = width;
            const onMove = (ev: MouseEvent) => {
              setWidth(startW - (ev.clientX - startX));
            };
            const onUp = () => {
              window.removeEventListener("mousemove", onMove);
              window.removeEventListener("mouseup", onUp);
            };
            window.addEventListener("mousemove", onMove);
            window.addEventListener("mouseup", onUp);
          }}
        >
          <div
            data-resize="true"
            className="absolute h-full w-1 cursor-col-resize"
            style={{ marginLeft: -2 }}
          />
          {children}
        </aside>
      )}
    </div>
  );
}
