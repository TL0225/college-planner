import { motion } from "framer-motion";
import { cn } from "../cn";
import { sidebarSpring, withReduceMotion } from "../motion/springPresets";
import { useReduceMotion } from "../motion/useReduceMotion";
import { radius, shell } from "../tokens";

export type SidebarItem = {
  id: string;
  title: string;
  icon?: React.ReactNode;
  badge?: string | number;
  subtitle?: string;
  indent?: boolean;
  /** Optional group label rendered above the item when it changes. */
  section?: string;
};

export function AppSidebar({
  items,
  selection,
  onSelect,
  footer,
  sectionTitle,
  collapsed = false,
  reduceMotion,
}: {
  items: SidebarItem[];
  selection: string;
  onSelect: (id: string) => void;
  footer?: React.ReactNode;
  sectionTitle?: string;
  collapsed?: boolean;
  reduceMotion?: boolean;
}) {
  const motionOff = useReduceMotion(reduceMotion);
  return (
    <aside className="flex h-full w-full flex-col bg-[var(--color-shell-chrome)]">
      <div
        className="min-h-0 flex-1 overflow-y-auto"
        style={{
          paddingTop: 6,
          paddingLeft: shell.sidebarContentHorizontalPadding,
          paddingRight: shell.sidebarContentHorizontalPadding,
        }}
      >
        <div
          className="flex flex-col"
          style={{
            gap: 2,
            padding: "8px 6px",
            borderRadius: radius.md,
            background: "var(--color-sidebar-section)",
            border: "1px solid var(--color-chrome-stroke)",
            boxShadow: "inset 0 1px 0 var(--color-card-highlight)",
          }}
        >
          {sectionTitle && !collapsed && (
            <div className="px-2.5 pb-1.5 pt-0.5 text-label font-semibold uppercase tracking-[0.07em]">
              {sectionTitle}
            </div>
          )}
          {items.map((item, index) => {
            const selected = selection === item.id;
            const prevSection = index > 0 ? items[index - 1]?.section : undefined;
            const showSection =
              !collapsed && item.section && item.section !== prevSection;
            return (
              <div key={item.id}>
                {showSection && (
                  <div className="px-2.5 pb-1 pt-2 text-caption font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                    {item.section}
                  </div>
                )}
              <motion.button
                type="button"
                onClick={() => onSelect(item.id)}
                title={item.title}
                whileTap={motionOff ? undefined : { scale: 0.98 }}
                transition={withReduceMotion(motionOff, sidebarSpring)}
                className={cn(
                  "relative flex w-full items-center gap-2 text-left",
                  selected
                    ? "font-semibold text-[var(--registrar-ink)]"
                    : "font-medium text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)] hover:text-[var(--color-text-main)]",
                )}
                style={{
                  minHeight: "var(--shell-sidebar-row-height, 28px)",
                  borderRadius: radius.sidebarRow,
                  padding: "5px 10px",
                  paddingLeft: item.indent ? 22 : 10,
                  fontSize: item.indent ? 12 : 12.5,
                }}
                aria-current={selected ? "page" : undefined}
              >
                {selected && (
                  <motion.span
                    layoutId="sidebarSelection"
                    className="absolute inset-0 shadow-[var(--shadow-pill)]"
                    style={{
                      borderRadius: radius.sidebarRow,
                      background: "color-mix(in srgb, var(--registrar-accent) 14%, transparent)",
                    }}
                    transition={withReduceMotion(motionOff, sidebarSpring)}
                  />
                )}
                {item.icon && (
                  <span className="relative z-10 shrink-0 opacity-80">{item.icon}</span>
                )}
                {!collapsed && (
                  <span className="relative z-10 min-w-0 flex-1 truncate">
                    {item.title}
                    {item.subtitle && (
                      <span className="mt-0.5 block truncate text-caption">
                        {item.subtitle}
                      </span>
                    )}
                  </span>
                )}
                {!collapsed && item.badge != null && (
                  <span className="relative z-10 rounded-full bg-[var(--color-primary-soft)] px-1.5 py-0.5 text-caption font-semibold text-[var(--color-primary)]">
                    {item.badge}
                  </span>
                )}
              </motion.button>
              </div>
            );
          })}
        </div>
      </div>
      {footer && (
        <div
          className="border-t border-[var(--color-chrome-stroke)]"
          style={{ padding: "10px 8px 12px 4px" }}
        >
          {footer}
        </div>
      )}
    </aside>
  );
}
