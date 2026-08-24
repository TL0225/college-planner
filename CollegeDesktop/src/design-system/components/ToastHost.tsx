import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { cn } from "../cn";
import { radius } from "../tokens";
import { withReduceMotion, standardSpring } from "../motion/springPresets";
import { subscribeToasts, type ToastPayload } from "@/lib/toast";

export function ToastHost({ reduceMotion = false }: { reduceMotion?: boolean }) {
  const [toasts, setToasts] = useState<ToastPayload[]>([]);

  useEffect(() => {
    return subscribeToasts((toast) => {
      setToasts((prev) => [...prev.slice(-3), toast]);
      window.setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== toast.id));
      }, 3200);
    });
  }, []);

  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-[80] flex w-[min(360px,92vw)] flex-col gap-2">
      <AnimatePresence>
        {toasts.map((t) => (
          <motion.div
            key={t.id}
            initial={{ opacity: 0, y: 8, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 6, scale: 0.98 }}
            transition={withReduceMotion(reduceMotion, standardSpring)}
            className={cn(
              "pointer-events-auto border px-3.5 py-2.5 text-[13px] shadow-[var(--shadow-sheet)]",
              t.kind === "error"
                ? "border-[color-mix(in_srgb,var(--color-error)_35%,var(--color-chrome-stroke))] bg-[var(--color-content-surface)] text-[var(--color-error)]"
                : t.kind === "success"
                  ? "border-[color-mix(in_srgb,var(--color-success)_35%,var(--color-chrome-stroke))] bg-[var(--color-content-surface)] text-[var(--color-text-main)]"
                  : "border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] text-[var(--color-text-main)]",
            )}
            style={{ borderRadius: radius.md }}
            role="status"
          >
            {t.message}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}
