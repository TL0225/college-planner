import { useCallback, useEffect, useMemo, useState } from "react";
import {
  BookOpen,
  Calendar,
  ListChecks,
  Folder,
  Globe,
  Mail,
  Pencil,
  Search,
  Trash2,
  User,
  X,
} from "lucide-react";
import { Button, EmptyState, ModalSheet, fieldControlClass } from "@/design-system";
import { ipc, type PlannerCourse, type Semester } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import {
  CourseDashboardCard,
  CourseDashboardInlineMetric,
  CourseDashboardResourceRow,
  CourseDashboardSectionTitle,
  CourseDashboardTaskRow,
  CourseStatusPill,
  courseProgressPercent,
} from "./CourseDashboardKit";

type DashboardTask = {
  id: string;
  title: string;
  dueAt?: string;
  isComplete: boolean;
  source: "task" | "event";
};

export function CourseDashboard({
  open,
  onOpenChange,
  course,
  semester,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  course: PlannerCourse | null;
  semester: Semester | null;
}) {
  const [notes, setNotes] = useState("");
  const [professor, setProfessor] = useState("");
  const [tasks, setTasks] = useState<DashboardTask[]>([]);
  const [vaultLinks, setVaultLinks] = useState<
    Array<{ id: string; title: string; category: string }>
  >([]);
  const [gradingCategories, setGradingCategories] = useState<
    Array<{ id: string; name: string; weight: number; sortOrder: number }>
  >([]);
  const [prerequisites, setPrerequisites] = useState<{
    satisfied: boolean;
    missingCodes: string[];
    notes: string;
  } | null>(null);
  const [taskFilter, setTaskFilter] = useState<"open" | "all">("open");
  const [search, setSearch] = useState("");
  const [searchActive, setSearchActive] = useState(false);

  const notesKey = course ? `course.notes.${course.id}` : "";
  const professorKey = course ? `course.professor.${course.code}` : "";

  const load = useCallback(async () => {
    if (!course) return;
    const [settings, calendarTasks, events, vault, categories, prereqEval] = await Promise.all([
      ipc.settingsGet(),
      ipc.calendarListTasks().catch(() => []),
      ipc.calendarListEvents().catch(() => []),
      ipc.documentsListVault().catch(() => []),
      ipc.academicsListGradingCategories(course.id).catch(() => []),
      ipc.academicsEvaluatePrerequisites(course.code).catch(() => null),
    ]);
    setNotes(settings.values[notesKey] ?? "");
    setProfessor(settings.values[professorKey] ?? "");
    const codeNeedle = course.code.toUpperCase();
    const merged: DashboardTask[] = [
      ...calendarTasks
        .filter(
          (t) =>
            t.title.toUpperCase().includes(codeNeedle) ||
            t.title.toUpperCase().startsWith(`${codeNeedle}:`),
        )
        .map((t) => ({
          id: t.id,
          title: t.title,
          dueAt: t.dueAt,
          isComplete: t.isComplete,
          source: "task" as const,
        })),
      ...events
        .filter(
          (e) =>
            e.title.toUpperCase().includes(codeNeedle) ||
            e.title.toUpperCase().startsWith(`${codeNeedle}:`),
        )
        .map((e) => ({
          id: e.id,
          title: e.title,
          dueAt: e.startAt,
          isComplete: false,
          source: "event" as const,
        })),
    ].sort((a, b) => (a.dueAt ?? "").localeCompare(b.dueAt ?? ""));
    setTasks(merged);
    setVaultLinks(
      vault.filter(
        (d) =>
          d.category === "syllabus" ||
          d.title.toUpperCase().includes(codeNeedle) ||
          d.relativePath.toUpperCase().includes(codeNeedle.replace(/\s+/g, "")),
      ),
    );
    setGradingCategories(categories);
    setPrerequisites(prereqEval);
  }, [course, notesKey, professorKey]);

  useEffect(() => {
    if (open && course) void load();
  }, [open, course, load]);

  const filteredTasks = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return tasks.filter((t) => {
      if (taskFilter === "open" && t.isComplete) return false;
      if (!needle) return true;
      return t.title.toLowerCase().includes(needle);
    });
  }, [tasks, taskFilter, search]);

  const gradingWeightTotal = useMemo(
    () => gradingCategories.reduce((sum, c) => sum + c.weight, 0),
    [gradingCategories],
  );

  if (!course) return null;

  const semesterLabel =
    semester?.label || (semester ? `${semester.season} ${semester.year}` : "Unassigned");
  const headerSubtitle = [semesterLabel, course.code].filter(Boolean).join(" · ");
  const progressText = courseProgressPercent(course.status);
  const syllabusSubtitle =
    vaultLinks.length > 0
      ? `${vaultLinks.length} linked file${vaultLinks.length === 1 ? "" : "s"}`
      : "Import or link a syllabus in Documents";

  return (
    <ModalSheet open={open} onOpenChange={onOpenChange} title={course.code} width={980}>
      <div className="space-y-0">
        <header className="border-b border-[var(--color-chrome-stroke)] px-1 pb-3.5 pt-2">
          <div className="flex flex-wrap items-baseline gap-2.5">
            <h2
              className="min-w-0 text-[var(--color-text-main)]"
              style={{ font: "var(--type-section-title)", fontSize: 20, letterSpacing: "-0.02em" }}
            >
              {course.title}
            </h2>
            <CourseStatusPill status={course.status} />
          </div>

          <div className="mt-2 flex flex-wrap items-center gap-3.5">
            {headerSubtitle ? (
              <p className="min-w-0 flex-1 truncate text-[13px] font-semibold text-[var(--color-text-light)]">
                {headerSubtitle}
              </p>
            ) : (
              <span className="flex-1" />
            )}
            <CourseDashboardInlineMetric label="Grade" value={course.grade ?? "—"} />
            <CourseDashboardInlineMetric
              label="Credits"
              value={course.credits.toFixed(course.credits % 1 === 0 ? 0 : 1)}
            />
            <CourseDashboardInlineMetric label="Progress" value={progressText} />
            <button
              type="button"
              className="rounded-md p-1 text-[var(--color-primary)] hover:bg-black/5"
              aria-label="Edit course"
              onClick={() => showToast("Course editing opens from Planner for now", "info")}
            >
              <Pencil className="h-4 w-4" />
            </button>
          </div>
        </header>

        <div className="grid gap-8 pt-4 lg:grid-cols-[minmax(300px,4fr)_minmax(420px,8fr)]">
          <aside className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <CourseDashboardSectionTitle>Grade</CourseDashboardSectionTitle>
                <div
                  className="mt-2.5 text-[var(--color-text-main)]"
                  style={{ font: "var(--type-page-title)", fontSize: 28, letterSpacing: "-0.03em" }}
                >
                  {course.grade ?? "—"}
                </div>
              </div>
              <div>
                <CourseDashboardSectionTitle>Professor</CourseDashboardSectionTitle>
                <div className="mt-2.5 flex items-start gap-2.5">
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[color-mix(in_srgb,var(--color-text-light)_18%,transparent)]">
                    <User className="h-3.5 w-3.5 text-[var(--color-text-light)]" />
                  </span>
                  <div className="min-w-0">
                    <input
                      className={`${fieldControlClass} !border-0 !bg-transparent !p-0 !shadow-none text-[13px] font-bold`}
                      value={professor}
                      onChange={(e) => setProfessor(e.target.value)}
                      placeholder="Not set"
                      onBlur={() =>
                        void ipc.settingsSet(professorKey, professor).catch(() => {
                          showToast("Could not save professor", "error");
                        })
                      }
                    />
                    <div className="mt-0.5 flex items-center gap-1 text-[12px] font-semibold text-[var(--color-text-light)]">
                      <Mail className="h-3 w-3" />
                      Add email in course details
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <CourseDashboardCard>
              <div className="flex items-center justify-between">
                <CourseDashboardSectionTitle>Notes</CourseDashboardSectionTitle>
                {notes ? (
                  <button
                    type="button"
                    className="rounded p-1 text-[var(--color-text-light)] hover:bg-black/5"
                    aria-label="Clear notes"
                    onClick={() => {
                      setNotes("");
                      void ipc.settingsSet(notesKey, "").catch(() => undefined);
                    }}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                ) : null}
              </div>
              <div className="relative">
                {!notes ? (
                  <p className="pointer-events-none absolute inset-x-1 top-1 text-[13px] text-[var(--color-text-light)] opacity-70">
                    Jot down anything about this course — reminders, links, professor preferences,
                    study plans…
                  </p>
                ) : null}
                <textarea
                  className={`${fieldControlClass} min-h-[96px] resize-y bg-transparent`}
                  rows={4}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  onBlur={() =>
                    void ipc.settingsSet(notesKey, notes).catch(() => {
                      showToast("Could not save notes", "error");
                    })
                  }
                />
              </div>
            </CourseDashboardCard>

            <CourseDashboardCard>
              <CourseDashboardSectionTitle>Resources</CourseDashboardSectionTitle>
              <CourseDashboardResourceRow
                title="Course Syllabus"
                subtitle={syllabusSubtitle}
                icon={<BookOpen className="h-4 w-4" />}
              />
              <CourseDashboardResourceRow
                title="Course Calendar"
                subtitle="View course events"
                icon={<Calendar className="h-4 w-4" />}
              />
              <CourseDashboardResourceRow
                title="Documents"
                subtitle={
                  vaultLinks.length === 0
                    ? "Link & organize files for this course"
                    : `${vaultLinks.length} linked file${vaultLinks.length === 1 ? "" : "s"}`
                }
                icon={<Folder className="h-4 w-4" />}
              />
              <CourseDashboardResourceRow
                title="View in Catalog"
                subtitle={course.code}
                icon={<Globe className="h-4 w-4" />}
              />
              {vaultLinks.length > 0 ? (
                <div className="space-y-2 pt-1">
                  <div className="text-[13px] font-semibold text-[var(--color-text-light)]">
                    Related documents
                  </div>
                  <ul className="space-y-1">
                    {vaultLinks.slice(0, 6).map((d) => (
                      <li
                        key={d.id}
                        className="flex items-center gap-2 text-[13px] text-[var(--color-text-main)]"
                      >
                        <span className="text-[var(--color-text-light)]">📄</span>
                        <span className="truncate">{d.title}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              ) : null}
            </CourseDashboardCard>

            {gradingCategories.length > 0 ? (
              <CourseDashboardCard>
                <CourseDashboardSectionTitle>Grading weights</CourseDashboardSectionTitle>
                <ul className="space-y-2">
                  {gradingCategories.slice(0, 8).map((c) => (
                    <li key={c.id} className="flex items-center justify-between gap-3 text-[13px]">
                      <span className="truncate font-semibold text-[var(--color-text-main)]">
                        {c.name}
                      </span>
                      <span className="shrink-0 font-bold tabular-nums text-[var(--color-primary)]">
                        {c.weight > 0 ? `${c.weight.toFixed(0)}%` : "—"}
                      </span>
                    </li>
                  ))}
                </ul>
                <p className="text-[12px] text-[var(--color-text-light)]">
                  Total weight {gradingWeightTotal.toFixed(1)}%
                </p>
              </CourseDashboardCard>
            ) : null}

            {prerequisites ? (
              <CourseDashboardCard>
                <CourseDashboardSectionTitle>Prerequisites</CourseDashboardSectionTitle>
                <div className="flex flex-wrap gap-1.5">
                  <span
                    className="inline-flex rounded-full px-2 py-1 text-[11px] font-semibold"
                    style={{
                      background: prerequisites.satisfied
                        ? "color-mix(in srgb, var(--color-success) 14%, transparent)"
                        : "color-mix(in srgb, var(--color-warning) 14%, transparent)",
                      color: prerequisites.satisfied
                        ? "var(--color-success)"
                        : "var(--color-warning)",
                    }}
                  >
                    {prerequisites.satisfied ? "Satisfied" : "Missing prerequisites"}
                  </span>
                  {prerequisites.missingCodes.map((code) => (
                    <span
                      key={code}
                      className="inline-flex rounded-full px-2 py-1 text-[11px] font-semibold"
                      style={{
                        background: "color-mix(in srgb, var(--color-error) 14%, transparent)",
                        color: "var(--color-error)",
                      }}
                    >
                      {code}
                    </span>
                  ))}
                </div>
                <p className="text-[13px] text-[var(--color-text-light)]">{prerequisites.notes}</p>
              </CourseDashboardCard>
            ) : null}
          </aside>

          <section>
            <CourseDashboardCard>
              <div className="flex flex-wrap items-center gap-2">
                <div className="flex min-w-0 flex-1 items-center gap-2">
                  <ListChecks className="h-4 w-4 text-[var(--color-primary)]" />
                  <CourseDashboardSectionTitle>Tasks & deadlines</CourseDashboardSectionTitle>
                </div>

                {searchActive ? (
                  <div className="flex min-w-[220px] flex-1 items-center gap-2 rounded-lg border border-[color-mix(in_srgb,var(--color-text-light)_15%,transparent)] bg-[var(--color-surface)] px-3 py-2">
                    <Search className="h-4 w-4 text-[var(--color-text-light)]" />
                    <input
                      className="min-w-0 flex-1 bg-transparent text-[13px] outline-none"
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      placeholder="Search tasks & deadlines"
                      autoFocus
                    />
                    {search ? (
                      <button type="button" onClick={() => setSearch("")} aria-label="Clear search">
                        <X className="h-4 w-4 text-[var(--color-text-light)]" />
                      </button>
                    ) : null}
                  </div>
                ) : (
                  <Button size="sm" variant="ghost" onClick={() => setSearchActive(true)}>
                    Search
                  </Button>
                )}

                <div className="flex gap-1">
                  <Button
                    size="sm"
                    variant={taskFilter === "open" ? "secondary" : "ghost"}
                    onClick={() => setTaskFilter("open")}
                  >
                    Open
                  </Button>
                  <Button
                    size="sm"
                    variant={taskFilter === "all" ? "secondary" : "ghost"}
                    onClick={() => setTaskFilter("all")}
                  >
                    All
                  </Button>
                </div>
              </div>

              <div className="space-y-3 pt-1">
                {filteredTasks.length === 0 ? (
                  <EmptyState
                    title="No matching items"
                    body="Tasks and calendar events tagged with this course code appear here."
                  />
                ) : (
                  filteredTasks.slice(0, 12).map((t) => (
                    <CourseDashboardTaskRow
                      key={`${t.source}-${t.id}`}
                      title={t.title}
                      dueAt={t.dueAt}
                      isComplete={t.isComplete}
                      badge={t.source === "task" ? "Task" : "Event"}
                      badgeTint={
                        t.source === "task" ? "var(--color-primary)" : "var(--color-warning)"
                      }
                    />
                  ))
                )}
              </div>
            </CourseDashboardCard>
          </section>
        </div>
      </div>
    </ModalSheet>
  );
}
