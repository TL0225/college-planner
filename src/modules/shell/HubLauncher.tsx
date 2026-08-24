import type { ReactNode } from "react";
import {
  GraduationCap,
  Wallet,
  CalendarDays,
  Briefcase,
  FolderOpen,
  Sparkles,
  UserRound,
} from "lucide-react";
import { ModalSheet } from "@/design-system";
import type { ModuleId } from "@/design-system";

const TILES: Array<{
  id: ModuleId;
  title: string;
  icon: ReactNode;
}> = [
  { id: "college", title: "College", icon: <GraduationCap size={22} /> },
  { id: "finance", title: "Finance", icon: <Wallet size={22} /> },
  { id: "calendar", title: "Calendar", icon: <CalendarDays size={22} /> },
  { id: "career", title: "Career", icon: <Briefcase size={22} /> },
  { id: "documents", title: "Documents", icon: <FolderOpen size={22} /> },
  { id: "assistant", title: "Assistant", icon: <Sparkles size={22} /> },
  { id: "profile", title: "Profile", icon: <UserRound size={22} /> },
];

export function HubLauncher({
  open,
  onOpenChange,
  onSelect,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelect: (module: ModuleId) => void;
}) {
  return (
    <ModalSheet open={open} onOpenChange={onOpenChange} title="College hubs">
      <p className="mb-4 text-[12px] text-[var(--color-text-light)]">
        Jump to a module — Swift hub launcher parity.
      </p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {TILES.map((tile) => (
          <button
            key={tile.id}
            type="button"
            className="flex flex-col items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-3 py-4 text-[var(--color-text-main)] hover:bg-[var(--color-row-hover)]"
            onClick={() => {
              onSelect(tile.id);
              onOpenChange(false);
            }}
          >
            <span className="text-[var(--color-primary)]">{tile.icon}</span>
            <span className="text-[13px] font-semibold">{tile.title}</span>
          </button>
        ))}
      </div>
    </ModalSheet>
  );
}
