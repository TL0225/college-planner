import { useCallback, useMemo, useState } from "react";
import { Upload } from "lucide-react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  MetricTile,
  ModalSheet,
  ProgressBar,
  SegmentedPills,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";

const SAMPLE_TRANSFER_SOURCE = "Community College";

type Eq = {
  id: string;
  sourceSchool: string;
  sourceCode: string;
  targetCode: string;
  credits?: number | null;
  notes: string;
  proofDocumentId?: string | null;
};

type AuditItem = {
  missingCodes: string[];
};

function parseEquivalencyCsv(text: string): Array<{
  sourceSchool: string;
  sourceCode: string;
  targetCode: string;
  credits?: number;
  notes?: string;
}> {
  const rows: Array<{
    sourceSchool: string;
    sourceCode: string;
    targetCode: string;
    credits?: number;
    notes?: string;
  }> = [];

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const parts = line.includes("\t")
      ? line.split("\t").map((p) => p.trim())
      : line.split(",").map((p) => p.trim());
    if (parts.length < 3) continue;
    const [sourceSchool, sourceCode, targetCode, creditsRaw, ...noteParts] = parts;
    const credits = creditsRaw ? Number(creditsRaw) : undefined;
    rows.push({
      sourceSchool,
      sourceCode,
      targetCode,
      credits: credits != null && !Number.isNaN(credits) ? credits : undefined,
      notes: noteParts.join(",").trim() || undefined,
    });
  }
  return rows;
}

function countBlocksRemaining(audit: { items: AuditItem[] } | null): number {
  if (!audit) return 0;
  const codes = new Set<string>();
  for (const item of audit.items) {
    for (const code of item.missingCodes) {
      codes.add(code);
    }
  }
  return codes.size;
}

export function TransferModule() {
  const [rows, setRows] = useState<Eq[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [form, setForm] = useState({
    sourceSchool: "",
    sourceCode: "",
    targetCode: "",
    credits: 3,
    notes: "",
  });
  const [auditProgress, setAuditProgress] = useState<number | null>(null);
  const [completedCredits, setCompletedCredits] = useState<number | null>(null);
  const [blocksRemaining, setBlocksRemaining] = useState(0);
  const [importOpen, setImportOpen] = useState(false);
  const [importText, setImportText] = useState("");
  const [importMode, setImportMode] = useState<"csv" | "community">("csv");
  const [dataMode, setDataMode] = useState<"live" | "sample">("live");
  const [vaultDocs, setVaultDocs] = useState<Array<{ id: string; title: string }>>([]);
  const [assistOpen, setAssistOpen] = useState(false);
  const [assistForm, setAssistForm] = useState({
    sourceSchoolId: "de_anza_college",
    targetSchoolId: "uc_berkeley",
    mode: "fixture" as "fixture" | "live" | "scrape",
  });

  const load = useCallback(async () => {
    const [eq, audit, summary, docs] = await Promise.all([
      ipc.transferListEquivalencies(),
      ipc.academicsGetRequirementAudit().catch(() => null),
      ipc.academicsGetAuditSummary().catch(() => null),
      ipc.documentsListVault().catch(() => []),
    ]);
    setRows(eq);
    setVaultDocs(docs.filter((d) => !d.isFolder).map((d) => ({ id: d.id, title: d.title || "Document" })));
    setAuditProgress(audit?.progressRatio ?? null);
    setCompletedCredits(summary?.completedCredits ?? null);
    setBlocksRemaining(countBlocksRemaining(audit));
  }, []);

  const { refresh, error } = useLiveQuery(load, ["transfer"]);
  const selectedRow = rows.find((r) => r.id === selected) ?? null;

  const displayRows = useMemo(() => {
    if (dataMode === "sample") {
      return rows.filter((r) => r.sourceSchool === SAMPLE_TRANSFER_SOURCE);
    }
    return rows;
  }, [rows, dataMode]);

  const transferCredits = useMemo(
    () => displayRows.reduce((sum, r) => sum + (r.credits ?? 0), 0),
    [displayRows],
  );

  const uniqueSchools = useMemo(
    () => new Set(displayRows.map((r) => r.sourceSchool)).size,
    [displayRows],
  );

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title="Transfer"
        subtitle={
          blocksRemaining > 0
            ? `${blocksRemaining} block${blocksRemaining === 1 ? "" : "s"} remaining in degree audit`
            : undefined
        }
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <SegmentedPills
              value={dataMode}
              onChange={setDataMode}
              options={[
                { id: "live", label: "Live" },
                { id: "sample", label: "Sample" },
              ]}
            />
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setAssistOpen(true)}>
              ASSIST
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setImportOpen(true)}>
              <Upload size={14} />
              Import
            </Button>
            <Button size="sm" onClick={() => setSheetOpen(true)}>
              Add equivalency
            </Button>
          </div>
        }
      />
      {error && <p className="px-3 text-meta text-[var(--color-error)]">{error}</p>}
      {dataMode === "sample" && (
        <AppCard className="mx-3 mb-2" title="Sample transfer data">
          <p className="mb-2 text-meta">
            Showing demo equivalencies from {SAMPLE_TRANSFER_SOURCE}. Load sample rows to explore
            degree impact, or switch to Live for your own mappings.
          </p>
          {rows.filter((r) => r.sourceSchool === SAMPLE_TRANSFER_SOURCE).length === 0 && (
            <Button
              size="sm"
              onClick={() =>
                void ipc
                  .demoSeedSampleData()
                  .then(() => {
                    showToast("Sample transfer rows loaded", "success");
                    return refresh();
                  })
                  .catch((e) => showToast(formatIpcError(e), "error"))
              }
            >
              Load sample equivalencies
            </Button>
          )}
        </AppCard>
      )}
      <div className="grid shrink-0 gap-2.5 px-3 pb-1 sm:grid-cols-4">
        <MetricTile label="Equivalencies" value={displayRows.length} accent="var(--color-primary)" />
        <MetricTile label="Transfer credits" value={transferCredits.toFixed(1)} accent="var(--color-warning)" />
        <MetricTile label="Source schools" value={uniqueSchools} />
        <MetricTile
          label="Blocks remaining"
          value={blocksRemaining}
          accent={blocksRemaining > 0 ? "var(--color-error)" : "var(--color-success)"}
        />
      </div>
      <AppCard className="mx-3 mb-2" title="Degree impact">
        <p className="mb-2 text-meta">
          Mapped transfer credits ({transferCredits.toFixed(1)} cr) apply toward your local degree
          audit alongside {completedCredits?.toFixed(1) ?? "0"} completed planner credits.
        </p>
        {auditProgress != null && <ProgressBar value={auditProgress} height={8} />}
      </AppCard>
      <div className="min-h-0 flex-1 p-3 pt-1">
        <TrailingInspector
          open={!!selectedRow}
          main={
            <AppCard title={`Equivalencies · ${displayRows.length}`}>
              {displayRows.length === 0 ? (
                <EmptyState
                  title={dataMode === "sample" ? "No sample equivalencies" : "No equivalencies"}
                  body={
                    dataMode === "sample"
                      ? "Load sample data from Settings or switch to Live to see your own rows."
                      : "Map transfer courses to local catalog codes, or load sample data from Settings."
                  }
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {displayRows.map((r) => (
                    <li key={r.id}>
                      <ListRow
                        selected={selected === r.id}
                        onClick={() => setSelected(r.id)}
                        title={r.sourceSchool}
                        subtitle={
                          <span className="inline-flex flex-wrap items-center gap-1.5">
                            <StatusChip title={r.sourceCode} tint="var(--color-warning)" filled />
                            <span className="text-label">→</span>
                            <StatusChip title={r.targetCode} tint="var(--color-primary)" filled />
                          </span>
                        }
                        trailing={
                          r.credits != null ? (
                            <StatusChip title={`${r.credits} cr`} />
                          ) : undefined
                        }
                      />
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
          }
        >
          {selectedRow && (
            <div className="flex h-full flex-col">
              <div
                className="border-b border-[var(--color-chrome-stroke)] px-4 py-3"
                style={{
                  background:
                    "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 8%, transparent), transparent)",
                }}
              >
                <p className="text-meta">
                  {selectedRow.sourceSchool}
                </p>
                <div className="mt-2 flex flex-wrap items-center gap-1.5">
                  <StatusChip
                    title={selectedRow.sourceCode}
                    tint="var(--color-warning)"
                    filled
                  />
                  <span className="text-caption">maps to</span>
                  <StatusChip
                    title={selectedRow.targetCode}
                    tint="var(--color-primary)"
                    filled
                  />
                </div>
                {selectedRow.credits != null && (
                  <div className="mt-2">
                    <StatusChip title={`${selectedRow.credits} credits`} />
                  </div>
                )}
              </div>
              <div className="min-h-0 flex-1 overflow-auto p-4">
                <p className="text-label font-semibold uppercase tracking-[0.05em]">
                  Notes
                </p>
                <p className="mt-1.5 text-meta leading-relaxed text-[var(--color-text-main)]">
                  {selectedRow.notes || "No notes for this equivalency."}
                </p>
                <div className="mt-4">
                  <p className="text-label font-semibold uppercase tracking-[0.05em]">
                    Proof document
                  </p>
                  <select
                    className={`${fieldControlClass} mt-1.5`}
                    value={selectedRow.proofDocumentId ?? ""}
                    onChange={async (e) => {
                      const next = e.target.value || null;
                      try {
                        await ipc.transferLinkProofDocument(selectedRow.id, next);
                        setRows((prev) =>
                          prev.map((r) =>
                            r.id === selectedRow.id ? { ...r, proofDocumentId: next } : r,
                          ),
                        );
                        showToast(next ? "Proof linked" : "Proof cleared", "success");
                      } catch (err) {
                        showToast(formatIpcError(err), "error");
                      }
                    }}
                  >
                    <option value="">None</option>
                    {vaultDocs.map((d) => (
                      <option key={d.id} value={d.id}>
                        {d.title}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
              <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                <Button size="sm" variant="ghost" onClick={() => setSelected(null)}>
                  Close
                </Button>
                <Button
                  size="sm"
                  variant="danger"
                  onClick={async () => {
                    if (
                      !confirmDelete(
                        `${selectedRow.sourceCode} → ${selectedRow.targetCode}`,
                      )
                    )
                      return;
                    try {
                      await ipc.transferDeleteEquivalency(selectedRow.id);
                      setSelected(null);
                      showToast("Equivalency deleted", "success");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Delete
                </Button>
              </div>
            </div>
          )}
        </TrailingInspector>
      </div>

      <ModalSheet open={sheetOpen} onOpenChange={setSheetOpen} title="Add equivalency">
        <div className="space-y-3">
          <FormField label="Source school">
            <input
              className={fieldControlClass}
              value={form.sourceSchool}
              onChange={(e) => setForm({ ...form, sourceSchool: e.target.value })}
            />
          </FormField>
          <FormField label="Source code">
            <input
              className={fieldControlClass}
              value={form.sourceCode}
              onChange={(e) => setForm({ ...form, sourceCode: e.target.value })}
              placeholder="CSC 110"
            />
          </FormField>
          <FormField label="Target code">
            <input
              className={fieldControlClass}
              value={form.targetCode}
              onChange={(e) => setForm({ ...form, targetCode: e.target.value })}
              placeholder="CS 101"
            />
          </FormField>
          <FormField label="Credits">
            <input
              className={fieldControlClass}
              type="number"
              value={form.credits}
              onChange={(e) => setForm({ ...form, credits: Number(e.target.value) })}
            />
          </FormField>
          <FormField label="Notes">
            <input
              className={fieldControlClass}
              value={form.notes}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
            />
          </FormField>
          <Button
            disabled={
              !form.sourceSchool.trim() ||
              !form.sourceCode.trim() ||
              !form.targetCode.trim()
            }
            onClick={async () => {
              try {
                await ipc.transferUpsertEquivalency({
                  sourceSchool: form.sourceSchool.trim(),
                  sourceCode: form.sourceCode.trim(),
                  targetCode: form.targetCode.trim(),
                  credits: form.credits,
                  notes: form.notes.trim() || undefined,
                });
                setSheetOpen(false);
                setForm({
                  sourceSchool: "",
                  sourceCode: "",
                  targetCode: "",
                  credits: 3,
                  notes: "",
                });
                showToast("Equivalency saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={importOpen}
        onOpenChange={setImportOpen}
        title="Import equivalencies"
      >
        <div className="space-y-3">
          <SegmentedPills
            value={importMode}
            onChange={setImportMode}
            options={[
              { id: "csv", label: "CSV rows" },
              { id: "community", label: "Community JSON" },
            ]}
          />
          {importMode === "csv" ? (
            <>
              <p className="text-meta leading-relaxed">
                Paste one row per line:{" "}
                <code className="text-caption">source school, source code, target code, credits, notes</code>
                . Comma or tab separated. Lines starting with # are ignored.
              </p>
              <FormField label="CSV rows">
                <textarea
                  className={fieldControlClass}
                  rows={8}
                  value={importText}
                  onChange={(e) => setImportText(e.target.value)}
                  placeholder={`Community College, CSC 110, CS 101, 3, Intro programming\nState U, MATH 201, MATH 220, 4`}
                />
              </FormField>
              <Button
                disabled={!importText.trim()}
                onClick={async () => {
                  const rows = parseEquivalencyCsv(importText);
                  if (rows.length === 0) {
                    showToast(
                      "No valid rows found — need at least source school, source code, target code",
                      "error",
                    );
                    return;
                  }
                  try {
                    const result = await ipc.transferImportEquivalencies(rows);
                    setImportOpen(false);
                    setImportText("");
                    showToast(
                      `Imported ${result.imported} equivalenc${result.imported === 1 ? "y" : "ies"}${
                        result.skipped > 0 ? ` (${result.skipped} skipped)` : ""
                      }`,
                      "success",
                    );
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Import rows
              </Button>
            </>
          ) : (
            <>
              <p className="text-meta leading-relaxed">
                Paste community equivalency JSON — an array of rows or{" "}
                <code className="text-caption">{`{ "equivalencies": [...] }`}</code>.
              </p>
              <FormField label="Community JSON">
                <textarea
                  className={fieldControlClass}
                  rows={8}
                  value={importText}
                  onChange={(e) => setImportText(e.target.value)}
                  placeholder={`{\n  "equivalencies": [\n    { "sourceSchool": "CC", "sourceCode": "CSC 110", "targetCode": "CS 101", "credits": 3 }\n  ]\n}`}
                />
              </FormField>
              <Button
                disabled={!importText.trim()}
                onClick={async () => {
                  try {
                    const result = await ipc.transferImportCommunityJson(importText);
                    setImportOpen(false);
                    setImportText("");
                    showToast(
                      `Imported ${result.imported} equivalenc${result.imported === 1 ? "y" : "ies"}${
                        result.skipped > 0 ? ` (${result.skipped} skipped)` : ""
                      }`,
                      "success",
                    );
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Import JSON
              </Button>
            </>
          )}
        </div>
      </ModalSheet>

      <ModalSheet open={assistOpen} onOpenChange={setAssistOpen} title="Import from ASSIST">
        <div className="space-y-3">
          <p className="text-meta leading-relaxed">
            Import articulation agreements from bundled fixtures, a community mirror, or live
            ASSIST.org scraping. School IDs can be numeric (e.g. <code>110</code>) or slugs like{" "}
            <code>de_anza_college</code> — scrape mode resolves slugs via the ASSIST institution
            hierarchy before calling the API.
          </p>
          <FormField label="Source school ID">
            <input
              className={fieldControlClass}
              value={assistForm.sourceSchoolId}
              onChange={(e) => setAssistForm((f) => ({ ...f, sourceSchoolId: e.target.value }))}
              placeholder="de_anza_college"
            />
          </FormField>
          <FormField label="Target school ID">
            <input
              className={fieldControlClass}
              value={assistForm.targetSchoolId}
              onChange={(e) => setAssistForm((f) => ({ ...f, targetSchoolId: e.target.value }))}
              placeholder="uc_berkeley"
            />
          </FormField>
          <SegmentedPills
            value={assistForm.mode}
            onChange={(mode) => setAssistForm((f) => ({ ...f, mode }))}
            options={[
              { id: "fixture", label: "Fixture" },
              { id: "live", label: "Mirror" },
              { id: "scrape", label: "Scrape" },
            ]}
          />
          <Button
            onClick={async () => {
              try {
                const result = await ipc.transferImportAssist({
                  sourceSchoolId: assistForm.sourceSchoolId.trim(),
                  targetSchoolId: assistForm.targetSchoolId.trim(),
                  mode: assistForm.mode,
                });
                setAssistOpen(false);
                showToast(
                  `ASSIST import: ${result.imported} equivalenc${result.imported === 1 ? "y" : "ies"}`,
                  "success",
                );
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Import ASSIST rows
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}
