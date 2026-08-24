import * as Dialog from "@radix-ui/react-dialog";
import { motion, AnimatePresence } from "framer-motion";
import { X } from "lucide-react";
import { sheetMetrics, radius } from "../tokens";
import { sheetTransition, withReduceMotion } from "../motion/springPresets";
import { cn } from "../cn";

export function ModalSheet({
  open,
  onOpenChange,
  title,
  children,
  width = sheetMetrics.widthDefault,
  reduceMotion = false,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  children: React.ReactNode;
  width?: number;
  reduceMotion?: boolean;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <AnimatePresence>
        {open && (
          <Dialog.Portal forceMount>
            <Dialog.Overlay asChild>
              <motion.div
                className="fixed inset-0 z-40 bg-black/25"
                style={{ backdropFilter: "blur(10px)", WebkitBackdropFilter: "blur(10px)" }}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={withReduceMotion(reduceMotion, sheetTransition)}
              />
            </Dialog.Overlay>
            <Dialog.Content asChild>
              <motion.div
                className={cn(
                  "fixed left-1/2 top-[46%] z-50 flex max-h-[82vh] -translate-x-1/2 -translate-y-1/2 flex-col overflow-hidden",
                  "border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)]",
                )}
                style={{
                  width,
                  minHeight: sheetMetrics.minHeight,
                  borderRadius: radius.sheet,
                  boxShadow: "var(--shadow-sheet)",
                }}
                initial={{ opacity: 0, scale: 0.97, y: 10 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.98, y: 6 }}
                transition={withReduceMotion(reduceMotion, sheetTransition)}
              >
                <div className="flex items-center justify-between border-b border-[var(--color-chrome-stroke)] px-5 py-3">
                  <Dialog.Title className="text-[15px] font-semibold text-[var(--color-text-main)]">
                    {title}
                  </Dialog.Title>
                  <Dialog.Close
                    className="inline-flex h-7 w-7 items-center justify-center rounded-full text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)]"
                    aria-label="Close"
                  >
                    <X size={14} />
                  </Dialog.Close>
                </div>
                <div className="min-h-0 flex-1 overflow-y-auto p-5">{children}</div>
              </motion.div>
            </Dialog.Content>
          </Dialog.Portal>
        )}
      </AnimatePresence>
    </Dialog.Root>
  );
}
