import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { Settings, UserRound } from "lucide-react";
import { cn } from "../cn";

export function UserMenu({
  displayName,
  onProfile,
  onSettings,
}: {
  displayName?: string;
  onProfile: () => void;
  onSettings: () => void;
}) {
  const initial = (displayName?.trim()?.[0] ?? "U").toUpperCase();
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger asChild>
        <button
          type="button"
          className={cn(
            "inline-flex h-8 min-w-8 items-center justify-center gap-1.5 rounded-[8px] px-1.5",
            "text-chrome text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)]",
          )}
          aria-label="Profile and settings"
          title="Profile & settings"
        >
          <span
            className="flex h-6 w-6 items-center justify-center rounded-full bg-[var(--color-primary-soft)] text-label font-semibold text-[var(--color-primary)]"
            aria-hidden
          >
            {initial}
          </span>
          {displayName ? (
            <span className="max-w-[88px] truncate text-chrome">{displayName}</span>
          ) : null}
        </button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          className="z-50 min-w-[160px] rounded-[10px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-1 shadow-[var(--shadow-elevated)]"
          side="top"
          align="start"
          sideOffset={6}
        >
          <DropdownMenu.Item
            className="flex cursor-pointer items-center gap-2 rounded-[6px] px-2.5 py-1.5 text-body outline-none data-[highlighted]:bg-[var(--color-row-hover)]"
            onSelect={onProfile}
          >
            <UserRound size={14} />
            Identity
          </DropdownMenu.Item>
          <DropdownMenu.Item
            className="flex cursor-pointer items-center gap-2 rounded-[6px] px-2.5 py-1.5 text-body outline-none data-[highlighted]:bg-[var(--color-row-hover)]"
            onSelect={onSettings}
          >
            <Settings size={14} />
            Settings
          </DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
