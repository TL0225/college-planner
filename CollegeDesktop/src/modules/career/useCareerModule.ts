import { createElement, useCallback, useEffect, useMemo, useState, type DragEvent, type ReactNode } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { ipc, formatIpcError, type PipelineMetrics } from "@/lib/ipc";
import { CareerInterviewTimeline } from "./views/CareerInterviewTimeline";
import {
  CAREER_APP_DRAG,
  statuses,
  statusLabels,
} from "./views/CareerPipelineView";
import { type PathInspectorTab } from "./views/CareerPathingView";
import {
  interviewStatuses,
  type BragEntryRow,
  type NetworkContactRow,
  type InterviewPrepRow,
} from "./growthTypes";
import { showToast } from "@/lib/toast";
import { navigate } from "@/lib/shell/navigate";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { buildResumeMarkdown } from "./buildResumeMarkdown";
import { buildResumeTypst } from "./buildResumeTypst";
import { openCareerApplyWindow } from "./CareerApplyWindow";
import {
  compensationCadences,
  eventKinds,
  journalMoods,
  milestoneStatuses,
  normalizeRoadmapLane,
  roadmapLanes,
  type ResumeDraftPane,
  type RoadmapLane,
} from "./CareerModals";

function postingHref(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return "";
  return trimmed.startsWith("http") ? trimmed : `https://${trimmed}`;
}

function readAppDragId(e: DragEvent): string | null {
  const id = e.dataTransfer.getData(CAREER_APP_DRAG);
  return id || null;
}

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

export function useCareerModule(page = "applications") {
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
    url: "",
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
  const [lastApplyPostingId, setLastApplyPostingId] = useState<string | null>(null);
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

  const reloadCareerEvents = useCallback(async () => {
    if (!selected) {
      setCareerEvents([]);
      return;
    }
    try {
      const events = await ipc.careerListEvents(selected);
      setCareerEvents(events);
    } catch {
      setCareerEvents([]);
    }
  }, [selected]);

  useEffect(() => {
    void reloadCareerEvents();
  }, [reloadCareerEvents, apps]);

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

  const interviewTimeline: ReactNode = selectedApp
    ? createElement(CareerInterviewTimeline, {
        events: careerEvents,
        onAdd: () => openEventSheet(),
        onEdit: (event) => openEventSheet(event),
      })
    : null;

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

  const handleLaneDrop = async (
    e: DragEvent,
    status: string,
    beforeAppId?: string,
  ) => {
    e.preventDefault();
    setDropTargetStatus(null);
    const appId = readAppDragId(e);
    if (!appId) return;
    const app = apps.find((a) => a.id === appId);
    if (!app) return;

    if (app.status === status) {
      const lane = byStatus.get(status) ?? [];
      const ids = lane.map((a) => a.id);
      const reordered = ids.filter((id) => id !== appId);
      if (beforeAppId && beforeAppId !== appId) {
        const insertIdx = reordered.indexOf(beforeAppId);
        if (insertIdx === -1) {
          reordered.push(appId);
        } else {
          reordered.splice(insertIdx, 0, appId);
        }
      } else {
        reordered.push(appId);
      }
      if (reordered.every((id, i) => ids[i] === id)) return;
      try {
        await ipc.careerReorderApplications(status, reordered);
      } catch (err) {
        showToast(formatIpcError(err), "error");
      }
      return;
    }

    const lane = byStatus.get(status) ?? [];
    let sortOrder: number | undefined;
    if (beforeAppId) {
      const idx = lane.findIndex((a) => a.id === beforeAppId);
      if (idx >= 0) sortOrder = idx;
    }
    try {
      await ipc.careerMoveApplication(appId, status, sortOrder);
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
    setLastApplyPostingId(null);
    await openCareerApplyWindow({
      applicationId: app.id,
      company: app.company,
      roleTitle: app.roleTitle,
      url: app.url,
    });
  };

  const resolvePostingApplicationId = async (
    posting: (typeof postings)[number],
  ): Promise<string | null> => {
    if (posting.trackedApplicationId) return posting.trackedApplicationId;
    try {
      const applicationId = await ipc.careerTrackJobPosting(posting.id);
      await refresh();
      return applicationId;
    } catch (err) {
      showToast(formatIpcError(err), "error");
      return null;
    }
  };

  const openApplyForPosting = async (posting: (typeof postings)[number]) => {
    if (!posting.url.trim()) {
      showToast("No posting URL to open", "error");
      return;
    }
    const applicationId = await resolvePostingApplicationId(posting);
    if (!applicationId) return;
    setLastApplySessionId(applicationId);
    setLastApplyPostingId(posting.id);
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
      setLastApplyPostingId(null);
      showToast("Marked as applied", "success");
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const markPostingApplyComplete = async (posting: (typeof postings)[number]) => {
    const applicationId = await resolvePostingApplicationId(posting);
    if (!applicationId) return;
    await markApplyComplete(applicationId);
  };

  const openBragBook = () => navigate({ hub: "career", page: "growth" });

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
      setForm({ company: "", roleTitle: "", status: "interested", location: "", url: "" });
      setSheetOpen(true);
    };
    window.addEventListener("college:quick-add", onQuick);
    return () => window.removeEventListener("college:quick-add", onQuick);
  }, []);

  return {
    shellView,
    layout,
    setLayout,
    apps,
    metrics,
    selected,
    setSelected,
    selectedPostingId,
    setSelectedPostingId,
    dropTargetStatus,
    setDropTargetStatus,
    sheetOpen,
    setSheetOpen,
    editingAppId,
    setEditingAppId,
    pathSheet,
    setPathSheet,
    editingPathId,
    setEditingPathId,
    postingSheet,
    setPostingSheet,
    form,
    setForm,
    pathForm,
    setPathForm,
    pathEntries,
    setPathEntries,
    selectedPathId,
    setSelectedPathId,
    postingForm,
    setPostingForm,
    importUrlSheet,
    setImportUrlSheet,
    importUrl,
    setImportUrl,
    importUrlBusy,
    setImportUrlBusy,
    syncBoardsSheet,
    setSyncBoardsSheet,
    syncBoardsBusy,
    setSyncBoardsBusy,
    syncBoardSources,
    setSyncBoardSources,
    syncBoardResult,
    setSyncBoardResult,
    companyBoards,
    setCompanyBoards,
    companyBoardForm,
    setCompanyBoardForm,
    companyBoardBusy,
    setCompanyBoardBusy,
    syncCompaniesBusy,
    setSyncCompaniesBusy,
    smartBoards,
    setSmartBoards,
    openingsScope,
    setOpeningsScope,
    smartBoardPostings,
    smartBoardSheet,
    setSmartBoardSheet,
    editingSmartBoardId,
    setEditingSmartBoardId,
    smartBoardForm,
    setSmartBoardForm,
    smartBoardBusy,
    setSmartBoardBusy,
    smartBoardPostingsBusy,
    postings,
    resumeText,
    setResumeText,
    jobText,
    setJobText,
    matchResult,
    setMatchResult,
    vaultDocs,
    selectedResumeId,
    setSelectedResumeId,
    resumeProfiles,
    setResumeProfiles,
    resumeMetrics,
    setResumeMetrics,
    tailoringForm,
    setTailoringForm,
    tailoringBusy,
    setTailoringBusy,
    matchBusy,
    setMatchBusy,
    draftSheet,
    setDraftSheet,
    draftPane,
    setDraftPane,
    draftPreviewAs,
    setDraftPreviewAs,
    draftMarkdown,
    setDraftMarkdown,
    draftTypst,
    setDraftTypst,
    draftBusy,
    draftCompileBusy,
    setDraftCompileBusy,
    includeBragInDraft,
    setIncludeBragInDraft,
    builderLoadNonce,
    careerEvents,
    eventSheet,
    setEventSheet,
    editingEventId,
    setEditingEventId,
    eventForm,
    setEventForm,
    bragEntries,
    bragSheet,
    setBragSheet,
    editingBragId,
    setEditingBragId,
    bragForm,
    setBragForm,
    networkContacts,
    selectedContactId,
    setSelectedContactId,
    contactSheet,
    setContactSheet,
    editingContactId,
    setEditingContactId,
    contactForm,
    setContactForm,
    interviewPrep,
    interviewSheet,
    setInterviewSheet,
    editingInterviewId,
    setEditingInterviewId,
    interviewForm,
    setInterviewForm,
    pathMilestones,
    setPathMilestones,
    pathDocuments,
    setPathDocuments,
    pathJournalEntries,
    setPathJournalEntries,
    pathPromotions,
    setPathPromotions,
    pathPeople,
    setPathPeople,
    pathBenefits,
    setPathBenefits,
    pathCompensation,
    setPathCompensation,
    employmentTerms,
    setEmploymentTerms,
    employmentBusy,
    setEmploymentBusy,
    careerSkills,
    setCareerSkills,
    pathPipeline,
    setPathPipeline,
    decisionJournal,
    setDecisionJournal,
    decisionBusy,
    setDecisionBusy,
    skillNameDraft,
    setSkillNameDraft,
    pathInspectorTab,
    setPathInspectorTab,
    lastApplySessionId,
    lastApplyPostingId,
    pathDocLinkSheet,
    setPathDocLinkSheet,
    milestoneSheet,
    setMilestoneSheet,
    journalSheet,
    setJournalSheet,
    promotionSheet,
    setPromotionSheet,
    personSheet,
    setPersonSheet,
    compensationSheet,
    setCompensationSheet,
    editingMilestoneId,
    setEditingMilestoneId,
    editingJournalId,
    setEditingJournalId,
    editingPromotionId,
    setEditingPromotionId,
    editingPersonId,
    setEditingPersonId,
    editingCompensationId,
    setEditingCompensationId,
    milestoneForm,
    setMilestoneForm,
    compensationForm,
    setCompensationForm,
    journalForm,
    setJournalForm,
    promotionForm,
    setPromotionForm,
    personForm,
    setPersonForm,
    refresh,
    error,
    selectedApp,
    visiblePostings,
    selectedPosting,
    selectedPath,
    selectedContact,
    pathMilestoneProgress,
    milestonesByLane,
    relatedPathApplications,
    openSmartBoardEditor,
    openBragEditor,
    openContactEditor,
    openInterviewEditor,
    openPathEditor,
    openMilestoneEditor,
    openCompensationEditor,
    openJournalEditor,
    openPromotionEditor,
    openPersonEditor,
    pathByOrg,
    openEventSheet,
    linkableVaultDocs,
    interviewTimeline,
    resumeLibrary,
    resumeProfileByVaultId,
    selectedResume,
    selectedResumeProfile,
    builderTailoring,
    generateResumeDraft,
    effectiveLayout,
    byOrg,
    byStatus,
    handleLaneDragOver,
    handleLaneDrop,
    openApplyForApp,
    openApplyForPosting,
    markApplyComplete,
    markPostingApplyComplete,
    reloadCareerEvents,
    openBragBook,
    openPostingInBrowser,
  };
}

export type CareerModuleState = ReturnType<typeof useCareerModule>;
