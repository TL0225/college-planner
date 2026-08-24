import { useCallback, useEffect, useMemo, useState, type DragEvent } from "react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  MetricTile,
  ModalSheet,
  StatusChip,
  fieldControlClass,
} from "@/design-system";
import {
  ipc,
  formatIpcError,
  type AuditSummary,
  type FinanceDashboardSummary,
  type GpaSummary,
  type PipelineMetrics,
  type PlannerCourse,
  type Semester,
} from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { OverviewWidgetGrid, type AdvisorPrepSummary } from "./OverviewWidgets";
import { DegreeRequirementsScreen } from "./DegreeRequirementsScreen";
import { PlannerCanvas } from "./PlannerCanvas";
import { CourseDashboard } from "./CourseDashboard";
import { AcademicsStatsSidebar } from "./AcademicsStatsSidebar";
import {
  PLANNER_DRAG_MIME,
  parsePlannerDragPayload,
  plannerDragDataTransfer,
  type PlannerDragPayload,
} from "./plannerDrag";

const ADVISOR_CHECKLIST_KEYS = [
  "profile.advisor.transcript",
  "profile.advisor.degreeAudit",
  "profile.advisor.gradPlan",
  "profile.advisor.questions",
  "profile.advisor.internships",
] as const;

function parseAdvisorPrep(settings: Record<string, string>): AdvisorPrepSummary | null {
  const hasChecklist =
    settings["profile.advisorPrep"] === "true" ||
    ADVISOR_CHECKLIST_KEYS.some((key) => key in settings);
  if (!hasChecklist) return null;
  const completed = ADVISOR_CHECKLIST_KEYS.filter((key) => settings[key] === "true").length;
  return { completed, total: ADVISOR_CHECKLIST_KEYS.length };
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

export function AcademicsModule({
  page = "academics",
  highlightSectionId,
}: {
  page?: string;
  highlightSectionId?: string;
}) {
  const view =
    page === "planner" ? "planner" : page === "degree" ? "degree" : "overview";
  const [summary, setSummary] = useState<AuditSummary | null>(null);
  const [semesters, setSemesters] = useState<Semester[]>([]);
  const [courses, setCourses] = useState<PlannerCourse[]>([]);
  const [audit, setAudit] = useState<{
    items: Array<{
      id: string;
      sectionTitle: string;
      creditsRequired?: number | null;
      creditsEarned: number;
      status: string;
      matchedCodes: string[];
      missingCodes: string[];
    }>;
    satisfiedCount: number;
    totalCount: number;
    progressRatio: number;
  } | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [courseSheet, setCourseSheet] = useState(false);
  const [season, setSeason] = useState("Fall");
  const [year, setYear] = useState(new Date().getFullYear());
  const [courseForm, setCourseForm] = useState({
    semesterId: "",
    code: "",
    title: "",
    credits: 3,
  });

  const [gpaSummary, setGpaSummary] = useState<GpaSummary | null>(null);
  const [careerMetrics, setCareerMetrics] = useState<PipelineMetrics | null>(null);
  const [financeSummary, setFinanceSummary] = useState<FinanceDashboardSummary | null>(null);
  const [vaultCount, setVaultCount] = useState(0);
  const [todayEvents, setTodayEvents] = useState<Array<{ id: string; title: string; startAt: string }>>(
    [],
  );
  const [weekAheadEvents, setWeekAheadEvents] = useState<
    Array<{ id: string; title: string; startAt: string }>
  >([]);
  const [deadlineTasks, setDeadlineTasks] = useState<
    Array<{ id: string; title: string; dueAt?: string }>
  >([]);
  const [openTaskRows, setOpenTaskRows] = useState<
    Array<{ id: string; title: string; dueAt?: string }>
  >([]);
  const [openTaskCount, setOpenTaskCount] = useState(0);
  const [savedSchoolCount, setSavedSchoolCount] = useState(0);
  const [advisorPrep, setAdvisorPrep] = useState<AdvisorPrepSummary | null>(null);
  const [careerFollowUps, setCareerFollowUps] = useState<
    Array<{ id: string; company: string; roleTitle: string; appliedAt?: string }>
  >([]);
  const [recentDocuments, setRecentDocuments] = useState<
    Array<{ id: string; title: string; updatedAt: string }>
  >([]);
  const [gpaSheetOpen, setGpaSheetOpen] = useState(false);
  const [creditsSheetOpen, setCreditsSheetOpen] = useState(false);
  const [dashboardCourse, setDashboardCourse] = useState<PlannerCourse | null>(null);
  const [dropTargetCategoryId, setDropTargetCategoryId] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [s, list, c, a, tasks, career, finance, gpa, events, vault, schools, settings, applications] =
      await Promise.all([
      ipc.academicsGetAuditSummary(),
      ipc.academicsListSemesters(),
      ipc.academicsListCourses(),
      ipc.academicsGetRequirementAudit(),
      ipc.calendarListTasks().catch(() => []),
      ipc.careerPipelineMetrics().catch(() => null),
      ipc.financeDashboardSummary().catch(() => null),
      ipc.academicsGetGpaSummary().catch(() => null as GpaSummary | null),
      ipc.calendarListEvents().catch(() => []),
      ipc.documentsListVault().catch(() => []),
      ipc.discoveryListInstitutions().catch(() => []),
      ipc.settingsGet().catch(() => ({ values: {} as Record<string, string> })),
      ipc.careerListApplications().catch(() => []),
    ]);
    setSummary(s);
    setSemesters(list);
    setCourses(c);
    setAudit(a);
    const now = new Date();
    const todayStart = startOfDay(now);
    const weekEnd = addDays(todayStart, 7);
    const today = events
      .filter((e) => {
        const d = new Date(e.startAt);
        return (
          d.getFullYear() === now.getFullYear() &&
          d.getMonth() === now.getMonth() &&
          d.getDate() === now.getDate()
        );
      })
      .slice(0, 6);
    setTodayEvents(today.map((e) => ({ id: e.id, title: e.title, startAt: e.startAt })));
    const weekAhead = events
      .filter((e) => {
        const start = new Date(e.startAt);
        return start >= todayStart && start < weekEnd;
      })
      .sort((a, b) => new Date(a.startAt).getTime() - new Date(b.startAt).getTime())
      .slice(0, 8);
    setWeekAheadEvents(
      weekAhead.map((e) => ({ id: e.id, title: e.title, startAt: e.startAt })),
    );
    const openTasks = tasks.filter((t) => !t.isComplete);
    setOpenTaskCount(openTasks.length);
    setOpenTaskRows(
      openTasks.slice(0, 6).map((t) => ({ id: t.id, title: t.title, dueAt: t.dueAt })),
    );
    const deadlineCutoff = addDays(todayStart, 14);
    const upcomingDeadlines = openTasks
      .filter((t) => {
        if (!t.dueAt) return false;
        const due = new Date(t.dueAt);
        return due >= todayStart && due < deadlineCutoff;
      })
      .sort((a, b) => new Date(a.dueAt!).getTime() - new Date(b.dueAt!).getTime())
      .slice(0, 6);
    setDeadlineTasks(
      upcomingDeadlines.map((t) => ({ id: t.id, title: t.title, dueAt: t.dueAt })),
    );
    setGpaSummary(gpa);
    setCareerMetrics(career);
    setFinanceSummary(finance);
    setVaultCount(vault.length);
    setRecentDocuments(
      vault
        .filter((d) => !d.isFolder)
        .sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime())
        .slice(0, 5)
        .map((d) => ({ id: d.id, title: d.title || "Document", updatedAt: d.updatedAt })),
    );
    setSavedSchoolCount(schools.filter((school) => school.isSaved).length);
    setAdvisorPrep(parseAdvisorPrep(settings.values));
    const followCutoff = addDays(todayStart, -7);
    setCareerFollowUps(
      applications
        .filter((app) => app.status === "applied")
        .filter((app) => {
          if (!app.appliedAt) return true;
          return new Date(app.appliedAt) <= followCutoff;
        })
        .slice(0, 6)
        .map((app) => ({
          id: app.id,
          company: app.company,
          roleTitle: app.roleTitle,
          appliedAt: app.appliedAt,
        })),
    );
    setCourseForm((prev) =>
      prev.semesterId || !list[0] ? prev : { ...prev, semesterId: list[0].id },
    );
  }, []);

  const { refresh, error } = useLiveQuery(load, [
    "planner",
    "catalog",
    "calendar",
    "career",
    "finance",
    "vault",
    "discovery",
    "profile",
  ]);

  useEffect(() => {
    if (!highlightSectionId || view !== "degree") return;
    const el = document.getElementById(`req-section-${highlightSectionId}`);
    el?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [highlightSectionId, view, audit?.items.length]);

  const isWorkspaceEmpty = useMemo(
    () =>
      (summary?.courseCount ?? 0) === 0 &&
      (summary?.semesterCount ?? 0) === 0 &&
      todayEvents.length === 0 &&
      openTaskCount === 0 &&
      (careerMetrics?.total ?? 0) === 0 &&
      vaultCount === 0,
    [summary, todayEvents.length, openTaskCount, careerMetrics, vaultCount],
  );

  const loadSample = useCallback(async () => {
    try {
      await ipc.demoSeedSampleData();
      showToast("Sample data loaded", "success");
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  }, [refresh]);

  const coursesBySemester = useMemo(() => {
    const map = new Map<string, PlannerCourse[]>();
    for (const c of courses) {
      const list = map.get(c.semesterId) ?? [];
      list.push(c);
      map.set(c.semesterId, list);
    }
    return map;
  }, [courses]);

  const gradedCourses = useMemo(
    () => courses.filter((c) => c.status === "completed" && c.grade),
    [courses],
  );

  const draggableRequirements = useMemo(() => {
    if (!audit) return [];
    const seen = new Set<string>();
    const rows: PlannerDragPayload[] = [];
    for (const item of audit.items) {
      for (const code of item.missingCodes) {
        const normalized = code.trim().toUpperCase();
        if (!normalized || seen.has(normalized)) continue;
        seen.add(normalized);
        rows.push({ code: normalized, title: normalized, credits: 3 });
      }
    }
    return rows;
  }, [audit]);

  const dashboardSemester = useMemo(
    () => semesters.find((s) => s.id === dashboardCourse?.semesterId) ?? null,
    [semesters, dashboardCourse],
  );

  const handleRequirementDrop = useCallback(
    async (semesterId: string, payload: PlannerDragPayload) => {
      try {
        const changed = await ipc.academicsAddRequirementCourse({
          semesterId,
          code: payload.code,
          title: payload.title,
          credits: payload.credits,
        });
        if (changed) {
          showToast(`${payload.code} added to term`, "success");
          await refresh();
        }
      } catch (e) {
        showToast(formatIpcError(e), "error");
      }
    },
    [refresh],
  );

  const handleFulfillmentDrop = useCallback(
    async (categoryId: string, payload: PlannerDragPayload) => {
      try {
        const changed = await ipc.academicsAssignFulfillment({
          categoryId,
          courseCode: payload.code,
        });
        if (changed) {
          showToast(`${payload.code} assigned to requirement`, "success");
          await refresh();
        } else {
          showToast(`${payload.code} already assigned`, "info");
        }
      } catch (e) {
        showToast(formatIpcError(e), "error");
      }
    },
    [refresh],
  );

  const readRequirementDropPayload = useCallback((e: DragEvent): PlannerDragPayload | null => {
    const raw =
      e.dataTransfer.getData(PLANNER_DRAG_MIME) || e.dataTransfer.getData("text/plain");
    return parsePlannerDragPayload(raw);
  }, []);

  const title =
    view === "planner" ? "Planner" : view === "degree" ? "Requirements" : "Overview";

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={title}
        actions={
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setSheetOpen(true)}>
              Add semester
            </Button>
            <Button size="sm" onClick={() => setCourseSheet(true)}>
              Add course
            </Button>
          </div>
        }
      />
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}

      {view === "overview" && (
        <div className="min-h-0 flex-1 overflow-auto px-3 pb-4 pt-1">
          <OverviewWidgetGrid
            data={{
              summary,
              gpa: gpaSummary,
              todayEvents,
              weekAheadEvents,
              deadlineTasks,
              openTasks: openTaskRows,
              openTaskCount,
              career: careerMetrics,
              finance: financeSummary,
              vaultCount,
              savedSchoolCount,
              advisorPrep,
              careerFollowUps,
              recentDocuments,
              isWorkspaceEmpty,
              onLoadSample: () => void loadSample(),
            }}
          />
        </div>
      )}

      {view === "planner" && (
        <div className="flex min-h-0 flex-1 flex-col gap-2 lg:flex-row">
          <AcademicsStatsSidebar
            summary={summary}
            gpa={gpaSummary}
            auditProgress={audit?.progressRatio}
            className="mx-3 shrink-0 lg:mx-0 lg:ml-3 lg:w-[240px]"
          />
          <div className="flex min-h-0 min-w-0 flex-1 flex-col">
            {draggableRequirements.length > 0 ? (
              <AppCard title="Drag to planner" className="mx-3 mb-1 shrink-0">
                <p className="mb-2 text-[11px] text-[var(--color-text-light)]">
                  Drop a requirement course onto a semester row in the planner canvas.
                </p>
                <div className="flex flex-wrap gap-1.5">
                  {draggableRequirements.slice(0, 24).map((row) => (
                    <RequirementDragChip key={row.code} payload={row} />
                  ))}
                </div>
              </AppCard>
            ) : null}
            <PlannerCanvas
              semesters={semesters}
              coursesBySemester={coursesBySemester}
              onAddSemester={() => setSheetOpen(true)}
              onDeleteSemester={(s) => {
                if (!confirmDelete(s.label || `${s.season} ${s.year}`)) return;
                void ipc
                  .academicsDeleteSemester(s.id)
                  .then(() => {
                    showToast("Semester deleted", "success");
                  })
                  .catch(() => showToast("Could not delete semester", "error"));
              }}
              onRequirementDrop={handleRequirementDrop}
              onOpenDashboard={setDashboardCourse}
            />
          </div>
        </div>
      )}

      {view === "degree" && (
        <DegreeRequirementsScreen
          audit={audit}
          summary={summary}
          gpaSummary={gpaSummary}
          highlightSectionId={highlightSectionId}
          dropTargetCategoryId={dropTargetCategoryId}
          onDropTargetChange={setDropTargetCategoryId}
          onRequirementDrop={(categoryId, payload) => void handleFulfillmentDrop(categoryId, payload)}
          readRequirementDropPayload={readRequirementDropPayload}
          onCreditsClick={() => setCreditsSheetOpen(true)}
          onGpaClick={() => setGpaSheetOpen(true)}
          onProgramChanged={() => void refresh()}
          requirementDragChip={(payload) => <RequirementDragChip payload={payload} />}
        />
      )}

      <ModalSheet open={gpaSheetOpen} onOpenChange={setGpaSheetOpen} title="GPA breakdown">
        <div className="space-y-3">
          <div className="grid gap-2 sm:grid-cols-3">
            <MetricTile
              label="Cumulative GPA"
              value={gpaSummary?.gpa != null ? gpaSummary.gpa.toFixed(2) : "—"}
              accent="var(--color-warning)"
            />
            <MetricTile label="Graded credits" value={gpaSummary?.gradedCredits.toFixed(1) ?? "0"} />
            <MetricTile label="Graded courses" value={gpaSummary?.gradedCourses ?? 0} />
          </div>
          {gradedCourses.length === 0 ? (
            <EmptyState
              title="No graded courses"
              body="Mark planner courses as completed and assign grades to compute GPA."
            />
          ) : (
            <ul className="divide-y divide-[var(--color-chrome-stroke)] rounded-lg border border-[var(--color-chrome-stroke)]">
              {gradedCourses.map((c) => (
                <li key={c.id} className="flex items-center justify-between px-3 py-2 text-[13px]">
                  <span>
                    {c.code} · {c.title}
                  </span>
                  <StatusChip title={`${c.grade} · ${c.credits} cr`} tint="var(--color-primary)" filled />
                </li>
              ))}
            </ul>
          )}
        </div>
      </ModalSheet>

      <ModalSheet open={creditsSheetOpen} onOpenChange={setCreditsSheetOpen} title="Credit summary">
        <div className="space-y-3">
          <div className="grid gap-2 sm:grid-cols-3">
            <MetricTile
              label="Completed"
              value={summary?.completedCredits.toFixed(1) ?? "0"}
              accent="var(--color-success)"
            />
            <MetricTile label="Planned" value={summary?.plannedCredits.toFixed(1) ?? "0"} />
            <MetricTile label="Total courses" value={summary?.courseCount ?? 0} />
          </div>
          <p className="text-[12px] text-[var(--color-text-light)]">
            Completed credits count courses marked completed in the planner. Planned credits include
            in-progress and planned rows (excluding dropped).
          </p>
        </div>
      </ModalSheet>

      <ModalSheet open={sheetOpen} onOpenChange={setSheetOpen} title="Add semester">
        <div className="space-y-3">
          <FormField label="Season">
            <select
              className={fieldControlClass}
              value={season}
              onChange={(e) => setSeason(e.target.value)}
            >
              {["Fall", "Spring", "Summer", "Winter"].map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Year">
            <input
              className={fieldControlClass}
              type="number"
              value={year}
              onChange={(e) => setYear(Number(e.target.value))}
            />
          </FormField>
          <Button
            onClick={async () => {
              await ipc.academicsUpsertSemester({ year, season, isCurrent: true });
              setSheetOpen(false);
            }}
          >
            Save semester
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={courseSheet} onOpenChange={setCourseSheet} title="Add course">
        <div className="space-y-3">
          <FormField label="Semester">
            <select
              className={fieldControlClass}
              value={courseForm.semesterId}
              onChange={(e) => setCourseForm({ ...courseForm, semesterId: e.target.value })}
            >
              {semesters.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Code">
            <input
              className={fieldControlClass}
              value={courseForm.code}
              onChange={(e) => setCourseForm({ ...courseForm, code: e.target.value })}
              placeholder="CS 101"
            />
          </FormField>
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={courseForm.title}
              onChange={(e) => setCourseForm({ ...courseForm, title: e.target.value })}
              placeholder="Intro to Computer Science"
            />
          </FormField>
          <FormField label="Credits">
            <input
              className={fieldControlClass}
              type="number"
              value={courseForm.credits}
              onChange={(e) => setCourseForm({ ...courseForm, credits: Number(e.target.value) })}
            />
          </FormField>
          <Button
            disabled={!courseForm.semesterId || !courseForm.code.trim()}
            onClick={async () => {
              await ipc.academicsUpsertCourse({
                semesterId: courseForm.semesterId,
                code: courseForm.code.trim(),
                title: courseForm.title.trim() || courseForm.code.trim(),
                credits: courseForm.credits,
                status: "planned",
              });
              setCourseSheet(false);
              setCourseForm((prev) => ({ ...prev, code: "", title: "" }));
            }}
          >
            Save course
          </Button>
        </div>
      </ModalSheet>

      <CourseDashboard
        open={!!dashboardCourse}
        onOpenChange={(open) => {
          if (!open) setDashboardCourse(null);
        }}
        course={dashboardCourse}
        semester={dashboardSemester}
      />
    </div>
  );
}

function RequirementDragChip({ payload }: { payload: PlannerDragPayload }) {
  return (
    <button
      type="button"
      draggable
      onDragStart={(e) => {
        e.dataTransfer.effectAllowed = "move";
        const dt = plannerDragDataTransfer(payload);
        e.dataTransfer.setData("application/x-college-planner-course", dt.getData("application/x-college-planner-course"));
        e.dataTransfer.setData("text/plain", dt.getData("text/plain"));
      }}
      className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium"
      style={{
        border: "1px solid var(--color-chrome-stroke)",
        background: "var(--color-surface)",
        cursor: "grab",
      }}
      title="Drag onto a semester term"
    >
      <span className="font-semibold">{payload.code}</span>
      {payload.credits != null ? (
        <span className="opacity-70">{payload.credits} cr</span>
      ) : null}
    </button>
  );
}

