import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  ListRow,
  MetricTile,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import type { ResumeProfileTailoring } from "../buildResumeMarkdown";
import { ResumeLiveBuilder } from "../ResumeLiveBuilder";

export type CareerVaultDocRow = {
  id: string;
  title: string;
  category: string;
  mimeType: string;
  fileSize: number;
  updatedAt: string;
  relativePath: string;
  hasFile: boolean;
};

export type CareerResumeProfileRow = {
  id: string;
  vaultDocId: string;
  targetRole: string;
  targetCompany: string;
  notes: string;
  updatedAt: string;
};

export type CareerResumeMetrics = {
  vaultResumeCount: number;
  profilesWithNotesCount: number;
  lastMatchScore?: number | null;
};

export type CareerTailoringForm = {
  targetRole: string;
  targetCompany: string;
  notes: string;
};

export type CareerKeywordMatchResult = {
  score: number;
  matched: string[];
  missing: string[];
};

const ATS_KEYWORD_PRESETS: Record<string, string> = {
  Software:
    "python javascript typescript java react node sql git agile scrum api rest microservices docker kubernetes aws azure ci cd testing debugging object oriented design algorithms data structures",
  Data:
    "python sql pandas numpy scipy machine learning statistics regression classification tableau power bi etl data visualization spark hadoop modeling analytics dashboard stakeholder",
  Finance:
    "excel financial modeling valuation dcf lbo m and a accounting gaap ifrs bloomberg capital markets equity research portfolio risk compliance forecasting budgeting presentation",
};

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function mimeLabel(mime: string, hasFile: boolean): string {
  if (!hasFile) return "Note";
  const m = mime.toLowerCase();
  if (m.includes("pdf")) return "PDF";
  if (m.includes("image")) return "Image";
  if (m.includes("word") || m.includes("msword") || m.includes("officedocument.word")) return "Doc";
  if (m.includes("text")) return "Text";
  if (m) return mime.split("/").pop()?.toUpperCase() || "File";
  return "File";
}

function categoryTint(category: string): string {
  switch (category) {
    case "syllabus":
      return "var(--color-primary)";
    case "transcript":
      return "var(--color-success)";
    case "resume":
      return "var(--color-warning)";
    case "receipt":
      return "#0ea5e9";
    case "general":
      return "var(--color-text-light)";
    default:
      return "var(--color-primary)";
  }
}

function profileHasNotes(p: CareerResumeProfileRow): boolean {
  return Boolean(p.targetRole.trim() || p.targetCompany.trim() || p.notes.trim());
}

function resumeProfileSubtitle(
  doc: CareerVaultDocRow,
  profile: CareerResumeProfileRow | undefined,
): string {
  const parts: string[] = [];
  if (profile?.targetRole.trim()) parts.push(profile.targetRole.trim());
  if (profile?.targetCompany.trim()) parts.push(`@ ${profile.targetCompany.trim()}`);
  if (parts.length) return parts.join(" ");
  if (doc.hasFile) {
    return `${formatBytes(doc.fileSize)} · ${new Date(doc.updatedAt).toLocaleDateString()}`;
  }
  return "Metadata only";
}

export type CareerResumesViewProps = {
  resumeMetrics: CareerResumeMetrics | null;
  resumeLibrary: CareerVaultDocRow[];
  resumeProfileByVaultId: Map<string, CareerResumeProfileRow>;
  builderLoadNonce: number;
  includeBragInDraft: boolean;
  builderTailoring: ResumeProfileTailoring | null;
  selectedResumeId: string | null;
  selectedResume: CareerVaultDocRow | null;
  selectedResumeProfile: CareerResumeProfileRow | undefined;
  tailoringForm: CareerTailoringForm;
  tailoringBusy: boolean;
  resumeText: string;
  jobText: string;
  matchBusy: boolean;
  matchResult: CareerKeywordMatchResult | null;
  onIncludeBragBookChange: (value: boolean) => void;
  onDraftOutputsChange: (outputs: { markdown: string; typst: string }) => void;
  onOpenSourceSheet: () => void;
  onSelectResume: (id: string) => void;
  onClearResumeSelection: () => void;
  onTailoringFormChange: (form: CareerTailoringForm) => void;
  onSaveTailoringNotes: () => void | Promise<void>;
  onOpenResume: () => void | Promise<void>;
  onRevealResume: () => void | Promise<void>;
  onResumeTextChange: (value: string) => void;
  onJobTextChange: (value: string) => void;
  onMatchKeywords: () => void | Promise<void>;
};

export function CareerResumesView({
  resumeMetrics,
  resumeLibrary,
  resumeProfileByVaultId,
  builderLoadNonce,
  includeBragInDraft,
  builderTailoring,
  selectedResumeId,
  selectedResume,
  selectedResumeProfile,
  tailoringForm,
  tailoringBusy,
  resumeText,
  jobText,
  matchBusy,
  matchResult,
  onIncludeBragBookChange,
  onDraftOutputsChange,
  onOpenSourceSheet,
  onSelectResume,
  onClearResumeSelection,
  onTailoringFormChange,
  onSaveTailoringNotes,
  onOpenResume,
  onRevealResume,
  onResumeTextChange,
  onJobTextChange,
  onMatchKeywords,
}: CareerResumesViewProps) {
  return (
    <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3">
      <div className="grid gap-2.5 sm:grid-cols-3">
        <MetricTile
          label="Vault resumes"
          value={resumeMetrics?.vaultResumeCount ?? resumeLibrary.length}
          accent="var(--color-primary)"
        />
        <MetricTile
          label="Tailored profiles"
          value={resumeMetrics?.profilesWithNotesCount ?? 0}
          accent="var(--color-warning)"
        />
        <MetricTile
          label="Last match"
          value={
            resumeMetrics?.lastMatchScore != null
              ? `${(resumeMetrics.lastMatchScore * 100).toFixed(0)}%`
              : "—"
          }
          accent="var(--color-success)"
        />
      </div>
      <ResumeLiveBuilder
        loadNonce={builderLoadNonce}
        includeBragBook={includeBragInDraft}
        onIncludeBragBookChange={onIncludeBragBookChange}
        tailoring={builderTailoring}
        onDraftOutputsChange={onDraftOutputsChange}
        onOpenSourceSheet={onOpenSourceSheet}
      />
      <div className="min-h-[220px]">
        <TrailingInspector
          open={!!selectedResume}
          main={
            <AppCard title="Resume library">
              {resumeLibrary.length === 0 ? (
                <EmptyState
                  title="No resumes in vault"
                  body="Import a PDF or DOC under Documents → Vault (set category to resume), or load sample data from Settings → Sample data. You can still paste resume text in Keyword match below."
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {resumeLibrary.map((d) => {
                    const profile = resumeProfileByVaultId.get(d.id);
                    return (
                      <li key={d.id}>
                        <ListRow
                          selected={selectedResumeId === d.id}
                          onClick={() => onSelectResume(d.id)}
                          leading={
                            <span
                              className="flex h-8 w-8 shrink-0 items-center justify-center text-caption font-bold tracking-wide"
                              style={{
                                borderRadius: 8,
                                border: "1px solid var(--color-chrome-stroke)",
                                background: `color-mix(in srgb, ${categoryTint(d.category)} 12%, var(--color-surface))`,
                                color: categoryTint(d.category),
                              }}
                            >
                              {mimeLabel(d.mimeType, d.hasFile).slice(0, 4)}
                            </span>
                          }
                          title={d.title || "Untitled"}
                          subtitle={resumeProfileSubtitle(d, profile)}
                          trailing={
                            <div className="flex flex-wrap items-center justify-end gap-1">
                              {profile && profileHasNotes(profile) ? (
                                <StatusChip title="Tailored" tint="var(--color-primary)" filled />
                              ) : null}
                              <StatusChip
                                title={d.category}
                                tint={categoryTint(d.category)}
                                filled
                              />
                              <StatusChip title={mimeLabel(d.mimeType, d.hasFile)} />
                            </div>
                          }
                        />
                      </li>
                    );
                  })}
                </ul>
              )}
            </AppCard>
          }
        >
          {selectedResume && (
            <div className="flex h-full flex-col">
              <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
                <h3
                  className="text-[var(--color-text-main)]"
                  style={{
                    font: "var(--type-section-title)",
                    fontSize: 16,
                    letterSpacing: "-0.02em",
                  }}
                >
                  {selectedResume.title || "Untitled"}
                </h3>
                <p className="mt-0.5 text-meta">
                  Updated {new Date(selectedResume.updatedAt).toLocaleString()}
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  <StatusChip
                    title={selectedResume.category}
                    tint={categoryTint(selectedResume.category)}
                    filled
                  />
                  <StatusChip
                    title={mimeLabel(selectedResume.mimeType, selectedResume.hasFile)}
                  />
                  {selectedResume.hasFile ? (
                    <StatusChip title={formatBytes(selectedResume.fileSize)} />
                  ) : (
                    <StatusChip title="No file" tint="var(--color-warning)" filled />
                  )}
                </div>
              </div>
              <div className="min-h-0 flex-1 space-y-3 overflow-auto p-4">
                <div>
                  <p className="text-label font-semibold uppercase tracking-[0.06em]">
                    File
                  </p>
                  <p className="mt-1 text-meta leading-relaxed">
                    {selectedResume.hasFile
                      ? selectedResume.relativePath
                      : "No file on disk — import from Documents → Vault."}
                  </p>
                </div>
                <div className="space-y-3 border-t border-[var(--color-chrome-stroke)] pt-3">
                  <p className="text-label font-semibold uppercase tracking-[0.06em]">
                    Tailoring notes
                  </p>
                  <FormField label="Target role">
                    <input
                      className={fieldControlClass}
                      value={tailoringForm.targetRole}
                      onChange={(e) =>
                        onTailoringFormChange({ ...tailoringForm, targetRole: e.target.value })
                      }
                      placeholder="Software Engineer Intern"
                    />
                  </FormField>
                  <FormField label="Target company">
                    <input
                      className={fieldControlClass}
                      value={tailoringForm.targetCompany}
                      onChange={(e) =>
                        onTailoringFormChange({ ...tailoringForm, targetCompany: e.target.value })
                      }
                      placeholder="Acme Corp"
                    />
                  </FormField>
                  <FormField label="Notes">
                    <textarea
                      className={fieldControlClass}
                      rows={4}
                      value={tailoringForm.notes}
                      onChange={(e) =>
                        onTailoringFormChange({ ...tailoringForm, notes: e.target.value })
                      }
                      placeholder="Emphasize ML project, trim barista bullets, mirror posting keywords…"
                    />
                  </FormField>
                  {selectedResumeProfile?.updatedAt && (
                    <p className="text-caption">
                      Saved{" "}
                      {new Date(selectedResumeProfile.updatedAt).toLocaleString(undefined, {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })}
                    </p>
                  )}
                </div>
              </div>
              <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                <Button
                  size="sm"
                  disabled={tailoringBusy}
                  onClick={() => void onSaveTailoringNotes()}
                >
                  Save notes
                </Button>
                <Button
                  size="sm"
                  disabled={!selectedResume.hasFile}
                  onClick={() => void onOpenResume()}
                >
                  Open
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={!selectedResume.hasFile}
                  onClick={() => void onRevealResume()}
                >
                  Reveal
                </Button>
                <Button size="sm" variant="ghost" onClick={onClearResumeSelection}>
                  Close
                </Button>
              </div>
            </div>
          )}
        </TrailingInspector>
      </div>
      <AppCard title="Keyword match">
        <div className="grid gap-3 lg:grid-cols-2">
          <FormField label="Resume text">
            <textarea
              className={fieldControlClass}
              rows={8}
              value={resumeText}
              onChange={(e) => onResumeTextChange(e.target.value)}
              placeholder="Paste resume bullets or summary…"
            />
          </FormField>
          <div className="space-y-2">
            <FormField label="Job description / keywords">
              <textarea
                className={fieldControlClass}
                rows={8}
                value={jobText}
                onChange={(e) => onJobTextChange(e.target.value)}
                placeholder="Paste the job posting or ATS keyword list…"
              />
            </FormField>
            <div>
              <p className="mb-1.5 text-caption">
                ATS keyword presets
              </p>
              <div className="flex flex-wrap gap-1.5">
                {Object.entries(ATS_KEYWORD_PRESETS).map(([label, keywords]) => (
                  <button
                    key={label}
                    type="button"
                    className="rounded-full border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-2.5 py-1 text-label text-[var(--color-text-main)] transition-colors hover:bg-[var(--color-row-hover)]"
                    onClick={() => onJobTextChange(keywords)}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
        <div className="mt-3 flex items-center gap-3">
          <Button
            size="sm"
            disabled={!resumeText.trim() || !jobText.trim() || matchBusy}
            onClick={() => void onMatchKeywords()}
          >
            Match keywords
          </Button>
          {matchResult && (
            <span className="text-section-title tabular-nums">
              Score {(matchResult.score * 100).toFixed(0)}%
            </span>
          )}
        </div>
        {matchResult && (
          <div className="mt-3 grid gap-2 text-meta sm:grid-cols-2">
            <div>
              <div className="mb-1 font-semibold text-[var(--color-success)]">Matched</div>
              <p className="text-[var(--color-text-light)]">
                {matchResult.matched.length ? matchResult.matched.join(", ") : "None yet"}
              </p>
            </div>
            <div>
              <div className="mb-1 font-semibold text-[var(--color-warning)]">Missing</div>
              <p className="text-[var(--color-text-light)]">
                {matchResult.missing.length ? matchResult.missing.join(", ") : "Covered"}
              </p>
            </div>
          </div>
        )}
        {!resumeText.trim() && !jobText.trim() && resumeLibrary.length === 0 && (
          <p className="mt-3 text-meta">
            No vault resumes yet — import under Documents or load sample data from Settings, then
            paste text here to compare against a posting.
          </p>
        )}
      </AppCard>
    </div>
  );
}
