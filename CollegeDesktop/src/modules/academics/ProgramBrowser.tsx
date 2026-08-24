import { useCallback, useEffect, useState } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  StatusChip,
} from "@/design-system";
import { ipc, formatIpcError, type ProgramDetail, type ProgramSummary } from "@/lib/ipc";
import { showToast } from "@/lib/toast";

export function ProgramBrowser({ onActiveChanged }: { onActiveChanged?: () => void }) {
  const [programs, setPrograms] = useState<ProgramSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<ProgramDetail | null>(null);
  const [busy, setBusy] = useState(false);

  const loadPrograms = useCallback(async () => {
    const rows = await ipc.academicsListPrograms();
    setPrograms(rows);
    const active = rows.find((row) => row.isActive);
    setSelectedId((prev) => prev ?? active?.id ?? rows[0]?.id ?? null);
  }, []);

  useEffect(() => {
    void loadPrograms().catch((err) => showToast(formatIpcError(err), "error"));
  }, [loadPrograms]);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      return;
    }
    void ipc
      .academicsGetProgramDetail(selectedId)
      .then(setDetail)
      .catch((err) => showToast(formatIpcError(err), "error"));
  }, [selectedId]);

  const setActive = async (programId: string) => {
    setBusy(true);
    try {
      await ipc.academicsSetActiveProgram(programId);
      await loadPrograms();
      const next = await ipc.academicsGetProgramDetail(programId);
      setDetail(next);
      setSelectedId(programId);
      showToast("Active program updated", "success");
      onActiveChanged?.();
    } catch (err) {
      showToast(formatIpcError(err), "error");
    } finally {
      setBusy(false);
    }
  };

  const activeProgram = programs.find((row) => row.isActive);

  return (
    <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
      <AppCard title="Programs">
        <p className="mb-3 text-[12px] text-[var(--color-text-light)]">
          {activeProgram
            ? `${activeProgram.name} (${activeProgram.degreeType}) is active`
            : "Pick a major or minor to scope the audit"}
        </p>
        {programs.length === 0 ? (
          <EmptyState
            title="No programs"
            body="Load sample data from Settings or ingest catalog requirements."
          />
        ) : (
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {programs.map((program) => (
              <li key={program.id}>
                <button
                  type="button"
                  className="w-full text-left"
                  onClick={() => setSelectedId(program.id)}
                >
                  <ListRow
                    title={`${program.name} · ${program.degreeType}`}
                    subtitle={`${program.universityName} · ${program.sectionCount} sections`}
                    trailing={
                      <div className="flex items-center gap-2">
                        {program.isActive ? (
                          <StatusChip title="Active" tint="var(--color-success)" filled />
                        ) : null}
                        {selectedId === program.id ? (
                          <StatusChip title="Selected" tint="var(--color-primary)" />
                        ) : null}
                      </div>
                    }
                  />
                </button>
              </li>
            ))}
          </ul>
        )}
      </AppCard>

      <AppCard title={detail ? `${detail.name} requirements` : "Program detail"}>
        {detail ? (
          <p className="mb-3 text-[12px] text-[var(--color-text-light)]">
            {detail.universityName} · {detail.degreeType}
          </p>
        ) : null}
        {!detail ? (
          <EmptyState title="Select a program" body="Choose a major or minor to inspect sections." />
        ) : (
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              {detail.isActive ? (
                <StatusChip title="Active audit scope" tint="var(--color-success)" filled />
              ) : (
                <Button size="sm" disabled={busy} onClick={() => void setActive(detail.id)}>
                  Set active program
                </Button>
              )}
              {detail.programUrl ? (
                <a
                  href={detail.programUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="text-[12px] text-[var(--color-primary)] underline-offset-2 hover:underline"
                >
                  Catalog page
                </a>
              ) : null}
            </div>
            {detail.requirements.length === 0 ? (
              <EmptyState title="No sections" body="This program has no requirement rows yet." />
            ) : (
              <ul className="space-y-2">
                {detail.requirements.map((req) => (
                  <li
                    key={req.id}
                    className="rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2.5"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <div className="text-[13px] font-semibold text-[var(--color-text-main)]">
                          {req.sectionTitle}
                        </div>
                        {req.ruleCodes.length > 0 ? (
                          <div className="mt-0.5 text-[11px] text-[var(--color-text-light)]">
                            {req.ruleCodes.join(", ")}
                          </div>
                        ) : null}
                      </div>
                      {req.creditsRequired != null ? (
                        <span className="shrink-0 text-[11px] tabular-nums text-[var(--color-text-light)]">
                          {req.creditsRequired} cr
                        </span>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </AppCard>
    </div>
  );
}
