import { useMemo, useState, type DragEvent } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  MetricTile,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, type PlannerCourse, type Semester } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import {
  PLANNER_DRAG_MIME,
  parsePlannerDragPayload,
  plannerDragDataTransfer,
  type PlannerDragPayload,
} from "./plannerDrag";

const COURSE_STATUSES = ["planned", "in_progress", "completed", "dropped"] as const;
const GRADES = ["A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"] as const;

export function PlannerCanvas({
  semesters,
  coursesBySemester,
  selectedSemesterId,
  onSelectSemester,
  onDeleteSemester,
  onRequirementDrop,
  onOpenDashboard,
}: {
  semesters: Semester[];
  coursesBySemester: Map<string, PlannerCourse[]>;
  selectedSemesterId: string | null;
  onSelectSemester: (id: string) => void;
  onDeleteSemester: (semester: Semester) => void;
  onRequirementDrop?: (semesterId: string, payload: PlannerDragPayload) => Promise<void>;
  onOpenDashboard?: (course: PlannerCourse) => void;
}) {
  const [selectedCourseId, setSelectedCourseId] = useState<string | null>(null);
  const [dropTargetSemesterId, setDropTargetSemesterId] = useState<string | null>(null);

  const plannerCourses = selectedSemesterId
    ? (coursesBySemester.get(selectedSemesterId) ?? [])
    : [];

  const selectedSemester = semesters.find((s) => s.id === selectedSemesterId) ?? null;
  const selectedCourse = plannerCourses.find((c) => c.id === selectedCourseId) ?? null;

  const termStats = useMemo(() => {
    let completedCredits = 0;
    let plannedCredits = 0;
    let totalCredits = 0;
    for (const c of plannerCourses) {
      totalCredits += c.credits;
      if (c.status === "completed") completedCredits += c.credits;
      else if (c.status === "planned") plannedCredits += c.credits;
    }
    return {
      courseCount: plannerCourses.length,
      totalCredits,
      completedCredits,
      plannedCredits,
    };
  }, [plannerCourses]);

  const handleSelectSemester = (id: string) => {
    onSelectSemester(id);
    setSelectedCourseId(null);
  };

  const readDropPayload = (e: DragEvent): PlannerDragPayload | null => {
    const raw =
      e.dataTransfer.getData(PLANNER_DRAG_MIME) || e.dataTransfer.getData("text/plain");
    return parsePlannerDragPayload(raw);
  };

  const handleSemesterDragOver = (e: DragEvent, semesterId: string) => {
    if (!onRequirementDrop) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    setDropTargetSemesterId(semesterId);
  };

  const handleSemesterDrop = async (e: DragEvent, semesterId: string) => {
    e.preventDefault();
    setDropTargetSemesterId(null);
    if (!onRequirementDrop) return;
    const payload = readDropPayload(e);
    if (!payload) return;
    await onRequirementDrop(semesterId, payload);
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-hidden px-3 pb-3 pt-1">
      <div className="flex shrink-0 flex-wrap items-center gap-2">
        {semesters.length === 0 ? (
          <p className="text-[12px] text-[var(--color-text-light)]">No terms yet — add a semester.</p>
        ) : (
          <div className="flex min-w-0 flex-1 items-center gap-1.5 overflow-x-auto pb-0.5">
            {semesters.map((s) => {
              const selected = selectedSemesterId === s.id;
              const dropTarget = dropTargetSemesterId === s.id;
              const label = s.label || `${s.season} ${s.year}`;
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => handleSelectSemester(s.id)}
                  onDragOver={(e) => handleSemesterDragOver(e, s.id)}
                  onDragLeave={() =>
                    setDropTargetSemesterId((prev) => (prev === s.id ? null : prev))
                  }
                  onDrop={(e) => void handleSemesterDrop(e, s.id)}
                  className="inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-[11px] font-medium transition-colors"
                  style={{
                    border: dropTarget
                      ? "1px solid color-mix(in srgb, var(--color-primary) 55%, var(--color-chrome-stroke))"
                      : "1px solid var(--color-chrome-stroke)",
                    background: dropTarget
                      ? "color-mix(in srgb, var(--color-primary) 12%, var(--color-surface))"
                      : selected
                        ? "var(--color-shell-selection)"
                        : "var(--color-surface)",
                    color: selected
                      ? "var(--color-text-main)"
                      : "var(--color-text-light)",
                    boxShadow: selected ? "var(--shadow-pill)" : undefined,
                  }}
                  aria-pressed={selected}
                >
                  <span className={selected ? "font-semibold" : undefined}>{label}</span>
                  {s.isCurrent ? (
                    <StatusChip title="Now" tint="var(--color-primary)" filled className="!py-0" />
                  ) : null}
                  <span className="tabular-nums opacity-70">
                    {coursesBySemester.get(s.id)?.length ?? 0}
                  </span>
                </button>
              );
            })}
          </div>
        )}
        {selectedSemester ? (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => onDeleteSemester(selectedSemester)}
          >
            Delete term
          </Button>
        ) : null}
      </div>

      {selectedSemesterId && semesters.length > 0 ? (
        <div className="grid shrink-0 gap-2 sm:grid-cols-2 lg:grid-cols-4">
          <MetricTile
            label="Term credits"
            value={termStats.totalCredits.toFixed(1)}
            accent="var(--color-primary)"
          />
          <MetricTile label="Courses" value={termStats.courseCount} />
          <MetricTile
            label="Completed"
            value={termStats.completedCredits.toFixed(1)}
            accent="var(--color-success)"
          />
          <MetricTile
            label="Planned"
            value={termStats.plannedCredits.toFixed(1)}
            accent="var(--color-primary)"
          />
        </div>
      ) : null}

      <div className="min-h-0 flex-1">
        <TrailingInspector
          open={!!selectedCourse}
          main={
            <AppCard
              title={
                selectedSemester?.label ||
                (selectedSemester
                  ? `${selectedSemester.season} ${selectedSemester.year}`
                  : "Courses")
              }
              className="h-full"
            >
              {!selectedSemesterId ? (
                <EmptyState title="Select a term" body="Choose a semester chip above." />
              ) : plannerCourses.length === 0 ? (
                <div
                  onDragOver={(e) => {
                    if (!selectedSemesterId || !onRequirementDrop) return;
                    handleSemesterDragOver(e, selectedSemesterId);
                  }}
                  onDragLeave={() => setDropTargetSemesterId(null)}
                  onDrop={(e) => {
                    if (!selectedSemesterId) return;
                    void handleSemesterDrop(e, selectedSemesterId);
                  }}
                  className="rounded-lg border border-dashed p-6"
                  style={{
                    borderColor:
                      dropTargetSemesterId === selectedSemesterId
                        ? "color-mix(in srgb, var(--color-primary) 55%, var(--color-chrome-stroke))"
                        : "var(--color-chrome-stroke)",
                    background:
                      dropTargetSemesterId === selectedSemesterId
                        ? "color-mix(in srgb, var(--color-primary) 6%, transparent)"
                        : undefined,
                  }}
                >
                  <EmptyState
                    title="Empty term"
                    body="Drag a requirement course onto this term, or use Add course."
                  />
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-2 p-1 sm:grid-cols-3 xl:grid-cols-4">
                  {plannerCourses.map((c) => (
                    <CourseCard
                      key={c.id}
                      course={c}
                      selected={selectedCourseId === c.id}
                      onSelect={() => setSelectedCourseId(c.id)}
                      draggablePayload={{
                        code: c.code,
                        title: c.title,
                        credits: c.credits,
                        source: "planner",
                      }}
                    />
                  ))}
                </div>
              )}
            </AppCard>
          }
        >
          {selectedCourse ? (
            <CourseInspector
              course={selectedCourse}
              onClose={() => setSelectedCourseId(null)}
              onDeleted={() => setSelectedCourseId(null)}
              onOpenDashboard={
                onOpenDashboard ? () => onOpenDashboard(selectedCourse) : undefined
              }
            />
          ) : null}
        </TrailingInspector>
      </div>
    </div>
  );
}

function CourseCard({
  course,
  selected,
  onSelect,
  draggablePayload,
}: {
  course: PlannerCourse;
  selected: boolean;
  onSelect: () => void;
  draggablePayload?: PlannerDragPayload;
}) {
  const tint = courseStatusTint(course.status);
  return (
    <button
      type="button"
      draggable={!!draggablePayload}
      onDragStart={(e) => {
        if (!draggablePayload) return;
        e.dataTransfer.effectAllowed = "copy";
        const dt = plannerDragDataTransfer(draggablePayload);
        e.dataTransfer.setData(
          PLANNER_DRAG_MIME,
          dt.getData(PLANNER_DRAG_MIME),
        );
        e.dataTransfer.setData("text/plain", dt.getData("text/plain"));
      }}
      onClick={onSelect}
      className="flex min-h-[88px] flex-col gap-2 p-2.5 text-left transition-colors"
      style={{
        borderRadius: 10,
        border: selected
          ? `1px solid color-mix(in srgb, ${tint} 45%, var(--color-chrome-stroke))`
          : "1px solid var(--color-chrome-stroke)",
        borderLeftWidth: 3,
        borderLeftColor: tint,
        background: selected
          ? `color-mix(in srgb, ${tint} 8%, var(--color-content-surface))`
          : "var(--color-content-surface)",
        boxShadow: selected
          ? `inset 0 1px 0 color-mix(in srgb, white 30%, transparent)`
          : "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
        cursor: draggablePayload ? "grab" : undefined,
      }}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="truncate text-[13px] font-semibold tracking-[-0.01em]">
            {course.code}
          </div>
          <div className="mt-0.5 line-clamp-2 text-[11px] leading-snug text-[var(--color-text-light)]">
            {course.title}
          </div>
        </div>
        <span className="shrink-0 text-[11px] font-medium tabular-nums text-[var(--color-text-light)]">
          {course.credits} cr
        </span>
      </div>
      <div className="mt-auto flex flex-wrap items-center gap-1.5">
        <StatusChip
          title={course.status.replace("_", " ")}
          tint={tint}
          filled
        />
        {course.grade ? (
          <StatusChip title={course.grade} tint="var(--color-text-main)" />
        ) : null}
      </div>
    </button>
  );
}

function CourseInspector({
  course,
  onClose,
  onDeleted,
  onOpenDashboard,
}: {
  course: PlannerCourse;
  onClose: () => void;
  onDeleted: () => void;
  onOpenDashboard?: () => void;
}) {
  const tint = courseStatusTint(course.status);

  return (
    <div className="flex h-full flex-col">
      <div
        className="border-b border-[var(--color-chrome-stroke)] px-4 py-3"
        style={{
          background: `linear-gradient(135deg, color-mix(in srgb, ${tint} 10%, transparent), transparent)`,
        }}
      >
        <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
          <StatusChip title={course.code} tint={tint} filled />
          <StatusChip
            title={course.status.replace("_", " ")}
            tint={tint}
            filled
          />
        </div>
        <h3
          className="text-[var(--color-text-main)]"
          style={{
            font: "var(--type-section-title)",
            fontSize: 16,
            letterSpacing: "-0.02em",
          }}
        >
          {course.title}
        </h3>
        <p className="mt-1 text-[12px] text-[var(--color-text-light)]">
          {course.credits} credits
          {course.grade ? ` · Grade ${course.grade}` : ""}
        </p>
      </div>

      <div className="min-h-0 flex-1 space-y-3 overflow-auto p-4">
        <FormField label="Course code">
          <input className={fieldControlClass} value={course.code} readOnly />
        </FormField>
        <FormField label="Title">
          <input className={fieldControlClass} value={course.title} readOnly />
        </FormField>
        <FormField label="Credits">
          <input
            className={fieldControlClass}
            type="number"
            value={course.credits}
            readOnly
          />
        </FormField>
        <FormField label="Status">
          <select
            className={fieldControlClass}
            value={course.status}
            onChange={(e) =>
              void ipc
                .academicsUpdateCourseStatus(course.id, e.target.value)
                .catch(() => showToast("Could not update status", "error"))
            }
          >
            {COURSE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s.replace("_", " ")}
              </option>
            ))}
          </select>
        </FormField>
        <FormField label="Grade">
          <select
            className={fieldControlClass}
            value={course.grade ?? ""}
            onChange={(e) =>
              void ipc
                .academicsUpdateCourseGrade(course.id, e.target.value || null)
                .catch(() => showToast("Could not update grade", "error"))
            }
          >
            <option value="">No grade</option>
            {GRADES.map((g) => (
              <option key={g} value={g}>
                {g}
              </option>
            ))}
          </select>
        </FormField>
      </div>

      <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
        {onOpenDashboard ? (
          <Button size="sm" variant="secondary" onClick={onOpenDashboard}>
            Course dashboard
          </Button>
        ) : null}
        <Button
          size="sm"
          variant="danger"
          onClick={() => {
            if (!confirmDelete(course.code || course.title || "course")) return;
            void ipc
              .academicsDeleteCourse(course.id)
              .then(() => {
                showToast("Course removed", "success");
                onDeleted();
              })
              .catch(() => showToast("Could not delete course", "error"));
          }}
        >
          Delete
        </Button>
        <Button size="sm" variant="ghost" onClick={onClose}>
          Close
        </Button>
      </div>
    </div>
  );
}

function courseStatusTint(status: string): string {
  switch (status) {
    case "completed":
      return "var(--color-success)";
    case "in_progress":
      return "var(--color-warning)";
    case "dropped":
      return "var(--color-error)";
    default:
      return "var(--color-primary)";
  }
}
