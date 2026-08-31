import { AcademicsModule } from "@/modules/academics/AcademicsModule";
import { CatalogModule } from "@/modules/catalog/CatalogModule";
import { DiscoveryModule } from "@/modules/discovery/DiscoveryModule";
import { TransferModule } from "@/modules/transfer/TransferModule";
import { LmsModule } from "@/modules/lms/LmsModule";
import { schoolPageToLegacy } from "@/lib/shell/defaults";

export function SchoolModule({ page }: { page: string }) {
  const legacy = schoolPageToLegacy(page);

  if (legacy.module === "discovery" || page === "schools" || page === "discovery") {
    return <DiscoveryModule />;
  }

  if (legacy.module === "catalog" || page === "catalog" || page === "discover") {
    return <CatalogModule />;
  }

  if (legacy.module === "transfer" || page === "transfer") {
    return <TransferModule />;
  }

  if (legacy.module === "lms" || page === "lms") {
    return <LmsModule />;
  }

  const academicsPage =
    page === "overview"
      ? "overview"
      : page === "courses"
        ? "courses"
        : page === "degree" || page.startsWith("req-")
          ? "degree"
          : "planner";

  return (
    <AcademicsModule
      page={academicsPage}
      highlightSectionId={page.startsWith("req-") ? page.slice(4) : undefined}
    />
  );
}
