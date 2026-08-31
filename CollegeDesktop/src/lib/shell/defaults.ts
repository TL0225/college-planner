import type { ModuleId } from "./types";

export function defaultPageFor(module: ModuleId): string {
  switch (module) {
    case "home":
      return "today";
    case "school":
      return "plan";
    case "career":
      return "pipeline";
    case "life":
      return "schedule";
    case "library":
      return "all";
    case "settings":
      return "appearance";
    default:
      return "today";
  }
}

/** Maps new hub pages to legacy module pages for existing feature components. */
export function schoolPageToLegacy(page: string): { module: string; page: string } {
  if (page === "overview") return { module: "academics", page: "overview" };
  if (page === "plan") return { module: "academics", page: "planner" };
  if (page === "courses") return { module: "academics", page: "courses" };
  if (page === "degree") return { module: "academics", page: "degree" };
  if (page === "schools" || page === "discovery") return { module: "discovery", page: "discovery" };
  if (page === "catalog" || page === "discover") return { module: "catalog", page: "catalog" };
  if (page === "transfer") return { module: "transfer", page: "transfer" };
  if (page === "lms") return { module: "lms", page: "lms" };
  if (page.startsWith("req-")) return { module: "academics", page };
  return { module: "academics", page: "planner" };
}

export function lifePageToLegacy(page: string): { finance?: string; calendar?: string } {
  const calendarPages = ["schedule", "tasks", "week", "day", "agenda", "month"];
  const financePages = [
    "money",
    "accounts",
    "ledger",
    "budgets",
    "goals",
    "inventory",
    "receipts",
    "reports",
    "net-worth",
  ];
  if (calendarPages.includes(page) || page.startsWith("source-")) {
    const cal =
      page === "schedule"
        ? "month"
        : page === "tasks"
          ? "tasks"
          : page.startsWith("source-")
            ? page
            : page;
    return { calendar: cal };
  }
  if (financePages.includes(page) || page.startsWith("account-")) {
    const fin =
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
                : page === "goals"
                  ? "goals"
                  : page;
    return { finance: fin };
  }
  return { calendar: "month" };
}

export function libraryPageToLegacy(page: string): { documents?: string; profile?: string } {
  const profilePages = ["identity", "portfolio", "experiences", "achievements", "advisor"];
  if (profilePages.includes(page)) return { profile: page };
  return { documents: page };
}

export function careerPageToLegacy(page: string): string {
  const map: Record<string, string> = {
    pipeline: "applications",
    pathing: "pathing",
    resume: "resumes",
    growth: "brag",
    openings: "openings",
    board: "board",
    stats: "stats",
    apply: "apply",
  };
  return map[page] ?? page;
}