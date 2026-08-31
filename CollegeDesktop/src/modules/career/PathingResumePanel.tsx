import { useEffect, useMemo, useState } from "react";
import { AppCard, Button, EmptyState, FormField, fieldControlClass } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";

type VaultDoc = {
  id: string;
  title: string;
  category: string;
  hasFile: boolean;
};

type Props = {
  entryId: string;
  resumeDocumentId?: string | null;
  vaultDocs: VaultDoc[];
  onSaved: (resumeDocumentId: string | null) => void;
};

export function PathingResumePanel({
  entryId,
  resumeDocumentId,
  vaultDocs,
  onSaved,
}: Props) {
  const [selectedId, setSelectedId] = useState(resumeDocumentId ?? "");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setSelectedId(resumeDocumentId ?? "");
  }, [resumeDocumentId, entryId]);

  const resumeDocs = useMemo(
    () =>
      vaultDocs.filter(
        (d) => d.category === "resume" || d.title.toLowerCase().includes("resume"),
      ),
    [vaultDocs],
  );

  const save = async () => {
    setBusy(true);
    try {
      const next = selectedId.trim() || null;
      await ipc.careerSetPathResume(entryId, next);
      onSaved(next);
      showToast("Resume linked to path entry", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const clear = async () => {
    setSelectedId("");
    setBusy(true);
    try {
      await ipc.careerSetPathResume(entryId, null);
      onSaved(null);
      showToast("Resume link cleared", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  return (
    <AppCard title="Resume">
      <p className="mb-3 text-meta">
        Choose the vault resume document associated with this path entry.
      </p>
      {resumeDocs.length === 0 ? (
        <EmptyState
          title="No resume documents"
          body="Import or create a resume in Documents (category: resume)."
        />
      ) : (
        <FormField label="Resume document">
          <select
            className={fieldControlClass}
            value={selectedId}
            onChange={(e) => setSelectedId(e.target.value)}
          >
            <option value="">None</option>
            {resumeDocs.map((doc) => (
              <option key={doc.id} value={doc.id}>
                {doc.title}
                {!doc.hasFile ? " (no file)" : ""}
              </option>
            ))}
          </select>
        </FormField>
      )}
      <div className="mt-3 flex flex-wrap gap-2">
        <Button size="sm" disabled={busy || resumeDocs.length === 0} onClick={() => void save()}>
          Save
        </Button>
        {resumeDocumentId ? (
          <Button size="sm" variant="ghost" disabled={busy} onClick={() => void clear()}>
            Clear
          </Button>
        ) : null}
      </div>
    </AppCard>
  );
}
