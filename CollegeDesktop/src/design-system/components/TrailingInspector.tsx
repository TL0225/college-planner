import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "../cn";
import { inspectorMetrics } from "../tokens";
import { sidebarSpring, withReduceMotion } from "../motion/springPresets";
import { useMotion } from "../motion/MotionProvider";

export function TrailingInspector({
  open,
  children,
  main,
  className,
  storageKey,
}: {
  open: boolean;
  children: React.ReactNode;
  main: React.ReactNode;
  className?: string;
  /** e.g. school.inspectorWidth — persisted via localStorage until IPC hook lands */
  storageKey?: string;
}) {
  const { reduceMotion } = useMotion();
  const [width, setWidth] = useState<number>(() => {
    if (storageKey && typeof localStorage !== "undefined") {
      const raw = localStorage.getItem(storageKey);
      const n = raw ? parseInt(raw, 10) : NaN;
      if (!Number.isNaN(n)) return n;
    }
    return inspectorMetrics.widthDefault;
  });

  const persistWidth = (w: number) => {
    if (storageKey) localStorage.setItem(storageKey, String(w));
  };

  return (
    <div className={cn("relative flex h-full min-h-0 w-full", className)}>
      <div className="min-w-0 flex-1 overflow-auto">{main}</div>
      <AnimatePresence>
        {open && (
          <motion.aside
            initial={reduceMotion ? false : { width: 0, opacity: 0 }}
            animate={{
              width: Math.min(inspectorMetrics.widthMax, Math.max(inspectorMetrics.widthMin, width)),
              opacity: 1,
            }}
            exit={reduceMotion ? undefined : { width: 0, opacity: 0 }}
            transition={withReduceMotion(reduceMotion, sidebarSpring)}
            className="relative shrink-0 overflow-auto border-l border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)]"
            aria-expanded={open}
          >
            <div
              data-resize="true"
              role="separator"
              aria-orientation="vertical"
              aria-label="Resize inspector"
              className="absolute bottom-0 left-0 top-0 w-1 cursor-col-resize"
              onMouseDown={(e) => {
                e.preventDefault();
                const startX = e.clientX;
                const startW = width;
                let latestW = startW;
                const onMove = (ev: MouseEvent) => {
                  latestW = Math.min(
                    inspectorMetrics.widthMax,
                    Math.max(inspectorMetrics.widthMin, startW - (ev.clientX - startX)),
                  );
                  setWidth(latestW);
                };
                const onUp = () => {
                  window.removeEventListener("mousemove", onMove);
                  window.removeEventListener("mouseup", onUp);
                  persistWidth(latestW);
                };
                window.addEventListener("mousemove", onMove);
                window.addEventListener("mouseup", onUp);
              }}
            />
            {children}
          </motion.aside>
        )}
      </AnimatePresence>
    </div>
  );
}
