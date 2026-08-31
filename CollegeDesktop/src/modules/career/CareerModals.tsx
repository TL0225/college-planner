import { type Dispatch, type SetStateAction } from "react";
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import {
  Button,
  FormField,
  ListRow,
  ModalSheet,
  NotesEditor,
  SegmentedPills,
  colors,
  fieldControlClass,
  StatusChip,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { statuses } from "./views/CareerPipelineView";
import { interviewStatuses, interviewStatusLabels } from "./growthTypes";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { compileResumeTypstToPdf } from "./buildResumeTypst";
import { SimpleMarkdown } from "@/modules/assistant/simpleMarkdown";

export type ResumeDraftPane = "markdown" | "typst" | "preview";

export const eventKinds = ["interview", "offer", "follow_up", "other"] as const;
export const eventKindLabels: Record<(typeof eventKinds)[number], string> = {
  interview: "Interview",
  offer: "Offer",
  follow_up: "Follow-up",
  other: "Other",
};
export const eventKindColor: Record<(typeof eventKinds)[number], string> = {
  interview: colors.careerLaneInterviewing,
  offer: colors.careerLaneOffer,
  follow_up: colors.careerLaneApplied,
  other: "var(--color-text-light)",
};

function fromDatetimeLocal(value: string): string {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return new Date().toISOString();
  return d.toISOString();
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
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

export const milestoneStatuses = ["planned", "in_progress", "done"] as const;
export const milestoneStatusLabels: Record<(typeof milestoneStatuses)[number], string> = {
  planned: "Planned",
  in_progress: "In progress",
  done: "Done",
};

export const compensationCadences = ["yearly", "monthly", "one_time"] as const;
export const compensationCadenceLabels: Record<(typeof compensationCadences)[number], string> = {
  yearly: "Yearly",
  monthly: "Monthly",
  one_time: "One-time",
};

export const roadmapLanes = ["learning", "impact", "promotion", "general"] as const;
export type RoadmapLane = (typeof roadmapLanes)[number];
export const roadmapLaneLabels: Record<RoadmapLane, string> = {
  learning: "Learning",
  impact: "Impact",
  promotion: "Promotion",
  general: "General",
};

export function normalizeRoadmapLane(lane: string | null | undefined): RoadmapLane {
  return roadmapLanes.includes(lane as RoadmapLane) ? (lane as RoadmapLane) : "general";
}

export const journalMoods = ["", "great", "ok", "hard"] as const;
export const journalMoodLabels: Record<(typeof journalMoods)[number], string> = {
  "": "None",
  great: "Great",
  ok: "OK",
  hard: "Hard",
};

type AppRow = {
  id: string;
  company: string;
  roleTitle: string;
  status: string;
  location: string;
  url: string;
  appliedAt?: string;
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

type OpeningsScope =
  | { kind: "all" }
  | { kind: "company"; id: string; name: string }
  | { kind: "smartBoard"; id: string; name: string };

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

type SyncBoardResult = {
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
};

type CompanyBoardRow = {
  id: string;
  displayName: string;
  careersUrl: string;
  platform: string;
  enabled: boolean;
  lastSyncedAt?: string | null;
};

export type CareerModalsProps = {
  sheetOpen: boolean;
  setSheetOpen: Dispatch<SetStateAction<boolean>>;
  editingAppId: string | null;
  setEditingAppId: Dispatch<SetStateAction<string | null>>;
  form: { company: string; roleTitle: string; status: string; location: string; url: string };
  setForm: Dispatch<
    SetStateAction<{ company: string; roleTitle: string; status: string; location: string; url: string }>
  >;
  pathSheet: boolean;
  setPathSheet: Dispatch<SetStateAction<boolean>>;
  editingPathId: string | null;
  setEditingPathId: Dispatch<SetStateAction<string | null>>;
  pathForm: {
    organization: string;
    roleTitle: string;
    startDate: string;
    endDate: string;
    summary: string;
  };
  setPathForm: Dispatch<
    SetStateAction<{
      organization: string;
      roleTitle: string;
      startDate: string;
      endDate: string;
      summary: string;
    }>
  >;
  setSelectedPathId: Dispatch<SetStateAction<string | null>>;
  postingSheet: boolean;
  setPostingSheet: Dispatch<SetStateAction<boolean>>;
  postingForm: { company: string; title: string; location: string; url: string };
  setPostingForm: Dispatch<
    SetStateAction<{ company: string; title: string; location: string; url: string }>
  >;
  importUrlSheet: boolean;
  setImportUrlSheet: Dispatch<SetStateAction<boolean>>;
  importUrl: string;
  setImportUrl: Dispatch<SetStateAction<string>>;
  importUrlBusy: boolean;
  setImportUrlBusy: Dispatch<SetStateAction<boolean>>;
  setSelectedPostingId: Dispatch<SetStateAction<string | null>>;
  refresh: () => void | Promise<void>;
  smartBoardSheet: boolean;
  setSmartBoardSheet: Dispatch<SetStateAction<boolean>>;
  editingSmartBoardId: string | null;
  setEditingSmartBoardId: Dispatch<SetStateAction<string | null>>;
  smartBoardBusy: boolean;
  setSmartBoardBusy: Dispatch<SetStateAction<boolean>>;
  smartBoardForm: {
    name: string;
    companyIds: string[];
    keywords: string;
    remoteOnly: boolean;
    daysPostedFilter: string;
  };
  setSmartBoardForm: Dispatch<
    SetStateAction<{
      name: string;
      companyIds: string[];
      keywords: string;
      remoteOnly: boolean;
      daysPostedFilter: string;
    }>
  >;
  companyBoards: CompanyBoardRow[];
  setCompanyBoards: Dispatch<SetStateAction<CompanyBoardRow[]>>;
  setSmartBoards: Dispatch<SetStateAction<JobBoardSmartBoardRow[]>>;
  openingsScope: OpeningsScope;
  setOpeningsScope: Dispatch<SetStateAction<OpeningsScope>>;
  syncBoardsSheet: boolean;
  setSyncBoardsSheet: Dispatch<SetStateAction<boolean>>;
  syncBoardResult: SyncBoardResult | null;
  setSyncBoardResult: Dispatch<SetStateAction<SyncBoardResult | null>>;
  syncBoardsBusy: boolean;
  setSyncBoardsBusy: Dispatch<SetStateAction<boolean>>;
  syncBoardSources: string[];
  setSyncBoardSources: Dispatch<SetStateAction<string[]>>;
  syncCompaniesBusy: boolean;
  setSyncCompaniesBusy: Dispatch<SetStateAction<boolean>>;
  companyBoardForm: { name: string; url: string };
  setCompanyBoardForm: Dispatch<SetStateAction<{ name: string; url: string }>>;
  companyBoardBusy: boolean;
  setCompanyBoardBusy: Dispatch<SetStateAction<boolean>>;
  eventSheet: boolean;
  setEventSheet: Dispatch<SetStateAction<boolean>>;
  editingEventId: string | null;
  setEditingEventId: Dispatch<SetStateAction<string | null>>;
  eventForm: { title: string; occursAt: string; kind: string; notes: string };
  setEventForm: Dispatch<
    SetStateAction<{ title: string; occursAt: string; kind: string; notes: string }>
  >;
  selectedApp: AppRow | null;
  reloadCareerEvents: () => void | Promise<void>;
  bragSheet: boolean;
  setBragSheet: Dispatch<SetStateAction<boolean>>;
  editingBragId: string | null;
  setEditingBragId: Dispatch<SetStateAction<string | null>>;
  bragForm: { title: string; occurredAt: string; summary: string; evidenceNote: string };
  setBragForm: Dispatch<
    SetStateAction<{ title: string; occurredAt: string; summary: string; evidenceNote: string }>
  >;
  contactSheet: boolean;
  setContactSheet: Dispatch<SetStateAction<boolean>>;
  editingContactId: string | null;
  setEditingContactId: Dispatch<SetStateAction<string | null>>;
  contactForm: {
    name: string;
    organization: string;
    roleTitle: string;
    email: string;
    lastContactAt: string;
    notes: string;
  };
  setContactForm: Dispatch<
    SetStateAction<{
      name: string;
      organization: string;
      roleTitle: string;
      email: string;
      lastContactAt: string;
      notes: string;
    }>
  >;
  setSelectedContactId: Dispatch<SetStateAction<string | null>>;
  milestoneSheet: boolean;
  setMilestoneSheet: Dispatch<SetStateAction<boolean>>;
  editingMilestoneId: string | null;
  setEditingMilestoneId: Dispatch<SetStateAction<string | null>>;
  milestoneForm: { title: string; status: string; dueAt: string; notes: string; lane: RoadmapLane };
  setMilestoneForm: Dispatch<
    SetStateAction<{
      title: string;
      status: string;
      dueAt: string;
      notes: string;
      lane: RoadmapLane;
    }>
  >;
  selectedPath: PathEntryRow | null;
  setPathMilestones: Dispatch<
    SetStateAction<
      Array<{
        id: string;
        pathEntryId: string;
        title: string;
        status: string;
        dueAt?: string | null;
        notes: string;
        lane: string;
      }>
    >
  >;
  setPathPipeline: Dispatch<
    SetStateAction<{
      openRoadmapItems: number;
      doneMilestones: number;
      bragWins: number;
      activeBenefits: number;
      promotions: number;
      people: number;
      compensationItems: number;
    } | null>
  >;
  compensationSheet: boolean;
  setCompensationSheet: Dispatch<SetStateAction<boolean>>;
  editingCompensationId: string | null;
  setEditingCompensationId: Dispatch<SetStateAction<string | null>>;
  compensationForm: {
    kind: string;
    title: string;
    amount: string;
    currency: string;
    cadence: (typeof compensationCadences)[number];
    notes: string;
  };
  setCompensationForm: Dispatch<
    SetStateAction<{
      kind: string;
      title: string;
      amount: string;
      currency: string;
      cadence: (typeof compensationCadences)[number];
      notes: string;
    }>
  >;
  setPathCompensation: Dispatch<
    SetStateAction<
      Array<{
        id: string;
        pathEntryId: string;
        kind: string;
        title: string;
        amount?: number | null;
        currency: string;
        cadence: string;
        notes: string;
        sortOrder: number;
      }>
    >
  >;
  journalSheet: boolean;
  setJournalSheet: Dispatch<SetStateAction<boolean>>;
  editingJournalId: string | null;
  setEditingJournalId: Dispatch<SetStateAction<string | null>>;
  journalForm: { title: string; occurredAt: string; mood: string; body: string };
  setJournalForm: Dispatch<
    SetStateAction<{ title: string; occurredAt: string; mood: string; body: string }>
  >;
  setPathJournalEntries: Dispatch<
    SetStateAction<
      Array<{
        id: string;
        pathEntryId: string;
        occurredAt: string;
        title: string;
        body: string;
        mood: string;
        sortOrder: number;
      }>
    >
  >;
  promotionSheet: boolean;
  setPromotionSheet: Dispatch<SetStateAction<boolean>>;
  editingPromotionId: string | null;
  setEditingPromotionId: Dispatch<SetStateAction<string | null>>;
  promotionForm: { title: string; effectiveAt: string; notes: string };
  setPromotionForm: Dispatch<
    SetStateAction<{ title: string; effectiveAt: string; notes: string }>
  >;
  setPathPromotions: Dispatch<
    SetStateAction<
      Array<{
        id: string;
        pathEntryId: string;
        title: string;
        effectiveAt?: string | null;
        notes: string;
        sortOrder: number;
      }>
    >
  >;
  personSheet: boolean;
  setPersonSheet: Dispatch<SetStateAction<boolean>>;
  editingPersonId: string | null;
  setEditingPersonId: Dispatch<SetStateAction<string | null>>;
  personForm: { name: string; roleTitle: string; relationship: string; notes: string };
  setPersonForm: Dispatch<
    SetStateAction<{ name: string; roleTitle: string; relationship: string; notes: string }>
  >;
  setPathPeople: Dispatch<
    SetStateAction<
      Array<{
        id: string;
        pathEntryId: string;
        name: string;
        roleTitle: string;
        relationship: string;
        notes: string;
        sortOrder: number;
      }>
    >
  >;
  pathDocLinkSheet: boolean;
  setPathDocLinkSheet: Dispatch<SetStateAction<boolean>>;
  linkableVaultDocs: VaultDoc[];
  vaultDocs: VaultDoc[];
  setPathDocuments: Dispatch<
    SetStateAction<
      Array<{
        id: string;
        pathEntryId: string;
        vaultDocId: string;
        note: string;
        title: string;
        category: string;
        hasFile: boolean;
      }>
    >
  >;
  interviewSheet: boolean;
  setInterviewSheet: Dispatch<SetStateAction<boolean>>;
  editingInterviewId: string | null;
  setEditingInterviewId: Dispatch<SetStateAction<string | null>>;
  interviewForm: {
    applicationId: string;
    company: string;
    roleTitle: string;
    scheduledAt: string;
    status: string;
    notes: string;
    questions: string;
  };
  setInterviewForm: Dispatch<
    SetStateAction<{
      applicationId: string;
      company: string;
      roleTitle: string;
      scheduledAt: string;
      status: string;
      notes: string;
      questions: string;
    }>
  >;
  apps: AppRow[];
  draftSheet: boolean;
  setDraftSheet: Dispatch<SetStateAction<boolean>>;
  draftPane: ResumeDraftPane;
  setDraftPane: Dispatch<SetStateAction<ResumeDraftPane>>;
  draftPreviewAs: "markdown" | "typst";
  setDraftPreviewAs: Dispatch<SetStateAction<"markdown" | "typst">>;
  includeBragInDraft: boolean;
  setIncludeBragInDraft: Dispatch<SetStateAction<boolean>>;
  draftBusy: boolean;
  draftMarkdown: string;
  draftTypst: string;
  draftCompileBusy: boolean;
  setDraftCompileBusy: Dispatch<SetStateAction<boolean>>;
  generateResumeDraft: (openSheet?: boolean) => void | Promise<void>;
};

export function CareerModals(props: CareerModalsProps) {
  const {
    sheetOpen,
    setSheetOpen,
    editingAppId,
    setEditingAppId,
    form,
    setForm,
    pathSheet,
    setPathSheet,
    editingPathId,
    setEditingPathId,
    pathForm,
    setPathForm,
    setSelectedPathId,
    postingSheet,
    setPostingSheet,
    postingForm,
    setPostingForm,
    importUrlSheet,
    setImportUrlSheet,
    importUrl,
    setImportUrl,
    importUrlBusy,
    setImportUrlBusy,
    setSelectedPostingId,
    refresh,
    smartBoardSheet,
    setSmartBoardSheet,
    editingSmartBoardId,
    setEditingSmartBoardId,
    smartBoardBusy,
    setSmartBoardBusy,
    smartBoardForm,
    setSmartBoardForm,
    companyBoards,
    setCompanyBoards,
    setSmartBoards,
    openingsScope,
    setOpeningsScope,
    syncBoardsSheet,
    setSyncBoardsSheet,
    syncBoardResult,
    setSyncBoardResult,
    syncBoardsBusy,
    setSyncBoardsBusy,
    syncBoardSources,
    setSyncBoardSources,
    syncCompaniesBusy,
    setSyncCompaniesBusy,
    companyBoardForm,
    setCompanyBoardForm,
    companyBoardBusy,
    setCompanyBoardBusy,
    eventSheet,
    setEventSheet,
    editingEventId,
    setEditingEventId,
    eventForm,
    setEventForm,
    selectedApp,
    reloadCareerEvents,
    bragSheet,
    setBragSheet,
    editingBragId,
    setEditingBragId,
    bragForm,
    setBragForm,
    contactSheet,
    setContactSheet,
    editingContactId,
    setEditingContactId,
    contactForm,
    setContactForm,
    setSelectedContactId,
    milestoneSheet,
    setMilestoneSheet,
    editingMilestoneId,
    setEditingMilestoneId,
    milestoneForm,
    setMilestoneForm,
    selectedPath,
    setPathMilestones,
    setPathPipeline,
    compensationSheet,
    setCompensationSheet,
    editingCompensationId,
    setEditingCompensationId,
    compensationForm,
    setCompensationForm,
    setPathCompensation,
    journalSheet,
    setJournalSheet,
    editingJournalId,
    setEditingJournalId,
    journalForm,
    setJournalForm,
    setPathJournalEntries,
    promotionSheet,
    setPromotionSheet,
    editingPromotionId,
    setEditingPromotionId,
    promotionForm,
    setPromotionForm,
    setPathPromotions,
    personSheet,
    setPersonSheet,
    editingPersonId,
    setEditingPersonId,
    personForm,
    setPersonForm,
    setPathPeople,
    pathDocLinkSheet,
    setPathDocLinkSheet,
    linkableVaultDocs,
    vaultDocs,
    setPathDocuments,
    interviewSheet,
    setInterviewSheet,
    editingInterviewId,
    setEditingInterviewId,
    interviewForm,
    setInterviewForm,
    apps,
    draftSheet,
    setDraftSheet,
    draftPane,
    setDraftPane,
    draftPreviewAs,
    setDraftPreviewAs,
    includeBragInDraft,
    setIncludeBragInDraft,
    draftBusy,
    draftMarkdown,
    draftTypst,
    draftCompileBusy,
    setDraftCompileBusy,
    generateResumeDraft,
  } = props;

  return (
    <>
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
          <FormField label="URL">
            <input
              className={fieldControlClass}
              value={form.url}
              onChange={(e) => setForm({ ...form, url: e.target.value })}
              placeholder="https://careers.example.com/jobs/123"
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
                  url: form.url.trim() || undefined,
                });
                setSheetOpen(false);
                setEditingAppId(null);
                setForm({ company: "", roleTitle: "", status: "interested", location: "", url: "" });
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
            <NotesEditor
              value={pathForm.summary}
              onChange={(summary) => setPathForm({ ...pathForm, summary })}
              minRows={3}
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
              try {
                await ipc.careerUpsertJobPosting({
                  company: postingForm.company.trim(),
                  title: postingForm.title.trim(),
                  location: postingForm.location.trim() || undefined,
                  url: postingForm.url.trim() || undefined,
                  postedAt: new Date().toISOString(),
                });
                setPostingSheet(false);
                setPostingForm({ company: "", title: "", location: "", url: "" });
                showToast("Opening saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
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
          <p className="text-meta">
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
          <p className="text-meta">
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
              <p className="text-meta">
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
                        <label className="flex cursor-pointer items-center gap-2 text-body">
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
          <label className="flex items-center gap-2 text-body">
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
        title="Find new jobs"
      >
        <div className="space-y-4">
          <div className="space-y-3">
            <p className="text-meta">
              Paste a company careers page URL to pull openings into your job list.
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
              <p className="text-meta">No company boards yet.</p>
            ) : (
              <ul className="max-h-40 divide-y divide-[var(--color-chrome-stroke)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)]">
                {companyBoards.map((c) => (
                  <li
                    key={c.id}
                    className="flex items-center justify-between gap-2 px-3 py-2 text-meta"
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
            <p className="text-meta">
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
                <label key={src.id} className="flex items-center gap-2 text-body">
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
            <div className="space-y-2 rounded-lg border border-[var(--color-chrome-stroke)] p-3 text-meta">
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
            <NotesEditor
              value={eventForm.notes}
              onChange={(notes) => setEventForm({ ...eventForm, notes })}
              minRows={3}
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
                  await reloadCareerEvents();
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
                    await reloadCareerEvents();
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
            <NotesEditor
              value={bragForm.summary}
              onChange={(summary) => setBragForm({ ...bragForm, summary })}
              minRows={4}
              placeholder="Impact, metrics, skills demonstrated…"
            />
          </FormField>
          <FormField label="Evidence note">
            <NotesEditor
              value={bragForm.evidenceNote}
              onChange={(evidenceNote) => setBragForm({ ...bragForm, evidenceNote })}
              minRows={2}
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
            <NotesEditor
              value={contactForm.notes}
              onChange={(notes) => setContactForm({ ...contactForm, notes })}
              minRows={3}
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
            <NotesEditor
              value={milestoneForm.notes}
              onChange={(notes) => setMilestoneForm({ ...milestoneForm, notes })}
              minRows={3}
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
            <NotesEditor
              value={compensationForm.notes}
              onChange={(notes) => setCompensationForm({ ...compensationForm, notes })}
              minRows={3}
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
            <NotesEditor
              value={journalForm.body}
              onChange={(body) => setJournalForm({ ...journalForm, body })}
              minRows={5}
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
            <NotesEditor
              value={promotionForm.notes}
              onChange={(notes) => setPromotionForm({ ...promotionForm, notes })}
              minRows={4}
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
            <NotesEditor
              value={personForm.notes}
              onChange={(notes) => setPersonForm({ ...personForm, notes })}
              minRows={4}
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
            <p className="text-meta">
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
            <NotesEditor
              value={interviewForm.questions}
              onChange={(questions) => setInterviewForm({ ...interviewForm, questions })}
              minRows={4}
              placeholder="Behavioral stories, technical topics, questions to ask them…"
            />
          </FormField>
          <FormField label="Notes">
            <NotesEditor
              value={interviewForm.notes}
              onChange={(notes) => setInterviewForm({ ...interviewForm, notes })}
              minRows={3}
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
              <label className="flex items-center gap-2 text-body">
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
              className="max-h-[min(480px,55vh)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-4 text-body"
            >
              {draftPreviewAs === "typst" && draftTypst.trim() ? (
                <>
                  <p className="mb-2 text-caption">
                    Compile PDF for final layout.
                  </p>
                  <pre
                    className="font-mono text-meta leading-relaxed whitespace-pre-wrap text-[var(--color-text-main)]"
                  >
                    {draftTypst}
                  </pre>
                </>
              ) : draftMarkdown.trim() ? (
                <SimpleMarkdown content={draftMarkdown} />
              ) : (
                <p className="text-meta">
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
    </>
  );
}
