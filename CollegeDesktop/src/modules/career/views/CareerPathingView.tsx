import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  ListRow,
  ProgressBar,
  SegmentedPills,
  StatusChip,
  TrailingInspector,
  colors,
  fieldControlClass,
  PathTimeline,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { openPath, revealItemInDir } from "@tauri-apps/plugin-opener";
import { formatDateLabel } from "../format";
import { laneColor, statuses, statusLabels } from "./CareerPipelineView";
import type { BragEntryRow } from "../growthTypes";
import { PathingDisclosurePanel } from "../PathingDisclosurePanel";
import { PathingGoalsPanel } from "../PathingGoalsPanel";
import { PathingRelatedPanel } from "../PathingRelatedPanel";
import { PathingResumePanel } from "../PathingResumePanel";
import { PathingRoleExpectationsPanel } from "../PathingRoleExpectationsPanel";
import { PathingScenariosPanel } from "../PathingScenariosPanel";
import { PathingStoriesPanel } from "../PathingStoriesPanel";

export type PathEntryRow = {
  id: string;
  organization: string;
  roleTitle: string;
  startDate?: string | null;
  endDate?: string | null;
  summary: string;
  resumeDocumentId?: string | null;
};

export type PathMilestoneRow = {
  id: string;
  pathEntryId: string;
  title: string;
  status: string;
  dueAt?: string | null;
  notes: string;
  lane: string;
};

export type PathDocumentRow = {
  id: string;
  pathEntryId: string;
  vaultDocId: string;
  note: string;
  title: string;
  category: string;
  hasFile: boolean;
};

export type PathJournalEntryRow = {
  id: string;
  pathEntryId: string;
  occurredAt: string;
  title: string;
  body: string;
  mood: string;
  sortOrder: number;
};

export type PathPromotionRow = {
  id: string;
  pathEntryId: string;
  title: string;
  effectiveAt?: string | null;
  notes: string;
  sortOrder: number;
};

export type PathPersonRow = {
  id: string;
  pathEntryId: string;
  name: string;
  roleTitle: string;
  relationship: string;
  notes: string;
  sortOrder: number;
};

export type PathBenefitRow = {
  id: string;
  pathEntryId: string;
  title: string;
  isActive: boolean;
  notes: string;
  sortOrder: number;
};

export type PathCompensationRow = {
  id: string;
  pathEntryId: string;
  kind: string;
  title: string;
  amount?: number | null;
  currency: string;
  cadence: string;
  notes: string;
  sortOrder: number;
};

export type PathEmploymentTerms = {
  pathEntryId: string;
  employmentType: string;
  workLocation: string;
  scheduleNotes: string;
  noticePeriod: string;
  otherTerms: string;
  updatedAt?: string | null;
};

export type CareerSkillRow = {
  id: string;
  name: string;
  evidenceCount: number;
  sortOrder: number;
};

export type AchievementPipeline = {
  openRoadmapItems: number;
  doneMilestones: number;
  bragWins: number;
  activeBenefits: number;
  promotions: number;
  people: number;
  compensationItems: number;
};

export type PathDecisionJournal = {
  pathEntryId: string;
  whyAccepted: string;
  alternatives: string;
  expectedBenefits: string;
  concerns: string;
  successCriteria: string;
  whyLeft: string;
  lessons: string;
  wouldDoDifferently: string;
  updatedAt?: string | null;
};

export type VaultDoc = {
  id: string;
  title: string;
  category: string;
  mimeType: string;
  fileSize: number;
  updatedAt: string;
  relativePath: string;
  hasFile: boolean;
};

export type AppRow = {
  id: string;
  company: string;
  roleTitle: string;
  status: string;
  location: string;
};

function formatPathDateRange(start?: string | null, end?: string | null): string {
  if (!start && !end) return "Dates unknown";
  return [start, end || "present"].filter(Boolean).join(" → ");
}

function categoryTint(category: string): string {
  switch (category) {
    case "syllabus":
      return "var(--color-primary)";
    case "transcript":
      return "var(--color-success)";
    case "resume":
      return "var(--color-warning)";
    case "cover_letter":
      return "var(--color-primary)";
    default:
      return "var(--color-text-light)";
  }
}

const milestoneStatuses = ["planned", "in_progress", "done"] as const;

const milestoneStatusLabels: Record<(typeof milestoneStatuses)[number], string> = {
  planned: "Planned",
  in_progress: "In progress",
  done: "Done",
};

const milestoneStatusColor: Record<(typeof milestoneStatuses)[number], string> = {
  planned: "var(--color-text-light)",
  in_progress: colors.careerLaneInterviewing,
  done: colors.careerLaneAccepted,
};

export const pathInspectorTabs = [
  "overview",
  "roadmap",
  "journal",
  "promotions",
  "people",
  "skills",
  "growth",
  "expectations",
  "related",
  "resume",
  "goals",
  "scenarios",
  "disclosure",
  "stories",
  "compensation",
  "decisions",
  "pipeline",
] as const;

export type PathInspectorTab = (typeof pathInspectorTabs)[number];

export type PathTabCategory = "plan" | "growth" | "network" | "comp";

export const pathTabCategories: Record<
  PathTabCategory,
  { label: string; tabs: PathInspectorTab[] }
> = {
  plan: {
    label: "Plan & Goals",
    tabs: ["overview", "roadmap", "goals", "journal", "pipeline"],
  },
  growth: {
    label: "Growth & Skills",
    tabs: ["growth", "expectations", "skills", "stories", "promotions"],
  },
  network: {
    label: "Network & People",
    tabs: ["people", "disclosure", "related"],
  },
  comp: {
    label: "Compensation",
    tabs: ["compensation", "decisions", "scenarios", "resume"],
  },
};

function categoryForTab(tab: PathInspectorTab): PathTabCategory {
  for (const [cat, config] of Object.entries(pathTabCategories)) {
    if (config.tabs.includes(tab)) return cat as PathTabCategory;
  }
  return "plan";
}

const pathInspectorTabLabels: Record<PathInspectorTab, string> = {
  overview: "Overview",
  roadmap: "Roadmap",
  journal: "Journal",
  promotions: "Promotions",
  people: "People",
  skills: "Skills",
  growth: "Growth",
  expectations: "Expectations",
  related: "Related",
  resume: "Resume",
  goals: "Goals",
  scenarios: "Scenarios",
  disclosure: "Disclosure",
  stories: "Stories",
  compensation: "Compensation",
  decisions: "Decisions",
  pipeline: "Pipeline",
};

const BENEFIT_PRESETS = [
  "Equity / RSU refresh",
  "Learning stipend",
  "Remote flexibility",
  "Title progression clarity",
  "Performance review cadence",
  "Health insurance",
  "401(k) match",
  "PTO / parental leave",
] as const;

const COMPENSATION_PRESETS = [
  { kind: "base_salary", title: "Base salary" },
  { kind: "bonus", title: "Annual bonus" },
  { kind: "equity", title: "Equity / RSUs" },
  { kind: "stipend", title: "Learning stipend" },
] as const;

const compensationCadences = ["yearly", "monthly", "one_time"] as const;
const compensationCadenceLabels: Record<(typeof compensationCadences)[number], string> = {
  yearly: "Yearly",
  monthly: "Monthly",
  one_time: "One-time",
};

const roadmapLanes = ["learning", "impact", "promotion", "general"] as const;
type RoadmapLane = (typeof roadmapLanes)[number];
const roadmapLaneLabels: Record<RoadmapLane, string> = {
  learning: "Learning",
  impact: "Impact",
  promotion: "Promotion",
  general: "General",
};

const employmentTypeOptions = [
  "",
  "full_time",
  "part_time",
  "contract",
  "internship",
  "freelance",
] as const;
const employmentTypeLabels: Record<(typeof employmentTypeOptions)[number], string> = {
  "": "Not set",
  full_time: "Full-time",
  part_time: "Part-time",
  contract: "Contract",
  internship: "Internship",
  freelance: "Freelance",
};

const journalMoods = ["", "great", "ok", "hard"] as const;

const journalMoodLabels: Record<(typeof journalMoods)[number], string> = {
  "": "None",
  great: "Great",
  ok: "OK",
  hard: "Hard",
};

const journalMoodColor: Record<Exclude<(typeof journalMoods)[number], "">, string> = {
  great: colors.careerLaneAccepted,
  ok: "var(--color-primary)",
  hard: colors.careerLaneRejected,
};

function formatCompensationAmount(row: PathCompensationRow): string {
  if (row.amount == null || Number.isNaN(row.amount)) return "Amount TBD";
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: row.currency || "USD",
      maximumFractionDigits: 0,
    }).format(row.amount);
  } catch {
    return `${row.currency || "USD"} ${row.amount}`;
  }
}

export type CareerPathingViewProps = {
  pathByOrg: { key: string; displayName: string; entries: PathEntryRow[] }[];
  byOrg: [string, AppRow[]][];
  selectedPathId: string | null;
  selectedPath: PathEntryRow | null;
  selectedAppId: string | null;
  pathInspectorTab: PathInspectorTab;
  pathPipeline: AchievementPipeline | null;
  pathDocuments: PathDocumentRow[];
  vaultDocs: VaultDoc[];
  relatedPathApplications: AppRow[];
  pathMilestones: PathMilestoneRow[];
  pathMilestoneProgress: { total: number; done: number; ratio: number };
  milestonesByLane: { lane: RoadmapLane; items: PathMilestoneRow[] }[];
  pathJournalEntries: PathJournalEntryRow[];
  pathPromotions: PathPromotionRow[];
  pathPeople: PathPersonRow[];
  skillNameDraft: string;
  careerSkills: CareerSkillRow[];
  bragEntries: BragEntryRow[];
  pathBenefits: PathBenefitRow[];
  pathCompensation: PathCompensationRow[];
  employmentTerms: PathEmploymentTerms | null;
  decisionJournal: PathDecisionJournal | null;
  employmentBusy: boolean;
  decisionBusy: boolean;
  pathEntries: PathEntryRow[];
  onSelectPathId: (id: string) => void;
  onClearPathSelection: () => void;
  onSelectAppId: (id: string) => void;
  onPathInspectorTabChange: (tab: PathInspectorTab) => void;
  onOpenPathDocLink: () => void;
  onPathDocumentsChange: (docs: PathDocumentRow[]) => void;
  onPathBenefitsChange: (benefits: PathBenefitRow[]) => void;
  onPathPipelineChange: (pipeline: AchievementPipeline | null) => void;
  onCareerSkillsChange: (skills: CareerSkillRow[]) => void;
  onSkillNameDraftChange: (value: string) => void;
  onPathCompensationChange: (rows: PathCompensationRow[]) => void;
  onEmploymentTermsChange: (terms: PathEmploymentTerms) => void;
  onEmploymentBusyChange: (busy: boolean) => void;
  onDecisionJournalChange: (journal: PathDecisionJournal) => void;
  onDecisionBusyChange: (busy: boolean) => void;
  onOpenMilestoneEditor: (milestone?: PathMilestoneRow) => void;
  onOpenJournalEditor: (entry?: PathJournalEntryRow) => void;
  onOpenPromotionEditor: (promotion?: PathPromotionRow) => void;
  onOpenPersonEditor: (person?: PathPersonRow) => void;
  onOpenCompensationEditor: (row?: PathCompensationRow) => void;
  onOpenPathEditor: (entry: PathEntryRow) => void;
  onDeletePathEntry: (entry: PathEntryRow) => void | Promise<void>;
  onOpenBragBook: () => void;
  onPathMerged: (targetId: string, entries: PathEntryRow[]) => void;
  onResumeDocumentSaved: (entryId: string, resumeDocumentId: string | null) => void;
};

export function CareerPathingView({
  pathByOrg,
  byOrg,
  selectedPathId,
  selectedPath,
  selectedAppId,
  pathInspectorTab,
  pathPipeline,
  pathDocuments,
  vaultDocs,
  relatedPathApplications,
  pathMilestones,
  pathMilestoneProgress,
  milestonesByLane,
  pathJournalEntries,
  pathPromotions,
  pathPeople,
  skillNameDraft,
  careerSkills,
  bragEntries,
  pathBenefits,
  pathCompensation,
  employmentTerms,
  decisionJournal,
  employmentBusy,
  decisionBusy,
  pathEntries,
  onSelectPathId,
  onClearPathSelection,
  onSelectAppId,
  onPathInspectorTabChange,
  onOpenPathDocLink,
  onPathDocumentsChange,
  onPathBenefitsChange,
  onPathPipelineChange,
  onCareerSkillsChange,
  onSkillNameDraftChange,
  onPathCompensationChange,
  onEmploymentTermsChange,
  onEmploymentBusyChange,
  onDecisionJournalChange,
  onDecisionBusyChange,
  onOpenMilestoneEditor,
  onOpenJournalEditor,
  onOpenPromotionEditor,
  onOpenPersonEditor,
  onOpenCompensationEditor,
  onOpenPathEditor,
  onDeletePathEntry,
  onOpenBragBook,
  onPathMerged,
  onResumeDocumentSaved,
}: CareerPathingViewProps) {
  return (
    <div className="min-h-0 flex-1 p-3 pt-1">
        <TrailingInspector
          open={!!selectedPath}
          storageKey="career.inspectorWidth"
          main={
            <div className="space-y-3 overflow-auto pb-2">
              {pathByOrg.length === 0 ? (
                <AppCard title="Career path">
                  <EmptyState
                    title="No path entries yet"
                    body="Track roles and orgs you’ve held — separate from the application pipeline."
                  />
                </AppCard>
              ) : (
                pathByOrg.map(({ key, displayName, entries }) => (
                  <AppCard key={key}>
                    <div className="mb-2 flex items-center justify-between gap-2">
                      <h2
                        className="text-[var(--color-text-main)]"
                        style={{ font: "var(--type-section-title)" }}
                      >
                        {displayName}
                      </h2>
                      <StatusChip
                        title={`${entries.length} ${entries.length === 1 ? "role" : "roles"}`}
                        tint="var(--color-primary)"
                        filled
                      />
                    </div>
                    <PathTimeline
                      items={entries.map((entry) => ({
                        id: entry.id,
                        title: entry.roleTitle,
                        meta: formatPathDateRange(entry.startDate, entry.endDate),
                        color: "var(--color-primary)",
                        selected: selectedPathId === entry.id,
                        onClick: () => onSelectPathId(entry.id),
                      }))}
                    />
                  </AppCard>
                ))
              )}
              {byOrg.length > 0 && (
                <div className="space-y-3">
                  <p className="text-label font-semibold uppercase tracking-[0.06em]">
                    From applications
                  </p>
                  {byOrg.map(([company, roles]) => (
                    <AppCard key={company} title={company}>
                      <PathTimeline
                        items={roles.map((role) => ({
                          id: role.id,
                          title: role.roleTitle,
                          subtitle:
                            statusLabels[role.status as (typeof statuses)[number]] ??
                            role.status,
                          meta: role.location || undefined,
                          color: laneColor[role.status] ?? colors.careerLaneInterested,
                          selected: selectedAppId === role.id,
                          onClick: () => onSelectAppId(role.id),
                        }))}
                      />
                    </AppCard>
                  ))}
                </div>
              )}
            </div>
          }
        >
          {selectedPath && (
            <div className="flex h-full flex-col">
              <div
                className="border-b border-[var(--color-chrome-stroke)] px-4 py-3"
                style={{
                  background:
                    "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 8%, transparent), transparent)",
                }}
              >
                <h3
                  className="text-[var(--color-text-main)]"
                  style={{
                    font: "var(--type-section-title)",
                    fontSize: 16,
                    letterSpacing: "-0.02em",
                  }}
                >
                  {selectedPath.roleTitle}
                </h3>
                <p className="mt-0.5 text-meta">
                  {formatPathDateRange(selectedPath.startDate, selectedPath.endDate)}
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  <StatusChip
                    title={selectedPath.roleTitle}
                    tint="var(--color-primary)"
                    filled
                  />
                  <StatusChip title={selectedPath.organization} />
                </div>
              </div>
              <div className="min-h-0 flex-1 space-y-3 overflow-auto p-4">
                {/* 2-tier Category & Subtab Selector */}
                <div className="space-y-2">
                  <SegmentedPills
                    value={categoryForTab(pathInspectorTab)}
                    onChange={(catId) => {
                      const firstTab = pathTabCategories[catId as PathTabCategory].tabs[0];
                      onPathInspectorTabChange(firstTab);
                    }}
                    options={Object.entries(pathTabCategories).map(([id, config]) => ({
                      id,
                      label: config.label,
                    }))}
                  />

                  <div className="flex flex-wrap gap-1 border-b border-[var(--color-chrome-stroke)] pb-2">
                    {pathTabCategories[categoryForTab(pathInspectorTab)].tabs.map((tabId) => {
                      const isActive = pathInspectorTab === tabId;
                      return (
                        <button
                          key={tabId}
                          type="button"
                          onClick={() => onPathInspectorTabChange(tabId)}
                          className={`rounded-md px-2.5 py-1 text-caption font-medium transition ${
                            isActive
                              ? "bg-[var(--color-primary)] text-white font-semibold"
                              : "bg-[var(--color-shell-chrome)] text-[var(--color-text-light)] hover:text-[var(--color-text-main)]"
                          }`}
                        >
                          {pathInspectorTabLabels[tabId]}
                        </button>
                      );
                    })}
                  </div>
                </div>

                {pathInspectorTab === "overview" && (
                  <>
                    {pathPipeline && (
                      <div className="space-y-2 rounded-[12px] border border-[var(--color-chrome-stroke)] p-3">
                        <p className="text-label font-semibold uppercase tracking-[0.06em]">
                          Achievement pipeline
                        </p>
                        <p className="text-caption">
                          Roadmap → done → Growth wins → Overview.
                        </p>
                        <div className="grid grid-cols-2 gap-2">
                          {(
                            [
                              ["Open roadmap", pathPipeline.openRoadmapItems, "roadmap"],
                              ["Done milestones", pathPipeline.doneMilestones, "roadmap"],
                              ["Brag wins", pathPipeline.bragWins, "stories"],
                              ["Active benefits", pathPipeline.activeBenefits, "growth"],
                              ["Compensation", pathPipeline.compensationItems, "compensation"],
                              ["Promotions", pathPipeline.promotions, "promotions"],
                              ["People", pathPipeline.people, "people"],
                            ] as const
                          ).map(([label, count, tab]) => (
                            <button
                              key={label}
                              type="button"
                              className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-2.5 py-2 text-left hover:bg-[var(--color-row-hover)]"
                              onClick={() => onPathInspectorTabChange(tab)}
                            >
                              <div
                                className="text-section-title font-semibold tabular-nums text-[var(--color-primary)]"
                                style={{ fontSize: 15 }}
                              >
                                {count}
                              </div>
                              <div className="text-caption">{label}</div>
                            </button>
                          ))}
                        </div>
                      </div>
                    )}
                    <div>
                      <p className="text-meta leading-relaxed">
                        {selectedPath.summary.trim()
                          ? selectedPath.summary
                          : "No summary yet — add notes when you edit this entry."}
                      </p>
                    </div>
                    <div className="space-y-2 border-t border-[var(--color-chrome-stroke)] pt-3">
                      <div className="flex items-center justify-between gap-2">
                        <p className="text-label font-semibold uppercase tracking-[0.06em]">
                          Documents
                        </p>
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => onOpenPathDocLink()}
                        >
                          Link document
                        </Button>
                      </div>
                      {pathDocuments.length > 0 ? (
                        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                          {pathDocuments.map((doc) => {
                            const vaultDoc = vaultDocs.find((d) => d.id === doc.vaultDocId);
                            const hasFile = doc.hasFile || Boolean(vaultDoc?.hasFile);
                            return (
                              <li key={doc.id}>
                                <ListRow
                                  title={doc.title.trim() || vaultDoc?.title || "Untitled"}
                                  subtitle={
                                    doc.note.trim() ||
                                    (hasFile ? "Linked vault file" : "Metadata only")
                                  }
                                  trailing={
                                    <div className="flex items-center gap-1.5">
                                      <StatusChip
                                        title={doc.category || vaultDoc?.category || "general"}
                                        tint={categoryTint(
                                          doc.category || vaultDoc?.category || "general",
                                        )}
                                        filled
                                      />
                                      {hasFile && (
                                        <>
                                          <Button
                                            size="sm"
                                            variant="ghost"
                                            onClick={async () => {
                                              const path = await ipc.documentsResolvePath(
                                                doc.vaultDocId,
                                              );
                                              if (!path) return;
                                              await openPath(path);
                                            }}
                                          >
                                            Open
                                          </Button>
                                          <Button
                                            size="sm"
                                            variant="ghost"
                                            onClick={async () => {
                                              const path = await ipc.documentsResolvePath(
                                                doc.vaultDocId,
                                              );
                                              if (!path) return;
                                              await revealItemInDir(path);
                                            }}
                                          >
                                            Reveal
                                          </Button>
                                        </>
                                      )}
                                      <Button
                                        size="sm"
                                        variant="ghost"
                                        onClick={async () => {
                                          if (
                                            !confirmDelete(
                                              doc.title.trim() || vaultDoc?.title || "document",
                                            )
                                          )
                                            return;
                                          if (!selectedPath) return;
                                          try {
                                            await ipc.careerUnlinkPathDocument(doc.id);
                                            const refreshed = await ipc.careerListPathDocuments(
                                              selectedPath.id,
                                            );
                                            onPathDocumentsChange(refreshed);
                                            showToast("Document unlinked", "success");
                                          } catch (err) {
                                            showToast(formatIpcError(err), "error");
                                          }
                                        }}
                                      >
                                        Unlink
                                      </Button>
                                    </div>
                                  }
                                />
                              </li>
                            );
                          })}
                        </ul>
                      ) : (
                        <p className="text-meta">
                          No linked documents — attach vault files for this path entry.
                        </p>
                      )}
                    </div>
                    {relatedPathApplications.length > 0 && (
                      <div className="space-y-2 border-t border-[var(--color-chrome-stroke)] pt-3">
                        <p className="text-label font-semibold uppercase tracking-[0.06em]">
                          Applications @ {selectedPath.organization}
                        </p>
                        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                          {relatedPathApplications.map((app) => (
                            <li key={app.id}>
                              <ListRow
                                onClick={() => onSelectAppId(app.id)}
                                title={app.roleTitle || "Untitled role"}
                                subtitle={app.location || undefined}
                                trailing={
                                  <StatusChip
                                    title={
                                      statusLabels[app.status as (typeof statuses)[number]] ??
                                      app.status
                                    }
                                    tint={laneColor[app.status] ?? colors.careerLaneInterested}
                                    filled
                                  />
                                }
                              />
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </>
                )}

                {pathInspectorTab === "roadmap" && (
                  <div className="space-y-3">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-label font-semibold uppercase tracking-[0.06em]">
                        Roadmap lanes
                      </p>
                      <Button size="sm" variant="secondary" onClick={() => onOpenMilestoneEditor()}>
                        Add milestone
                      </Button>
                    </div>
                    {pathMilestones.length > 0 ? (
                      <>
                        <div className="flex items-center justify-between gap-2 text-caption">
                          <span>
                            {pathMilestoneProgress.done} of {pathMilestoneProgress.total} done
                          </span>
                          <span className="tabular-nums">
                            {Math.round(pathMilestoneProgress.ratio * 100)}%
                          </span>
                        </div>
                        <ProgressBar value={pathMilestoneProgress.ratio} height={8} />
                        <div className="space-y-3">
                          {(milestonesByLane.length > 0
                            ? milestonesByLane
                            : [{ lane: "general" as RoadmapLane, items: pathMilestones }]
                          ).map(({ lane, items }) => (
                            <div key={lane} className="space-y-1">
                              <div className="flex items-center gap-2">
                                <p className="text-label font-semibold uppercase tracking-[0.06em]">
                                  {roadmapLaneLabels[lane]}
                                </p>
                                <span className="text-caption tabular-nums text-[var(--color-text-light)]">
                                  {items.length}
                                </span>
                              </div>
                              <ul className="divide-y divide-[var(--color-chrome-stroke)] rounded-[10px] border border-[var(--color-chrome-stroke)]">
                                {items.map((milestone) => {
                                  const status = milestoneStatuses.includes(
                                    milestone.status as (typeof milestoneStatuses)[number],
                                  )
                                    ? (milestone.status as (typeof milestoneStatuses)[number])
                                    : "planned";
                                  return (
                                    <li key={milestone.id}>
                                      <ListRow
                                        onClick={() => onOpenMilestoneEditor(milestone)}
                                        title={milestone.title}
                                        subtitle={[
                                          milestone.dueAt
                                            ? `Due ${formatDateLabel(milestone.dueAt)}`
                                            : null,
                                          milestone.notes.trim() || null,
                                        ]
                                          .filter(Boolean)
                                          .join(" · ")}
                                        trailing={
                                          <StatusChip
                                            title={milestoneStatusLabels[status]}
                                            tint={milestoneStatusColor[status]}
                                            filled={status === "done"}
                                          />
                                        }
                                      />
                                    </li>
                                  );
                                })}
                              </ul>
                            </div>
                          ))}
                        </div>
                      </>
                    ) : (
                      <p className="text-meta">
                        No milestones yet — add goals across Learning, Impact, Promotion, or
                        General lanes.
                      </p>
                    )}
                  </div>
                )}

                {pathInspectorTab === "journal" && (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-label font-semibold uppercase tracking-[0.06em]">
                        Journal
                      </p>
                      <Button size="sm" variant="secondary" onClick={() => onOpenJournalEditor()}>
                        Add entry
                      </Button>
                    </div>
                    {pathJournalEntries.length > 0 ? (
                      <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                        {pathJournalEntries.map((entry) => {
                          const mood = journalMoods.includes(
                            entry.mood as (typeof journalMoods)[number],
                          )
                            ? (entry.mood as (typeof journalMoods)[number])
                            : "";
                          return (
                            <li key={entry.id}>
                              <ListRow
                                onClick={() => onOpenJournalEditor(entry)}
                                title={entry.title.trim() || "Untitled entry"}
                                subtitle={
                                  entry.body.trim()
                                    ? entry.body.trim().slice(0, 120) +
                                      (entry.body.trim().length > 120 ? "…" : "")
                                    : "No notes"
                                }
                                trailing={
                                  <div className="flex flex-wrap items-center justify-end gap-1">
                                    {mood ? (
                                      <StatusChip
                                        title={journalMoodLabels[mood]}
                                        tint={journalMoodColor[mood]}
                                        filled
                                      />
                                    ) : null}
                                    <StatusChip
                                      title={formatDateLabel(entry.occurredAt)}
                                      tint="var(--color-primary)"
                                    />
                                  </div>
                                }
                              />
                            </li>
                          );
                        })}
                      </ul>
                    ) : (
                      <p className="text-meta">
                        No journal entries yet — log reflections, wins, and challenges for this role.
                      </p>
                    )}
                  </div>
                )}

                {pathInspectorTab === "promotions" && (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-label font-semibold uppercase tracking-[0.06em]">
                        Promotions
                      </p>
                      <Button size="sm" variant="secondary" onClick={() => onOpenPromotionEditor()}>
                        Add promotion
                      </Button>
                    </div>
                    {pathPromotions.length > 0 ? (
                      <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                        {pathPromotions.map((promotion) => (
                          <li key={promotion.id}>
                            <ListRow
                              onClick={() => onOpenPromotionEditor(promotion)}
                              title={promotion.title}
                              subtitle={
                                promotion.notes.trim()
                                  ? promotion.notes.trim().slice(0, 120) +
                                    (promotion.notes.trim().length > 120 ? "…" : "")
                                  : "No notes"
                              }
                              trailing={
                                <div className="flex flex-wrap items-center justify-end gap-1">
                                  {promotion.effectiveAt ? (
                                    <StatusChip
                                      title={formatDateLabel(promotion.effectiveAt)}
                                      tint="var(--color-primary)"
                                      filled
                                    />
                                  ) : (
                                    <StatusChip title="No date" />
                                  )}
                                </div>
                              }
                            />
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="text-meta">
                        No promotions logged — track title changes and level-ups for this role.
                      </p>
                    )}
                  </div>
                )}

                {pathInspectorTab === "people" && (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-label font-semibold uppercase tracking-[0.06em]">
                        People
                      </p>
                      <Button size="sm" variant="secondary" onClick={() => onOpenPersonEditor()}>
                        Add person
                      </Button>
                    </div>
                    {pathPeople.length > 0 ? (
                      <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                        {pathPeople.map((person) => (
                          <li key={person.id}>
                            <ListRow
                              onClick={() => onOpenPersonEditor(person)}
                              title={person.name}
                              subtitle={
                                [
                                  person.roleTitle.trim() || null,
                                  person.notes.trim()
                                    ? person.notes.trim().slice(0, 80) +
                                      (person.notes.trim().length > 80 ? "…" : "")
                                    : null,
                                ]
                                  .filter(Boolean)
                                  .join(" · ") || "No notes"
                              }
                              trailing={
                                <div className="flex flex-wrap items-center justify-end gap-1">
                                  {person.relationship.trim() ? (
                                    <StatusChip
                                      title={person.relationship.trim()}
                                      tint="var(--color-primary)"
                                      filled
                                    />
                                  ) : null}
                                  {person.roleTitle.trim() ? (
                                    <StatusChip title={person.roleTitle.trim()} />
                                  ) : null}
                                </div>
                              }
                            />
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="text-meta">
                        No people yet — note managers, mentors, and collaborators for this role.
                      </p>
                    )}
                  </div>
                )}

                {pathInspectorTab === "skills" && (
                  <div className="space-y-3">
                    <p className="text-meta">
                      Skill graph with evidence counts. Inferred tags from brag/roadmap appear as
                      suggestions.
                    </p>
                    <div className="flex gap-2">
                      <input
                        className={fieldControlClass}
                        value={skillNameDraft}
                        onChange={(e) => onSkillNameDraftChange(e.target.value)}
                        placeholder="Add skill…"
                      />
                      <Button
                        size="sm"
                        disabled={!skillNameDraft.trim()}
                        onClick={async () => {
                          try {
                            await ipc.careerUpsertSkill({ name: skillNameDraft.trim() });
                            onSkillNameDraftChange("");
                            onCareerSkillsChange(await ipc.careerListSkills());
                            showToast("Skill added", "success");
                          } catch (e) {
                            showToast(formatIpcError(e), "error");
                          }
                        }}
                      >
                        Add
                      </Button>
                    </div>
                    {careerSkills.length === 0 ? (
                      <EmptyState
                        title="No skills yet"
                        body="Add skills you want to track across roles, or accept a suggestion below."
                      />
                    ) : (
                      <ul className="space-y-2">
                        {careerSkills.map((s) => (
                          <li
                            key={s.id}
                            className="flex items-center gap-2 rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                          >
                            <div className="min-w-0 flex-1">
                              <div className="text-body font-medium">{s.name}</div>
                              <StatusChip
                                title={`${s.evidenceCount} evidence`}
                                tint="var(--color-primary)"
                                filled
                              />
                            </div>
                            <Button
                              size="sm"
                              variant="secondary"
                              onClick={async () => {
                                try {
                                  await ipc.careerAddSkillEvidence({
                                    skillId: s.id,
                                    pathEntryId: selectedPath.id,
                                    note: `Evidence from ${selectedPath.roleTitle}`,
                                  });
                                  onCareerSkillsChange(await ipc.careerListSkills());
                                  showToast("Evidence added", "success");
                                } catch (e) {
                                  showToast(formatIpcError(e), "error");
                                }
                              }}
                            >
                              + Evidence
                            </Button>
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={async () => {
                                if (!confirmDelete(s.name)) return;
                                try {
                                  await ipc.careerDeleteSkill(s.id);
                                  onCareerSkillsChange(await ipc.careerListSkills());
                                } catch (e) {
                                  showToast(formatIpcError(e), "error");
                                }
                              }}
                            >
                              Delete
                            </Button>
                          </li>
                        ))}
                      </ul>
                    )}
                    {(() => {
                      const known = new Set(careerSkills.map((s) => s.name.toLowerCase()));
                      const tokens = new Set<string>();
                      for (const b of bragEntries) {
                        for (const word of `${b.title} ${b.summary}`.split(/\W+/)) {
                          const w = word.trim().toLowerCase();
                          if (w.length >= 5 && !known.has(w)) tokens.add(w);
                        }
                      }
                      for (const m of pathMilestones) {
                        for (const word of m.title.split(/\W+/)) {
                          const w = word.trim().toLowerCase();
                          if (w.length >= 5 && !known.has(w)) tokens.add(w);
                        }
                      }
                      const suggestions = [...tokens].slice(0, 8);
                      if (suggestions.length === 0) return null;
                      return (
                        <div>
                          <p className="mb-1.5 text-label font-semibold uppercase tracking-[0.05em]">
                            Suggestions
                          </p>
                          <div className="flex flex-wrap gap-1.5">
                            {suggestions.map((s) => (
                              <button
                                key={s}
                                type="button"
                                className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-caption hover:bg-[var(--color-row-hover)]"
                                onClick={async () => {
                                  try {
                                    await ipc.careerUpsertSkill({ name: s });
                                    onCareerSkillsChange(await ipc.careerListSkills());
                                  } catch (e) {
                                    showToast(formatIpcError(e), "error");
                                  }
                                }}
                              >
                                + {s}
                              </button>
                            ))}
                          </div>
                        </div>
                      );
                    })()}
                  </div>
                )}

                {pathInspectorTab === "growth" && (
                  <div className="space-y-3">
                    <AppCard title="Promotion ladder">
                      {pathPromotions.length === 0 ? (
                        <p className="text-meta">
                          Log promotions under the Promotions tab to visualize growth.
                        </p>
                      ) : (
                        <ul className="space-y-2">
                          {pathPromotions.map((p) => (
                            <li
                              key={p.id}
                              className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                            >
                              <div className="text-section-title">{p.title}</div>
                              {p.effectiveAt && (
                                <p className="mt-0.5 text-caption">
                                  {new Date(p.effectiveAt).toLocaleDateString()}
                                </p>
                              )}
                            </li>
                          ))}
                        </ul>
                      )}
                    </AppCard>
                    <AppCard title="Benefits">
                      <p className="mb-2 text-meta">
                        Track what you have vs. what you expected. Presets seed rows quickly.
                      </p>
                      <div className="mb-3 flex flex-wrap gap-1.5">
                        {BENEFIT_PRESETS.filter(
                          (p) => !pathBenefits.some((b) => b.title.toLowerCase() === p.toLowerCase()),
                        ).map((preset) => (
                          <button
                            key={preset}
                            type="button"
                            className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-caption hover:bg-[var(--color-row-hover)]"
                            onClick={async () => {
                              try {
                                await ipc.careerUpsertPathBenefit({
                                  pathEntryId: selectedPath.id,
                                  title: preset,
                                  isActive: false,
                                });
                                onPathBenefitsChange(
                                  await ipc.careerListPathBenefits(selectedPath.id),
                                );
                              } catch (e) {
                                showToast(formatIpcError(e), "error");
                              }
                            }}
                          >
                            + {preset}
                          </button>
                        ))}
                      </div>
                      {pathBenefits.length === 0 ? (
                        <EmptyState
                          title="No benefits logged"
                          body="Add a preset above or create a custom benefit."
                        />
                      ) : (
                        <ul className="space-y-2">
                          {pathBenefits.map((b) => (
                            <li
                              key={b.id}
                              className="flex items-center gap-2 rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                            >
                              <label className="flex min-w-0 flex-1 cursor-pointer items-center gap-2">
                                <input
                                  type="checkbox"
                                  checked={b.isActive}
                                  onChange={async () => {
                                    try {
                                      await ipc.careerUpsertPathBenefit({
                                        id: b.id,
                                        pathEntryId: selectedPath.id,
                                        title: b.title,
                                        isActive: !b.isActive,
                                        notes: b.notes,
                                      });
                                      onPathBenefitsChange(
                                        await ipc.careerListPathBenefits(selectedPath.id),
                                      );
                                      onPathPipelineChange(
                                        await ipc.careerPathAchievementPipeline(selectedPath.id),
                                      );
                                    } catch (e) {
                                      showToast(formatIpcError(e), "error");
                                    }
                                  }}
                                />
                                <span
                                  className={`text-body ${
                                    b.isActive
                                      ? "font-medium text-[var(--color-text-main)]"
                                      : "text-[var(--color-text-light)]"
                                  }`}
                                >
                                  {b.title}
                                </span>
                              </label>
                              <Button
                                size="sm"
                                variant="ghost"
                                onClick={async () => {
                                  if (!confirmDelete(b.title)) return;
                                  try {
                                    await ipc.careerDeletePathBenefit(b.id);
                                    onPathBenefitsChange(
                                      await ipc.careerListPathBenefits(selectedPath.id),
                                    );
                                  } catch (e) {
                                    showToast(formatIpcError(e), "error");
                                  }
                                }}
                              >
                                Delete
                              </Button>
                            </li>
                          ))}
                        </ul>
                      )}
                    </AppCard>
                  </div>
                )}

                {pathInspectorTab === "goals" && selectedPath && (
                  <PathingGoalsPanel
                    entryId={selectedPath.id}
                    organization={selectedPath.organization}
                  />
                )}

                {pathInspectorTab === "expectations" && selectedPath && (
                  <PathingRoleExpectationsPanel entryId={selectedPath.id} />
                )}

                {pathInspectorTab === "related" && selectedPath && (
                  <PathingRelatedPanel
                    entryId={selectedPath.id}
                    pathEntries={pathEntries.map((e) => ({
                      id: e.id,
                      organization: e.organization,
                      roleTitle: e.roleTitle,
                    }))}
                    onMerged={async (targetId) => {
                      const refreshed = await ipc.careerListPathEntries();
                      onPathMerged(targetId, refreshed);
                    }}
                  />
                )}

                {pathInspectorTab === "resume" && selectedPath && (
                  <PathingResumePanel
                    entryId={selectedPath.id}
                    resumeDocumentId={selectedPath.resumeDocumentId}
                    vaultDocs={vaultDocs}
                    onSaved={(resumeDocumentId) => {
                      onResumeDocumentSaved(selectedPath.id, resumeDocumentId);
                    }}
                  />
                )}

                {pathInspectorTab === "scenarios" && selectedPath && (
                  <PathingScenariosPanel entryId={selectedPath.id} />
                )}

                {pathInspectorTab === "disclosure" && selectedPath && (
                  <PathingDisclosurePanel entryId={selectedPath.id} />
                )}

                {pathInspectorTab === "stories" && (
                  <PathingStoriesPanel bragEntries={bragEntries} onOpenBragBook={onOpenBragBook} />
                )}

                {pathInspectorTab === "compensation" && employmentTerms && (
                  <div className="space-y-3">
                    <AppCard title="Compensation">
                      <p className="mb-2 text-meta">
                        Track pay components for this role. Presets seed common rows quickly.
                      </p>
                      <div className="mb-3 flex flex-wrap gap-1.5">
                        {COMPENSATION_PRESETS.filter(
                          (p) =>
                            !pathCompensation.some(
                              (c) => c.title.toLowerCase() === p.title.toLowerCase(),
                            ),
                        ).map((preset) => (
                          <button
                            key={preset.kind}
                            type="button"
                            className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-caption hover:bg-[var(--color-row-hover)]"
                            onClick={async () => {
                              try {
                                await ipc.careerUpsertPathCompensation({
                                  pathEntryId: selectedPath.id,
                                  kind: preset.kind,
                                  title: preset.title,
                                  currency: "USD",
                                  cadence: "yearly",
                                });
                                onPathCompensationChange(
                                  await ipc.careerListPathCompensation(selectedPath.id),
                                );
                                onPathPipelineChange(
                                  await ipc.careerPathAchievementPipeline(selectedPath.id),
                                );
                              } catch (e) {
                                showToast(formatIpcError(e), "error");
                              }
                            }}
                          >
                            + {preset.title}
                          </button>
                        ))}
                      </div>
                      <div className="mb-2 flex justify-end">
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => onOpenCompensationEditor()}
                        >
                          Add custom
                        </Button>
                      </div>
                      {pathCompensation.length === 0 ? (
                        <EmptyState
                          title="No compensation logged"
                          body="Add a preset above or create a custom line item."
                        />
                      ) : (
                        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                          {pathCompensation.map((row) => (
                            <li key={row.id}>
                              <ListRow
                                onClick={() => onOpenCompensationEditor(row)}
                                title={row.title}
                                subtitle={[
                                  formatCompensationAmount(row),
                                  compensationCadenceLabels[
                                    compensationCadences.includes(
                                      row.cadence as (typeof compensationCadences)[number],
                                    )
                                      ? (row.cadence as (typeof compensationCadences)[number])
                                      : "yearly"
                                  ],
                                  row.notes.trim() || null,
                                ]
                                  .filter(Boolean)
                                  .join(" · ")}
                              />
                            </li>
                          ))}
                        </ul>
                      )}
                    </AppCard>
                    <AppCard title="Employment terms">
                      <div className="space-y-3">
                        <FormField label="Employment type">
                          <select
                            className={fieldControlClass}
                            value={employmentTerms.employmentType}
                            onChange={(e) =>
                              onEmploymentTermsChange({
                                ...employmentTerms,
                                employmentType: e.target.value,
                              })
                            }
                          >
                            {employmentTypeOptions.map((opt) => (
                              <option key={opt || "unset"} value={opt}>
                                {employmentTypeLabels[opt]}
                              </option>
                            ))}
                          </select>
                        </FormField>
                        <FormField label="Work location">
                          <input
                            className={fieldControlClass}
                            value={employmentTerms.workLocation}
                            onChange={(e) =>
                              onEmploymentTermsChange({
                                ...employmentTerms,
                                workLocation: e.target.value,
                              })
                            }
                            placeholder="Remote, hybrid, city…"
                          />
                        </FormField>
                        <FormField label="Schedule notes">
                          <textarea
                            className={fieldControlClass}
                            rows={2}
                            value={employmentTerms.scheduleNotes}
                            onChange={(e) =>
                              onEmploymentTermsChange({
                                ...employmentTerms,
                                scheduleNotes: e.target.value,
                              })
                            }
                            placeholder="Core hours, on-call, travel…"
                          />
                        </FormField>
                        <FormField label="Notice period">
                          <input
                            className={fieldControlClass}
                            value={employmentTerms.noticePeriod}
                            onChange={(e) =>
                              onEmploymentTermsChange({
                                ...employmentTerms,
                                noticePeriod: e.target.value,
                              })
                            }
                            placeholder="2 weeks, 30 days…"
                          />
                        </FormField>
                        <FormField label="Other terms">
                          <textarea
                            className={fieldControlClass}
                            rows={2}
                            value={employmentTerms.otherTerms}
                            onChange={(e) =>
                              onEmploymentTermsChange({
                                ...employmentTerms,
                                otherTerms: e.target.value,
                              })
                            }
                            placeholder="Non-compete, probation, equity cliffs…"
                          />
                        </FormField>
                        <Button
                          size="sm"
                          disabled={employmentBusy}
                          onClick={async () => {
                            onEmploymentBusyChange(true);
                            try {
                              await ipc.careerUpsertPathEmploymentTerms({
                                pathEntryId: selectedPath.id,
                                employmentType: employmentTerms.employmentType,
                                workLocation: employmentTerms.workLocation,
                                scheduleNotes: employmentTerms.scheduleNotes,
                                noticePeriod: employmentTerms.noticePeriod,
                                otherTerms: employmentTerms.otherTerms,
                              });
                              onEmploymentTermsChange(
                                await ipc.careerGetPathEmploymentTerms(selectedPath.id),
                              );
                              showToast("Employment terms saved", "success");
                            } catch (e) {
                              showToast(formatIpcError(e), "error");
                            } finally {
                              onEmploymentBusyChange(false);
                            }
                          }}
                        >
                          Save terms
                        </Button>
                      </div>
                    </AppCard>
                  </div>
                )}

                {pathInspectorTab === "decisions" && decisionJournal && (
                  <div className="space-y-3">
                    <p className="text-meta">
                      Private decision journal — why you accepted, concerns, and lessons. Never
                      exported with resume drafts.
                    </p>
                    {(
                      [
                        ["Why did you accept this role?", "whyAccepted"],
                        ["What alternatives did you consider?", "alternatives"],
                        ["What benefits did you expect?", "expectedBenefits"],
                        ["What concerns did you have?", "concerns"],
                        ["What would success look like?", "successCriteria"],
                        ["If it ended: why did you leave?", "whyLeft"],
                        ["Lessons learned", "lessons"],
                        ["What would you do differently?", "wouldDoDifferently"],
                      ] as const
                    ).map(([label, key]) => (
                      <FormField key={key} label={label}>
                        <textarea
                          className={fieldControlClass}
                          rows={2}
                          value={decisionJournal[key]}
                          onChange={(e) =>
                            onDecisionJournalChange({ ...decisionJournal, [key]: e.target.value })
                          }
                        />
                      </FormField>
                    ))}
                    <Button
                      size="sm"
                      disabled={decisionBusy}
                      onClick={async () => {
                        onDecisionBusyChange(true);
                        try {
                          await ipc.careerUpsertPathDecisionJournal({
                            pathEntryId: selectedPath.id,
                            whyAccepted: decisionJournal.whyAccepted,
                            alternatives: decisionJournal.alternatives,
                            expectedBenefits: decisionJournal.expectedBenefits,
                            concerns: decisionJournal.concerns,
                            successCriteria: decisionJournal.successCriteria,
                            whyLeft: decisionJournal.whyLeft,
                            lessons: decisionJournal.lessons,
                            wouldDoDifferently: decisionJournal.wouldDoDifferently,
                          });
                          showToast("Decision journal saved", "success");
                        } catch (e) {
                          showToast(formatIpcError(e), "error");
                        } finally {
                          onDecisionBusyChange(false);
                        }
                      }}
                    >
                      Save journal
                    </Button>
                  </div>
                )}

                {pathInspectorTab === "pipeline" && pathPipeline && (
                  <div className="space-y-3">
                    <p className="text-meta">
                      One path: Roadmap item → done → Growth section → Overview win.
                    </p>
                    {(
                      [
                        [
                          "Open Roadmap items",
                          pathPipeline.openRoadmapItems,
                          "Plan what’s next",
                          "roadmap" as PathInspectorTab,
                        ],
                        [
                          "Done milestones",
                          pathPipeline.doneMilestones,
                          "Ready for brag / growth",
                          "roadmap" as PathInspectorTab,
                        ],
                        [
                          "Brag wins",
                          pathPipeline.bragWins,
                          "Interview-ready accomplishments",
                          "stories" as PathInspectorTab,
                        ],
                        [
                          "Active benefits",
                          pathPipeline.activeBenefits,
                          "Compensation package tracking",
                          "growth" as PathInspectorTab,
                        ],
                        [
                          "Compensation lines",
                          pathPipeline.compensationItems,
                          "Salary, bonus, equity, stipends",
                          "compensation" as PathInspectorTab,
                        ],
                        [
                          "Promotions logged",
                          pathPipeline.promotions,
                          "Title & level history",
                          "promotions" as PathInspectorTab,
                        ],
                        [
                          "People network",
                          pathPipeline.people,
                          "Managers & mentors",
                          "people" as PathInspectorTab,
                        ],
                      ] as const
                    ).map(([title, count, hint, tab]) => (
                      <button
                        key={title}
                        type="button"
                        className="flex w-full items-center justify-between rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2.5 text-left hover:bg-[var(--color-row-hover)]"
                        onClick={() => onPathInspectorTabChange(tab)}
                      >
                        <div>
                          <div className="text-body font-medium">
                            {title}
                          </div>
                          <div className="text-caption">{hint}</div>
                        </div>
                        <span
                          className="text-section-title font-semibold tabular-nums text-[var(--color-primary)]"
                          style={{ fontSize: 18 }}
                        >
                          {count}
                        </span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
              <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                <Button size="sm" variant="secondary" onClick={() => onOpenPathEditor(selectedPath)}>
                  Edit
                </Button>
                <Button
                  size="sm"
                  variant="danger"
                  onClick={() => void onDeletePathEntry(selectedPath)}
                >
                  Delete
                </Button>
                <Button size="sm" variant="ghost" onClick={() => onClearPathSelection()}>
                  Close
                </Button>
              </div>
            </div>
          )}
        </TrailingInspector>
      </div>

  );
}
