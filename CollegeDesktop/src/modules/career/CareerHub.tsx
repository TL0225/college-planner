import { CareerModule } from "./CareerModule";
import { CareerGrowthView } from "./views/CareerGrowthView";
import { careerPageToLegacy } from "@/lib/shell/defaults";

/**
 * Hub router for Career — maps Path D sidebar pages to legacy CareerModule views.
 */
export function CareerHub({ page }: { page: string }) {
  if (page === "growth") return <CareerGrowthView />;
  return <CareerModule page={careerPageToLegacy(page)} />;
}

export { CareerModule } from "./CareerModule";
