import type { ReactNode } from "react";
import { Home, GraduationCap, Briefcase, CalendarDays, FolderOpen } from "lucide-react";
import { ModalSheet, HubModuleTile, StaggeredItem, StaggeredList } from "@/design-system";
import type { HubId } from "@/design-system/tokens";

const TILES: Array<{
  id: HubId;
  title: string;
  subtitle: string;
  icon: ReactNode;
}> = [
  { id: "home", title: "Home", subtitle: "Today & goals", icon: <Home size={20} /> },
  { id: "school", title: "School", subtitle: "Plan, degree, LMS", icon: <GraduationCap size={20} /> },
  { id: "career", title: "Career", subtitle: "Applications & pathing", icon: <Briefcase size={20} /> },
  { id: "life", title: "Life", subtitle: "Schedule & money", icon: <CalendarDays size={20} /> },
  { id: "library", title: "Library", subtitle: "Files & portfolio", icon: <FolderOpen size={20} /> },
];

export function HubLauncher({
  open,
  onOpenChange,
  onSelect,
  activeIndex = 0,
  onActiveIndexChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelect: (hub: HubId) => void;
  activeIndex?: number;
  onActiveIndexChange?: (index: number) => void;
}) {
  const cols = 3;
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (!onActiveIndexChange) return;
    if (e.key === "ArrowRight") {
      e.preventDefault();
      onActiveIndexChange(Math.min(activeIndex + 1, TILES.length - 1));
    } else if (e.key === "ArrowLeft") {
      e.preventDefault();
      onActiveIndexChange(Math.max(activeIndex - 1, 0));
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      onActiveIndexChange(Math.min(activeIndex + cols, TILES.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      onActiveIndexChange(Math.max(activeIndex - cols, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const tile = TILES[activeIndex];
      if (tile) {
        onSelect(tile.id);
        onOpenChange(false);
      }
    }
  };

  return (
    <ModalSheet open={open} onOpenChange={onOpenChange} title="All hubs" width={720}>
      <p className="mb-4 text-caption">Jump to a hub — arrow keys + Enter, or click a tile.</p>
      <div role="listbox" aria-label="Hubs" onKeyDown={handleKeyDown}>
        <StaggeredList className="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
          {TILES.map((tile, i) => (
            <StaggeredItem key={tile.id}>
              <div role="option" aria-selected={i === activeIndex}>
                <HubModuleTile
                  icon={tile.icon}
                  title={tile.title}
                  subtitle={tile.subtitle}
                  onClick={() => {
                    onSelect(tile.id);
                    onOpenChange(false);
                  }}
                />
              </div>
            </StaggeredItem>
          ))}
        </StaggeredList>
      </div>
    </ModalSheet>
  );
}
