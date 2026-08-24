import { motion } from "framer-motion";
import { cn } from "../cn";
import { sidebarSpring, withReduceMotion } from "../motion/springPresets";
import { radius, shell } from "../tokens";

export type SidebarItem = {
  id: string;
  title: string;
  icon?: React.ReactNode;
  badge?: string | number;
  subtitle?: string;
  indent?: boolean;
};

export function AppSidebar({
  items,
  selection,
  onSelect,
  footer,
  sectionTitle,
  collapsed = false,
  reduceMotion = false,
}: {
  items: SidebarItem[];
  selection: string;
  onSelect: (id: string) => void;
  footer?: React.ReactNode;
  sectionTitle?: string;
  collapsed?: boolean;
  reduceMotion?: boolean;
}) {
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
            border: "1px solid color-mix(in srgb, var(--color-text-main) 8%, transparent)",
            boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
          }}
        >
          {sectionTitle && !collapsed && (
            <div className="px-2.5 pb-1.5 pt-0.5 text-[10px] font-semibold uppercase tracking-[0.07em] text-[var(--color-text-light)]">
              {sectionTitle}
            </div>
          )}
          {items.map((item) => {
            const selected = selection === item.id;
            return (
              <motion.button
                key={item.id}
                type="button"
                onClick={() => onSelect(item.id)}
                title={item.title}
                whileTap={reduceMotion ? undefined : { scale: 0.98 }}
                transition={withReduceMotion(reduceMotion, sidebarSpring)}
                className={cn(
                  "relative flex w-full items-center gap-2 text-left",
                  selected
                    ? "font-semibold text-[var(--color-text-main)]"
                    : "font-medium text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)] hover:text-[var(--color-text-main)]",
                )}
                style={{
                  minHeight: shell.sidebarRowMinHeight,
                  borderRadius: radius.sidebarRow,
                  padding: "5px 10px",
                  paddingLeft: item.indent ? 22 : 10,
                  fontSize: item.indent ? 12 : 12.5,
                }}
              >
                {selected && (
                  <motion.span
                    layoutId="sidebarSelection"
                    className="absolute inset-0 bg-[var(--color-shell-selection)] shadow-[var(--shadow-pill)]"
                    style={{ borderRadius: radius.sidebarRow }}
                    transition={withReduceMotion(reduceMotion, sidebarSpring)}
                  />
                )}
                {item.icon && (
                  <span className="relative z-10 shrink-0 opacity-80">{item.icon}</span>
                )}
                {!collapsed && (
                  <span className="relative z-10 min-w-0 flex-1 truncate">
                    {item.title}
                    {item.subtitle && (
                      <span className="mt-0.5 block truncate text-[10px] font-normal text-[var(--color-text-light)]">
                        {item.subtitle}
                      </span>
                    )}
                  </span>
                )}
                {!collapsed && item.badge != null && (
                  <span className="relative z-10 rounded-full bg-[var(--color-primary-soft)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--color-primary)]">
                    {item.badge}
                  </span>
                )}
              </motion.button>
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
