import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  MetricTile,
  ModalSheet,
  StatusChip,
  fieldControlClass,
} from "@/design-system";
import { ipc, type PlannerCourse, type Semester } from "@/lib/ipc";
import { showToast } from "@/lib/toast";

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

  const progressPct = useMemo(() => {
    if (!course) return 0;
    if (course.status === "completed") return 100;
    if (course.status === "in_progress") return 55;
    if (course.status === "dropped") return 0;
    return 18;
  }, [course]);

  const gradingWeightTotal = useMemo(
    () => gradingCategories.reduce((sum, c) => sum + c.weight, 0),
    [gradingCategories],
  );

  if (!course) return null;

  const semesterLabel =
    semester?.label || (semester ? `${semester.season} ${semester.year}` : "Unassigned");

  return (
    <ModalSheet
      open={open}
      onOpenChange={onOpenChange}
      title={`${course.code} dashboard`}
      width={920}
    >
      <div className="space-y-3">
        <div
          className="rounded-xl border border-[var(--color-chrome-stroke)] px-4 py-3"
          style={{
            background:
              "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 8%, transparent), transparent)",
          }}
        >
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5">
                <StatusChip title={course.status.replace("_", " ")} filled />
                {course.grade ? <StatusChip title={`Grade ${course.grade}`} /> : null}
              </div>
              <h3
                className="mt-1 text-[var(--color-text-main)]"
                style={{ font: "var(--type-section-title)", fontSize: 18, letterSpacing: "-0.02em" }}
              >
                {course.title}
              </h3>
              <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
                {semesterLabel} · {course.credits} credits · {progressPct}% progress
              </p>
            </div>
            <div className="grid grid-cols-3 gap-2">
              <MetricTile label="Credits" value={course.credits.toFixed(1)} />
              <MetricTile label="Grade" value={course.grade ?? "—"} accent="var(--color-warning)" />
              <MetricTile label="Open items" value={tasks.filter((t) => !t.isComplete).length} />
            </div>
          </div>
        </div>

        <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
          <div className="space-y-3">
            <AppCard title="Professor">
              <FormField label="Name">
                <input
                  className={fieldControlClass}
                  value={professor}
                  onChange={(e) => setProfessor(e.target.value)}
                  placeholder="Dr. Smith"
                  onBlur={() =>
                    void ipc.settingsSet(professorKey, professor).catch(() => {
                      showToast("Could not save professor", "error");
                    })
                  }
                />
              </FormField>
            </AppCard>

            <AppCard title="Notes">
              <textarea
                className={fieldControlClass}
                rows={5}
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Course notes autosave on blur…"
                onBlur={() =>
                  void ipc.settingsSet(notesKey, notes).catch(() => {
                    showToast("Could not save notes", "error");
                  })
                }
              />
            </AppCard>

            <AppCard title="Resources">
              {vaultLinks.length === 0 ? (
                <EmptyState
                  title="No linked documents"
                  body="Import a syllabus PDF in Documents or Syllabus AI."
                />
              ) : (
                <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                  {vaultLinks.slice(0, 8).map((d) => (
                    <li key={d.id} className="flex items-center justify-between py-2 text-[13px]">
                      <span className="truncate">{d.title}</span>
                      <StatusChip title={d.category} />
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>

            <AppCard title="Prerequisites">
              {!prerequisites ? (
                <EmptyState title="Checking prerequisites…" body="Loading catalog and planner data." />
              ) : (
                <>
                  <div className="mb-2 flex flex-wrap gap-1.5">
                    <StatusChip
                      title={prerequisites.satisfied ? "Satisfied" : "Missing prerequisites"}
                      tint={
                        prerequisites.satisfied ? "var(--color-success)" : "var(--color-warning)"
                      }
                      filled
                    />
                    {prerequisites.missingCodes.map((code) => (
                      <StatusChip key={code} title={code} tint="var(--color-error)" />
                    ))}
                  </div>
                  <p className="text-[12px] text-[var(--color-text-light)]">{prerequisites.notes}</p>
                </>
              )}
            </AppCard>

            <AppCard title="Grading categories">
              {gradingCategories.length === 0 ? (
                <EmptyState
                  title="No categories"
                  body="Grading weights from your Swift planner import appear here when present."
                />
              ) : (
                <>
                  <p className="mb-2 text-[11px] text-[var(--color-text-light)]">
                    Total weight {gradingWeightTotal.toFixed(1)}%
                  </p>
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {gradingCategories.map((c) => (
                      <li key={c.id} className="flex items-center justify-between py-2 text-[13px]">
                        <span className="truncate">{c.name}</span>
                        <StatusChip title={`${c.weight.toFixed(1)}%`} />
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </AppCard>
          </div>

          <AppCard title="Tasks & deadlines">
            <div className="mb-3 flex gap-1">
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
            <FormField label="Search">
              <input
                className={fieldControlClass}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Filter tasks…"
              />
            </FormField>
            {filteredTasks.length === 0 ? (
              <EmptyState
                title="No matching items"
                body="Tasks and calendar events tagged with this course code appear here."
              />
            ) : (
              <ul className="mt-2 divide-y divide-[var(--color-chrome-stroke)] rounded-lg border border-[var(--color-chrome-stroke)]">
                {filteredTasks.slice(0, 16).map((t) => (
                  <li key={`${t.source}-${t.id}`} className="flex items-center justify-between px-3 py-2">
                    <div className="min-w-0">
                      <div className="truncate text-[13px] font-medium">{t.title}</div>
                      {t.dueAt ? (
                        <div className="text-[11px] text-[var(--color-text-light)]">
                          {new Date(t.dueAt).toLocaleString()}
                        </div>
                      ) : null}
                    </div>
                    <div className="flex shrink-0 items-center gap-1.5">
                      <StatusChip title={t.source} />
                      {t.isComplete ? (
                        <StatusChip title="Done" tint="var(--color-success)" filled />
                      ) : (
                        <StatusChip title="Open" tint="var(--color-primary)" />
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        </div>
      </div>
    </ModalSheet>
  );
}
