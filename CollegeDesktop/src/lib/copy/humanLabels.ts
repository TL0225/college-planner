import type { ModuleId } from "@/lib/shell/types";

/** User-facing labels for internal IDs — single source of truth for shell copy. */
export const HUMAN_LABELS = {
  vault: "Files",
  ledger: "Transactions",
  lms: "Course portal",
  pathing: "Career path",
  discovery: "Explore schools",
  pipeline: "Applications",
  schedule: "Month",
  money: "Money",
  dashboard: "Money",
  catalog: "Browse catalog",
  plan: "Academic plan",
  courses: "My courses",
  degree: "Degree progress",
  schools: "Explore schools",
  all: "All files",
  today: "Today",
  week: "Week",
  goals: "Goals",
  recents: "Recents",
  tasks: "Tasks",
  month: "Month",
  day: "Day",
  agenda: "Agenda",
  budgets: "Budgets",
  reports: "Reports",
  accounts: "Accounts",
  openings: "Openings",
  resume: "Resume",
  growth: "Growth",
  transfer: "Transfer",
  google: "Google Calendar",
  outlook: "Outlook",
  apple: "Apple Calendar",
  ics: "Calendar app",
  in_progress: "In progress",
  satisfied: "Complete",
  not_started: "Not started",
  checking: "Checking",
  checking_account: "Checking",
  savings: "Savings",
  credit: "Credit card",
  investment: "Investment",
} as const;

export type HumanLabelKey = keyof typeof HUMAN_LABELS;

export function humanLabel(key: string, fallback?: string): string {
  const k = key as HumanLabelKey;
  if (k in HUMAN_LABELS) return HUMAN_LABELS[k];
  if (fallback) return fallback;
  return key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

export function humanPageTitle(_module: ModuleId, page: string): string {
  if (page.startsWith("req-")) return "Degree progress";
  if (page.startsWith("account-")) return "Account";
  if (page.startsWith("source-")) return "Calendar";
  if (page.startsWith("folder-")) return HUMAN_LABELS.vault;
  if (page.startsWith("course-")) return HUMAN_LABELS.courses;
  if (page.startsWith("cat-")) return HUMAN_LABELS.vault;
  const key = page as HumanLabelKey;
  if (key in HUMAN_LABELS) return HUMAN_LABELS[key];
  return humanLabel(page);
}

export const SETTINGS_CATEGORY_LABELS = {
  you: "You",
  appearance: "Look & feel",
  connections: "Connections",
  "school-work": "School & work",
  advanced: "Advanced",
} as const;
