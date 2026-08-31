import { useCallback, useEffect, useMemo, useState } from "react";
import { AppCard, Button, EmptyState, FormField, ListRow, fieldControlClass } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDanger, confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";

type PathEntryOption = {
  id: string;
  organization: string;
  roleTitle: string;
};

type RelationshipRow = {
  id: string;
  fromEntryId: string;
  toEntryId: string;
  kind: string;
  notes: string;
  createdAt: string;
  linkedEntryId: string;
  linkedOrganization: string;
  linkedRoleTitle: string;
  direction: string;
};

type Props = {
  entryId: string;
  pathEntries: PathEntryOption[];
  onMerged: (targetId: string) => void;
};

const relationshipKinds = ["related", "promotion", "transfer", "rehire", "merged"] as const;

const kindLabels: Record<(typeof relationshipKinds)[number], string> = {
  related: "Related",
  promotion: "Promotion",
  transfer: "Transfer",
  rehire: "Rehire",
  merged: "Merged",
};

export function PathingRelatedPanel({ entryId, pathEntries, onMerged }: Props) {
  const [relationships, setRelationships] = useState<RelationshipRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [pickerId, setPickerId] = useState("");
  const [pickerKind, setPickerKind] = useState<(typeof relationshipKinds)[number]>("related");
  const [pickerNotes, setPickerNotes] = useState("");

  const reload = useCallback(async () => {
    const rows = await ipc.careerListPathRelationships(entryId);
    setRelationships(rows);
  }, [entryId]);

  useEffect(() => {
    void reload().catch(() => setRelationships([]));
  }, [reload]);

  const linkableEntries = useMemo(
    () =>
      pathEntries.filter(
        (e) =>
          e.id !== entryId &&
          !relationships.some(
            (r) => r.linkedEntryId === e.id && r.kind === pickerKind,
          ),
      ),
    [pathEntries, entryId, relationships, pickerKind],
  );

  const addLink = async () => {
    if (!pickerId) {
      showToast("Choose an entry to link", "error");
      return;
    }
    setBusy(true);
    try {
      await ipc.careerUpsertPathRelationship({
        fromEntryId: entryId,
        toEntryId: pickerId,
        kind: pickerKind,
        notes: pickerNotes,
      });
      setPickerId("");
      setPickerNotes("");
      await reload();
      showToast("Entry linked", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const deleteLink = async (row: RelationshipRow) => {
    if (!confirmDelete(`${row.linkedRoleTitle || row.linkedOrganization}`)) return;
    setBusy(true);
    try {
      await ipc.careerDeletePathRelationship(row.id);
      await reload();
      showToast("Link removed", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const mergeInto = async (targetId: string, label: string) => {
    const source = pathEntries.find((e) => e.id === entryId);
    const sourceLabel = source
      ? `${source.roleTitle || "Role"} @ ${source.organization || "Org"}`
      : "this entry";
    if (
      !confirmDanger(
        `Merge ${sourceLabel} into “${label}”?\n\nMilestones and journal entries move to the target. The source entry is deleted.`,
      )
    ) {
      return;
    }
    setBusy(true);
    try {
      await ipc.careerMergePathEntries(entryId, targetId);
      showToast("Entries merged", "success");
      onMerged(targetId);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-3">
      <AppCard title="Related entries">
        <p className="mb-3 text-meta">
          Link promotions, transfers, or related roles. Merge duplicates into a canonical entry.
        </p>
        {relationships.length === 0 ? (
          <EmptyState title="No linked entries" body="Add a related path entry below." />
        ) : (
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {relationships.map((row) => {
              const label = [row.linkedRoleTitle, row.linkedOrganization]
                .filter(Boolean)
                .join(" · ");
              return (
                <li key={row.id} className="py-1">
                  <ListRow
                    title={label || "Untitled entry"}
                    subtitle={[
                      kindLabels[row.kind as (typeof relationshipKinds)[number]] ?? row.kind,
                      row.direction === "incoming" ? "Incoming" : "Outgoing",
                      row.notes.trim() || null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                    trailing={
                      <div className="flex shrink-0 gap-1">
                        {row.kind !== "merged" && row.linkedEntryId !== entryId ? (
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={busy}
                            onClick={() =>
                              void mergeInto(row.linkedEntryId, label || "target entry")
                            }
                          >
                            Merge into
                          </Button>
                        ) : null}
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy}
                          onClick={() => void deleteLink(row)}
                        >
                          Remove
                        </Button>
                      </div>
                    }
                  />
                </li>
              );
            })}
          </ul>
        )}
      </AppCard>

      <AppCard title="Add link">
        <div className="space-y-3">
          <FormField label="Path entry">
            <select
              className={fieldControlClass}
              value={pickerId}
              onChange={(e) => setPickerId(e.target.value)}
            >
              <option value="">Select entry…</option>
              {linkableEntries.map((e) => (
                <option key={e.id} value={e.id}>
                  {[e.roleTitle, e.organization].filter(Boolean).join(" @ ") || e.id}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Kind">
            <select
              className={fieldControlClass}
              value={pickerKind}
              onChange={(e) =>
                setPickerKind(e.target.value as (typeof relationshipKinds)[number])
              }
            >
              {relationshipKinds
                .filter((k) => k !== "merged")
                .map((k) => (
                  <option key={k} value={k}>
                    {kindLabels[k]}
                  </option>
                ))}
            </select>
          </FormField>
          <FormField label="Notes">
            <input
              className={fieldControlClass}
              value={pickerNotes}
              onChange={(e) => setPickerNotes(e.target.value)}
              placeholder="Optional context…"
            />
          </FormField>
          <Button size="sm" disabled={busy || !pickerId} onClick={() => void addLink()}>
            Link entry
          </Button>
        </div>
      </AppCard>
    </div>
  );
}
