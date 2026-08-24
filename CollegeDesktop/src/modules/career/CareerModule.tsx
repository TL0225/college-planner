import { useCallback, useEffect, useMemo, useState, type DragEvent } from "react";
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import { openPath, openUrl, revealItemInDir } from "@tauri-apps/plugin-opener";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  MetricTile,
  ModalSheet,
  SegmentedPills,
  TrailingInspector,
  colors,
  fieldControlClass,
  StatusChip,
  ProgressBar,
  LaneDot,
  KanbanLaneHeader,
  PathTimeline,
} from "@/design-system";
import { ipc, formatIpcError, type PipelineMetrics } from "@/lib/ipc";
import { shellNavigate } from "@/lib/shellNavigate";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { buildResumeMarkdown } from "./buildResumeMarkdown";
import { buildResumeTypst, compileResumeTypstToPdf } from "./buildResumeTypst";
import { ResumeLiveBuilder } from "./ResumeLiveBuilder";
import { openCareerApplyWindow } from "./CareerApplyWindow";
import { openResumePopOutWindow } from "./openResumePopOut";
import { PathingDisclosurePanel } from "./PathingDisclosurePanel";
import { PathingGoalsPanel } from "./PathingGoalsPanel";
import { PathingRelatedPanel } from "./PathingRelatedPanel";
import { PathingResumePanel } from "./PathingResumePanel";
import { PathingRoleExpectationsPanel } from "./PathingRoleExpectationsPanel";
import { PathingScenariosPanel } from "./PathingScenariosPanel";
import { PathingStoriesPanel } from "./PathingStoriesPanel";
import { SimpleMarkdown } from "@/modules/assistant/simpleMarkdown";

type ResumeDraftPane = "markdown" | "typst" | "preview";

const laneColor: Record<string, string> = {
  interested: colors.careerLaneInterested,
  applied: colors.careerLaneApplied,
  interviewing: colors.careerLaneInterviewing,
  offer: colors.careerLaneOffer,
  rejected: colors.careerLaneRejected,
  accepted: colors.careerLaneAccepted,
};

const statuses = [
  "interested",
  "applied",
  "interviewing",
  "offer",
  "rejected",
  "accepted",
] as const;

const statusLabels: Record<(typeof statuses)[number], string> = {
  interested: "Interested",
  applied: "Applied",
  interviewing: "Interviewing",
  offer: "Offer",
  rejected: "Rejected",
  accepted: "Accepted",
};

const CAREER_APP_DRAG = "application/x-college-career-app";

function postingHref(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return "";
  return trimmed.startsWith("http") ? trimmed : `https://${trimmed}`;
}

function readAppDragId(e: DragEvent): string | null {
  const id = e.dataTransfer.getData(CAREER_APP_DRAG);
  return id || null;
}

const eventKinds = ["interview", "offer", "follow_up", "other"] as const;

const eventKindLabels: Record<(typeof eventKinds)[number], string> = {
  interview: "Interview",
  offer: "Offer",
  follow_up: "Follow-up",
  other: "Other",
};

const eventKindColor: Record<(typeof eventKinds)[number], string> = {
  interview: colors.careerLaneInterviewing,
  offer: colors.careerLaneOffer,
  follow_up: colors.careerLaneApplied,
  other: "var(--color-text-light)",
};

type CareerEventRow = {
  id: string;
  applicationId?: string | null;
  title: string;
  occursAt: string;
  kind: string;
  notes: string;
};

function toDatetimeLocal(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromDatetimeLocal(value: string): string {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return new Date().toISOString();
  return d.toISOString();
}

function formatEventWhen(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

type AppRow = {
  id: string;
  company: string;
  roleTitle: string;
  status: string;
  location: string;
  url: string;
  appliedAt?: string;
};

type JobBoardSmartFilter = {
  smartQuery?: string;
  keywords?: string[];
  requiredSkills?: string[];
  jobTypeKeywords?: string[];
  scheduleKeywords?: string[];
  locationKeywords?: string[];
  minMatchScore?: number | null;
  daysPostedFilter?: string;
  hideOnBoard?: boolean;
  showClosed?: boolean;
  closingSoonOnly?: boolean;
  remoteOnly?: boolean;
};

type JobBoardSmartBoardRow = {
  id: string;
  name: string;
  companyIds: string[];
  filter: JobBoardSmartFilter;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
};

type OpeningsScope =
  | { kind: "all" }
  | { kind: "company"; id: string; name: string }
  | { kind: "smartBoard"; id: string; name: string };

const statusOrder: Record<string, number> = {
  interested: 0,
  applied: 1,
  interviewing: 2,
  offer: 3,
  accepted: 4,
  rejected: 5,
};

type VaultDoc = {
  id: string;
  title: string;
  category: string;
  mimeType: string;
  fileSize: number;
  updatedAt: string;
  relativePath: string;
  hasFile: boolean;
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

function isResumeLibraryDoc(d: VaultDoc): boolean {
  if (d.category === "resume" || d.category === "general") return true;
  const t = d.title.toLowerCase();
  return t.includes("resume") || t.includes("cv");
}

type ResumeProfileRow = {
  id: string;
  vaultDocId: string;
  targetRole: string;
  targetCompany: string;
  notes: string;
  updatedAt: string;
};

const ATS_KEYWORD_PRESETS: Record<string, string> = {
  Software:
    "python javascript typescript java react node sql git agile scrum api rest microservices docker kubernetes aws azure ci cd testing debugging object oriented design algorithms data structures",
  Data:
    "python sql pandas numpy scipy machine learning statistics regression classification tableau power bi etl data visualization spark hadoop modeling analytics dashboard stakeholder",
  Finance:
    "excel financial modeling valuation dcf lbo m and a accounting gaap ifrs bloomberg capital markets equity research portfolio risk compliance forecasting budgeting presentation",
};

function profileHasNotes(p: ResumeProfileRow): boolean {
  return Boolean(p.targetRole.trim() || p.targetCompany.trim() || p.notes.trim());
}

function resumeProfileSubtitle(
  doc: VaultDoc,
  profile: ResumeProfileRow | undefined,
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

type PathEntryRow = {
  id: string;
  organization: string;
  roleTitle: string;
  startDate?: string | null;
  endDate?: string | null;
  summary: string;
  resumeDocumentId?: string | null;
};

function normalizePathOrg(org: string): string {
  return org.trim().toLowerCase() || "unknown";
}

function pathStartSortKey(startDate?: string | null): number {
  if (!startDate) return 0;
  const t = new Date(startDate).getTime();
  return Number.isNaN(t) ? 0 : t;
}

function formatPathDateRange(start?: string | null, end?: string | null): string {
  if (!start && !end) return "Dates unknown";
  return [start, end || "present"].filter(Boolean).join(" → ");
}

function formatDateLabel(value?: string | null): string {
  if (!value) return "No date";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString(undefined, { dateStyle: "medium" });
}

type BragEntryRow = {
  id: string;
  title: string;
  occurredAt?: string | null;
  summary: string;
  evidenceNote: string;
};

type NetworkContactRow = {
  id: string;
  name: string;
  organization: string;
  roleTitle: string;
  email: string;
  lastContactAt?: string | null;
  notes: string;
};

type InterviewPrepRow = {
  id: string;
  applicationId?: string | null;
  company: string;
  roleTitle: string;
  scheduledAt?: string | null;
  status: string;
  notes: string;
  questions: string;
};

const interviewStatuses = ["upcoming", "completed", "cancelled"] as const;

const interviewStatusLabels: Record<(typeof interviewStatuses)[number], string> = {
  upcoming: "Upcoming",
  completed: "Completed",
  cancelled: "Cancelled",
};

const interviewStatusColor: Record<(typeof interviewStatuses)[number], string> = {
  upcoming: colors.careerLaneInterviewing,
  completed: colors.careerLaneAccepted,
  cancelled: colors.careerLaneRejected,
};

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

const pathInspectorTabs = [
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
type PathInspectorTab = (typeof pathInspectorTabs)[number];

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

type PathMilestoneRow = {
  id: string;
  pathEntryId: string;
  title: string;
  status: string;
  dueAt?: string | null;
  notes: string;
  lane: string;
};

type PathDocumentRow = {
  id: string;
  pathEntryId: string;
  vaultDocId: string;
  note: string;
  title: string;
  category: string;
  hasFile: boolean;
};

type PathJournalEntryRow = {
  id: string;
  pathEntryId: string;
  occurredAt: string;
  title: string;
  body: string;
  mood: string;
  sortOrder: number;
};

type PathPromotionRow = {
  id: string;
  pathEntryId: string;
  title: string;
  effectiveAt?: string | null;
  notes: string;
  sortOrder: number;
};

type PathPersonRow = {
  id: string;
  pathEntryId: string;
  name: string;
  roleTitle: string;
  relationship: string;
  notes: string;
  sortOrder: number;
};

type PathBenefitRow = {
  id: string;
  pathEntryId: string;
  title: string;
  isActive: boolean;
  notes: string;
  sortOrder: number;
};

type PathCompensationRow = {
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

type PathEmploymentTerms = {
  pathEntryId: string;
  employmentType: string;
  workLocation: string;
  scheduleNotes: string;
  noticePeriod: string;
  otherTerms: string;
  updatedAt?: string | null;
};

type CareerSkillRow = {
  id: string;
  name: string;
  evidenceCount: number;
  sortOrder: number;
};

type AchievementPipeline = {
  openRoadmapItems: number;
  doneMilestones: number;
  bragWins: number;
  activeBenefits: number;
  promotions: number;
  people: number;
  compensationItems: number;
};

type PathDecisionJournal = {
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

const emptyDecisionJournal = (pathEntryId: string): PathDecisionJournal => ({
  pathEntryId,
  whyAccepted: "",
  alternatives: "",
  expectedBenefits: "",
  concerns: "",
  successCriteria: "",
  whyLeft: "",
  lessons: "",
  wouldDoDifferently: "",
  updatedAt: null,
});

const emptyEmploymentTerms = (pathEntryId: string): PathEmploymentTerms => ({
  pathEntryId,
  employmentType: "",
  workLocation: "",
  scheduleNotes: "",
  noticePeriod: "",
  otherTerms: "",
  updatedAt: null,
});

function normalizeRoadmapLane(lane: string | null | undefined): RoadmapLane {
  return roadmapLanes.includes(lane as RoadmapLane) ? (lane as RoadmapLane) : "general";
}

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

export function CareerModule({ page = "applications" }: { page?: string }) {
  const shellView =
    page === "pathing"
      ? "pathing"
      : page === "brag"
        ? "brag"
        : page === "networking"
          ? "networking"
          : page === "interview"
            ? "interview"
            : page === "stats"
              ? "stats"
              : page === "apply"
                ? "apply"
                : page === "board"
                  ? "board"
                  : page === "resumes"
                    ? "resumes"
                    : page === "openings"
                      ? "openings"
                      : "applications";
  const [layout, setLayout] = useState<"list" | "board">(
    shellView === "board" ? "board" : "list",
  );
  const [apps, setApps] = useState<AppRow[]>([]);
  const [metrics, setMetrics] = useState<PipelineMetrics | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [selectedPostingId, setSelectedPostingId] = useState<string | null>(null);
  const [dropTargetStatus, setDropTargetStatus] = useState<string | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [editingAppId, setEditingAppId] = useState<string | null>(null);
  const [pathSheet, setPathSheet] = useState(false);
  const [editingPathId, setEditingPathId] = useState<string | null>(null);
  const [postingSheet, setPostingSheet] = useState(false);
  const [form, setForm] = useState({
    company: "",
    roleTitle: "",
    status: "interested",
    location: "",
  });
  const [pathForm, setPathForm] = useState({
    organization: "",
    roleTitle: "",
    startDate: "",
    endDate: "",
    summary: "",
  });
  const [pathEntries, setPathEntries] = useState<PathEntryRow[]>([]);
  const [selectedPathId, setSelectedPathId] = useState<string | null>(null);
  const [postingForm, setPostingForm] = useState({
    company: "",
    title: "",
    location: "",
    url: "",
  });
  const [importUrlSheet, setImportUrlSheet] = useState(false);
  const [importUrl, setImportUrl] = useState("");
  const [importUrlBusy, setImportUrlBusy] = useState(false);
  const [syncBoardsSheet, setSyncBoardsSheet] = useState(false);
  const [syncBoardsBusy, setSyncBoardsBusy] = useState(false);
  const [syncBoardSources, setSyncBoardSources] = useState<string[]>([
    "remote_ok",
    "jobicy",
    "y_combinator",
  ]);
  const [syncBoardResult, setSyncBoardResult] = useState<{
    imported: number;
    updated: number;
    skipped: number;
    fetched: number;
    sources: Array<{
      source: string;
      label: string;
      imported: number;
      updated: number;
      skipped: number;
      fetched: number;
      error?: string | null;
    }>;
  } | null>(null);
  const [companyBoards, setCompanyBoards] = useState<
    Array<{
      id: string;
      displayName: string;
      careersUrl: string;
      platform: string;
      enabled: boolean;
      lastSyncedAt?: string | null;
    }>
  >([]);
  const [companyBoardForm, setCompanyBoardForm] = useState({ name: "", url: "" });
  const [companyBoardBusy, setCompanyBoardBusy] = useState(false);
  const [syncCompaniesBusy, setSyncCompaniesBusy] = useState(false);
  const [smartBoards, setSmartBoards] = useState<JobBoardSmartBoardRow[]>([]);
  const [openingsScope, setOpeningsScope] = useState<OpeningsScope>({ kind: "all" });
  const [smartBoardPostings, setSmartBoardPostings] = useState<
    Array<{
      id: string;
      company: string;
      title: string;
      location: string;
      url: string;
      postedAt?: string | null;
      trackedApplicationId?: string | null;
    }>
  >([]);
  const [smartBoardSheet, setSmartBoardSheet] = useState(false);
  const [editingSmartBoardId, setEditingSmartBoardId] = useState<string | null>(null);
  const [smartBoardForm, setSmartBoardForm] = useState({
    name: "",
    companyIds: [] as string[],
    keywords: "",
    remoteOnly: false,
    daysPostedFilter: "all",
  });
  const [smartBoardBusy, setSmartBoardBusy] = useState(false);
  const [smartBoardPostingsBusy, setSmartBoardPostingsBusy] = useState(false);
  const [postings, setPostings] = useState<
    Array<{
      id: string;
      company: string;
      title: string;
      location: string;
      url: string;
      postedAt?: string | null;
      trackedApplicationId?: string | null;
    }>
  >([]);
  const [resumeText, setResumeText] = useState("");
  const [jobText, setJobText] = useState("");
  const [matchResult, setMatchResult] = useState<{
    score: number;
    matched: string[];
    missing: string[];
  } | null>(null);
  const [vaultDocs, setVaultDocs] = useState<VaultDoc[]>([]);
  const [selectedResumeId, setSelectedResumeId] = useState<string | null>(null);
  const [resumeProfiles, setResumeProfiles] = useState<ResumeProfileRow[]>([]);
  const [resumeMetrics, setResumeMetrics] = useState<{
    vaultResumeCount: number;
    profilesWithNotesCount: number;
    lastMatchScore?: number | null;
  } | null>(null);
  const [tailoringForm, setTailoringForm] = useState({
    targetRole: "",
    targetCompany: "",
    notes: "",
  });
  const [tailoringBusy, setTailoringBusy] = useState(false);
  const [matchBusy, setMatchBusy] = useState(false);
  const [draftSheet, setDraftSheet] = useState(false);
  const [draftPane, setDraftPane] = useState<ResumeDraftPane>("markdown");
  const [draftPreviewAs, setDraftPreviewAs] = useState<"markdown" | "typst">("markdown");
  const [draftMarkdown, setDraftMarkdown] = useState("");
  const [draftTypst, setDraftTypst] = useState("");
  const [draftBusy, setDraftBusy] = useState(false);
  const [draftCompileBusy, setDraftCompileBusy] = useState(false);
  const [includeBragInDraft, setIncludeBragInDraft] = useState(true);
  const [builderLoadNonce, setBuilderLoadNonce] = useState(0);
  const [careerEvents, setCareerEvents] = useState<CareerEventRow[]>([]);
  const [eventSheet, setEventSheet] = useState(false);
  const [editingEventId, setEditingEventId] = useState<string | null>(null);
  const [eventForm, setEventForm] = useState({
    title: "",
    occursAt: "",
    kind: "interview",
    notes: "",
  });
  const [bragEntries, setBragEntries] = useState<BragEntryRow[]>([]);
  const [bragSheet, setBragSheet] = useState(false);
  const [editingBragId, setEditingBragId] = useState<string | null>(null);
  const [bragForm, setBragForm] = useState({
    title: "",
    occurredAt: "",
    summary: "",
    evidenceNote: "",
  });
  const [networkContacts, setNetworkContacts] = useState<NetworkContactRow[]>([]);
  const [selectedContactId, setSelectedContactId] = useState<string | null>(null);
  const [contactSheet, setContactSheet] = useState(false);
  const [editingContactId, setEditingContactId] = useState<string | null>(null);
  const [contactForm, setContactForm] = useState({
    name: "",
    organization: "",
    roleTitle: "",
    email: "",
    lastContactAt: "",
    notes: "",
  });
  const [interviewPrep, setInterviewPrep] = useState<InterviewPrepRow[]>([]);
  const [interviewSheet, setInterviewSheet] = useState(false);
  const [editingInterviewId, setEditingInterviewId] = useState<string | null>(null);
  const [interviewForm, setInterviewForm] = useState({
    applicationId: "",
    company: "",
    roleTitle: "",
    scheduledAt: "",
    status: "upcoming",
    notes: "",
    questions: "",
  });
  const [pathMilestones, setPathMilestones] = useState<PathMilestoneRow[]>([]);
  const [pathDocuments, setPathDocuments] = useState<PathDocumentRow[]>([]);
  const [pathJournalEntries, setPathJournalEntries] = useState<PathJournalEntryRow[]>([]);
  const [pathPromotions, setPathPromotions] = useState<PathPromotionRow[]>([]);
  const [pathPeople, setPathPeople] = useState<PathPersonRow[]>([]);
  const [pathBenefits, setPathBenefits] = useState<PathBenefitRow[]>([]);
  const [pathCompensation, setPathCompensation] = useState<PathCompensationRow[]>([]);
  const [employmentTerms, setEmploymentTerms] = useState<PathEmploymentTerms | null>(null);
  const [employmentBusy, setEmploymentBusy] = useState(false);
  const [careerSkills, setCareerSkills] = useState<CareerSkillRow[]>([]);
  const [pathPipeline, setPathPipeline] = useState<AchievementPipeline | null>(null);
  const [decisionJournal, setDecisionJournal] = useState<PathDecisionJournal | null>(null);
  const [decisionBusy, setDecisionBusy] = useState(false);
  const [skillNameDraft, setSkillNameDraft] = useState("");
  const [pathInspectorTab, setPathInspectorTab] = useState<PathInspectorTab>("overview");
  const [lastApplySessionId, setLastApplySessionId] = useState<string | null>(null);
  const [pathDocLinkSheet, setPathDocLinkSheet] = useState(false);
  const [milestoneSheet, setMilestoneSheet] = useState(false);
  const [journalSheet, setJournalSheet] = useState(false);
  const [promotionSheet, setPromotionSheet] = useState(false);
  const [personSheet, setPersonSheet] = useState(false);
  const [compensationSheet, setCompensationSheet] = useState(false);
  const [editingMilestoneId, setEditingMilestoneId] = useState<string | null>(null);
  const [editingJournalId, setEditingJournalId] = useState<string | null>(null);
  const [editingPromotionId, setEditingPromotionId] = useState<string | null>(null);
  const [editingPersonId, setEditingPersonId] = useState<string | null>(null);
  const [editingCompensationId, setEditingCompensationId] = useState<string | null>(null);
  const [milestoneForm, setMilestoneForm] = useState({
    title: "",
    status: "planned",
    dueAt: "",
    notes: "",
    lane: "general" as RoadmapLane,
  });
  const [compensationForm, setCompensationForm] = useState({
    kind: "base_salary",
    title: "",
    amount: "",
    currency: "USD",
    cadence: "yearly" as (typeof compensationCadences)[number],
    notes: "",
  });
  const [journalForm, setJournalForm] = useState({
    title: "",
    occurredAt: "",
    mood: "",
    body: "",
  });
  const [promotionForm, setPromotionForm] = useState({
    title: "",
    effectiveAt: "",
    notes: "",
  });
  const [personForm, setPersonForm] = useState({
    name: "",
    roleTitle: "",
    relationship: "",
    notes: "",
  });

  const load = useCallback(async () => {
    const [a, m, docs, posts, paths, brag, contacts, interviews, profiles, rMetrics] =
      await Promise.all([
        ipc.careerListApplications(),
        ipc.careerPipelineMetrics(),
        ipc.documentsListVault().catch(() => []),
        ipc.careerListJobPostings().catch(() => []),
        ipc.careerListPathEntries().catch(() => []),
        ipc.careerListBragEntries().catch(() => []),
        ipc.careerListNetworkContacts().catch(() => []),
        ipc.careerListInterviewPrep().catch(() => []),
        ipc.careerListResumeProfiles().catch(() => []),
        ipc.careerResumeMetrics().catch(() => null),
      ]);
    setApps(a);
    setMetrics(m);
    setVaultDocs(docs);
    setPostings(posts);
    setPathEntries(paths);
    setBragEntries(brag);
    setNetworkContacts(contacts);
    setInterviewPrep(interviews);
    setResumeProfiles(profiles);
    setResumeMetrics(rMetrics);
  }, []);

  const { refresh, error } = useLiveQuery(load, ["career", "vault"]);
  const selectedApp = apps.find((a) => a.id === selected) ?? null;

  const visiblePostings = useMemo(() => {
    if (openingsScope.kind === "smartBoard") return smartBoardPostings;
    if (openingsScope.kind === "company") {
      return postings.filter((p) => p.company.trim() === openingsScope.name.trim());
    }
    return postings;
  }, [openingsScope, postings, smartBoardPostings]);

  const selectedPosting =
    visiblePostings.find((p) => p.id === selectedPostingId) ??
    postings.find((p) => p.id === selectedPostingId) ??
    null;
  const selectedPath = pathEntries.find((p) => p.id === selectedPathId) ?? null;
  const selectedContact =
    networkContacts.find((c) => c.id === selectedContactId) ?? null;

  const pathMilestoneProgress = useMemo(() => {
    const total = pathMilestones.length;
    const done = pathMilestones.filter((m) => m.status === "done").length;
    return { total, done, ratio: total > 0 ? done / total : 0 };
  }, [pathMilestones]);

  const milestonesByLane = useMemo(() => {
    const groups = roadmapLanes.map((lane) => ({
      lane,
      items: pathMilestones.filter((m) => normalizeRoadmapLane(m.lane) === lane),
    }));
    return groups.filter((g) => g.items.length > 0);
  }, [pathMilestones]);

  const relatedPathApplications = useMemo(() => {
    if (!selectedPath) return [];
    const orgKey = normalizePathOrg(selectedPath.organization);
    return apps.filter((a) => normalizePathOrg(a.company) === orgKey);
  }, [selectedPath, apps]);

  useEffect(() => {
    if (shellView !== "openings") return;
    void ipc.careerListJobBoardCompanies().then(setCompanyBoards).catch(() => undefined);
    void ipc.careerListSmartBoards().then(setSmartBoards).catch(() => undefined);
  }, [shellView]);

  useEffect(() => {
    if (openingsScope.kind !== "smartBoard") {
      setSmartBoardPostings([]);
      setSmartBoardPostingsBusy(false);
      return;
    }
    setSmartBoardPostingsBusy(true);
    void ipc
      .careerQuerySmartBoardPostings({ smartBoardId: openingsScope.id })
      .then((rows) => {
        setSmartBoardPostings(rows);
        setSelectedPostingId((prev) =>
          prev && rows.some((r) => r.id === prev) ? prev : null,
        );
      })
      .catch(() => setSmartBoardPostings([]))
      .finally(() => setSmartBoardPostingsBusy(false));
  }, [openingsScope, postings]);

  const openSmartBoardEditor = useCallback(
    (board?: JobBoardSmartBoardRow) => {
      if (board) {
        setEditingSmartBoardId(board.id);
        setSmartBoardForm({
          name: board.name,
          companyIds: [...board.companyIds],
          keywords: (board.filter.keywords ?? []).join(", "),
          remoteOnly: board.filter.remoteOnly ?? false,
          daysPostedFilter: board.filter.daysPostedFilter ?? "all",
        });
      } else {
        setEditingSmartBoardId(null);
        setSmartBoardForm({
          name: "",
          companyIds: companyBoards.filter((c) => c.enabled).map((c) => c.id),
          keywords: "",
          remoteOnly: false,
          daysPostedFilter: "all",
        });
      }
      setSmartBoardSheet(true);
    },
    [companyBoards],
  );

  const openBragEditor = useCallback((entry?: BragEntryRow) => {
    if (entry) {
      setEditingBragId(entry.id);
      setBragForm({
        title: entry.title,
        occurredAt: entry.occurredAt?.slice(0, 10) ?? "",
        summary: entry.summary,
        evidenceNote: entry.evidenceNote,
      });
    } else {
      setEditingBragId(null);
      setBragForm({ title: "", occurredAt: "", summary: "", evidenceNote: "" });
    }
    setBragSheet(true);
  }, []);

  const openContactEditor = useCallback((contact?: NetworkContactRow) => {
    if (contact) {
      setEditingContactId(contact.id);
      setContactForm({
        name: contact.name,
        organization: contact.organization,
        roleTitle: contact.roleTitle,
        email: contact.email,
        lastContactAt: contact.lastContactAt?.slice(0, 10) ?? "",
        notes: contact.notes,
      });
    } else {
      setEditingContactId(null);
      setContactForm({
        name: "",
        organization: "",
        roleTitle: "",
        email: "",
        lastContactAt: "",
        notes: "",
      });
    }
    setContactSheet(true);
  }, []);

  const openInterviewEditor = useCallback((prep?: InterviewPrepRow) => {
    if (prep) {
      setEditingInterviewId(prep.id);
      setInterviewForm({
        applicationId: prep.applicationId ?? "",
        company: prep.company,
        roleTitle: prep.roleTitle,
        scheduledAt: prep.scheduledAt ? toDatetimeLocal(prep.scheduledAt) : "",
        status: interviewStatuses.includes(prep.status as (typeof interviewStatuses)[number])
          ? prep.status
          : "upcoming",
        notes: prep.notes,
        questions: prep.questions,
      });
    } else {
      setEditingInterviewId(null);
      setInterviewForm({
        applicationId: "",
        company: "",
        roleTitle: "",
        scheduledAt: toDatetimeLocal(new Date().toISOString()),
        status: "upcoming",
        notes: "",
        questions: "",
      });
    }
    setInterviewSheet(true);
  }, []);

  const openPathEditor = useCallback((entry: PathEntryRow) => {
    setEditingPathId(entry.id);
    setPathForm({
      organization: entry.organization,
      roleTitle: entry.roleTitle,
      startDate: entry.startDate ?? "",
      endDate: entry.endDate ?? "",
      summary: entry.summary ?? "",
    });
    setPathSheet(true);
  }, []);

  const openMilestoneEditor = useCallback((milestone?: PathMilestoneRow) => {
    if (milestone) {
      setEditingMilestoneId(milestone.id);
      setMilestoneForm({
        title: milestone.title,
        status: milestoneStatuses.includes(milestone.status as (typeof milestoneStatuses)[number])
          ? milestone.status
          : "planned",
        dueAt: milestone.dueAt?.slice(0, 10) ?? "",
        notes: milestone.notes,
        lane: normalizeRoadmapLane(milestone.lane),
      });
    } else {
      setEditingMilestoneId(null);
      setMilestoneForm({ title: "", status: "planned", dueAt: "", notes: "", lane: "general" });
    }
    setMilestoneSheet(true);
  }, []);

  const openCompensationEditor = useCallback((row?: PathCompensationRow) => {
    if (row) {
      setEditingCompensationId(row.id);
      setCompensationForm({
        kind: row.kind || "base_salary",
        title: row.title,
        amount: row.amount != null ? String(row.amount) : "",
        currency: row.currency || "USD",
        cadence: compensationCadences.includes(row.cadence as (typeof compensationCadences)[number])
          ? (row.cadence as (typeof compensationCadences)[number])
          : "yearly",
        notes: row.notes,
      });
    } else {
      setEditingCompensationId(null);
      setCompensationForm({
        kind: "base_salary",
        title: "",
        amount: "",
        currency: "USD",
        cadence: "yearly",
        notes: "",
      });
    }
    setCompensationSheet(true);
  }, []);

  const openJournalEditor = useCallback((entry?: PathJournalEntryRow) => {
    if (entry) {
      setEditingJournalId(entry.id);
      setJournalForm({
        title: entry.title,
        occurredAt: toDatetimeLocal(entry.occurredAt),
        mood: journalMoods.includes(entry.mood as (typeof journalMoods)[number])
          ? entry.mood
          : "",
        body: entry.body,
      });
    } else {
      setEditingJournalId(null);
      setJournalForm({
        title: "",
        occurredAt: toDatetimeLocal(new Date().toISOString()),
        mood: "",
        body: "",
      });
    }
    setJournalSheet(true);
  }, []);

  const openPromotionEditor = useCallback((promotion?: PathPromotionRow) => {
    if (promotion) {
      setEditingPromotionId(promotion.id);
      setPromotionForm({
        title: promotion.title,
        effectiveAt: promotion.effectiveAt?.slice(0, 10) ?? "",
        notes: promotion.notes,
      });
    } else {
      setEditingPromotionId(null);
      setPromotionForm({ title: "", effectiveAt: "", notes: "" });
    }
    setPromotionSheet(true);
  }, []);

  const openPersonEditor = useCallback((person?: PathPersonRow) => {
    if (person) {
      setEditingPersonId(person.id);
      setPersonForm({
        name: person.name,
        roleTitle: person.roleTitle,
        relationship: person.relationship,
        notes: person.notes,
      });
    } else {
      setEditingPersonId(null);
      setPersonForm({ name: "", roleTitle: "", relationship: "", notes: "" });
    }
    setPersonSheet(true);
  }, []);

  const pathByOrg = useMemo(() => {
    const map = new Map<string, { displayName: string; entries: PathEntryRow[] }>();
    for (const entry of pathEntries) {
      const key = normalizePathOrg(entry.organization);
      const group = map.get(key);
      if (group) {
        group.entries.push(entry);
      } else {
        map.set(key, {
          displayName: entry.organization.trim() || "Unknown",
          entries: [entry],
        });
      }
    }
    for (const group of map.values()) {
      group.entries.sort(
        (a, b) => pathStartSortKey(b.startDate) - pathStartSortKey(a.startDate),
      );
    }
    return [...map.entries()]
      .sort((a, b) => a[1].displayName.localeCompare(b[1].displayName))
      .map(([key, group]) => ({ key, ...group }));
  }, [pathEntries]);

  const openEventSheet = useCallback((event?: CareerEventRow) => {
    if (event) {
      setEditingEventId(event.id);
      setEventForm({
        title: event.title,
        occursAt: toDatetimeLocal(event.occursAt),
        kind: eventKinds.includes(event.kind as (typeof eventKinds)[number])
          ? event.kind
          : "other",
        notes: event.notes,
      });
    } else {
      setEditingEventId(null);
      setEventForm({
        title: "",
        occursAt: toDatetimeLocal(new Date().toISOString()),
        kind: "interview",
        notes: "",
      });
    }
    setEventSheet(true);
  }, []);

  useEffect(() => {
    if (!selected) {
      setCareerEvents([]);
      return;
    }
    void ipc
      .careerListEvents(selected)
      .then(setCareerEvents)
      .catch(() => setCareerEvents([]));
  }, [selected, apps]);

  useEffect(() => {
    if (!selectedPathId) {
      setPathMilestones([]);
      return;
    }
    void ipc
      .careerListPathMilestones(selectedPathId)
      .then(setPathMilestones)
      .catch(() => setPathMilestones([]));
  }, [selectedPathId, pathEntries]);

  useEffect(() => {
    if (!selectedPathId) {
      setPathDocuments([]);
      return;
    }
    void ipc
      .careerListPathDocuments(selectedPathId)
      .then(setPathDocuments)
      .catch(() => setPathDocuments([]));
  }, [selectedPathId, pathEntries]);

  useEffect(() => {
    if (!selectedPathId) {
      setPathJournalEntries([]);
      return;
    }
    void ipc
      .careerListPathJournalEntries(selectedPathId)
      .then(setPathJournalEntries)
      .catch(() => setPathJournalEntries([]));
  }, [selectedPathId, pathEntries]);

  useEffect(() => {
    if (!selectedPathId) {
      setPathPromotions([]);
      return;
    }
    void ipc
      .careerListPathPromotions(selectedPathId)
      .then(setPathPromotions)
      .catch(() => setPathPromotions([]));
  }, [selectedPathId, pathEntries]);

  useEffect(() => {
    if (!selectedPathId) {
      setPathPeople([]);
      return;
    }
    void ipc
      .careerListPathPeople(selectedPathId)
      .then(setPathPeople)
      .catch(() => setPathPeople([]));
  }, [selectedPathId, pathEntries]);

  useEffect(() => {
    if (!selectedPathId) {
      setPathBenefits([]);
      setPathCompensation([]);
      setEmploymentTerms(null);
      setDecisionJournal(null);
      setPathPipeline(null);
      return;
    }
    void ipc
      .careerListPathBenefits(selectedPathId)
      .then(setPathBenefits)
      .catch(() => setPathBenefits([]));
    void ipc
      .careerListPathCompensation(selectedPathId)
      .then(setPathCompensation)
      .catch(() => setPathCompensation([]));
    void ipc
      .careerGetPathEmploymentTerms(selectedPathId)
      .then(setEmploymentTerms)
      .catch(() => setEmploymentTerms(emptyEmploymentTerms(selectedPathId)));
    void ipc
      .careerGetPathDecisionJournal(selectedPathId)
      .then(setDecisionJournal)
      .catch(() => setDecisionJournal(emptyDecisionJournal(selectedPathId)));
    void ipc
      .careerPathAchievementPipeline(selectedPathId)
      .then(setPathPipeline)
      .catch(() => setPathPipeline(null));
  }, [selectedPathId, pathEntries]);

  useEffect(() => {
    void ipc
      .careerListSkills()
      .then(setCareerSkills)
      .catch(() => setCareerSkills([]));
  }, [pathEntries, bragEntries]);

  useEffect(() => {
    setPathInspectorTab("overview");
  }, [selectedPathId]);

  const linkedPathVaultIds = useMemo(
    () => new Set(pathDocuments.map((doc) => doc.vaultDocId)),
    [pathDocuments],
  );
  const linkableVaultDocs = useMemo(
    () => vaultDocs.filter((doc) => !linkedPathVaultIds.has(doc.id)),
    [vaultDocs, linkedPathVaultIds],
  );

  const interviewTimeline = selectedApp ? (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
          Interview timeline
        </p>
        <Button size="sm" variant="secondary" onClick={() => openEventSheet()}>
          Add event
        </Button>
      </div>
      {careerEvents.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">No events yet.</p>
      ) : (
        <PathTimeline
          items={careerEvents.map((event) => {
            const kind = eventKinds.includes(event.kind as (typeof eventKinds)[number])
              ? (event.kind as (typeof eventKinds)[number])
              : "other";
            return {
              id: event.id,
              title: event.title,
              subtitle: eventKindLabels[kind],
              meta: formatEventWhen(event.occursAt),
              color: eventKindColor[kind],
              onClick: () => openEventSheet(event),
            };
          })}
        />
      )}
    </div>
  ) : null;

  const resumeLibrary = useMemo(
    () => vaultDocs.filter(isResumeLibraryDoc),
    [vaultDocs],
  );
  const resumeProfileByVaultId = useMemo(() => {
    const map = new Map<string, ResumeProfileRow>();
    for (const profile of resumeProfiles) {
      map.set(profile.vaultDocId, profile);
    }
    return map;
  }, [resumeProfiles]);
  const selectedResume = resumeLibrary.find((d) => d.id === selectedResumeId) ?? null;
  const selectedResumeProfile = selectedResume
    ? resumeProfileByVaultId.get(selectedResume.id)
    : undefined;

  useEffect(() => {
    if (!selectedResume) {
      setTailoringForm({ targetRole: "", targetCompany: "", notes: "" });
      return;
    }
    const profile = resumeProfileByVaultId.get(selectedResume.id);
    setTailoringForm({
      targetRole: profile?.targetRole ?? "",
      targetCompany: profile?.targetCompany ?? "",
      notes: profile?.notes ?? "",
    });
  }, [selectedResume, resumeProfileByVaultId]);

  const builderTailoring = useMemo(() => {
    if (
      !selectedResume ||
      !(
        tailoringForm.targetRole.trim() ||
        tailoringForm.targetCompany.trim() ||
        tailoringForm.notes.trim()
      )
    ) {
      return null;
    }
    return {
      targetRole: tailoringForm.targetRole,
      targetCompany: tailoringForm.targetCompany,
      notes: tailoringForm.notes,
    };
  }, [selectedResume, tailoringForm]);

  const generateResumeDraft = useCallback(async (openSheet = true) => {
    setDraftBusy(true);
    try {
      setBuilderLoadNonce((n) => n + 1);
      const [identity, experiences, achievements, brag, skills] = await Promise.all([
        ipc.profileGetIdentity(),
        ipc.profileListExperiences(),
        ipc.profileListAchievements(),
        includeBragInDraft
          ? ipc.careerListBragEntries().catch(() => [] as BragEntryRow[])
          : Promise.resolve([] as BragEntryRow[]),
        ipc.careerListSkills().catch(() => [] as Array<{ name: string }>),
      ]);
      const draftInput = {
        identity,
        experiences,
        achievements,
        skills: skills.map((s) => s.name).filter(Boolean),
        bragEntries: brag,
        includeBragBook: includeBragInDraft,
        tailoring: builderTailoring,
      };
      setDraftMarkdown(buildResumeMarkdown(draftInput));
      setDraftTypst(buildResumeTypst(draftInput));
      if (openSheet) setDraftSheet(true);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setDraftBusy(false);
    }
  }, [includeBragInDraft, builderTailoring]);

  const effectiveLayout =
    shellView === "board"
      ? "board"
      : shellView === "pathing" ||
          shellView === "brag" ||
          shellView === "networking" ||
          shellView === "interview" ||
          shellView === "resumes" ||
          shellView === "openings"
        ? "list"
        : layout;

  const timeline = useMemo(() => {
    return [...apps].sort((a, b) => {
      const ao = statusOrder[a.status] ?? 99;
      const bo = statusOrder[b.status] ?? 99;
      if (ao !== bo) return ao - bo;
      return a.company.localeCompare(b.company);
    });
  }, [apps]);

  const byOrg = useMemo(() => {
    const map = new Map<string, AppRow[]>();
    for (const a of timeline) {
      const list = map.get(a.company) ?? [];
      list.push(a);
      map.set(a.company, list);
    }
    return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [timeline]);

  const byStatus = useMemo(() => {
    const map = new Map<string, AppRow[]>();
    for (const s of statuses) map.set(s, []);
    for (const a of apps) {
      const key = statuses.includes(a.status as (typeof statuses)[number])
        ? a.status
        : "interested";
      const list = map.get(key) ?? [];
      list.push(a);
      map.set(key, list);
    }
    return map;
  }, [apps]);

  const handleLaneDragOver = (e: DragEvent, status: string) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    setDropTargetStatus(status);
  };

  const handleLaneDrop = async (e: DragEvent, status: string) => {
    e.preventDefault();
    setDropTargetStatus(null);
    const appId = readAppDragId(e);
    if (!appId) return;
    const app = apps.find((a) => a.id === appId);
    if (!app || app.status === status) return;
    try {
      await ipc.careerMoveApplication(appId, status);
      showToast(
        `Moved to ${statusLabels[status as (typeof statuses)[number]] ?? status}`,
        "success",
      );
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const openApplyForApp = async (app: AppRow) => {
    if (!app.url.trim()) {
      showToast("No application URL to open", "error");
      return;
    }
    setLastApplySessionId(app.id);
    await openCareerApplyWindow({
      applicationId: app.id,
      company: app.company,
      roleTitle: app.roleTitle,
      url: app.url,
    });
  };

  const openApplyForPosting = async (posting: (typeof postings)[number]) => {
    if (!posting.url.trim()) {
      showToast("No posting URL to open", "error");
      return;
    }
    const applicationId = posting.trackedApplicationId ?? posting.id;
    setLastApplySessionId(applicationId);
    await openCareerApplyWindow({
      applicationId,
      company: posting.company,
      roleTitle: posting.title,
      url: posting.url,
    });
  };

  const markApplyComplete = async (applicationId: string) => {
    try {
      await ipc.careerApplyComplete(applicationId);
      setLastApplySessionId(null);
      showToast("Marked as applied", "success");
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const openBragBook = () => {
    window.dispatchEvent(
      new CustomEvent("college:navigate", { detail: { module: "career", page: "brag" } }),
    );
  };

  const openPostingInBrowser = async (url: string) => {
    const href = postingHref(url);
    if (!href) {
      showToast("No URL to open", "error");
      return;
    }
    try {
      await openUrl(href);
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  useEffect(() => {
    const onQuick = (ev: Event) => {
      const kind = (ev as CustomEvent<{ kind?: string }>).detail?.kind;
      if (kind !== "application") return;
      setEditingAppId(null);
      setForm({ company: "", roleTitle: "", status: "interested", location: "" });
      setSheetOpen(true);
    };
    window.addEventListener("college:quick-add", onQuick);
    return () => window.removeEventListener("college:quick-add", onQuick);
  }, []);

  return (
    <div className="relative flex h-full flex-col">
      <AppPageHeader
        title={
          shellView === "pathing"
            ? "Pathing"
            : shellView === "brag"
              ? "Brag Book"
              : shellView === "networking"
                ? "Networking"
                : shellView === "interview"
                  ? "Interview"
                  : shellView === "board"
                    ? "Board"
                    : shellView === "resumes"
                      ? "Resumes"
                      : shellView === "openings"
                        ? "Openings"
                        : "Applications"
        }
        leading={
          shellView === "applications" ? (
            <SegmentedPills
              value={layout}
              onChange={setLayout}
              options={[
                { id: "list", label: "List" },
                { id: "board", label: "Board" },
              ]}
            />
          ) : undefined
        }
        actions={
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            {shellView === "openings" ? (
              <>
                <Button size="sm" variant="secondary" onClick={() => openSmartBoardEditor()}>
                  Smart board
                </Button>
                <Button size="sm" variant="secondary" onClick={() => setSyncBoardsSheet(true)}>
                  Sync boards
                </Button>
                <Button size="sm" variant="secondary" onClick={() => setImportUrlSheet(true)}>
                  Import from URL
                </Button>
                <Button size="sm" onClick={() => setPostingSheet(true)}>
                  Add opening
                </Button>
              </>
            ) : shellView === "pathing" ? (
              <Button
                size="sm"
                onClick={() => {
                  setEditingPathId(null);
                  setPathForm({
                    organization: "",
                    roleTitle: "",
                    startDate: "",
                    endDate: "",
                    summary: "",
                  });
                  setPathSheet(true);
                }}
              >
                Add path entry
              </Button>
            ) : shellView === "brag" ? (
              <Button size="sm" onClick={() => openBragEditor()}>
                Add win
              </Button>
            ) : shellView === "networking" ? (
              <Button size="sm" onClick={() => openContactEditor()}>
                Add contact
              </Button>
            ) : shellView === "interview" ? (
              <Button size="sm" onClick={() => openInterviewEditor()}>
                Add prep
              </Button>
            ) : shellView === "resumes" ? (
              <>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => void openResumePopOutWindow()}
                >
                  Pop out
                </Button>
                <Button
                  size="sm"
                  disabled={draftBusy}
                  onClick={() => void generateResumeDraft(false)}
                >
                  {draftBusy ? "Loading…" : "New draft"}
                </Button>
              </>
            ) : (
              <Button
                size="sm"
                onClick={() => {
                  setEditingAppId(null);
                  setForm({ company: "", roleTitle: "", status: "interested", location: "" });
                  setSheetOpen(true);
                }}
              >
                Add application
              </Button>
            )}
          </div>
        }
      />
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}

      {shellView === "openings" && (
        <div className="min-h-0 flex-1 overflow-hidden p-3">
          <TrailingInspector
            open={Boolean(selectedPosting)}
            main={
              <AppCard title="Job openings" className="h-full overflow-auto">
                <div className="mb-3 flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    className={`rounded-full px-3 py-1 text-[12px] font-medium transition-colors ${
                      openingsScope.kind === "all"
                        ? "bg-[var(--color-primary)] text-white"
                        : "bg-[var(--color-chrome-fill)] text-[var(--color-text-main)] hover:bg-[var(--color-chrome-stroke)]"
                    }`}
                    onClick={() => {
                      setOpeningsScope({ kind: "all" });
                      setSelectedPostingId(null);
                    }}
                  >
                    All
                  </button>
                  {companyBoards
                    .filter((c) => c.enabled)
                    .map((c) => {
                      const active =
                        openingsScope.kind === "company" && openingsScope.id === c.id;
                      return (
                        <button
                          key={c.id}
                          type="button"
                          className={`rounded-full px-3 py-1 text-[12px] font-medium transition-colors ${
                            active
                              ? "bg-[var(--color-primary)] text-white"
                              : "bg-[var(--color-chrome-fill)] text-[var(--color-text-main)] hover:bg-[var(--color-chrome-stroke)]"
                          }`}
                          onClick={() => {
                            setOpeningsScope({ kind: "company", id: c.id, name: c.displayName });
                            setSelectedPostingId(null);
                          }}
                        >
                          {c.displayName}
                        </button>
                      );
                    })}
                  {smartBoards.map((board) => {
                    const active =
                      openingsScope.kind === "smartBoard" && openingsScope.id === board.id;
                    return (
                      <button
                        key={board.id}
                        type="button"
                        className={`rounded-full px-3 py-1 text-[12px] font-medium transition-colors ${
                          active
                            ? "bg-[color-mix(in_srgb,var(--color-primary)_85%,#6366f1)] text-white"
                            : "bg-[color-mix(in_srgb,var(--color-primary)_12%,var(--color-chrome-fill))] text-[var(--color-text-main)] hover:bg-[var(--color-chrome-stroke)]"
                        }`}
                        onClick={() => {
                          setOpeningsScope({
                            kind: "smartBoard",
                            id: board.id,
                            name: board.name,
                          });
                          setSelectedPostingId(null);
                        }}
                        onDoubleClick={() => openSmartBoardEditor(board)}
                        title="Double-click to edit"
                      >
                        {board.name}
                      </button>
                    );
                  })}
                  <Button size="sm" variant="ghost" onClick={() => openSmartBoardEditor()}>
                    + Smart board
                  </Button>
                </div>
                {openingsScope.kind === "smartBoard" && smartBoardPostingsBusy ? (
                  <p className="px-1 py-6 text-center text-[12px] text-[var(--color-text-light)]">
                    Loading smart board…
                  </p>
                ) : visiblePostings.length === 0 ? (
                  <EmptyState
                    title={
                      openingsScope.kind === "smartBoard"
                        ? "No matches for this smart board"
                        : "No openings yet"
                    }
                    body={
                      openingsScope.kind === "smartBoard"
                        ? "Try editing filters or sync company boards to refresh postings."
                        : "Add roles from job boards, or reload sample data from Settings."
                    }
                  />
                ) : (
                  <div className="space-y-4">
                    {[...visiblePostings
                      .reduce((map, p) => {
                        const key = p.company.trim() || "Unknown company";
                        const list = map.get(key) ?? [];
                        list.push(p);
                        map.set(key, list);
                        return map;
                      }, new Map<string, typeof visiblePostings>())
                      .entries()].map(([company, group]) => (
                      <div key={company}>
                        <div className="mb-2 flex items-center gap-2">
                          <h3 className="text-[13px] font-semibold text-[var(--color-text-main)]">
                            {company}
                          </h3>
                          <StatusChip title={`${group.length} roles`} />
                        </div>
                        <ul className="divide-y divide-[var(--color-chrome-stroke)] rounded-lg border border-[var(--color-chrome-stroke)]">
                          {group.map((p) => (
                            <li key={p.id}>
                              <ListRow
                                selected={selectedPostingId === p.id}
                                onClick={() => setSelectedPostingId(p.id)}
                                title={p.title}
                                subtitle={p.location || undefined}
                                trailing={p.trackedApplicationId ? "Tracked" : undefined}
                              />
                            </li>
                          ))}
                        </ul>
                      </div>
                    ))}
                  </div>
                )}
              </AppCard>
            }
          >
            {selectedPosting && (
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
                    {selectedPosting.title}
                  </h3>
                  <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
                    {selectedPosting.company}
                  </p>
                  {selectedPosting.location ? (
                    <div className="mt-2">
                      <StatusChip title={selectedPosting.location} />
                    </div>
                  ) : null}
                  {selectedPosting.url ? (
                    <p className="mt-2 break-all text-[11px] text-[var(--color-text-light)]">
                      {selectedPosting.url}
                    </p>
                  ) : null}
                </div>
                <div className="min-h-0 flex-1 overflow-auto p-4">
                  {selectedPosting.postedAt ? (
                    <p className="text-[12px] text-[var(--color-text-light)]">
                      Posted {formatEventWhen(selectedPosting.postedAt)}
                    </p>
                  ) : (
                    <p className="text-[12px] text-[var(--color-text-light)]">
                      Open a posting link to review the role before applying in College.
                    </p>
                  )}
                </div>
                <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                  {!selectedPosting.trackedApplicationId ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={async () => {
                        try {
                          await ipc.careerTrackJobPosting(selectedPosting.id);
                          showToast("Added to pipeline", "success");
                        } catch (err) {
                          showToast(formatIpcError(err), "error");
                        }
                      }}
                    >
                      Track
                    </Button>
                  ) : null}
                  {selectedPosting.url.trim() ? (
                    <>
                      <Button size="sm" onClick={() => void openApplyForPosting(selectedPosting)}>
                        Apply in College
                      </Button>
                      {lastApplySessionId ===
                      (selectedPosting.trackedApplicationId ?? selectedPosting.id) ? (
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() =>
                            void markApplyComplete(
                              selectedPosting.trackedApplicationId ?? selectedPosting.id,
                            )
                          }
                        >
                          Mark applied
                        </Button>
                      ) : null}
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => void openPostingInBrowser(selectedPosting.url)}
                      >
                        Open in browser
                      </Button>
                    </>
                  ) : null}
                  <Button
                    size="sm"
                    variant="danger"
                    onClick={async () => {
                      if (!confirmDelete(selectedPosting.title || "opening")) return;
                      try {
                        await ipc.careerDeleteJobPosting(selectedPosting.id);
                        setSelectedPostingId(null);
                        showToast("Opening deleted", "success");
                      } catch (err) {
                        showToast(formatIpcError(err), "error");
                      }
                    }}
                  >
                    Delete
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setSelectedPostingId(null)}>
                    Close
                  </Button>
                </div>
              </div>
            )}
          </TrailingInspector>
        </div>
      )}

      {shellView === "resumes" && (
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
            onIncludeBragBookChange={setIncludeBragInDraft}
            tailoring={builderTailoring}
            onDraftOutputsChange={({ markdown, typst }) => {
              setDraftMarkdown(markdown);
              setDraftTypst(typst);
            }}
            onOpenSourceSheet={() => {
              setDraftPane("preview");
              setDraftPreviewAs("markdown");
              setDraftSheet(true);
            }}
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
                              onClick={() => setSelectedResumeId(d.id)}
                              leading={
                                <span
                                  className="flex h-8 w-8 shrink-0 items-center justify-center text-[10px] font-bold tracking-wide"
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
                                    <StatusChip
                                      title="Tailored"
                                      tint="var(--color-primary)"
                                      filled
                                    />
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
                    <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
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
                      <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                        File
                      </p>
                      <p className="mt-1 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                        {selectedResume.hasFile
                          ? selectedResume.relativePath
                          : "No file on disk — import from Documents → Vault."}
                      </p>
                    </div>
                    <div className="space-y-3 border-t border-[var(--color-chrome-stroke)] pt-3">
                      <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                        Tailoring notes
                      </p>
                      <FormField label="Target role">
                        <input
                          className={fieldControlClass}
                          value={tailoringForm.targetRole}
                          onChange={(e) =>
                            setTailoringForm({ ...tailoringForm, targetRole: e.target.value })
                          }
                          placeholder="Software Engineer Intern"
                        />
                      </FormField>
                      <FormField label="Target company">
                        <input
                          className={fieldControlClass}
                          value={tailoringForm.targetCompany}
                          onChange={(e) =>
                            setTailoringForm({ ...tailoringForm, targetCompany: e.target.value })
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
                            setTailoringForm({ ...tailoringForm, notes: e.target.value })
                          }
                          placeholder="Emphasize ML project, trim barista bullets, mirror posting keywords…"
                        />
                      </FormField>
                      {selectedResumeProfile?.updatedAt && (
                        <p className="text-[11px] text-[var(--color-text-light)]">
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
                      onClick={async () => {
                        setTailoringBusy(true);
                        try {
                          await ipc.careerUpsertResumeProfile({
                            vaultDocId: selectedResume.id,
                            targetRole: tailoringForm.targetRole.trim(),
                            targetCompany: tailoringForm.targetCompany.trim(),
                            notes: tailoringForm.notes.trim(),
                          });
                          const [profiles, rMetrics] = await Promise.all([
                            ipc.careerListResumeProfiles(),
                            ipc.careerResumeMetrics(),
                          ]);
                          setResumeProfiles(profiles);
                          setResumeMetrics(rMetrics);
                          showToast("Tailoring notes saved", "success");
                        } catch (e) {
                          showToast(formatIpcError(e), "error");
                        } finally {
                          setTailoringBusy(false);
                        }
                      }}
                    >
                      Save notes
                    </Button>
                    <Button
                      size="sm"
                      disabled={!selectedResume.hasFile}
                      onClick={async () => {
                        const path = await ipc.documentsResolvePath(selectedResume.id);
                        if (!path) return;
                        await openPath(path);
                      }}
                    >
                      Open
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={!selectedResume.hasFile}
                      onClick={async () => {
                        const path = await ipc.documentsResolvePath(selectedResume.id);
                        if (!path) return;
                        await revealItemInDir(path);
                      }}
                    >
                      Reveal
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => setSelectedResumeId(null)}>
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
                  onChange={(e) => setResumeText(e.target.value)}
                  placeholder="Paste resume bullets or summary…"
                />
              </FormField>
              <div className="space-y-2">
                <FormField label="Job description / keywords">
                  <textarea
                    className={fieldControlClass}
                    rows={8}
                    value={jobText}
                    onChange={(e) => setJobText(e.target.value)}
                    placeholder="Paste the job posting or ATS keyword list…"
                  />
                </FormField>
                <div>
                  <p className="mb-1.5 text-[11px] text-[var(--color-text-light)]">
                    ATS keyword presets
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {Object.entries(ATS_KEYWORD_PRESETS).map(([label, keywords]) => (
                      <button
                        key={label}
                        type="button"
                        className="rounded-full border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-2.5 py-1 text-[11px] font-medium text-[var(--color-text-main)] transition-colors hover:bg-[var(--color-row-hover)]"
                        onClick={() => setJobText(keywords)}
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
                onClick={async () => {
                  setMatchBusy(true);
                  try {
                    const res = await ipc.careerResumeKeywordMatch({
                      resumeText,
                      jobText,
                    });
                    setMatchResult(res);
                    const rMetrics = await ipc.careerResumeMetrics();
                    setResumeMetrics(rMetrics);
                  } finally {
                    setMatchBusy(false);
                  }
                }}
              >
                Match keywords
              </Button>
              {matchResult && (
                <span className="text-[13px] font-semibold tabular-nums">
                  Score {(matchResult.score * 100).toFixed(0)}%
                </span>
              )}
            </div>
            {matchResult && (
              <div className="mt-3 grid gap-2 text-[12px] sm:grid-cols-2">
                <div>
                  <div className="mb-1 font-semibold text-[var(--color-success)]">Matched</div>
                  <p className="text-[var(--color-text-light)]">
                    {matchResult.matched.length
                      ? matchResult.matched.join(", ")
                      : "None yet"}
                  </p>
                </div>
                <div>
                  <div className="mb-1 font-semibold text-[var(--color-warning)]">Missing</div>
                  <p className="text-[var(--color-text-light)]">
                    {matchResult.missing.length
                      ? matchResult.missing.join(", ")
                      : "Covered"}
                  </p>
                </div>
              </div>
            )}
            {!resumeText.trim() && !jobText.trim() && resumeLibrary.length === 0 && (
              <p className="mt-3 text-[12px] text-[var(--color-text-light)]">
                No vault resumes yet — import under Documents or load sample data from Settings, then
                paste text here to compare against a posting.
              </p>
            )}
          </AppCard>
        </div>
      )}

      {(shellView === "applications" || shellView === "board") && (
        <>
          <div className="grid gap-2.5 px-3 pt-1 sm:grid-cols-3 lg:grid-cols-6">
            {(
              [
                ["Interested", metrics?.interested, colors.careerLaneInterested],
                ["Applied", metrics?.applied, colors.careerLaneApplied],
                ["Interviewing", metrics?.interviewing, colors.careerLaneInterviewing],
                ["Offer", metrics?.offer, colors.careerLaneOffer],
                ["Rejected", metrics?.rejected, colors.careerLaneRejected],
                ["Accepted", metrics?.accepted, colors.careerLaneAccepted],
              ] as const
            ).map(([label, value, accent]) => (
              <MetricTile key={label} label={label} value={value ?? 0} accent={accent} />
            ))}
          </div>
          <div className="min-h-0 flex-1 p-3 pt-3">
            {effectiveLayout === "board" ? (
              <div className="flex h-full gap-2.5 overflow-x-auto pb-1">
                {statuses.map((status) => {
                  const lane = byStatus.get(status) ?? [];
                  const isDropTarget = dropTargetStatus === status;
                  return (
                    <div
                      key={status}
                      className="flex w-[232px] shrink-0 flex-col overflow-hidden"
                      style={{
                        borderRadius: 14,
                        border: isDropTarget
                          ? "1px solid color-mix(in srgb, var(--color-primary) 55%, var(--color-chrome-stroke))"
                          : "1px solid var(--color-chrome-stroke)",
                        background: isDropTarget
                          ? "color-mix(in srgb, var(--color-primary) 8%, var(--color-surface))"
                          : "var(--color-surface)",
                        boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
                      }}
                      onDragOver={(e) => handleLaneDragOver(e, status)}
                      onDragLeave={() =>
                        setDropTargetStatus((prev) => (prev === status ? null : prev))
                      }
                      onDrop={(e) => void handleLaneDrop(e, status)}
                    >
                      <KanbanLaneHeader
                        title={statusLabels[status]}
                        count={lane.length}
                        tint={laneColor[status]!}
                      />
                      <div className="min-h-0 flex-1 space-y-2 overflow-y-auto p-2">
                        {lane.length === 0 ? (
                          <p className="px-1 py-3 text-center text-[11px] text-[var(--color-text-light)]">
                            Empty lane
                          </p>
                        ) : (
                          lane.map((a) => (
                            <button
                              key={a.id}
                              type="button"
                              draggable
                              onDragStart={(e) => {
                                e.dataTransfer.effectAllowed = "move";
                                e.dataTransfer.setData(CAREER_APP_DRAG, a.id);
                                e.dataTransfer.setData("text/plain", a.roleTitle);
                              }}
                              onClick={() => setSelected(a.id)}
                              className={`w-full px-2.5 py-2.5 text-left transition-colors ${
                                selected === a.id
                                  ? "bg-[var(--color-primary-soft)]"
                                  : "bg-[var(--color-content-surface)] hover:bg-[var(--color-row-hover)]"
                              }`}
                              style={{
                                borderRadius: 10,
                                border:
                                  selected === a.id
                                    ? "1px solid color-mix(in srgb, var(--color-primary) 40%, var(--color-chrome-stroke))"
                                    : "1px solid var(--color-chrome-stroke)",
                                boxShadow:
                                  selected === a.id
                                    ? "var(--shadow-pill)"
                                    : "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
                                cursor: "grab",
                              }}
                            >
                              <div className="truncate text-[12.5px] font-semibold tracking-[-0.01em] text-[var(--color-text-main)]">
                                {a.roleTitle}
                              </div>
                              <div className="mt-0.5 truncate text-[11px] text-[var(--color-text-light)]">
                                {a.company}
                              </div>
                              {a.location ? (
                                <div className="mt-1.5">
                                  <StatusChip title={a.location} />
                                </div>
                              ) : null}
                            </button>
                          ))
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <TrailingInspector
                open={!!selectedApp}
                main={
                  <AppCard title="Pipeline">
                    {apps.length === 0 ? (
                      <EmptyState
                        title="No applications yet"
                        body="Track roles here, or load sample data from Settings."
                      />
                    ) : (
                      <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                        {apps.map((a) => (
                          <li key={a.id}>
                            <ListRow
                              selected={selected === a.id}
                              onClick={() => setSelected(a.id)}
                              leading={
                                <LaneDot
                                  color={laneColor[a.status] ?? colors.careerLaneInterested}
                                  size={9}
                                />
                              }
                              title={a.roleTitle || "Untitled role"}
                              subtitle={`${a.company}${a.location ? ` · ${a.location}` : ""}`}
                              trailing={
                                <StatusChip
                                  title={statusLabels[a.status as (typeof statuses)[number]] ?? a.status}
                                  tint={laneColor[a.status] ?? colors.careerLaneInterested}
                                  filled
                                />
                              }
                            />
                          </li>
                        ))}
                      </ul>
                    )}
                  </AppCard>
                }
              >
                {selectedApp && (
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
                        {selectedApp.roleTitle}
                      </h3>
                      <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
                        {selectedApp.company}
                      </p>
                      <div className="mt-2">
                        <StatusChip
                          title={
                            statusLabels[selectedApp.status as (typeof statuses)[number]] ??
                            selectedApp.status
                          }
                          tint={laneColor[selectedApp.status] ?? colors.careerLaneInterested}
                          filled
                        />
                      </div>
                    </div>
                    <div className="min-h-0 flex-1 space-y-3 overflow-auto p-4">
                    <FormField label="Status">
                      <select
                        className={fieldControlClass}
                        value={selectedApp.status}
                        onChange={async (e) => {
                          await ipc.careerMoveApplication(selectedApp.id, e.target.value);
                        }}
                      >
                        {statuses.map((s) => (
                          <option key={s} value={s}>
                            {statusLabels[s]}
                          </option>
                        ))}
                      </select>
                    </FormField>
                    {selectedApp.location && (
                      <p className="text-[12px] text-[var(--color-text-light)]">
                        {selectedApp.location}
                      </p>
                    )}
                    {selectedApp.url.trim() ? (
                      <p className="break-all text-[11px] text-[var(--color-text-light)]">
                        {selectedApp.url}
                      </p>
                    ) : null}
                    {interviewTimeline}
                    </div>
                    <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                      {selectedApp.url.trim() ? (
                        <>
                          <Button size="sm" onClick={() => void openApplyForApp(selectedApp)}>
                            Apply in College
                          </Button>
                          {lastApplySessionId === selectedApp.id ? (
                            <Button
                              size="sm"
                              variant="secondary"
                              onClick={() => void markApplyComplete(selectedApp.id)}
                            >
                              Mark applied
                            </Button>
                          ) : null}
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => void openPostingInBrowser(selectedApp.url)}
                          >
                            Open in browser
                          </Button>
                        </>
                      ) : null}
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => {
                          setEditingAppId(selectedApp.id);
                          setForm({
                            company: selectedApp.company,
                            roleTitle: selectedApp.roleTitle,
                            status: selectedApp.status,
                            location: selectedApp.location || "",
                          });
                          setSheetOpen(true);
                        }}
                      >
                        Edit
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => setSelected(null)}>
                        Close
                      </Button>
                      <Button
                        size="sm"
                        variant="danger"
                        onClick={async () => {
                          if (!confirmDelete(`${selectedApp.roleTitle} @ ${selectedApp.company}`))
                            return;
                          try {
                            await ipc.careerDeleteApplication(selectedApp.id);
                            setSelected(null);
                            showToast("Application deleted", "success");
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
            )}
          </div>
        </>
      )}

      {shellView === "pathing" && (
        <div className="min-h-0 flex-1 p-3 pt-1">
          <TrailingInspector
            open={!!selectedPath}
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
                          onClick: () => setSelectedPathId(entry.id),
                        }))}
                      />
                    </AppCard>
                  ))
                )}
                {byOrg.length > 0 && (
                  <div className="space-y-3">
                    <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
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
                            selected: selected === role.id,
                            onClick: () => setSelected(role.id),
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
                  <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
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
                <div className="min-h-0 flex-1 space-y-4 overflow-auto p-4">
                  <SegmentedPills
                    value={pathInspectorTab}
                    onChange={setPathInspectorTab}
                    options={pathInspectorTabs.map((id) => ({
                      id,
                      label: pathInspectorTabLabels[id],
                    }))}
                  />

                  {pathInspectorTab === "overview" && (
                    <>
                      {pathPipeline && (
                        <div className="space-y-2 rounded-[12px] border border-[var(--color-chrome-stroke)] p-3">
                          <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                            Achievement pipeline
                          </p>
                          <p className="text-[11px] text-[var(--color-text-light)]">
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
                                onClick={() => setPathInspectorTab(tab)}
                              >
                                <div className="text-[15px] font-semibold tabular-nums text-[var(--color-primary)]">
                                  {count}
                                </div>
                                <div className="text-[10px] text-[var(--color-text-light)]">{label}</div>
                              </button>
                            ))}
                          </div>
                        </div>
                      )}
                      <div>
                        <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
                          {selectedPath.summary.trim()
                            ? selectedPath.summary
                            : "No summary yet — add notes when you edit this entry."}
                        </p>
                      </div>
                      <div className="space-y-2 border-t border-[var(--color-chrome-stroke)] pt-3">
                        <div className="flex items-center justify-between gap-2">
                          <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                            Documents
                          </p>
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => setPathDocLinkSheet(true)}
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
                                              setPathDocuments(refreshed);
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
                          <p className="text-[12px] text-[var(--color-text-light)]">
                            No linked documents — attach vault files for this path entry.
                          </p>
                        )}
                      </div>
                      {relatedPathApplications.length > 0 && (
                        <div className="space-y-2 border-t border-[var(--color-chrome-stroke)] pt-3">
                          <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                            Applications @ {selectedPath.organization}
                          </p>
                          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                            {relatedPathApplications.map((app) => (
                              <li key={app.id}>
                                <ListRow
                                  onClick={() => setSelected(app.id)}
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
                        <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                          Roadmap lanes
                        </p>
                        <Button size="sm" variant="secondary" onClick={() => openMilestoneEditor()}>
                          Add milestone
                        </Button>
                      </div>
                      {pathMilestones.length > 0 ? (
                        <>
                          <div className="flex items-center justify-between gap-2 text-[11px] text-[var(--color-text-light)]">
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
                                  <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                                    {roadmapLaneLabels[lane]}
                                  </p>
                                  <span className="text-[10px] tabular-nums text-[var(--color-text-light)]">
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
                                          onClick={() => openMilestoneEditor(milestone)}
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
                        <p className="text-[12px] text-[var(--color-text-light)]">
                          No milestones yet — add goals across Learning, Impact, Promotion, or
                          General lanes.
                        </p>
                      )}
                    </div>
                  )}

                  {pathInspectorTab === "journal" && (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                          Journal
                        </p>
                        <Button size="sm" variant="secondary" onClick={() => openJournalEditor()}>
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
                                  onClick={() => openJournalEditor(entry)}
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
                        <p className="text-[12px] text-[var(--color-text-light)]">
                          No journal entries yet — log reflections, wins, and challenges for this role.
                        </p>
                      )}
                    </div>
                  )}

                  {pathInspectorTab === "promotions" && (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                          Promotions
                        </p>
                        <Button size="sm" variant="secondary" onClick={() => openPromotionEditor()}>
                          Add promotion
                        </Button>
                      </div>
                      {pathPromotions.length > 0 ? (
                        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                          {pathPromotions.map((promotion) => (
                            <li key={promotion.id}>
                              <ListRow
                                onClick={() => openPromotionEditor(promotion)}
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
                        <p className="text-[12px] text-[var(--color-text-light)]">
                          No promotions logged — track title changes and level-ups for this role.
                        </p>
                      )}
                    </div>
                  )}

                  {pathInspectorTab === "people" && (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <p className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
                          People
                        </p>
                        <Button size="sm" variant="secondary" onClick={() => openPersonEditor()}>
                          Add person
                        </Button>
                      </div>
                      {pathPeople.length > 0 ? (
                        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                          {pathPeople.map((person) => (
                            <li key={person.id}>
                              <ListRow
                                onClick={() => openPersonEditor(person)}
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
                        <p className="text-[12px] text-[var(--color-text-light)]">
                          No people yet — note managers, mentors, and collaborators for this role.
                        </p>
                      )}
                    </div>
                  )}

                  {pathInspectorTab === "skills" && (
                    <div className="space-y-3">
                      <p className="text-[12px] text-[var(--color-text-light)]">
                        Skill graph with evidence counts. Inferred tags from brag/roadmap appear as
                        suggestions.
                      </p>
                      <div className="flex gap-2">
                        <input
                          className={fieldControlClass}
                          value={skillNameDraft}
                          onChange={(e) => setSkillNameDraft(e.target.value)}
                          placeholder="Add skill…"
                        />
                        <Button
                          size="sm"
                          disabled={!skillNameDraft.trim()}
                          onClick={async () => {
                            try {
                              await ipc.careerUpsertSkill({ name: skillNameDraft.trim() });
                              setSkillNameDraft("");
                              setCareerSkills(await ipc.careerListSkills());
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
                                <div className="text-[13px] font-medium">{s.name}</div>
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
                                    setCareerSkills(await ipc.careerListSkills());
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
                                    setCareerSkills(await ipc.careerListSkills());
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
                            <p className="mb-1.5 text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                              Suggestions
                            </p>
                            <div className="flex flex-wrap gap-1.5">
                              {suggestions.map((s) => (
                                <button
                                  key={s}
                                  type="button"
                                  className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-[11px] hover:bg-[var(--color-row-hover)]"
                                  onClick={async () => {
                                    try {
                                      await ipc.careerUpsertSkill({ name: s });
                                      setCareerSkills(await ipc.careerListSkills());
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
                          <p className="text-[12px] text-[var(--color-text-light)]">
                            Log promotions under the Promotions tab to visualize growth.
                          </p>
                        ) : (
                          <ul className="space-y-2">
                            {pathPromotions.map((p) => (
                              <li
                                key={p.id}
                                className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                              >
                                <div className="text-[13px] font-semibold">{p.title}</div>
                                {p.effectiveAt && (
                                  <p className="mt-0.5 text-[11px] text-[var(--color-text-light)]">
                                    {new Date(p.effectiveAt).toLocaleDateString()}
                                  </p>
                                )}
                              </li>
                            ))}
                          </ul>
                        )}
                      </AppCard>
                      <AppCard title="Benefits">
                        <p className="mb-2 text-[12px] text-[var(--color-text-light)]">
                          Track what you have vs. what you expected. Presets seed rows quickly.
                        </p>
                        <div className="mb-3 flex flex-wrap gap-1.5">
                          {BENEFIT_PRESETS.filter(
                            (p) => !pathBenefits.some((b) => b.title.toLowerCase() === p.toLowerCase()),
                          ).map((preset) => (
                            <button
                              key={preset}
                              type="button"
                              className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-[11px] hover:bg-[var(--color-row-hover)]"
                              onClick={async () => {
                                try {
                                  await ipc.careerUpsertPathBenefit({
                                    pathEntryId: selectedPath.id,
                                    title: preset,
                                    isActive: false,
                                  });
                                  setPathBenefits(
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
                                        setPathBenefits(
                                          await ipc.careerListPathBenefits(selectedPath.id),
                                        );
                                        setPathPipeline(
                                          await ipc.careerPathAchievementPipeline(selectedPath.id),
                                        );
                                      } catch (e) {
                                        showToast(formatIpcError(e), "error");
                                      }
                                    }}
                                  />
                                  <span
                                    className={`text-[13px] ${
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
                                      setPathBenefits(
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
                        setPathEntries(refreshed);
                        setSelectedPathId(targetId);
                        setPathInspectorTab("overview");
                      }}
                    />
                  )}

                  {pathInspectorTab === "resume" && selectedPath && (
                    <PathingResumePanel
                      entryId={selectedPath.id}
                      resumeDocumentId={selectedPath.resumeDocumentId}
                      vaultDocs={vaultDocs}
                      onSaved={(resumeDocumentId) => {
                        setPathEntries((prev) =>
                          prev.map((e) =>
                            e.id === selectedPath.id ? { ...e, resumeDocumentId } : e,
                          ),
                        );
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
                    <PathingStoriesPanel bragEntries={bragEntries} onOpenBragBook={openBragBook} />
                  )}

                  {pathInspectorTab === "compensation" && employmentTerms && (
                    <div className="space-y-3">
                      <AppCard title="Compensation">
                        <p className="mb-2 text-[12px] text-[var(--color-text-light)]">
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
                              className="rounded-full border border-[var(--color-chrome-stroke)] px-2.5 py-1 text-[11px] hover:bg-[var(--color-row-hover)]"
                              onClick={async () => {
                                try {
                                  await ipc.careerUpsertPathCompensation({
                                    pathEntryId: selectedPath.id,
                                    kind: preset.kind,
                                    title: preset.title,
                                    currency: "USD",
                                    cadence: "yearly",
                                  });
                                  setPathCompensation(
                                    await ipc.careerListPathCompensation(selectedPath.id),
                                  );
                                  setPathPipeline(
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
                            onClick={() => openCompensationEditor()}
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
                                  onClick={() => openCompensationEditor(row)}
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
                                setEmploymentTerms({
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
                                setEmploymentTerms({
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
                                setEmploymentTerms({
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
                                setEmploymentTerms({
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
                                setEmploymentTerms({
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
                              setEmploymentBusy(true);
                              try {
                                await ipc.careerUpsertPathEmploymentTerms({
                                  pathEntryId: selectedPath.id,
                                  employmentType: employmentTerms.employmentType,
                                  workLocation: employmentTerms.workLocation,
                                  scheduleNotes: employmentTerms.scheduleNotes,
                                  noticePeriod: employmentTerms.noticePeriod,
                                  otherTerms: employmentTerms.otherTerms,
                                });
                                setEmploymentTerms(
                                  await ipc.careerGetPathEmploymentTerms(selectedPath.id),
                                );
                                showToast("Employment terms saved", "success");
                              } catch (e) {
                                showToast(formatIpcError(e), "error");
                              } finally {
                                setEmploymentBusy(false);
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
                      <p className="text-[12px] text-[var(--color-text-light)]">
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
                              setDecisionJournal({ ...decisionJournal, [key]: e.target.value })
                            }
                          />
                        </FormField>
                      ))}
                      <Button
                        size="sm"
                        disabled={decisionBusy}
                        onClick={async () => {
                          setDecisionBusy(true);
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
                            setDecisionBusy(false);
                          }
                        }}
                      >
                        Save journal
                      </Button>
                    </div>
                  )}

                  {pathInspectorTab === "pipeline" && pathPipeline && (
                    <div className="space-y-3">
                      <p className="text-[12px] text-[var(--color-text-light)]">
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
                          onClick={() => setPathInspectorTab(tab)}
                        >
                          <div>
                            <div className="text-[13px] font-medium text-[var(--color-text-main)]">
                              {title}
                            </div>
                            <div className="text-[11px] text-[var(--color-text-light)]">{hint}</div>
                          </div>
                          <span className="text-[18px] font-semibold tabular-nums text-[var(--color-primary)]">
                            {count}
                          </span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
                <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                  <Button size="sm" variant="secondary" onClick={() => openPathEditor(selectedPath)}>
                    Edit
                  </Button>
                  <Button
                    size="sm"
                    variant="danger"
                    onClick={async () => {
                      if (
                        !confirmDelete(
                          `${selectedPath.roleTitle.trim() || "entry"} @ ${selectedPath.organization.trim() || "org"}`,
                        )
                      )
                        return;
                      try {
                        await ipc.careerDeletePathEntry(selectedPath.id);
                        setSelectedPathId(null);
                        showToast("Path entry deleted", "success");
                      } catch (e) {
                        showToast(formatIpcError(e), "error");
                      }
                    }}
                  >
                    Delete
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setSelectedPathId(null)}>
                    Close
                  </Button>
                </div>
              </div>
            )}
          </TrailingInspector>
        </div>
      )}

      {shellView === "stats" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          <AppCard title="Pipeline stats">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <MetricTile label="Total" value={metrics?.total ?? apps.length} accent="var(--color-primary)" />
              <MetricTile label="Applied" value={metrics?.applied ?? "—"} />
              <MetricTile label="Interviewing" value={metrics?.interviewing ?? "—"} accent="var(--color-success)" />
              <MetricTile label="Offers" value={metrics?.offer ?? "—"} accent="var(--color-success)" />
            </div>
            <Button size="sm" variant="secondary" className="mt-3" onClick={() => shellNavigate("career", "board")}>
              Open board
            </Button>
          </AppCard>
        </div>
      )}

      {shellView === "apply" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          <AppCard title="Apply profile">
            <p className="mb-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
              Default autofill payload for Tier A–C apply flows. Edit identity in Profile, then run autofill
              from an application row.
            </p>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={() => shellNavigate("profile", "identity")}>
                Edit identity
              </Button>
              <Button size="sm" variant="secondary" onClick={() => shellNavigate("career", "applications")}>
                Open applications
              </Button>
            </div>
          </AppCard>
        </div>
      )}

      {shellView === "brag" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          {bragEntries.length === 0 ? (
            <AppCard title="Brag Book">
              <EmptyState
                title="No wins logged yet"
                body="Capture accomplishments, metrics, and evidence for interviews and performance reviews."
              />
            </AppCard>
          ) : (
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
              {bragEntries.map((entry) => (
                <button
                  key={entry.id}
                  type="button"
                  onClick={() => openBragEditor(entry)}
                  className="text-left transition-colors hover:bg-[var(--color-row-hover)]"
                  style={{
                    borderRadius: 12,
                    border: "1px solid var(--color-chrome-stroke)",
                    background: "var(--color-content-surface)",
                    boxShadow: "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
                    padding: "14px 16px",
                  }}
                >
                  <div className="flex items-start justify-between gap-2">
                    <h3
                      className="text-[var(--color-text-main)]"
                      style={{ font: "var(--type-section-title)", fontSize: 14 }}
                    >
                      {entry.title}
                    </h3>
                    <StatusChip title={formatDateLabel(entry.occurredAt)} filled />
                  </div>
                  {entry.summary.trim() ? (
                    <p className="mt-2 line-clamp-3 text-[12px] leading-relaxed text-[var(--color-text-light)]">
                      {entry.summary}
                    </p>
                  ) : (
                    <p className="mt-2 text-[12px] text-[var(--color-text-light)]">No summary</p>
                  )}
                  {entry.evidenceNote.trim() ? (
                    <p className="mt-2 text-[11px] text-[var(--color-text-light)]">
                      Evidence: {entry.evidenceNote}
                    </p>
                  ) : null}
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {shellView === "networking" && (
        <div className="min-h-0 flex-1 p-3 pt-1">
          <TrailingInspector
            open={!!selectedContact}
            main={
              <AppCard title="Contacts">
                {networkContacts.length === 0 ? (
                  <EmptyState
                    title="No contacts yet"
                    body="Track recruiters, alumni, and mentors you meet along the way."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {networkContacts.map((contact) => (
                      <li key={contact.id}>
                        <ListRow
                          selected={selectedContactId === contact.id}
                          onClick={() => setSelectedContactId(contact.id)}
                          title={contact.name}
                          subtitle={[
                            contact.roleTitle,
                            contact.organization,
                            contact.email,
                          ]
                            .filter(Boolean)
                            .join(" · ")}
                          trailing={
                            <StatusChip
                              title={formatDateLabel(contact.lastContactAt)}
                              tint="var(--color-primary)"
                            />
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
            }
          >
            {selectedContact && (
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
                    {selectedContact.name}
                  </h3>
                  <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
                    {[selectedContact.roleTitle, selectedContact.organization]
                      .filter(Boolean)
                      .join(" @ ") || "No org"}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {selectedContact.email ? (
                      <StatusChip title={selectedContact.email} tint="var(--color-primary)" />
                    ) : null}
                    <StatusChip
                      title={`Last: ${formatDateLabel(selectedContact.lastContactAt)}`}
                      filled
                    />
                  </div>
                </div>
                <div className="min-h-0 flex-1 overflow-auto p-4">
                  <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
                    {selectedContact.notes.trim()
                      ? selectedContact.notes
                      : "No notes yet — add context when you edit this contact."}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => openContactEditor(selectedContact)}
                  >
                    Edit
                  </Button>
                  <Button
                    size="sm"
                    variant="danger"
                    onClick={async () => {
                      if (!confirmDelete(selectedContact.name || "contact")) return;
                      try {
                        await ipc.careerDeleteNetworkContact(selectedContact.id);
                        setSelectedContactId(null);
                        showToast("Contact deleted", "success");
                      } catch (e) {
                        showToast(formatIpcError(e), "error");
                      }
                    }}
                  >
                    Delete
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setSelectedContactId(null)}>
                    Close
                  </Button>
                </div>
              </div>
            )}
          </TrailingInspector>
        </div>
      )}

      {shellView === "interview" && (
        <div className="min-h-0 flex-1 overflow-auto p-3">
          <AppCard title="Interview prep">
            {interviewPrep.length === 0 ? (
              <EmptyState
                title="No interviews scheduled"
                body="Plan questions, notes, and status for upcoming screens and onsite loops."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {interviewPrep.map((prep) => {
                  const linkedApp = prep.applicationId
                    ? apps.find((a) => a.id === prep.applicationId)
                    : null;
                  const status = interviewStatuses.includes(
                    prep.status as (typeof interviewStatuses)[number],
                  )
                    ? (prep.status as (typeof interviewStatuses)[number])
                    : "upcoming";
                  return (
                    <li key={prep.id}>
                      <ListRow
                        onClick={() => openInterviewEditor(prep)}
                        title={prep.roleTitle || "Untitled role"}
                        subtitle={[
                          prep.company,
                          prep.scheduledAt ? formatEventWhen(prep.scheduledAt) : null,
                          linkedApp
                            ? `App: ${linkedApp.roleTitle} @ ${linkedApp.company}`
                            : null,
                        ]
                          .filter(Boolean)
                          .join(" · ")}
                        trailing={
                          <StatusChip
                            title={interviewStatusLabels[status]}
                            tint={interviewStatusColor[status]}
                            filled
                          />
                        }
                      />
                    </li>
                  );
                })}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {effectiveLayout === "board" && selectedApp && (
        <div
          className="absolute bottom-4 right-4 z-20 w-[320px] overflow-hidden"
          style={{
            borderRadius: 14,
            border: "1px solid var(--color-chrome-stroke)",
            background: "var(--color-content-surface)",
            boxShadow: "0 12px 40px rgba(0,0,0,0.14), inset 0 1px 0 color-mix(in srgb, white 40%, transparent)",
          }}
        >
          <div
            className="border-b border-[var(--color-chrome-stroke)] px-4 py-3"
            style={{
              background: `linear-gradient(90deg, color-mix(in srgb, ${laneColor[selectedApp.status] ?? colors.careerLaneInterested} 14%, transparent), transparent)`,
            }}
          >
            <h3
              className="text-[var(--color-text-main)]"
              style={{ font: "var(--type-section-title)", fontSize: 15, letterSpacing: "-0.02em" }}
            >
              {selectedApp.roleTitle}
            </h3>
            <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">{selectedApp.company}</p>
            <div className="mt-2">
              <StatusChip
                title={
                  statusLabels[selectedApp.status as (typeof statuses)[number]] ??
                  selectedApp.status
                }
                tint={laneColor[selectedApp.status] ?? colors.careerLaneInterested}
                filled
              />
            </div>
          </div>
          <div className="space-y-3 p-4">
            <FormField label="Move to">
              <select
                className={fieldControlClass}
                value={selectedApp.status}
                onChange={async (e) => {
                  await ipc.careerMoveApplication(selectedApp.id, e.target.value);
                }}
              >
                {statuses.map((s) => (
                  <option key={s} value={s}>
                    {statusLabels[s]}
                  </option>
                ))}
              </select>
            </FormField>
            {interviewTimeline}
            {selectedApp.url.trim() ? (
              <p className="break-all text-[11px] text-[var(--color-text-light)]">
                {selectedApp.url}
              </p>
            ) : null}
            <div className="flex flex-wrap gap-2">
              {selectedApp.url.trim() ? (
                <>
                  <Button size="sm" onClick={() => void openApplyForApp(selectedApp)}>
                    Apply in College
                  </Button>
                  {lastApplySessionId === selectedApp.id ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => void markApplyComplete(selectedApp.id)}
                    >
                      Mark applied
                    </Button>
                  ) : null}
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => void openPostingInBrowser(selectedApp.url)}
                  >
                    Open in browser
                  </Button>
                </>
              ) : null}
              <Button size="sm" variant="ghost" onClick={() => setSelected(null)}>
                Close
              </Button>
              <Button
                size="sm"
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(`${selectedApp.roleTitle} @ ${selectedApp.company}`)) return;
                  try {
                    await ipc.careerDeleteApplication(selectedApp.id);
                    setSelected(null);
                    showToast("Application deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            </div>
          </div>
        </div>
      )}

      <ModalSheet
        open={sheetOpen}
        onOpenChange={setSheetOpen}
        title={editingAppId ? "Edit application" : "Add application"}
      >
        <div className="space-y-3">
          <FormField label="Company">
            <input
              className={fieldControlClass}
              value={form.company}
              onChange={(e) => setForm({ ...form, company: e.target.value })}
            />
          </FormField>
          <FormField label="Role">
            <input
              className={fieldControlClass}
              value={form.roleTitle}
              onChange={(e) => setForm({ ...form, roleTitle: e.target.value })}
            />
          </FormField>
          <FormField label="Location">
            <input
              className={fieldControlClass}
              value={form.location}
              onChange={(e) => setForm({ ...form, location: e.target.value })}
            />
          </FormField>
          <FormField label="Status">
            <select
              className={fieldControlClass}
              value={form.status}
              onChange={(e) => setForm({ ...form, status: e.target.value })}
            >
              {statuses.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </FormField>
          <Button
            disabled={!form.company.trim() || !form.roleTitle.trim()}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingAppId);
                await ipc.careerUpsertApplication({
                  id: editingAppId ?? undefined,
                  company: form.company.trim(),
                  roleTitle: form.roleTitle.trim(),
                  status: form.status,
                  location: form.location.trim() || undefined,
                });
                setSheetOpen(false);
                setEditingAppId(null);
                setForm({ company: "", roleTitle: "", status: "interested", location: "" });
                showToast(wasEdit ? "Application updated" : "Application saved", "success");
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
        open={pathSheet}
        onOpenChange={setPathSheet}
        title={editingPathId ? "Edit path entry" : "Add path entry"}
      >
        <div className="space-y-3">
          <FormField label="Organization">
            <input
              className={fieldControlClass}
              value={pathForm.organization}
              onChange={(e) => setPathForm({ ...pathForm, organization: e.target.value })}
            />
          </FormField>
          <FormField label="Role">
            <input
              className={fieldControlClass}
              value={pathForm.roleTitle}
              onChange={(e) => setPathForm({ ...pathForm, roleTitle: e.target.value })}
            />
          </FormField>
          <FormField label="Start (YYYY-MM-DD)">
            <input
              className={fieldControlClass}
              value={pathForm.startDate}
              onChange={(e) => setPathForm({ ...pathForm, startDate: e.target.value })}
              placeholder="2024-06-01"
            />
          </FormField>
          <FormField label="End (blank = present)">
            <input
              className={fieldControlClass}
              value={pathForm.endDate}
              onChange={(e) => setPathForm({ ...pathForm, endDate: e.target.value })}
            />
          </FormField>
          <FormField label="Summary">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={pathForm.summary}
              onChange={(e) => setPathForm({ ...pathForm, summary: e.target.value })}
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!pathForm.organization.trim() || !pathForm.roleTitle.trim()}
              onClick={async () => {
                try {
                  const wasEdit = Boolean(editingPathId);
                  await ipc.careerUpsertPathEntry({
                    id: editingPathId ?? undefined,
                    organization: pathForm.organization.trim(),
                    roleTitle: pathForm.roleTitle.trim(),
                    startDate: pathForm.startDate.trim() || undefined,
                    endDate: pathForm.endDate.trim() || undefined,
                    summary: pathForm.summary.trim() || undefined,
                  });
                  setPathSheet(false);
                  setEditingPathId(null);
                  showToast(wasEdit ? "Path entry updated" : "Path entry saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingPathId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (
                    !confirmDelete(
                      `${pathForm.roleTitle.trim() || "entry"} @ ${pathForm.organization.trim() || "org"}`,
                    )
                  )
                    return;
                  try {
                    await ipc.careerDeletePathEntry(editingPathId);
                    setPathSheet(false);
                    setEditingPathId(null);
                    setSelectedPathId(null);
                    showToast("Path entry deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet open={postingSheet} onOpenChange={setPostingSheet} title="Add opening">
        <div className="space-y-3">
          <FormField label="Company">
            <input
              className={fieldControlClass}
              value={postingForm.company}
              onChange={(e) => setPostingForm({ ...postingForm, company: e.target.value })}
            />
          </FormField>
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={postingForm.title}
              onChange={(e) => setPostingForm({ ...postingForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Location">
            <input
              className={fieldControlClass}
              value={postingForm.location}
              onChange={(e) => setPostingForm({ ...postingForm, location: e.target.value })}
            />
          </FormField>
          <FormField label="URL">
            <input
              className={fieldControlClass}
              value={postingForm.url}
              onChange={(e) => setPostingForm({ ...postingForm, url: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!postingForm.company.trim() || !postingForm.title.trim()}
            onClick={async () => {
              await ipc.careerUpsertJobPosting({
                company: postingForm.company.trim(),
                title: postingForm.title.trim(),
                location: postingForm.location.trim() || undefined,
                url: postingForm.url.trim() || undefined,
                postedAt: new Date().toISOString(),
              });
              setPostingSheet(false);
              setPostingForm({ company: "", title: "", location: "", url: "" });
            }}
          >
            Save opening
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={importUrlSheet}
        onOpenChange={(open) => {
          setImportUrlSheet(open);
          if (!open) {
            setImportUrl("");
            setImportUrlBusy(false);
          }
        }}
        title="Import from URL"
      >
        <div className="space-y-3">
          <p className="text-[12px] text-[var(--color-text-light)]">
            Paste a job posting link. College fetches the page and extracts title, company, and
            description heuristics into Openings.
          </p>
          <FormField label="Posting URL">
            <input
              className={fieldControlClass}
              value={importUrl}
              onChange={(e) => setImportUrl(e.target.value)}
              placeholder="https://careers.example.com/jobs/123"
              autoFocus
            />
          </FormField>
          <Button
            disabled={!importUrl.trim() || importUrlBusy}
            onClick={async () => {
              setImportUrlBusy(true);
              try {
                const id = await ipc.careerImportJobFromUrl(importUrl.trim());
                setImportUrlSheet(false);
                setImportUrl("");
                setSelectedPostingId(id);
                await refresh();
                showToast("Opening imported", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              } finally {
                setImportUrlBusy(false);
              }
            }}
          >
            {importUrlBusy ? "Importing…" : "Import opening"}
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={smartBoardSheet}
        onOpenChange={(open) => {
          setSmartBoardSheet(open);
          if (!open) {
            setEditingSmartBoardId(null);
            setSmartBoardBusy(false);
          } else if (!editingSmartBoardId && companyBoards.length > 0) {
            void ipc.careerListJobBoardCompanies().then(setCompanyBoards).catch(() => undefined);
          }
        }}
        title={editingSmartBoardId ? "Edit smart board" : "Create smart board"}
      >
        <div className="space-y-4">
          <p className="text-[12px] text-[var(--color-text-light)]">
            Combine multiple company boards with keyword and remote filters.
          </p>
          <FormField label="Board name">
            <input
              className={fieldControlClass}
              value={smartBoardForm.name}
              onChange={(e) => setSmartBoardForm((f) => ({ ...f, name: e.target.value }))}
              placeholder="e.g. Remote SWE internships"
              autoFocus
            />
          </FormField>
          <FormField label="Companies">
            {companyBoards.filter((c) => c.enabled).length === 0 ? (
              <p className="text-[12px] text-[var(--color-text-light)]">
                Add company boards under Sync boards first.
              </p>
            ) : (
              <ul className="max-h-40 divide-y divide-[var(--color-chrome-stroke)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)]">
                {companyBoards
                  .filter((c) => c.enabled)
                  .map((c) => {
                    const checked = smartBoardForm.companyIds.includes(c.id);
                    return (
                      <li key={c.id} className="px-3 py-2">
                        <label className="flex cursor-pointer items-center gap-2 text-[13px]">
                          <input
                            type="checkbox"
                            checked={checked}
                            onChange={(e) => {
                              setSmartBoardForm((f) => ({
                                ...f,
                                companyIds: e.target.checked
                                  ? [...f.companyIds, c.id]
                                  : f.companyIds.filter((id) => id !== c.id),
                              }));
                            }}
                          />
                          <span className="font-medium text-[var(--color-text-main)]">
                            {c.displayName}
                          </span>
                          <span className="text-[var(--color-text-light)]">{c.platform}</span>
                        </label>
                      </li>
                    );
                  })}
              </ul>
            )}
          </FormField>
          <FormField label="Keywords">
            <input
              className={fieldControlClass}
              value={smartBoardForm.keywords}
              onChange={(e) => setSmartBoardForm((f) => ({ ...f, keywords: e.target.value }))}
              placeholder="software, intern, python (comma-separated)"
            />
          </FormField>
          <FormField label="Posted within">
            <select
              className={fieldControlClass}
              value={smartBoardForm.daysPostedFilter}
              onChange={(e) =>
                setSmartBoardForm((f) => ({ ...f, daysPostedFilter: e.target.value }))
              }
            >
              <option value="all">Any time</option>
              <option value="day1">Last 24 hours</option>
              <option value="days7">Last 7 days</option>
              <option value="days30">Last 30 days</option>
              <option value="thirtyPlusDays">30+ days ago</option>
            </select>
          </FormField>
          <label className="flex items-center gap-2 text-[13px] text-[var(--color-text-main)]">
            <input
              type="checkbox"
              checked={smartBoardForm.remoteOnly}
              onChange={(e) =>
                setSmartBoardForm((f) => ({ ...f, remoteOnly: e.target.checked }))
              }
            />
            Remote only
          </label>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={
                smartBoardBusy ||
                !smartBoardForm.name.trim() ||
                smartBoardForm.companyIds.length === 0
              }
              onClick={async () => {
                setSmartBoardBusy(true);
                try {
                  const keywords = smartBoardForm.keywords
                    .split(",")
                    .map((k) => k.trim())
                    .filter(Boolean);
                  const id = await ipc.careerUpsertSmartBoard({
                    id: editingSmartBoardId ?? undefined,
                    name: smartBoardForm.name.trim(),
                    companyIds: smartBoardForm.companyIds,
                    filter: {
                      keywords,
                      remoteOnly: smartBoardForm.remoteOnly,
                      daysPostedFilter: smartBoardForm.daysPostedFilter,
                    },
                  });
                  const boards = await ipc.careerListSmartBoards();
                  setSmartBoards(boards);
                  setSmartBoardSheet(false);
                  setOpeningsScope({
                    kind: "smartBoard",
                    id,
                    name: smartBoardForm.name.trim(),
                  });
                  showToast(
                    editingSmartBoardId ? "Smart board updated" : "Smart board created",
                    "success",
                  );
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                } finally {
                  setSmartBoardBusy(false);
                }
              }}
            >
              {smartBoardBusy ? "Saving…" : "Save smart board"}
            </Button>
            {editingSmartBoardId ? (
              <Button
                variant="danger"
                disabled={smartBoardBusy}
                onClick={async () => {
                  if (!confirmDelete(smartBoardForm.name)) return;
                  setSmartBoardBusy(true);
                  try {
                    await ipc.careerDeleteSmartBoard(editingSmartBoardId);
                    setSmartBoards(await ipc.careerListSmartBoards());
                    setSmartBoardSheet(false);
                    if (
                      openingsScope.kind === "smartBoard" &&
                      openingsScope.id === editingSmartBoardId
                    ) {
                      setOpeningsScope({ kind: "all" });
                    }
                    showToast("Smart board deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  } finally {
                    setSmartBoardBusy(false);
                  }
                }}
              >
                Delete
              </Button>
            ) : null}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={syncBoardsSheet}
        onOpenChange={(open) => {
          setSyncBoardsSheet(open);
          if (!open) {
            setSyncBoardResult(null);
            setSyncBoardsBusy(false);
            setSyncCompaniesBusy(false);
          } else {
            void ipc.careerListJobBoardCompanies().then(setCompanyBoards).catch(() => undefined);
          }
        }}
        title="Sync job boards"
      >
        <div className="space-y-4">
          <div className="space-y-3">
            <p className="text-[12px] text-[var(--color-text-light)]">
              Company boards (Greenhouse, Workday, Lever, Oracle, iCIMS, Talemetry) — paste a careers URL, then sync into
              Openings.
            </p>
            <div className="flex flex-col gap-2 sm:flex-row">
              <input
                className={`${fieldControlClass} flex-1`}
                placeholder="Company name"
                value={companyBoardForm.name}
                onChange={(e) =>
                  setCompanyBoardForm((f) => ({ ...f, name: e.target.value }))
                }
              />
              <input
                className={`${fieldControlClass} flex-[2]`}
                placeholder="https://boards.greenhouse.io/… · myworkdayjobs.com · oraclecloud · icims…"
                value={companyBoardForm.url}
                onChange={(e) =>
                  setCompanyBoardForm((f) => ({ ...f, url: e.target.value }))
                }
              />
              <Button
                size="sm"
                disabled={companyBoardBusy || !companyBoardForm.url.trim()}
                onClick={async () => {
                  setCompanyBoardBusy(true);
                  try {
                    await ipc.careerUpsertJobBoardCompany({
                      displayName: companyBoardForm.name.trim() || "Company",
                      careersUrl: companyBoardForm.url.trim(),
                      enabled: true,
                    });
                    setCompanyBoardForm({ name: "", url: "" });
                    setCompanyBoards(await ipc.careerListJobBoardCompanies());
                    showToast("Company board saved", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  } finally {
                    setCompanyBoardBusy(false);
                  }
                }}
              >
                Add
              </Button>
            </div>
            {companyBoards.length === 0 ? (
              <p className="text-[12px] text-[var(--color-text-light)]">No company boards yet.</p>
            ) : (
              <ul className="max-h-40 divide-y divide-[var(--color-chrome-stroke)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)]">
                {companyBoards.map((c) => (
                  <li
                    key={c.id}
                    className="flex items-center justify-between gap-2 px-3 py-2 text-[12px]"
                  >
                    <span className="min-w-0">
                      <span className="block truncate font-medium text-[var(--color-text-main)]">
                        {c.displayName}
                      </span>
                      <span className="block truncate text-[var(--color-text-light)]">
                        {c.platform} · {c.careersUrl}
                      </span>
                    </span>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={async () => {
                        try {
                          await ipc.careerDeleteJobBoardCompany(c.id);
                          setCompanyBoards(await ipc.careerListJobBoardCompanies());
                        } catch (e) {
                          showToast(formatIpcError(e), "error");
                        }
                      }}
                    >
                      Remove
                    </Button>
                  </li>
                ))}
              </ul>
            )}
            <Button
              disabled={syncCompaniesBusy || companyBoards.length === 0}
              onClick={async () => {
                setSyncCompaniesBusy(true);
                setSyncBoardResult(null);
                try {
                  const res = await ipc.careerSyncJobBoardCompanies();
                  setSyncBoardResult(res);
                  setCompanyBoards(await ipc.careerListJobBoardCompanies());
                  await refresh();
                  showToast(
                    `Company boards: ${res.imported} new, ${res.updated} updated`,
                    "success",
                  );
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                } finally {
                  setSyncCompaniesBusy(false);
                }
              }}
            >
              {syncCompaniesBusy ? "Syncing companies…" : "Sync company boards"}
            </Button>
          </div>

          <div className="space-y-3 border-t border-[var(--color-chrome-stroke)] pt-3">
            <p className="text-[12px] text-[var(--color-text-light)]">
              Public hubs (RemoteOK, Jobicy, Y Combinator) — rate-limited; may fail if a board blocks
              automated access.
            </p>
            <div className="space-y-2">
              {[
                { id: "remote_ok", label: "RemoteOK" },
                { id: "jobicy", label: "Jobicy" },
                { id: "y_combinator", label: "Y Combinator" },
                { id: "built_in", label: "Built In" },
                { id: "usajobs", label: "USAJobs" },
              ].map((src) => (
                <label key={src.id} className="flex items-center gap-2 text-[13px]">
                  <input
                    type="checkbox"
                    checked={syncBoardSources.includes(src.id)}
                    onChange={(e) => {
                      setSyncBoardSources((prev) =>
                        e.target.checked ? [...prev, src.id] : prev.filter((s) => s !== src.id),
                      );
                    }}
                  />
                  {src.label}
                </label>
              ))}
            </div>
            <Button
              disabled={syncBoardsBusy || syncBoardSources.length === 0}
              onClick={async () => {
                setSyncBoardsBusy(true);
                setSyncBoardResult(null);
                try {
                  const res = await ipc.careerSyncJobBoards({ sources: syncBoardSources });
                  setSyncBoardResult(res);
                  await refresh();
                  showToast(`Hubs: ${res.imported} new, ${res.updated} updated`, "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                } finally {
                  setSyncBoardsBusy(false);
                }
              }}
            >
              {syncBoardsBusy ? "Syncing hubs…" : "Sync public hubs"}
            </Button>
          </div>

          {syncBoardResult ? (
            <div className="space-y-2 rounded-lg border border-[var(--color-chrome-stroke)] p-3 text-[12px]">
              <p className="text-[var(--color-text-main)]">
                Fetched {syncBoardResult.fetched} · imported {syncBoardResult.imported} · updated{" "}
                {syncBoardResult.updated} · skipped {syncBoardResult.skipped}
              </p>
              <ul className="space-y-1 text-[var(--color-text-light)]">
                {syncBoardResult.sources.map((row) => (
                  <li key={row.source}>
                    {row.label}: {row.fetched} fetched
                    {row.error ? ` — ${row.error}` : ` (${row.imported} new, ${row.updated} updated)`}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      </ModalSheet>

      <ModalSheet
        open={eventSheet}
        onOpenChange={setEventSheet}
        title={editingEventId ? "Edit event" : "Add event"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={eventForm.title}
              onChange={(e) => setEventForm({ ...eventForm, title: e.target.value })}
              placeholder="Phone screen, onsite, offer call…"
            />
          </FormField>
          <FormField label="When">
            <input
              type="datetime-local"
              className={fieldControlClass}
              value={eventForm.occursAt}
              onChange={(e) => setEventForm({ ...eventForm, occursAt: e.target.value })}
            />
          </FormField>
          <FormField label="Kind">
            <select
              className={fieldControlClass}
              value={eventForm.kind}
              onChange={(e) => setEventForm({ ...eventForm, kind: e.target.value })}
            >
              {eventKinds.map((k) => (
                <option key={k} value={k}>
                  {eventKindLabels[k]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={eventForm.notes}
              onChange={(e) => setEventForm({ ...eventForm, notes: e.target.value })}
            />
          </FormField>
          <div className="flex flex-wrap items-center gap-2">
            {editingEventId && (
              <StatusChip
                title={
                  eventKindLabels[
                    eventKinds.includes(eventForm.kind as (typeof eventKinds)[number])
                      ? (eventForm.kind as (typeof eventKinds)[number])
                      : "other"
                  ]
                }
                tint={
                  eventKindColor[
                    eventKinds.includes(eventForm.kind as (typeof eventKinds)[number])
                      ? (eventForm.kind as (typeof eventKinds)[number])
                      : "other"
                  ]
                }
                filled
              />
            )}
            <Button
              disabled={!eventForm.title.trim() || !eventForm.occursAt || !selectedApp}
              onClick={async () => {
                if (!selectedApp) return;
                try {
                  const wasEdit = Boolean(editingEventId);
                  await ipc.careerUpsertEvent({
                    id: editingEventId ?? undefined,
                    applicationId: selectedApp.id,
                    title: eventForm.title.trim(),
                    occursAt: fromDatetimeLocal(eventForm.occursAt),
                    kind: eventForm.kind,
                    notes: eventForm.notes.trim() || undefined,
                  });
                  setEventSheet(false);
                  setEditingEventId(null);
                  showToast(wasEdit ? "Event updated" : "Event saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingEventId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(eventForm.title.trim() || "event")) return;
                  try {
                    await ipc.careerDeleteEvent(editingEventId);
                    setEventSheet(false);
                    setEditingEventId(null);
                    showToast("Event deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={bragSheet}
        onOpenChange={setBragSheet}
        title={editingBragId ? "Edit win" : "Add win"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={bragForm.title}
              onChange={(e) => setBragForm({ ...bragForm, title: e.target.value })}
              placeholder="Shipped feature X, won hackathon…"
            />
          </FormField>
          <FormField label="Occurred (YYYY-MM-DD)">
            <input
              className={fieldControlClass}
              value={bragForm.occurredAt}
              onChange={(e) => setBragForm({ ...bragForm, occurredAt: e.target.value })}
            />
          </FormField>
          <FormField label="Summary">
            <textarea
              className={fieldControlClass}
              rows={4}
              value={bragForm.summary}
              onChange={(e) => setBragForm({ ...bragForm, summary: e.target.value })}
              placeholder="Impact, metrics, skills demonstrated…"
            />
          </FormField>
          <FormField label="Evidence note">
            <textarea
              className={fieldControlClass}
              rows={2}
              value={bragForm.evidenceNote}
              onChange={(e) => setBragForm({ ...bragForm, evidenceNote: e.target.value })}
              placeholder="Link, doc, or where to find proof"
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!bragForm.title.trim()}
              onClick={async () => {
                try {
                  const wasEdit = Boolean(editingBragId);
                  await ipc.careerUpsertBragEntry({
                    id: editingBragId ?? undefined,
                    title: bragForm.title.trim(),
                    occurredAt: bragForm.occurredAt.trim() || undefined,
                    summary: bragForm.summary.trim() || undefined,
                    evidenceNote: bragForm.evidenceNote.trim() || undefined,
                  });
                  setBragSheet(false);
                  setEditingBragId(null);
                  showToast(wasEdit ? "Win updated" : "Win saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingBragId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(bragForm.title.trim() || "win")) return;
                  try {
                    await ipc.careerDeleteBragEntry(editingBragId);
                    setBragSheet(false);
                    setEditingBragId(null);
                    showToast("Win deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={contactSheet}
        onOpenChange={setContactSheet}
        title={editingContactId ? "Edit contact" : "Add contact"}
      >
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={contactForm.name}
              onChange={(e) => setContactForm({ ...contactForm, name: e.target.value })}
            />
          </FormField>
          <FormField label="Organization">
            <input
              className={fieldControlClass}
              value={contactForm.organization}
              onChange={(e) => setContactForm({ ...contactForm, organization: e.target.value })}
            />
          </FormField>
          <FormField label="Role">
            <input
              className={fieldControlClass}
              value={contactForm.roleTitle}
              onChange={(e) => setContactForm({ ...contactForm, roleTitle: e.target.value })}
            />
          </FormField>
          <FormField label="Email">
            <input
              className={fieldControlClass}
              type="email"
              value={contactForm.email}
              onChange={(e) => setContactForm({ ...contactForm, email: e.target.value })}
            />
          </FormField>
          <FormField label="Last contact (YYYY-MM-DD)">
            <input
              className={fieldControlClass}
              value={contactForm.lastContactAt}
              onChange={(e) => setContactForm({ ...contactForm, lastContactAt: e.target.value })}
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={contactForm.notes}
              onChange={(e) => setContactForm({ ...contactForm, notes: e.target.value })}
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!contactForm.name.trim()}
              onClick={async () => {
                try {
                  const wasEdit = Boolean(editingContactId);
                  const id = await ipc.careerUpsertNetworkContact({
                    id: editingContactId ?? undefined,
                    name: contactForm.name.trim(),
                    organization: contactForm.organization.trim() || undefined,
                    roleTitle: contactForm.roleTitle.trim() || undefined,
                    email: contactForm.email.trim() || undefined,
                    lastContactAt: contactForm.lastContactAt.trim() || undefined,
                    notes: contactForm.notes.trim() || undefined,
                  });
                  setContactSheet(false);
                  setEditingContactId(null);
                  if (!wasEdit) setSelectedContactId(id);
                  showToast(wasEdit ? "Contact updated" : "Contact saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingContactId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(contactForm.name.trim() || "contact")) return;
                  try {
                    await ipc.careerDeleteNetworkContact(editingContactId);
                    setContactSheet(false);
                    setEditingContactId(null);
                    setSelectedContactId(null);
                    showToast("Contact deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={milestoneSheet}
        onOpenChange={setMilestoneSheet}
        title={editingMilestoneId ? "Edit milestone" : "Add milestone"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={milestoneForm.title}
              onChange={(e) => setMilestoneForm({ ...milestoneForm, title: e.target.value })}
              placeholder="Promotion, certification, project ship…"
            />
          </FormField>
          <FormField label="Status">
            <select
              className={fieldControlClass}
              value={milestoneForm.status}
              onChange={(e) => setMilestoneForm({ ...milestoneForm, status: e.target.value })}
            >
              {milestoneStatuses.map((s) => (
                <option key={s} value={s}>
                  {milestoneStatusLabels[s]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Lane">
            <select
              className={fieldControlClass}
              value={milestoneForm.lane}
              onChange={(e) =>
                setMilestoneForm({
                  ...milestoneForm,
                  lane: normalizeRoadmapLane(e.target.value),
                })
              }
            >
              {roadmapLanes.map((lane) => (
                <option key={lane} value={lane}>
                  {roadmapLaneLabels[lane]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Due (YYYY-MM-DD)">
            <input
              className={fieldControlClass}
              value={milestoneForm.dueAt}
              onChange={(e) => setMilestoneForm({ ...milestoneForm, dueAt: e.target.value })}
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={milestoneForm.notes}
              onChange={(e) => setMilestoneForm({ ...milestoneForm, notes: e.target.value })}
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!milestoneForm.title.trim() || !selectedPath}
              onClick={async () => {
                if (!selectedPath) return;
                try {
                  const wasEdit = Boolean(editingMilestoneId);
                  await ipc.careerUpsertPathMilestone({
                    id: editingMilestoneId ?? undefined,
                    pathEntryId: selectedPath.id,
                    title: milestoneForm.title.trim(),
                    status: milestoneForm.status,
                    dueAt: milestoneForm.dueAt.trim() || undefined,
                    notes: milestoneForm.notes.trim() || undefined,
                    lane: milestoneForm.lane,
                  });
                  const refreshed = await ipc.careerListPathMilestones(selectedPath.id);
                  setPathMilestones(refreshed);
                  setPathPipeline(await ipc.careerPathAchievementPipeline(selectedPath.id));
                  setMilestoneSheet(false);
                  setEditingMilestoneId(null);
                  showToast(wasEdit ? "Milestone updated" : "Milestone saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingMilestoneId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(milestoneForm.title.trim() || "milestone")) return;
                  if (!selectedPath) return;
                  try {
                    await ipc.careerDeletePathMilestone(editingMilestoneId);
                    const refreshed = await ipc.careerListPathMilestones(selectedPath.id);
                    setPathMilestones(refreshed);
                    setMilestoneSheet(false);
                    setEditingMilestoneId(null);
                    showToast("Milestone deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={compensationSheet}
        onOpenChange={setCompensationSheet}
        title={editingCompensationId ? "Edit compensation" : "Add compensation"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={compensationForm.title}
              onChange={(e) =>
                setCompensationForm({ ...compensationForm, title: e.target.value })
              }
              placeholder="Base salary, signing bonus…"
            />
          </FormField>
          <FormField label="Kind">
            <select
              className={fieldControlClass}
              value={compensationForm.kind}
              onChange={(e) =>
                setCompensationForm({ ...compensationForm, kind: e.target.value })
              }
            >
              <option value="base_salary">Base salary</option>
              <option value="bonus">Bonus</option>
              <option value="equity">Equity</option>
              <option value="stipend">Stipend</option>
              <option value="other">Other</option>
            </select>
          </FormField>
          <FormField label="Amount">
            <input
              className={fieldControlClass}
              inputMode="decimal"
              value={compensationForm.amount}
              onChange={(e) =>
                setCompensationForm({ ...compensationForm, amount: e.target.value })
              }
              placeholder="120000"
            />
          </FormField>
          <FormField label="Currency">
            <input
              className={fieldControlClass}
              value={compensationForm.currency}
              onChange={(e) =>
                setCompensationForm({ ...compensationForm, currency: e.target.value })
              }
              placeholder="USD"
            />
          </FormField>
          <FormField label="Cadence">
            <select
              className={fieldControlClass}
              value={compensationForm.cadence}
              onChange={(e) =>
                setCompensationForm({
                  ...compensationForm,
                  cadence: e.target.value as (typeof compensationCadences)[number],
                })
              }
            >
              {compensationCadences.map((c) => (
                <option key={c} value={c}>
                  {compensationCadenceLabels[c]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={compensationForm.notes}
              onChange={(e) =>
                setCompensationForm({ ...compensationForm, notes: e.target.value })
              }
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!compensationForm.title.trim() || !selectedPath}
              onClick={async () => {
                if (!selectedPath) return;
                try {
                  const wasEdit = Boolean(editingCompensationId);
                  const parsedAmount = compensationForm.amount.trim()
                    ? Number(compensationForm.amount.trim())
                    : undefined;
                  if (
                    compensationForm.amount.trim() &&
                    (parsedAmount == null || Number.isNaN(parsedAmount))
                  ) {
                    showToast("Enter a valid amount", "error");
                    return;
                  }
                  await ipc.careerUpsertPathCompensation({
                    id: editingCompensationId ?? undefined,
                    pathEntryId: selectedPath.id,
                    kind: compensationForm.kind,
                    title: compensationForm.title.trim(),
                    amount: parsedAmount,
                    currency: compensationForm.currency.trim() || "USD",
                    cadence: compensationForm.cadence,
                    notes: compensationForm.notes.trim() || undefined,
                  });
                  setPathCompensation(
                    await ipc.careerListPathCompensation(selectedPath.id),
                  );
                  setPathPipeline(
                    await ipc.careerPathAchievementPipeline(selectedPath.id),
                  );
                  setCompensationSheet(false);
                  setEditingCompensationId(null);
                  showToast(
                    wasEdit ? "Compensation updated" : "Compensation saved",
                    "success",
                  );
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingCompensationId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(compensationForm.title.trim() || "compensation")) return;
                  if (!selectedPath) return;
                  try {
                    await ipc.careerDeletePathCompensation(editingCompensationId);
                    setPathCompensation(
                      await ipc.careerListPathCompensation(selectedPath.id),
                    );
                    setPathPipeline(
                      await ipc.careerPathAchievementPipeline(selectedPath.id),
                    );
                    setCompensationSheet(false);
                    setEditingCompensationId(null);
                    showToast("Compensation deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={journalSheet}
        onOpenChange={setJournalSheet}
        title={editingJournalId ? "Edit journal entry" : "Add journal entry"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={journalForm.title}
              onChange={(e) => setJournalForm({ ...journalForm, title: e.target.value })}
              placeholder="Weekly reflection, project retrospective…"
            />
          </FormField>
          <FormField label="When">
            <input
              type="datetime-local"
              className={fieldControlClass}
              value={journalForm.occurredAt}
              onChange={(e) => setJournalForm({ ...journalForm, occurredAt: e.target.value })}
            />
          </FormField>
          <FormField label="Mood">
            <select
              className={fieldControlClass}
              value={journalForm.mood}
              onChange={(e) => setJournalForm({ ...journalForm, mood: e.target.value })}
            >
              {journalMoods.map((m) => (
                <option key={m || "none"} value={m}>
                  {journalMoodLabels[m]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={5}
              value={journalForm.body}
              onChange={(e) => setJournalForm({ ...journalForm, body: e.target.value })}
              placeholder="What went well? What was hard? What did you learn?"
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!journalForm.occurredAt.trim() || !selectedPath}
              onClick={async () => {
                if (!selectedPath) return;
                try {
                  const wasEdit = Boolean(editingJournalId);
                  const occurredAt = fromDatetimeLocal(journalForm.occurredAt);
                  if (!occurredAt) {
                    showToast("Enter a valid date and time", "error");
                    return;
                  }
                  await ipc.careerUpsertPathJournalEntry({
                    id: editingJournalId ?? undefined,
                    pathEntryId: selectedPath.id,
                    occurredAt,
                    title: journalForm.title.trim(),
                    body: journalForm.body.trim(),
                    mood: journalForm.mood || undefined,
                  });
                  const refreshed = await ipc.careerListPathJournalEntries(selectedPath.id);
                  setPathJournalEntries(refreshed);
                  setJournalSheet(false);
                  setEditingJournalId(null);
                  showToast(wasEdit ? "Journal entry updated" : "Journal entry saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingJournalId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(journalForm.title.trim() || "journal entry")) return;
                  if (!selectedPath) return;
                  try {
                    await ipc.careerDeletePathJournalEntry(editingJournalId);
                    const refreshed = await ipc.careerListPathJournalEntries(selectedPath.id);
                    setPathJournalEntries(refreshed);
                    setJournalSheet(false);
                    setEditingJournalId(null);
                    showToast("Journal entry deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={promotionSheet}
        onOpenChange={setPromotionSheet}
        title={editingPromotionId ? "Edit promotion" : "Add promotion"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={promotionForm.title}
              onChange={(e) => setPromotionForm({ ...promotionForm, title: e.target.value })}
              placeholder="Senior Engineer, Team Lead…"
            />
          </FormField>
          <FormField label="Effective date">
            <input
              type="date"
              className={fieldControlClass}
              value={promotionForm.effectiveAt}
              onChange={(e) => setPromotionForm({ ...promotionForm, effectiveAt: e.target.value })}
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={4}
              value={promotionForm.notes}
              onChange={(e) => setPromotionForm({ ...promotionForm, notes: e.target.value })}
              placeholder="Scope change, comp band, announcement context…"
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!promotionForm.title.trim() || !selectedPath}
              onClick={async () => {
                if (!selectedPath) return;
                try {
                  const wasEdit = Boolean(editingPromotionId);
                  await ipc.careerUpsertPathPromotion({
                    id: editingPromotionId ?? undefined,
                    pathEntryId: selectedPath.id,
                    title: promotionForm.title.trim(),
                    effectiveAt: promotionForm.effectiveAt.trim() || undefined,
                    notes: promotionForm.notes.trim() || undefined,
                  });
                  const refreshed = await ipc.careerListPathPromotions(selectedPath.id);
                  setPathPromotions(refreshed);
                  setPromotionSheet(false);
                  setEditingPromotionId(null);
                  showToast(wasEdit ? "Promotion updated" : "Promotion saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingPromotionId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(promotionForm.title.trim() || "promotion")) return;
                  if (!selectedPath) return;
                  try {
                    await ipc.careerDeletePathPromotion(editingPromotionId);
                    const refreshed = await ipc.careerListPathPromotions(selectedPath.id);
                    setPathPromotions(refreshed);
                    setPromotionSheet(false);
                    setEditingPromotionId(null);
                    showToast("Promotion deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={personSheet}
        onOpenChange={setPersonSheet}
        title={editingPersonId ? "Edit person" : "Add person"}
      >
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={personForm.name}
              onChange={(e) => setPersonForm({ ...personForm, name: e.target.value })}
              placeholder="Jane Smith"
            />
          </FormField>
          <FormField label="Role">
            <input
              className={fieldControlClass}
              value={personForm.roleTitle}
              onChange={(e) => setPersonForm({ ...personForm, roleTitle: e.target.value })}
              placeholder="Engineering Manager"
            />
          </FormField>
          <FormField label="Relationship">
            <input
              className={fieldControlClass}
              value={personForm.relationship}
              onChange={(e) => setPersonForm({ ...personForm, relationship: e.target.value })}
              placeholder="Manager, mentor, peer…"
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={4}
              value={personForm.notes}
              onChange={(e) => setPersonForm({ ...personForm, notes: e.target.value })}
              placeholder="How they helped, follow-up reminders…"
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!personForm.name.trim() || !selectedPath}
              onClick={async () => {
                if (!selectedPath) return;
                try {
                  const wasEdit = Boolean(editingPersonId);
                  await ipc.careerUpsertPathPerson({
                    id: editingPersonId ?? undefined,
                    pathEntryId: selectedPath.id,
                    name: personForm.name.trim(),
                    roleTitle: personForm.roleTitle.trim() || undefined,
                    relationship: personForm.relationship.trim() || undefined,
                    notes: personForm.notes.trim() || undefined,
                  });
                  const refreshed = await ipc.careerListPathPeople(selectedPath.id);
                  setPathPeople(refreshed);
                  setPersonSheet(false);
                  setEditingPersonId(null);
                  showToast(wasEdit ? "Person updated" : "Person saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingPersonId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (!confirmDelete(personForm.name.trim() || "person")) return;
                  if (!selectedPath) return;
                  try {
                    await ipc.careerDeletePathPerson(editingPersonId);
                    const refreshed = await ipc.careerListPathPeople(selectedPath.id);
                    setPathPeople(refreshed);
                    setPersonSheet(false);
                    setEditingPersonId(null);
                    showToast("Person deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={pathDocLinkSheet}
        onOpenChange={setPathDocLinkSheet}
        title="Link document"
      >
        <div className="space-y-3">
          {linkableVaultDocs.length === 0 ? (
            <p className="text-[12px] text-[var(--color-text-light)]">
              {vaultDocs.length === 0
                ? "No vault documents yet — import files in Documents first."
                : "All vault documents are already linked to this path entry."}
            </p>
          ) : (
            <ul className="max-h-[min(420px,60vh)] divide-y divide-[var(--color-chrome-stroke)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)]">
              {linkableVaultDocs.map((doc) => (
                <li key={doc.id}>
                  <ListRow
                    onClick={async () => {
                      if (!selectedPath) return;
                      try {
                        await ipc.careerLinkPathDocument({
                          pathEntryId: selectedPath.id,
                          vaultDocId: doc.id,
                        });
                        const refreshed = await ipc.careerListPathDocuments(selectedPath.id);
                        setPathDocuments(refreshed);
                        setPathDocLinkSheet(false);
                        showToast("Document linked", "success");
                      } catch (e) {
                        showToast(formatIpcError(e), "error");
                      }
                    }}
                    title={doc.title || "Untitled"}
                    subtitle={
                      doc.hasFile
                        ? `${formatBytes(doc.fileSize)} · ${new Date(doc.updatedAt).toLocaleDateString()}`
                        : "Metadata only"
                    }
                    trailing={
                      <StatusChip
                        title={doc.category}
                        tint={categoryTint(doc.category)}
                        filled
                      />
                    }
                  />
                </li>
              ))}
            </ul>
          )}
        </div>
      </ModalSheet>

      <ModalSheet
        open={interviewSheet}
        onOpenChange={setInterviewSheet}
        title={editingInterviewId ? "Edit interview prep" : "Add interview prep"}
      >
        <div className="space-y-3">
          <FormField label="Company">
            <input
              className={fieldControlClass}
              value={interviewForm.company}
              onChange={(e) => setInterviewForm({ ...interviewForm, company: e.target.value })}
            />
          </FormField>
          <FormField label="Role">
            <input
              className={fieldControlClass}
              value={interviewForm.roleTitle}
              onChange={(e) => setInterviewForm({ ...interviewForm, roleTitle: e.target.value })}
            />
          </FormField>
          <FormField label="Linked application (optional)">
            <select
              className={fieldControlClass}
              value={interviewForm.applicationId}
              onChange={(e) => {
                const appId = e.target.value;
                const linked = apps.find((a) => a.id === appId);
                setInterviewForm((prev) => ({
                  ...prev,
                  applicationId: appId,
                  company: linked && !prev.company.trim() ? linked.company : prev.company,
                  roleTitle: linked && !prev.roleTitle.trim() ? linked.roleTitle : prev.roleTitle,
                }));
              }}
            >
              <option value="">None</option>
              {apps.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.roleTitle} @ {a.company}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Scheduled">
            <input
              type="datetime-local"
              className={fieldControlClass}
              value={interviewForm.scheduledAt}
              onChange={(e) => setInterviewForm({ ...interviewForm, scheduledAt: e.target.value })}
            />
          </FormField>
          <FormField label="Status">
            <select
              className={fieldControlClass}
              value={interviewForm.status}
              onChange={(e) => setInterviewForm({ ...interviewForm, status: e.target.value })}
            >
              {interviewStatuses.map((s) => (
                <option key={s} value={s}>
                  {interviewStatusLabels[s]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Questions to prepare">
            <textarea
              className={fieldControlClass}
              rows={4}
              value={interviewForm.questions}
              onChange={(e) => setInterviewForm({ ...interviewForm, questions: e.target.value })}
              placeholder="Behavioral stories, technical topics, questions to ask them…"
            />
          </FormField>
          <FormField label="Notes">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={interviewForm.notes}
              onChange={(e) => setInterviewForm({ ...interviewForm, notes: e.target.value })}
            />
          </FormField>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!interviewForm.company.trim() || !interviewForm.roleTitle.trim()}
              onClick={async () => {
                try {
                  const wasEdit = Boolean(editingInterviewId);
                  await ipc.careerUpsertInterviewPrep({
                    id: editingInterviewId ?? undefined,
                    applicationId: interviewForm.applicationId.trim() || undefined,
                    company: interviewForm.company.trim(),
                    roleTitle: interviewForm.roleTitle.trim(),
                    scheduledAt: interviewForm.scheduledAt
                      ? fromDatetimeLocal(interviewForm.scheduledAt)
                      : undefined,
                    status: interviewForm.status,
                    notes: interviewForm.notes.trim() || undefined,
                    questions: interviewForm.questions.trim() || undefined,
                  });
                  setInterviewSheet(false);
                  setEditingInterviewId(null);
                  showToast(wasEdit ? "Interview prep updated" : "Interview prep saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save
            </Button>
            {editingInterviewId && (
              <Button
                variant="danger"
                onClick={async () => {
                  if (
                    !confirmDelete(
                      `${interviewForm.roleTitle.trim() || "prep"} @ ${interviewForm.company.trim() || "company"}`,
                    )
                  )
                    return;
                  try {
                    await ipc.careerDeleteInterviewPrep(editingInterviewId);
                    setInterviewSheet(false);
                    setEditingInterviewId(null);
                    showToast("Interview prep deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }}
              >
                Delete
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>

      <ModalSheet
        open={draftSheet}
        onOpenChange={setDraftSheet}
        title={
          draftPane === "markdown"
            ? "Resume draft (Markdown)"
            : draftPane === "typst"
              ? "Resume draft (Typst)"
              : "Resume draft (Preview)"
        }
        width={720}
      >
        <div className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-3">
              <SegmentedPills<ResumeDraftPane>
                options={[
                  { id: "markdown", label: "Markdown" },
                  { id: "typst", label: "Typst" },
                  { id: "preview", label: "Preview" },
                ]}
                value={draftPane}
                onChange={(pane) => {
                  if (pane === "preview") {
                    setDraftPreviewAs(draftPane === "typst" ? "typst" : "markdown");
                  }
                  setDraftPane(pane);
                }}
              />
              <label className="flex items-center gap-2 text-[13px] text-[var(--color-text-main)]">
                <input
                  type="checkbox"
                  checked={includeBragInDraft}
                  onChange={(e) => setIncludeBragInDraft(e.target.checked)}
                />
                Include brag book
              </label>
            </div>
            <Button
              size="sm"
              variant="secondary"
              disabled={draftBusy}
              onClick={() => void generateResumeDraft()}
            >
              Regenerate
            </Button>
          </div>
          {draftPane === "preview" ? (
            <div
              className="max-h-[min(480px,55vh)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-4 text-[13px] text-[var(--color-text-main)]"
            >
              {draftPreviewAs === "typst" && draftTypst.trim() ? (
                <>
                  <p className="mb-2 text-[11px] text-[var(--color-text-light)]">
                    Compile PDF for final layout.
                  </p>
                  <pre
                    className="font-mono text-[12px] leading-relaxed whitespace-pre-wrap text-[var(--color-text-main)]"
                  >
                    {draftTypst}
                  </pre>
                </>
              ) : draftMarkdown.trim() ? (
                <SimpleMarkdown content={draftMarkdown} />
              ) : (
                <p className="text-[12px] text-[var(--color-text-light)]">
                  Generate a draft to preview formatted output.
                </p>
              )}
            </div>
          ) : (
            <FormField label={draftPane === "markdown" ? "Markdown" : "Typst source"}>
              <textarea
                className={fieldControlClass}
                rows={18}
                readOnly
                value={draftPane === "markdown" ? draftMarkdown : draftTypst}
                onFocus={(e) => e.currentTarget.select()}
              />
            </FormField>
          )}
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              disabled={
                !(draftPane === "preview"
                  ? draftPreviewAs === "typst"
                    ? draftTypst
                    : draftMarkdown
                  : draftPane === "markdown"
                    ? draftMarkdown
                    : draftTypst).trim()
              }
              onClick={async () => {
                const content =
                  draftPane === "preview"
                    ? draftPreviewAs === "typst"
                      ? draftTypst
                      : draftMarkdown
                    : draftPane === "markdown"
                      ? draftMarkdown
                      : draftTypst;
                const isMarkdown =
                  draftPane === "preview" ? draftPreviewAs === "markdown" : draftPane === "markdown";
                try {
                  await navigator.clipboard.writeText(content);
                  showToast(
                    isMarkdown ? "Copied Markdown to clipboard" : "Copied Typst to clipboard",
                    "success",
                  );
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Copy
            </Button>
            <Button
              size="sm"
              variant="secondary"
              disabled={
                !(draftPane === "preview"
                  ? draftPreviewAs === "typst"
                    ? draftTypst
                    : draftMarkdown
                  : draftPane === "markdown"
                    ? draftMarkdown
                    : draftTypst).trim()
              }
              onClick={async () => {
                const content =
                  draftPane === "preview"
                    ? draftPreviewAs === "typst"
                      ? draftTypst
                      : draftMarkdown
                    : draftPane === "markdown"
                      ? draftMarkdown
                      : draftTypst;
                const isMarkdown =
                  draftPane === "preview" ? draftPreviewAs === "markdown" : draftPane === "markdown";
                try {
                  const picked = await save({
                    title: "Save resume draft",
                    defaultPath: isMarkdown ? "resume-draft.md" : "resume-draft.typ",
                    filters: isMarkdown
                      ? [{ name: "Markdown", extensions: ["md"] }]
                      : [{ name: "Typst", extensions: ["typ"] }],
                  });
                  if (!picked) return;
                  await writeTextFile(picked, content);
                  showToast("Resume draft saved", "success");
                } catch (e) {
                  showToast(formatIpcError(e), "error");
                }
              }}
            >
              Save…
            </Button>
            {draftPane === "typst" && (
              <Button
                size="sm"
                variant="secondary"
                disabled={!draftTypst.trim() || draftCompileBusy}
                onClick={async () => {
                  setDraftCompileBusy(true);
                  try {
                    const result = await compileResumeTypstToPdf(draftTypst);
                    if (result === "ok") {
                      showToast("PDF compiled", "success");
                    }
                  } catch (e) {
                    const message = e instanceof Error ? e.message : formatIpcError(e);
                    if (message.includes("typst not found")) {
                      showToast("Install Typst from https://typst.app if missing", "error");
                    } else {
                      showToast(message, "error");
                    }
                  } finally {
                    setDraftCompileBusy(false);
                  }
                }}
              >
                {draftCompileBusy ? "Compiling…" : "Compile PDF"}
              </Button>
            )}
          </div>
        </div>
      </ModalSheet>
    </div>
  );
}
