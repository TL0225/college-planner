import { ipc } from "@/lib/ipc";

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

let pathingMigrationDone = false;

async function ensurePathingMigrated(): Promise<void> {
  if (pathingMigrationDone) return;
  try {
    await ipc.careerMigratePathingSettings();
  } catch {
    // Non-fatal — empty DB or first run.
  }
  pathingMigrationDone = true;
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
  await ensurePathingMigrated();
  const rows = await ipc.careerListPathGoals();
  return rows.map((r) => ({
    id: r.id,
    entryId: r.entryId,
    title: r.title,
    category: r.category as PathGoalCategory,
    cadence: r.cadence as PathGoalCadence,
    targetDate: r.targetDate ?? undefined,
    notes: r.notes || undefined,
  }));
}

export async function savePathGoals(goals: PathGoal[]): Promise<void> {
  await ensurePathingMigrated();
  const existing = await ipc.careerListPathGoals();
  const keep = new Set(goals.map((g) => g.id));
  for (const row of existing) {
    if (!keep.has(row.id)) {
      await ipc.careerDeletePathGoal(row.id);
    }
  }
  for (const g of goals) {
    await ipc.careerUpsertPathGoal({
      id: g.id,
      entryId: g.entryId,
      title: g.title,
      category: g.category,
      cadence: g.cadence,
      targetDate: g.targetDate,
      notes: g.notes,
    });
  }
}

export async function loadScenarioMap(): Promise<Record<string, PathScenarioPair>> {
  await ensurePathingMigrated();
  const entries = await ipc.careerListPathEntries();
  const out: Record<string, PathScenarioPair> = {};
  await Promise.all(
    entries.map(async (e) => {
      const row = await ipc.careerGetPathScenario(e.id);
      if (row) {
        out[e.id] = { current: row.current, alternate: row.alternate };
      }
    }),
  );
  return out;
}

export async function saveScenarioMap(map: Record<string, PathScenarioPair>): Promise<void> {
  await ensurePathingMigrated();
  await Promise.all(
    Object.entries(map).map(([entryId, pair]) =>
      ipc.careerSavePathScenario({
        entryId,
        current: pair.current,
        alternate: pair.alternate,
      }),
    ),
  );
}

export async function loadDisclosureMap(): Promise<Record<string, PathDisclosureChecklist>> {
  await ensurePathingMigrated();
  const entries = await ipc.careerListPathEntries();
  const out: Record<string, PathDisclosureChecklist> = {};
  await Promise.all(
    entries.map(async (e) => {
      const row = await ipc.careerGetPathDisclosure(e.id);
      if (row) {
        out[e.id] = { comp: row.comp, benefits: row.benefits, equity: row.equity };
      }
    }),
  );
  return out;
}

export async function saveDisclosureMap(map: Record<string, PathDisclosureChecklist>): Promise<void> {
  await ensurePathingMigrated();
  await Promise.all(
    Object.entries(map).map(([entryId, checklist]) =>
      ipc.careerSavePathDisclosure({
        entryId,
        comp: checklist.comp,
        benefits: checklist.benefits,
        equity: checklist.equity,
      }),
    ),
  );
}
