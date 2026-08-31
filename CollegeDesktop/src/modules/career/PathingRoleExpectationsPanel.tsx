import { useCallback, useEffect, useState } from "react";
import { AppCard, Button, EmptyState, FormField, fieldControlClass } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";

type ExpectationBox = {
  id: string;
  title: string;
  body: string;
  sortOrder: number;
};

type Props = {
  entryId: string;
};

const newBox = (): ExpectationBox => ({
  id: crypto.randomUUID(),
  title: "",
  body: "",
  sortOrder: 0,
});

export function PathingRoleExpectationsPanel({ entryId }: Props) {
  const [summary, setSummary] = useState("");
  const [boxes, setBoxes] = useState<ExpectationBox[]>([]);
  const [busy, setBusy] = useState(false);
  const [loaded, setLoaded] = useState(false);

  const reload = useCallback(async () => {
    const row = await ipc.careerGetRoleExpectation(entryId);
    setSummary(row.summary);
    setBoxes(
      row.boxes.map((b, index) => ({
        id: b.id,
        title: b.title,
        body: b.body,
        sortOrder: b.sortOrder ?? index,
      })),
    );
    setLoaded(true);
  }, [entryId]);

  useEffect(() => {
    setLoaded(false);
    void reload().catch(() => {
      setSummary("");
      setBoxes([]);
      setLoaded(true);
    });
  }, [reload]);

  const save = async () => {
    setBusy(true);
    try {
      await ipc.careerSaveRoleExpectation({
        pathEntryId: entryId,
        summary,
        boxes: boxes.map((b, index) => ({
          id: b.id,
          title: b.title,
          body: b.body,
          sortOrder: index,
        })),
      });
      showToast("Expectations saved", "success");
      await reload();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const updateBox = (id: string, patch: Partial<ExpectationBox>) => {
    setBoxes((prev) => prev.map((b) => (b.id === id ? { ...b, ...patch } : b)));
  };

  const removeBox = (id: string) => {
    setBoxes((prev) => prev.filter((b) => b.id !== id));
  };

  if (!loaded) {
    return (
      <AppCard title="Expectations">
        <p className="text-meta">Loading…</p>
      </AppCard>
    );
  }

  return (
    <div className="space-y-3">
      <AppCard title="Expectations">
        <p className="mb-3 text-meta">
          Capture what you expect from this role — responsibilities, support, and check-in notes.
        </p>
        <FormField label="Summary">
          <textarea
            className={fieldControlClass}
            rows={4}
            value={summary}
            onChange={(e) => setSummary(e.target.value)}
            placeholder="Overall expectations for this role…"
          />
        </FormField>
        <div className="mt-4 space-y-3">
          <div className="flex items-center justify-between gap-2">
            <span className="text-meta font-medium text-[var(--color-text-main)]">
              Expectation boxes
            </span>
            <Button size="sm" variant="secondary" onClick={() => setBoxes((prev) => [...prev, newBox()])}>
              Add box
            </Button>
          </div>
          {boxes.length === 0 ? (
            <EmptyState
              title="No boxes yet"
              body="Add boxes for specific expectations (title + detail)."
            />
          ) : (
            <ul className="space-y-3">
              {boxes.map((box) => (
                <li
                  key={box.id}
                  className="rounded-[10px] border border-[var(--color-chrome-stroke)] p-3"
                >
                  <FormField label="Title">
                    <input
                      className={fieldControlClass}
                      value={box.title}
                      onChange={(e) => updateBox(box.id, { title: e.target.value })}
                      placeholder="Manager support, ramp timeline…"
                    />
                  </FormField>
                  <FormField label="Body">
                    <textarea
                      className={`${fieldControlClass} mt-2`}
                      rows={3}
                      value={box.body}
                      onChange={(e) => updateBox(box.id, { body: e.target.value })}
                      placeholder="What you expect and how you'll measure it…"
                    />
                  </FormField>
                  <div className="mt-2 flex justify-end">
                    <Button size="sm" variant="ghost" onClick={() => removeBox(box.id)}>
                      Remove
                    </Button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
        <div className="mt-4">
          <Button size="sm" disabled={busy} onClick={() => void save()}>
            Save expectations
          </Button>
        </div>
      </AppCard>
    </div>
  );
}
