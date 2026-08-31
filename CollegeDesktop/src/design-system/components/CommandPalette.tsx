import { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "framer-motion";
import { Search, GripHorizontal, CornerDownLeft } from "lucide-react";
import { clampToBounds, useShellBounds } from "@/lib/shell/ShellBoundsContext";
import { radius } from "../tokens";
import { withReduceMotion } from "../motion/springPresets";
import { useReduceMotion } from "../motion/useReduceMotion";
import { cn } from "../cn";
import { fieldControlClass } from "./Button";

export type CommandItem = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string;
  group?: string;
  icon?: React.ReactNode;
  run: () => void;
};

const POS_KEY = "ui.commandPalette.pos";
const PALETTE_WIDTH = 640;

/** Three sections only — Navigate, Actions, Library. */
const GROUP_ORDER = ["Navigate", "Actions", "Library"];
const ITEMS_PER_SECTION = 3;

const fadeTransition = { duration: 0.18, ease: "easeOut" as const };

function readStoredPos(): { x: number; y: number } | null {
  try {
    const raw = localStorage.getItem(POS_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { x: number; y: number };
    if (typeof parsed.x === "number" && typeof parsed.y === "number") return parsed;
  } catch {
    /* ignore */
  }
  return null;
}

function groupItems(items: CommandItem[]): Array<{ group: string; items: CommandItem[] }> {
  const byGroup = new Map<string, CommandItem[]>();
  for (const item of items) {
    const g = item.group ?? "Library";
    if (!byGroup.has(g)) byGroup.set(g, []);
    byGroup.get(g)!.push(item);
  }
  return GROUP_ORDER.filter((g) => byGroup.has(g)).map((group) => ({
    group,
    items: byGroup.get(group)!,
  }));
}

export function CommandPalette({
  open,
  onOpenChange,
  items,
  reduceMotion,
  placeholder = "Search anything — pages, actions, courses, files…",
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  items: CommandItem[];
  reduceMotion?: boolean;
  placeholder?: string;
}) {
  const motionOff = useReduceMotion(reduceMotion);
  const bounds = useShellBounds();
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [pos, setPos] = useState({ x: 0, y: 0 });
  const inputRef = useRef<HTMLInputElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const posRef = useRef(readStoredPos() ?? { x: 0, y: 0 });

  const panelWidth = Math.min(PALETTE_WIDTH, Math.max(280, bounds.width - 24));

  const syncPosition = (offset = posRef.current) => {
    const h = panelRef.current?.offsetHeight ?? 480;
    const baseX = bounds.left + (bounds.width - panelWidth) / 2;
    const baseY = bounds.top + Math.round(bounds.height * 0.14);
    setPos(clampToBounds(baseX + offset.x, baseY + offset.y, panelWidth, h, bounds));
  };

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter((item) => {
      const hay = `${item.title} ${item.subtitle ?? ""} ${item.keywords ?? ""} ${item.group ?? ""}`
        .toLowerCase();
      return hay.includes(q);
    });
  }, [items, query]);

  const grouped = useMemo(() => {
    const sections = groupItems(filtered);
    if (!query.trim()) {
      return sections.map((section) => ({
        ...section,
        items: section.items.slice(0, ITEMS_PER_SECTION),
      }));
    }
    return sections;
  }, [filtered, query]);
  const flatOrder = useMemo(() => grouped.flatMap((g) => g.items), [grouped]);

  useEffect(() => {
    if (!open) return;
    setQuery("");
    setActive(0);
    syncPosition();
    const t = window.setTimeout(() => inputRef.current?.focus(), 30);
    return () => window.clearTimeout(t);
  }, [open, bounds, panelWidth]);

  useEffect(() => {
    if (!open) return;
    syncPosition();
  }, [bounds.width, bounds.height, open]);

  useEffect(() => {
    setActive(0);
  }, [query]);

  const runAt = (index: number) => {
    const item = flatOrder[index];
    if (!item) return;
    onOpenChange(false);
    item.run();
  };

  const onDragStart = (e: React.PointerEvent) => {
    e.preventDefault();
    const startX = e.clientX;
    const startY = e.clientY;
    const origX = posRef.current.x;
    const origY = posRef.current.y;

    const onMove = (ev: PointerEvent) => {
      const next = {
        x: origX + (ev.clientX - startX),
        y: origY + (ev.clientY - startY),
      };
      posRef.current = next;
      syncPosition(next);
    };

    const onUp = (ev: PointerEvent) => {
      posRef.current = {
        x: origX + (ev.clientX - startX),
        y: origY + (ev.clientY - startY),
      };
      try {
        localStorage.setItem(POS_KEY, JSON.stringify(posRef.current));
      } catch {
        /* ignore */
      }
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  };

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onOpenChange(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onOpenChange]);

  const listboxId = "command-palette-listbox";
  let runningIndex = -1;
  const transition = withReduceMotion(motionOff, fadeTransition);

  return createPortal(
    <AnimatePresence>
      {open && (
        <>
          <motion.button
            type="button"
            aria-label="Close search"
            className="fixed inset-0 z-[69] cursor-default border-0 bg-black/20 p-0"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={transition}
            onClick={() => onOpenChange(false)}
          />
          <motion.div
            ref={panelRef}
            role="dialog"
            aria-modal="false"
            aria-label="Search"
            className={cn(
              "pointer-events-auto fixed z-[70] flex flex-col overflow-hidden",
              "border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)]",
            )}
            style={{
              left: pos.x,
              top: pos.y,
              width: panelWidth,
              maxHeight: `min(520px, ${Math.max(200, bounds.height - 16)}px)`,
              borderRadius: radius.sheet,
              boxShadow: "var(--shadow-sheet)",
              willChange: "opacity",
            }}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={transition}
              onKeyDown={(e) => {
                if (e.key === "ArrowDown") {
                  e.preventDefault();
                  setActive((i) => Math.min(i + 1, Math.max(flatOrder.length - 1, 0)));
                } else if (e.key === "ArrowUp") {
                  e.preventDefault();
                  setActive((i) => Math.max(i - 1, 0));
                } else if (e.key === "Enter") {
                  e.preventDefault();
                  runAt(active);
                }
              }}
            >
              <div className="flex items-center gap-2.5 border-b border-[var(--color-chrome-stroke)] px-4 py-3.5">
                <Search size={18} className="shrink-0 text-[var(--color-text-light)]" />
                <input
                  ref={inputRef}
                  role="combobox"
                  aria-expanded="true"
                  aria-controls={listboxId}
                  aria-activedescendant={
                    flatOrder[active] ? `cmd-${flatOrder[active].id}` : undefined
                  }
                  className={cn(
                    fieldControlClass,
                    "border-0 bg-transparent px-0 py-1 text-[16px] shadow-none focus:ring-0",
                  )}
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={placeholder}
                  aria-label="Search everything"
                />
                <kbd className="rounded-[6px] border border-[var(--color-chrome-stroke)] px-1.5 py-0.5 text-caption">
                  esc
                </kbd>
                <button
                  type="button"
                  onPointerDown={onDragStart}
                  className="ml-1 shrink-0 cursor-grab touch-none rounded-[6px] p-1 text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)] active:cursor-grabbing"
                  aria-label="Drag to move search"
                  title="Drag to move"
                >
                  <GripHorizontal size={16} />
                </button>
              </div>
              <ul
                id={listboxId}
                className="max-h-[min(420px,55vh)] overflow-y-auto p-2"
                role="listbox"
              >
                {flatOrder.length === 0 ? (
                  <li className="px-3 py-8 text-center text-caption">No matches</li>
                ) : (
                  grouped.map((section) => (
                    <li key={section.group} role="presentation">
                      <div className="sticky top-0 z-[1] bg-[var(--color-content-surface)] px-2.5 pb-1 pt-2.5 text-caption font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                        {section.group}
                      </div>
                      <ul role="group" aria-label={section.group}>
                        {section.items.map((item) => {
                          runningIndex += 1;
                          const index = runningIndex;
                          const isActive = index === active;
                          return (
                            <li
                              key={item.id}
                              id={`cmd-${item.id}`}
                              role="option"
                              aria-selected={isActive}
                            >
                              <button
                                type="button"
                                className={cn(
                                  "flex w-full items-center gap-3 rounded-[10px] px-3 py-2.5 text-left",
                                  isActive
                                    ? "bg-[var(--color-shell-selection)]"
                                    : "hover:bg-[var(--color-row-hover)]",
                                )}
                                onMouseEnter={() => setActive(index)}
                                onClick={() => runAt(index)}
                              >
                                <span
                                  className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[8px] text-[var(--registrar-accent)]"
                                  style={{
                                    background:
                                      "color-mix(in srgb, var(--registrar-accent) 10%, var(--color-surface))",
                                    border: "1px solid var(--color-chrome-stroke)",
                                  }}
                                  aria-hidden
                                >
                                  {item.icon ?? <Search size={14} />}
                                </span>
                                <span className="min-w-0 flex-1">
                                  <span className="block truncate text-body font-medium">
                                    {item.title}
                                  </span>
                                  {item.subtitle && (
                                    <span className="block truncate text-caption text-[var(--color-text-light)]">
                                      {item.subtitle}
                                    </span>
                                  )}
                                </span>
                                {isActive && (
                                  <CornerDownLeft
                                    size={14}
                                    className="shrink-0 text-[var(--color-text-light)]"
                                  />
                                )}
                              </button>
                            </li>
                          );
                        })}
                      </ul>
                    </li>
                  ))
                )}
              </ul>
              <div className="flex items-center gap-3 border-t border-[var(--color-chrome-stroke)] px-4 py-2 text-caption text-[var(--color-text-light)]">
                <span className="inline-flex items-center gap-1">
                  <kbd className="rounded-[4px] border border-[var(--color-chrome-stroke)] px-1">↑↓</kbd>
                  navigate
                </span>
                <span className="inline-flex items-center gap-1">
                  <kbd className="rounded-[4px] border border-[var(--color-chrome-stroke)] px-1">↵</kbd>
                  open
                </span>
                <span className="ml-auto">{flatOrder.length} results</span>
              </div>
            </motion.div>
        </>
      )}
    </AnimatePresence>,
    document.body,
  );
}
