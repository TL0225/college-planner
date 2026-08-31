import { useState } from "react";
import { SegmentedPills } from "@/design-system";
import { CareerModule } from "../CareerModule";

const GROWTH_PAGES = [
  { id: "brag", label: "Brag book" },
  { id: "networking", label: "Networking" },
  { id: "interview", label: "Interview" },
] as const;

/** Growth hub — combines brag, networking, and interview without extra sidebar hops. */
export function CareerGrowthView() {
  const [tab, setTab] = useState<string>("brag");
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="shrink-0 border-b border-[var(--color-chrome-stroke)] px-3 py-2">
        <SegmentedPills
          options={GROWTH_PAGES.map((p) => ({ id: p.id, label: p.label }))}
          value={tab}
          onChange={setTab}
        />
      </div>
      <div className="min-h-0 flex-1">
        <CareerModule page={tab} />
      </div>
    </div>
  );
}
