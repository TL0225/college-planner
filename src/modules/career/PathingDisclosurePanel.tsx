import { useCallback, useEffect, useState } from "react";
import { AppCard } from "@/design-system";
import { formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import {
  defaultDisclosureChecklist,
  loadDisclosureMap,
  pathDisclosureItems,
  saveDisclosureMap,
  type PathDisclosureChecklist,
} from "./pathingSettings";

type Props = {
  entryId: string;
};

export function PathingDisclosurePanel({ entryId }: Props) {
  const [checklist, setChecklist] = useState<PathDisclosureChecklist>(
    defaultDisclosureChecklist(),
  );
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    const map = await loadDisclosureMap();
    setChecklist(map[entryId] ?? defaultDisclosureChecklist());
  }, [entryId]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const toggle = async (id: keyof PathDisclosureChecklist) => {
    const next = { ...checklist, [id]: !checklist[id] };
    setChecklist(next);
    setBusy(true);
    try {
      const map = await loadDisclosureMap();
      map[entryId] = next;
      await saveDisclosureMap(map);
    } catch (e) {
      showToast(formatIpcError(e), "error");
      void reload();
    } finally {
      setBusy(false);
    }
  };

  const doneCount = pathDisclosureItems.filter((item) => checklist[item.id]).length;

  return (
    <AppCard title="Disclosure readiness">
      <p className="mb-3 text-[12px] text-[var(--color-text-light)]">
        Confirm comp, benefits, and equity are documented before sharing this role in a disclosure
        bundle.
      </p>
      <p className="mb-3 text-[11px] font-medium text-[var(--color-text-light)]">
        {doneCount} of {pathDisclosureItems.length} complete
      </p>
      <ul className="space-y-2">
        {pathDisclosureItems.map((item) => {
          const checked = checklist[item.id];
          return (
            <li key={item.id}>
              <button
                type="button"
                disabled={busy}
                className="flex w-full items-start gap-2.5 rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2.5 text-left hover:bg-[var(--color-row-hover)] disabled:opacity-60"
                onClick={() => void toggle(item.id)}
              >
                <span
                  className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border ${
                    checked
                      ? "border-[var(--color-primary)] bg-[var(--color-primary)] text-white"
                      : "border-[var(--color-chrome-stroke)]"
                  }`}
                  aria-hidden
                >
                  {checked ? "✓" : ""}
                </span>
                <span className="min-w-0 flex-1">
                  <span
                    className={`block text-[13px] font-medium ${
                      checked
                        ? "text-[var(--color-text-light)] line-through"
                        : "text-[var(--color-text-main)]"
                    }`}
                  >
                    {item.title}
                  </span>
                  <span className="mt-0.5 block text-[11px] text-[var(--color-text-light)]">
                    {item.subtitle}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </AppCard>
  );
}
