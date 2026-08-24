import { ipc } from "@/lib/ipc";

export const PATHING_GOALS_KEY = "career.pathing.goals";
export const PATHING_SCENARIOS_KEY = "career.pathing.scenarios";
export const PATHING_DISCLOSURE_KEY = "career.pathing.disclosure";

export type PathGoalCategory = "tenure" | "benefits" | "tuition" | "custom";
export type PathGoalCadence = "monthly" | "quarterly" | "yearly";

export type PathGoal = {
  id: string;
  entryId: string;
  title: string;
  category: PathGoalCategory;
  cadence: PathGoalCadence;
  targetDate?: string;
  notes?: string;
};

export type PathScenarioCard = {
  title: string;
  notes: string;
};

export type PathScenarioPair = {
  current: PathScenarioCard;
  alternate: PathScenarioCard;
};

export type PathDisclosureChecklist = {
  comp: boolean;
  benefits: boolean;
  equity: boolean;
};

export const pathGoalCategoryLabels: Record<PathGoalCategory, string> = {
  tenure: "Tenure",
  benefits: "Benefits",
  tuition: "Tuition",
  custom: "Custom",
};

export const pathGoalCadenceLabels: Record<PathGoalCadence, string> = {
  monthly: "Monthly",
  quarterly: "Quarterly",
  yearly: "Yearly",
};

export const pathDisclosureItems: Array<{
  id: keyof PathDisclosureChecklist;
  title: string;
  subtitle: string;
}> = [
  {
    id: "comp",
    title: "Compensation documented",
    subtitle: "Base pay, bonus targets, and review cadence are recorded.",
  },
  {
    id: "benefits",
    title: "Benefits reviewed",
    subtitle: "Health, PTO, stipends, and other perks are captured.",
  },
  {
    id: "equity",
    title: "Equity / RSUs documented",
    subtitle: "Grant size, vesting, and refresh expectations are noted.",
  },
];

function parseJson<T>(raw: string | undefined, fallback: T): T {
  if (!raw?.trim()) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export function newPathGoalId(): string {
  return crypto.randomUUID();
}

export function defaultScenarioPair(): PathScenarioPair {
  return {
    current: { title: "Current path", notes: "" },
    alternate: { title: "Alternate path", notes: "" },
  };
}

export function defaultDisclosureChecklist(): PathDisclosureChecklist {
  return { comp: false, benefits: false, equity: false };
}

export async function loadPathGoals(): Promise<PathGoal[]> {
  const settings = await ipc.settingsGet();
  return parseJson<PathGoal[]>(settings.values[PATHING_GOALS_KEY], []);
}

export async function savePathGoals(goals: PathGoal[]): Promise<void> {
  await ipc.settingsSet(PATHING_GOALS_KEY, JSON.stringify(goals));
}

export async function loadScenarioMap(): Promise<Record<string, PathScenarioPair>> {
  const settings = await ipc.settingsGet();
  return parseJson<Record<string, PathScenarioPair>>(settings.values[PATHING_SCENARIOS_KEY], {});
}

export async function saveScenarioMap(map: Record<string, PathScenarioPair>): Promise<void> {
  await ipc.settingsSet(PATHING_SCENARIOS_KEY, JSON.stringify(map));
}

export async function loadDisclosureMap(): Promise<Record<string, PathDisclosureChecklist>> {
  const settings = await ipc.settingsGet();
  return parseJson<Record<string, PathDisclosureChecklist>>(settings.values[PATHING_DISCLOSURE_KEY], {});
}

export async function saveDisclosureMap(map: Record<string, PathDisclosureChecklist>): Promise<void> {
  await ipc.settingsSet(PATHING_DISCLOSURE_KEY, JSON.stringify(map));
}
