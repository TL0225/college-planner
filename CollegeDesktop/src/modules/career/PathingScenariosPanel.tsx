import { useCallback, useEffect, useState } from "react";
import { AppCard, FormField, fieldControlClass } from "@/design-system";
import { formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import {
  defaultScenarioPair,
  loadScenarioMap,
  saveScenarioMap,
  type PathScenarioPair,
} from "./pathingSettings";

type Props = {
  entryId: string;
};

export function PathingScenariosPanel({ entryId }: Props) {
  const [pair, setPair] = useState<PathScenarioPair>(defaultScenarioPair());
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    const map = await loadScenarioMap();
    setPair(map[entryId] ?? defaultScenarioPair());
  }, [entryId]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const persist = async (next: PathScenarioPair) => {
    setBusy(true);
    try {
      const map = await loadScenarioMap();
      map[entryId] = next;
      await saveScenarioMap(map);
      setPair(next);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const updateCard = (
    key: keyof PathScenarioPair,
    field: "title" | "notes",
    value: string,
  ) => {
    setPair((prev) => ({
      ...prev,
      [key]: { ...prev[key], [field]: value },
    }));
  };

  const commitCard = () => {
    void persist(pair);
  };

  return (
    <div className="space-y-3">
      <p className="text-meta">
        Compare your current trajectory with an alternate option. There is no single “best” score.
      </p>
      <div className="grid gap-3 sm:grid-cols-2">
        {(["current", "alternate"] as const).map((key) => (
          <AppCard key={key} title={key === "current" ? "Current scenario" : "Alternate scenario"}>
            <div className="space-y-3">
              <FormField label="Title">
                <input
                  className={fieldControlClass}
                  value={pair[key].title}
                  disabled={busy}
                  onChange={(e) => updateCard(key, "title", e.target.value)}
                  onBlur={commitCard}
                />
              </FormField>
              <FormField label="Notes">
                <textarea
                  className={fieldControlClass}
                  rows={5}
                  disabled={busy}
                  value={pair[key].notes}
                  onChange={(e) => updateCard(key, "notes", e.target.value)}
                  onBlur={commitCard}
                  placeholder="Assumptions, tradeoffs, what would change…"
                />
              </FormField>
            </div>
          </AppCard>
        ))}
      </div>
    </div>
  );
}
