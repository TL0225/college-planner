import { cn } from "../cn";
import { shell } from "../tokens";
import { WindowChromeControls } from "./WindowChromeControls";
import { usePlatform } from "../platform/PlatformProvider";

/**
 * Super-app chrome matching AppShellSplitLayout:
 * traffic-light / logo cell | ModulePillBar header | window controls
 * sidebar rail              | content stage
 */
export function ShellSplitLayout({
  logo,
  header,
  sidebar,
  children,
  sidebarWidth,
  sidebarCollapsed = false,
}: {
  logo?: React.ReactNode;
  header: React.ReactNode;
  sidebar: React.ReactNode;
  children: React.ReactNode;
  sidebarWidth?: number;
  sidebarCollapsed?: boolean;
}) {
  const { platform } = usePlatform();
  const width =
    sidebarWidth ??
    (sidebarCollapsed ? shell.sidebarCollapsedWidth : shell.sidebarWidth);

  return (
    <div
      className="flex h-full w-full flex-col bg-[var(--color-shell-chrome)]"
    >
      <div
        className="flex shrink-0 border-b border-[var(--color-chrome-stroke)]"
        style={{ height: shell.chromeHeaderTotalHeight }}
      >
        <div
          className="flex shrink-0 items-end border-r border-[var(--color-chrome-stroke)]"
          style={{
            width,
            paddingLeft: "var(--shell-titlebar-inset)",
            paddingBottom: 10,
          }}
          data-tauri-drag-region
        >
          {logo}
        </div>
        <div
          className="flex min-w-0 flex-1 items-end px-3"
          style={{ paddingBottom: 8 }}
          data-tauri-drag-region
        >
          {header}
        </div>
        {platform !== "macos" ? <WindowChromeControls /> : null}
      </div>

      <div className="flex min-h-0 flex-1">
        <div
          className="shrink-0 border-r border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)]"
          style={{ width }}
        >
          {sidebar}
        </div>
        <div className={cn("min-h-0 min-w-0 flex-1")}>{children}</div>
      </div>
    </div>
  );
}
