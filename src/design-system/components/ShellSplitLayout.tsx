import { cn } from "../cn";
import { shell } from "../tokens";

/**
 * Super-app chrome matching AppShellSplitLayout:
 * traffic-light / logo cell | ModulePillBar header
 * sidebar rail              | white content stage
 */
export function ShellSplitLayout({
  logo,
  header,
  sidebar,
  children,
  sidebarWidth = shell.sidebarWidth,
}: {
  logo?: React.ReactNode;
  header: React.ReactNode;
  sidebar: React.ReactNode;
  children: React.ReactNode;
  sidebarWidth?: number;
}) {
  return (
    <div
      className="flex h-full w-full flex-col"
      style={{
        background:
          "linear-gradient(180deg, color-mix(in srgb, white 28%, var(--color-shell-chrome)) 0%, var(--color-shell-chrome) 48px)",
      }}
    >
      <div
        className="flex shrink-0 border-b border-[var(--color-chrome-stroke)]"
        style={{ height: shell.chromeHeaderTotalHeight }}
      >
        <div
          className="flex shrink-0 items-end border-r border-[var(--color-chrome-stroke)]"
          style={{
            width: sidebarWidth,
            paddingLeft: Math.min(shell.titlebarLeadingInset, 16),
            paddingBottom: 10,
          }}
          data-tauri-drag-region
        >
          {logo ?? (
            <div
              className="flex h-7 w-7 items-center justify-center text-[11px] font-bold text-white"
              style={{
                borderRadius: 8,
                background:
                  "linear-gradient(145deg, color-mix(in srgb, white 22%, var(--color-primary)), var(--color-primary))",
                boxShadow: "var(--shadow-pill)",
              }}
              aria-hidden
            >
              C
            </div>
          )}
        </div>
        <div
          className="flex min-w-0 flex-1 items-end px-3"
          style={{ paddingBottom: 8 }}
          data-tauri-drag-region
        >
          {header}
        </div>
      </div>

      <div className="flex min-h-0 flex-1">
        <div
          className="shrink-0 border-r border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)]"
          style={{ width: sidebarWidth }}
        >
          {sidebar}
        </div>
        <div className={cn("min-h-0 min-w-0 flex-1")}>{children}</div>
      </div>
    </div>
  );
}
