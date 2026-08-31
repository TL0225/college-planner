import { useCallback, useEffect, useState } from "react";
import { AppCard, Button, EmptyState, FormField, fieldControlClass } from "@/design-system";
import { formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import {
  loadPathGoals,
  newPathGoalId,
  pathGoalCadenceLabels,
  pathGoalCategoryLabels,
  savePathGoals,
  type PathGoal,
  type PathGoalCadence,
  type PathGoalCategory,
} from "./pathingSettings";

type Props = {
  entryId: string;
  organization: string;
};

const goalCategories = Object.keys(pathGoalCategoryLabels) as PathGoalCategory[];
const goalCadences = Object.keys(pathGoalCadenceLabels) as PathGoalCadence[];

const emptyDraft = (entryId: string): PathGoal => ({
  id: "",
  entryId,
  title: "",
  category: "tenure",
  cadence: "yearly",
  targetDate: "",
  notes: "",
});

export function PathingGoalsPanel({ entryId, organization }: Props) {
  const [goals, setGoals] = useState<PathGoal[]>([]);
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState<PathGoal | null>(null);

  const reload = useCallback(async () => {
    const all = await loadPathGoals();
    setGoals(all.filter((g) => g.entryId === entryId));
  }, [entryId]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const persist = async (nextAll: PathGoal[]) => {
    setBusy(true);
    try {
      const all = await loadPathGoals();
      const others = all.filter((g) => g.entryId !== entryId);
      await savePathGoals([...others, ...nextAll]);
      setGoals(nextAll);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const openNew = () => {
    setEditing({ ...emptyDraft(entryId), id: newPathGoalId() });
  };

  const saveDraft = async () => {
    if (!editing?.title.trim()) {
      showToast("Title is required", "error");
      return;
    }
    const exists = goals.some((g) => g.id === editing.id);
    const next = exists
      ? goals.map((g) => (g.id === editing.id ? editing : g))
      : [...goals, editing];
    await persist(next);
    setEditing(null);
    showToast("Goal saved", "success");
  };

  const deleteGoal = async (id: string) => {
    await persist(goals.filter((g) => g.id !== id));
    showToast("Goal deleted", "success");
  };

  return (
    <div className="space-y-3">
      <AppCard title="Goals">
        <p className="mb-3 text-meta">
          Track tenure, benefits windows, and tuition targets for{" "}
          {organization.trim() || "this role"}.
        </p>
        {goals.length === 0 ? (
          <EmptyState title="No goals yet" body="Add a goal to revisit on a cadence." />
        ) : (
          <ul className="space-y-2">
            {goals.map((goal) => (
              <li
                key={goal.id}
                className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <div className="text-body font-medium">
                      {goal.title}
                    </div>
                    <p className="mt-0.5 text-caption">
                      {pathGoalCategoryLabels[goal.category]} ·{" "}
                      {pathGoalCadenceLabels[goal.cadence]}
                      {goal.targetDate
                        ? ` · ${new Date(goal.targetDate).toLocaleDateString()}`
                        : ""}
                    </p>
                    {goal.notes?.trim() ? (
                      <p className="mt-1 text-meta">
                        {goal.notes}
                      </p>
                    ) : null}
                  </div>
                  <div className="flex shrink-0 gap-1">
                    <Button size="sm" variant="ghost" onClick={() => setEditing(goal)}>
                      Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={busy}
                      onClick={() => void deleteGoal(goal.id)}
                    >
                      Delete
                    </Button>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
        <div className="mt-3">
          <Button size="sm" variant="secondary" onClick={openNew}>
            Add goal
          </Button>
        </div>
      </AppCard>

      {editing && (
        <AppCard title={goals.some((g) => g.id === editing.id) ? "Edit goal" : "New goal"}>
          <div className="space-y-3">
            <FormField label="Title">
              <input
                className={fieldControlClass}
                value={editing.title}
                onChange={(e) => setEditing({ ...editing, title: e.target.value })}
                placeholder="Stay 2 years, use tuition benefit…"
              />
            </FormField>
            <div className="grid grid-cols-2 gap-2">
              <FormField label="Category">
                <select
                  className={fieldControlClass}
                  value={editing.category}
                  onChange={(e) =>
                    setEditing({ ...editing, category: e.target.value as PathGoalCategory })
                  }
                >
                  {goalCategories.map((c) => (
                    <option key={c} value={c}>
                      {pathGoalCategoryLabels[c]}
                    </option>
                  ))}
                </select>
              </FormField>
              <FormField label="Cadence">
                <select
                  className={fieldControlClass}
                  value={editing.cadence}
                  onChange={(e) =>
                    setEditing({ ...editing, cadence: e.target.value as PathGoalCadence })
                  }
                >
                  {goalCadences.map((c) => (
                    <option key={c} value={c}>
                      {pathGoalCadenceLabels[c]}
                    </option>
                  ))}
                </select>
              </FormField>
            </div>
            <FormField label="Target date">
              <input
                type="date"
                className={fieldControlClass}
                value={editing.targetDate ?? ""}
                onChange={(e) => setEditing({ ...editing, targetDate: e.target.value })}
              />
            </FormField>
            <FormField label="Notes">
              <textarea
                className={fieldControlClass}
                rows={3}
                value={editing.notes ?? ""}
                onChange={(e) => setEditing({ ...editing, notes: e.target.value })}
              />
            </FormField>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" disabled={busy} onClick={() => void saveDraft()}>
                Save
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setEditing(null)}>
                Cancel
              </Button>
            </div>
          </div>
        </AppCard>
      )}
    </div>
  );
}
