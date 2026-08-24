import { useEffect, useMemo, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { motion, AnimatePresence } from "framer-motion";
import { Search } from "lucide-react";
import { radius } from "../tokens";
import { sheetTransition, withReduceMotion } from "../motion/springPresets";
import { cn } from "../cn";
import { fieldControlClass } from "./Button";

export type CommandItem = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string;
  group?: string;
  run: () => void;
};

export function CommandPalette({
  open,
  onOpenChange,
  items,
  reduceMotion = false,
  placeholder = "Jump to…",
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  items: CommandItem[];
  reduceMotion?: boolean;
  placeholder?: string;
}) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter((item) => {
      const hay = `${item.title} ${item.subtitle ?? ""} ${item.keywords ?? ""} ${item.group ?? ""}`
        .toLowerCase();
      return hay.includes(q);
    });
  }, [items, query]);

  useEffect(() => {
    if (!open) return;
    setQuery("");
    setActive(0);
    const t = window.setTimeout(() => inputRef.current?.focus(), 30);
    return () => window.clearTimeout(t);
  }, [open]);

  useEffect(() => {
    setActive(0);
  }, [query]);

  const runAt = (index: number) => {
    const item = filtered[index];
    if (!item) return;
    onOpenChange(false);
    item.run();
  };

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <AnimatePresence>
        {open && (
          <Dialog.Portal forceMount>
            <Dialog.Overlay asChild>
              <motion.div
                className="fixed inset-0 z-[60] bg-black/30"
                style={{ backdropFilter: "blur(6px)", WebkitBackdropFilter: "blur(6px)" }}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={withReduceMotion(reduceMotion, sheetTransition)}
              />
            </Dialog.Overlay>
            <Dialog.Content asChild>
              <motion.div
                className={cn(
                  "fixed left-1/2 top-[18%] z-[70] flex w-[min(520px,92vw)] -translate-x-1/2 flex-col overflow-hidden",
                  "border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)]",
                )}
                style={{
                  borderRadius: radius.sheet,
                  boxShadow: "var(--shadow-sheet)",
                }}
                initial={{ opacity: 0, scale: 0.97, y: -8 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.98, y: -4 }}
                transition={withReduceMotion(reduceMotion, sheetTransition)}
                onKeyDown={(e) => {
                  if (e.key === "ArrowDown") {
                    e.preventDefault();
                    setActive((i) => Math.min(i + 1, Math.max(filtered.length - 1, 0)));
                  } else if (e.key === "ArrowUp") {
                    e.preventDefault();
                    setActive((i) => Math.max(i - 1, 0));
                  } else if (e.key === "Enter") {
                    e.preventDefault();
                    runAt(active);
                  }
                }}
              >
                <Dialog.Title className="sr-only">Command palette</Dialog.Title>
                <div className="flex items-center gap-2 border-b border-[var(--color-chrome-stroke)] px-3 py-2.5">
                  <Search size={15} className="shrink-0 text-[var(--color-text-light)]" />
                  <input
                    ref={inputRef}
                    className={cn(fieldControlClass, "border-0 bg-transparent px-0 py-1 shadow-none focus:ring-0")}
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder={placeholder}
                    aria-label="Filter commands"
                  />
                  <kbd className="rounded-[6px] border border-[var(--color-chrome-stroke)] px-1.5 py-0.5 text-[10px] text-[var(--color-text-light)]">
                    esc
                  </kbd>
                </div>
                <ul className="max-h-[min(360px,50vh)] overflow-y-auto p-1.5" role="listbox">
                  {filtered.length === 0 ? (
                    <li className="px-3 py-6 text-center text-[12px] text-[var(--color-text-light)]">
                      No matches
                    </li>
                  ) : (
                    filtered.map((item, index) => (
                      <li key={item.id} role="option" aria-selected={index === active}>
                        <button
                          type="button"
                          className={cn(
                            "flex w-full flex-col items-start rounded-[8px] px-3 py-2 text-left",
                            index === active
                              ? "bg-[var(--color-shell-selection)]"
                              : "hover:bg-[var(--color-row-hover)]",
                          )}
                          onMouseEnter={() => setActive(index)}
                          onClick={() => runAt(index)}
                        >
                          <span className="text-[13px] font-medium text-[var(--color-text-main)]">
                            {item.title}
                          </span>
                          {(item.subtitle || item.group) && (
                            <span className="text-[11px] text-[var(--color-text-light)]">
                              {[item.group, item.subtitle].filter(Boolean).join(" · ")}
                            </span>
                          )}
                        </button>
                      </li>
                    ))
                  )}
                </ul>
              </motion.div>
            </Dialog.Content>
          </Dialog.Portal>
        )}
      </AnimatePresence>
    </Dialog.Root>
  );
}
