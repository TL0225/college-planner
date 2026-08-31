import { FinanceModule } from "@/modules/finance/FinanceModule";
import { CalendarModule } from "@/modules/calendar/CalendarModule";
import { lifePageToLegacy } from "@/lib/shell/defaults";

export function LifeModule({ page }: { page: string }) {
  const legacy = lifePageToLegacy(page);

  if (legacy.finance) {
    const financePage =
      page === "money"
        ? "dashboard"
        : page === "ledger"
          ? "ledger"
          : page === "budgets"
            ? "budgets"
            : page === "reports"
              ? "reports"
              : page === "accounts"
                ? "accounts"
                : page.startsWith("account-")
                  ? page
                  : legacy.finance;
    return <FinanceModule page={financePage} />;
  }

  const calendarPage =
    page === "schedule"
      ? "month"
      : page === "tasks"
        ? "tasks"
        : page === "week"
          ? "week"
          : page === "day"
            ? "day"
            : legacy.calendar ?? "month";

  return <CalendarModule page={calendarPage} />;
}
