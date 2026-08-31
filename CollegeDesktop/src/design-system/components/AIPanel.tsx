import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Sparkles, Minus } from "lucide-react";
import { cn } from "../cn";
import { withReduceMotion } from "../motion/springPresets";
import { useMotion } from "../motion/MotionProvider";

const WIDTH_KEY = "ui.aiPanel.width";
const MIN_WIDTH = 340;
const MAX_WIDTH = 720;
const DEFAULT_WIDTH = 420;

function readStoredWidth(): number {
  try {
    const raw = Number(localStorage.getItem(WIDTH_KEY));
    if (Number.isFinite(raw) && raw >= MIN_WIDTH && raw <= MAX_WIDTH) return raw;
  } catch {
    /* ignore */
  }
  return DEFAULT_WIDTH;
}

const panelSpring = { type: "spring" as const, stiffness: 420, damping: 38, mass: 0.9 };

/**
 * In-flow assistant sidebar (Claude/ChatGPT style): pushes page content
 * instead of overlaying it, and supports drag-to-resize. "Minimize" pops
 * the assistant out into its own small OS window instead of collapsing in place.
 */
export function AIPanel({
  open,
  onOpenChange,
  children,
  triggerRef,
  onPopOut,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  children: React.ReactNode;
  triggerRef?: React.RefObject<HTMLElement | null>;
  /** Called when the user clicks minimize — should close this panel and open a standalone window. */
  onPopOut?: () => void;
}) {
  const { reduceMotion } = useMotion();
  const [width, setWidth] = useState(readStoredWidth);
  const draggingRef = useRef<{ startX: number; startWidth: number } | null>(null);

  useEffect(() => {
    try {
      localStorage.setItem(WIDTH_KEY, String(width));
    } catch {
      /* ignore */
    }
  }, [width]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onOpenChange(false);
        triggerRef?.current?.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onOpenChange, triggerRef]);

  const onResizeStart = (e: React.PointerEvent) => {
    e.preventDefault();
    draggingRef.current = { startX: e.clientX, startWidth: width };
    const onMove = (ev: PointerEvent) => {
      const drag = draggingRef.current;
      if (!drag) return;
      const delta = drag.startX - ev.clientX;
      setWidth(Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, drag.startWidth + delta)));
    };
    const onUp = () => {
      draggingRef.current = null;
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  };

  const effectiveWidth = open ? width : 0;

  return (
    <motion.div
      className="relative flex h-full shrink-0 overflow-hidden"
      animate={{ width: effectiveWidth }}
      transition={withReduceMotion(reduceMotion, panelSpring)}
      style={{ willChange: "width" }}
    >
      <AnimatePresence>
        {open && (
          <motion.div
            role="complementary"
            aria-label="Assistant"
            className={cn(
              "absolute inset-y-0 right-0 flex flex-col",
              "border-l border-[var(--registrar-rule)]",
            )}
            style={{ width, background: "var(--registrar-assistant-bg)", color: "#f0ede6" }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={withReduceMotion(reduceMotion, { duration: 0.15 })}
          >
            <div
              className="absolute inset-y-0 left-0 z-10 w-1.5 cursor-col-resize hover:bg-[var(--color-primary)]/15"
              onPointerDown={onResizeStart}
              role="separator"
              aria-orientation="vertical"
              aria-label="Resize assistant panel"
            />

            <div className="flex shrink-0 items-center justify-between border-b border-[var(--registrar-rule)] px-3 py-2">
              <div
                className="flex items-center gap-2"
                style={{ fontFamily: "var(--font-display)", fontWeight: 600, color: "#f0ede6" }}
              >
                <Sparkles size={16} style={{ color: "var(--registrar-accent)" }} />
                Assistant
              </div>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  className="rounded-[8px] p-1.5 hover:bg-[var(--color-row-hover)]"
                  aria-label="Minimize to a separate window"
                  title="Minimize to window"
                  onClick={() => onPopOut?.()}
                >
                  <Minus size={16} />
                </button>
                <button
                  type="button"
                  className="rounded-[8px] p-1.5 hover:bg-[var(--color-row-hover)]"
                  aria-label="Close assistant"
                  title="Close"
                  onClick={() => {
                    onOpenChange(false);
                    triggerRef?.current?.focus();
                  }}
                >
                  <X size={16} />
                </button>
              </div>
            </div>
            <div className="min-h-0 flex-1 overflow-hidden">{children}</div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

export function AIFloatingButton({
  onClick,
  buttonRef,
  hidden,
}: {
  onClick: () => void;
  buttonRef?: React.RefObject<HTMLButtonElement | null>;
  hidden?: boolean;
}) {
  if (hidden) return null;
  return (
    <button
      ref={buttonRef}
      type="button"
      onClick={onClick}
      className={cn(
        "fixed bottom-5 right-5 z-40 flex h-11 w-11 items-center justify-center rounded-full",
        "bg-[var(--color-primary)] text-white shadow-[var(--shadow-elevated)]",
        "hover:brightness-110",
      )}
      aria-label="Ask assistant"
      title="Ask assistant"
    >
      <Sparkles size={20} />
    </button>
  );
}
