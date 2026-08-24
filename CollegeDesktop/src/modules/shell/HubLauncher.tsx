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
import { ModalSheet, HubModuleTile } from "@/design-system";
import type { ModuleId } from "@/design-system";

const TILES: Array<{
  id: ModuleId;
  title: string;
  subtitle: string;
  icon: ReactNode;
}> = [
  { id: "college", title: "College", subtitle: "Planner, degree, overview", icon: <GraduationCap size={20} /> },
  { id: "finance", title: "Finance", subtitle: "Accounts, budgets, reports", icon: <Wallet size={20} /> },
  { id: "calendar", title: "Calendar", subtitle: "Month, week, tasks", icon: <CalendarDays size={20} /> },
  { id: "career", title: "Career", subtitle: "Applications, pathing, resume", icon: <Briefcase size={20} /> },
  { id: "documents", title: "Documents", subtitle: "Vault and linked files", icon: <FolderOpen size={20} /> },
  { id: "assistant", title: "Assistant", subtitle: "Chat and syllabus AI", icon: <Sparkles size={20} /> },
  { id: "profile", title: "Profile", subtitle: "Identity and portfolio", icon: <UserRound size={20} /> },
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
    <ModalSheet open={open} onOpenChange={onOpenChange} title="College hubs" width={720}>
      <p className="mb-4 text-[12px] text-[var(--color-text-light)]">
        Jump to a module — same hub grid as the Swift super-app launcher.
      </p>
      <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
        {TILES.map((tile) => (
          <HubModuleTile
            key={tile.id}
            icon={tile.icon}
            title={tile.title}
            subtitle={tile.subtitle}
            onClick={() => {
              onSelect(tile.id);
              onOpenChange(false);
            }}
          />
        ))}
      </div>
    </ModalSheet>
  );
}
