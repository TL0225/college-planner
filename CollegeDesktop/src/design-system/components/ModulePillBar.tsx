import { motion } from "framer-motion";
import { cn } from "../cn";
import { pillSpring, withReduceMotion } from "../motion/springPresets";
import { shell } from "../tokens";

export type ModulePillItem = {
  id: string;
  title: string;
  icon: React.ReactNode;
};

export function ModulePillBar({
  items,
  selection,
  onSelect,
  onReselect,
  reduceMotion = false,
  className,
}: {
  items: ModulePillItem[];
  selection: string;
  onSelect: (id: string) => void;
  onReselect?: (id: string) => void;
  reduceMotion?: boolean;
  className?: string;
}) {
  return (
    <div
      className={cn("flex w-full items-center gap-2", className)}
      style={{ height: shell.pillBarHeight }}
      data-tauri-drag-region
    >
      {items.map((item) => {
        const selected = selection === item.id;
        return (
          <motion.button
            key={item.id}
            type="button"
            whileTap={reduceMotion ? undefined : { scale: 0.96 }}
            transition={withReduceMotion(reduceMotion, pillSpring)}
            onClick={() => {
              if (selected) onReselect?.(item.id);
              else onSelect(item.id);
            }}
            className={cn(
              "relative inline-flex items-center gap-1.5 px-3 py-1.5 transition-colors",
              selected
                ? "font-semibold text-[var(--color-text-main)]"
                : "font-medium text-[var(--color-text-light)] hover:text-[var(--color-text-main)]",
            )}
            style={{ font: "var(--type-chrome)", borderRadius: 999 }}
            aria-pressed={selected}
          >
            {selected && (
              <motion.span
                layoutId="modulePillSelection"
                className="absolute inset-0 bg-[var(--color-shell-selection)] shadow-[var(--shadow-pill)]"
                style={{ borderRadius: 999 }}
                transition={withReduceMotion(reduceMotion, pillSpring)}
              />
            )}
            <span className="relative z-10 inline-flex items-center gap-1.5">
              <span className={cn("opacity-75", selected && "opacity-90")}>{item.icon}</span>
              {item.title}
            </span>
          </motion.button>
        );
      })}
      <div className="min-w-0 flex-1" data-tauri-drag-region />
    </div>
  );
}
