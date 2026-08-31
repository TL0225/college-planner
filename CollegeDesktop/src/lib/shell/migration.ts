import type { LegacyModuleId, ShellRecent } from "./types";
import { IA_VERSION } from "./types";
import type { ModuleId } from "@/design-system/tokens";

const HUB_OR_SETTINGS = new Set(["home", "school", "career", "life", "library", "settings"]);

const MODULE_MAP: Record<string, ModuleId> = {
  college: "school",
  finance: "life",
  calendar: "life",
  documents: "library",
  profile: "library",
  assistant: "home",
  home: "home",
  school: "school",
  career: "career",
  life: "life",
  library: "library",
  settings: "settings",
};

const PAGE_MAP: Record<string, Record<string, string>> = {
  college: {
    academics: "today",
    planner: "plan",
    catalog: "discover",
    degree: "degree",
    transfer: "transfer",
    discovery: "discover",
    lms: "lms",
  },
  finance: {
    dashboard: "money",
    accounts: "money",
    ledger: "money",
    budgets: "budgets",
    goals: "budgets",
    inventory: "money",
    receipts: "money",
    reports: "reports",
    "net-worth": "reports",
  },
  calendar: {
    month: "schedule",
    week: "schedule",
    day: "schedule",
    agenda: "schedule",
    tasks: "tasks",
  },
  documents: {
    all: "all",
    recent: "recent",
    starred: "starred",
    "needs-review": "needs-review",
  },
  profile: {
    identity: "identity",
    experiences: "portfolio",
    achievements: "portfolio",
    portfolio: "portfolio",
    advisor: "identity",
  },
  assistant: {
    chat: "today",
    syllabus: "today",
  },
};

function remapPage(legacyModule: string, page: string): string {
  if (legacyModule === "college" && page.startsWith("req-")) return `degree`;
  if (legacyModule === "finance" && page.startsWith("account-")) return `money`;
  if (legacyModule === "calendar" && page.startsWith("source-")) return "schedule";
  if (legacyModule === "documents" && (page.startsWith("folder-") || page.startsWith("course-"))) {
    return page;
  }
  if (legacyModule === "documents" && page.startsWith("cat-")) return page;
  const hub = MODULE_MAP[legacyModule];
  if (!hub) return page;
  const table = PAGE_MAP[legacyModule];
  return table?.[page] ?? page;
}

export type MigrationResult = {
  module: ModuleId;
  page: string;
  recents: ShellRecent[];
  openAi: boolean;
  showWhatsNew: boolean;
};

export function migrateShellState(values: Record<string, string>): MigrationResult {
  const iaVersion = parseInt(values["shell.iaVersion"] ?? "1", 10);
  const showWhatsNew = iaVersion < IA_VERSION;

  let openAi = false;
  let rawModule = values["shell.module"] ?? "home";
  let rawPage = values["shell.page"] ?? "today";

  if (rawModule === "assistant") {
    openAi = true;
    rawModule = "home";
    rawPage = "today";
  }

  const module = MODULE_MAP[rawModule] ?? (HUB_OR_SETTINGS.has(rawModule) ? (rawModule as ModuleId) : "home");
  const page = remapPage(rawModule, rawPage);

  let recents: ShellRecent[] = [];
  try {
    const raw = values["shell.recents"];
    if (raw) {
      const parsed = JSON.parse(raw) as ShellRecent[];
      if (Array.isArray(parsed)) {
        recents = parsed
          .map((r) => {
            const m = MODULE_MAP[r.module as string] ?? r.module;
            if (m === "home" && (r.module as string) === "assistant") return null;
            return {
              module: m as ModuleId,
              page: remapPage(r.module as string, r.page),
              title: r.title,
            };
          })
          .filter((r): r is ShellRecent => r != null)
          .slice(0, 8);
      }
    }
  } catch {
    recents = [];
  }

  return { module, page, recents, openAi, showWhatsNew };
}

export function isLegacyModule(id: string): id is LegacyModuleId {
  return id in MODULE_MAP && !HUB_OR_SETTINGS.has(id);
}
