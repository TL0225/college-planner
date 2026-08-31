import { AppPageHeader, Button, SegmentedPills } from "@/design-system";
import type { ReactNode } from "react";

const PAGE_TITLES: Record<string, string> = {
  pathing: "Pathing",
  brag: "Brag Book",
  networking: "Networking",
  interview: "Interview",
  board: "Board",
  resumes: "Resumes",
  openings: "Openings",
  stats: "Pipeline stats",
  apply: "Apply profile",
};

export function careerPageTitle(shellView: string): string {
  return PAGE_TITLES[shellView] ?? "Applications";
}

export function CareerPageHeader({
  shellView,
  layout,
  onLayoutChange,
  onRefresh,
  actions,
}: {
  shellView: string;
  layout: "list" | "board";
  onLayoutChange: (layout: "list" | "board") => void;
  onRefresh: () => void;
  actions: ReactNode;
}) {
  return (
    <AppPageHeader
      title={careerPageTitle(shellView)}
      leading={
        shellView === "applications" ? (
          <SegmentedPills
            value={layout}
            onChange={onLayoutChange}
            options={[
              { id: "list", label: "List" },
              { id: "board", label: "Board" },
            ]}
          />
        ) : undefined
      }
      actions={
        <div className="flex gap-2">
          <Button size="sm" variant="secondary" onClick={onRefresh}>
            Refresh
          </Button>
          {actions}
        </div>
      }
    />
  );
}
