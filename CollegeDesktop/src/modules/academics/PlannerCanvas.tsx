import { useMemo, useState, type DragEvent } from "react";
import {
  CalendarPlus,
  ChevronRight,
  Inbox,
  Pencil,
  Trash2,
  XCircle,
} from "lucide-react";
import { ipc, type PlannerCourse, type Semester } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import {
  PLANNER_DRAG_MIME,
  parsePlannerDragPayload,
  type PlannerDragPayload,
} from "./plannerDrag";
import {
  courseStatusState,
  plannerStatusPalette,
  semesterDominantState,
  semesterTotalCredits,
  type PlannerStatusState,
} from "./plannerStatus";

function PlannerStatusPill({ state }: { state: PlannerStatusState }) {
  const palette = plannerStatusPalette(state);
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-[7px] py-[3px] text-label font-semibold"
      style={{ background: palette.pillBg, color: palette.pillFg }}
    >
      {palette.label}
    </span>
  );
}

export function PlannerCanvas({
  semesters,
  coursesBySemester,
  onDeleteSemester,
  onEditSemester,
  onRequirementDrop,
  onOpenDashboard,
  onAddSemester,
}: {
  semesters: Semester[];
  coursesBySemester: Map<string, PlannerCourse[]>;
  onDeleteSemester: (semester: Semester) => void;
  onEditSemester?: (semester: Semester) => void;
  onRequirementDrop?: (semesterId: string, payload: PlannerDragPayload) => Promise<void>;
  onOpenDashboard?: (course: PlannerCourse) => void;
  onAddSemester: () => void;
}) {
  const [expandedIds, setExpandedIds] = useState<Set<string>>(() => new Set());
  const [dropTargetSemesterId, setDropTargetSemesterId] = useState<string | null>(null);

  const headerLabel = useMemo(() => {
    const count = semesters.length;
    if (count === 0) return "NO SEMESTERS";
    return `${count} SEMESTER${count === 1 ? "" : "S"}`;
  }, [semesters.length]);

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

  const toggleExpanded = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-1">
      <div className="mx-auto w-full max-w-[720px] space-y-2">
        <div className="px-1 pb-0.5 pt-1 text-caption font-bold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
          {headerLabel}
        </div>

        <div className="space-y-2">
          {semesters.map((semester) => {
            const courses = coursesBySemester.get(semester.id) ?? [];
            const displayTitle = semester.label || `${semester.season} ${semester.year}`;
            const dominantState = semesterDominantState(courses);
            const totalCredits = semesterTotalCredits(courses);
            const expanded = expandedIds.has(semester.id);
            const dropTarget = dropTargetSemesterId === semester.id;

            return (
              <SemesterRowCompact
                key={semester.id}
                semester={semester}
                displayTitle={displayTitle}
                courses={courses}
                dominantState={dominantState}
                totalCredits={totalCredits}
                expanded={expanded}
                dropTarget={dropTarget}
                onToggleExpanded={() => toggleExpanded(semester.id)}
                onDelete={() => onDeleteSemester(semester)}
                onEdit={onEditSemester ? () => onEditSemester(semester) : undefined}
                onDragOver={(e) => handleSemesterDragOver(e, semester.id)}
                onDragLeave={() =>
                  setDropTargetSemesterId((prev) => (prev === semester.id ? null : prev))
                }
                onDrop={(e) => void handleSemesterDrop(e, semester.id)}
                onOpenDashboard={onOpenDashboard}
              />
            );
          })}
        </div>

        <button
          type="button"
          onClick={onAddSemester}
          className="flex w-full items-center justify-center gap-2 rounded-xl border border-dashed px-3 py-3 text-body font-medium text-[var(--color-text-light)] transition-colors hover:text-[var(--color-text-main)]"
          style={{
            borderColor: "color-mix(in srgb, var(--color-text-main) 18%, transparent)",
            background: "var(--color-surface)",
          }}
        >
          <CalendarPlus className="h-4 w-4" />
          Add Semester
        </button>
      </div>
    </div>
  );
}

function SemesterRowCompact({
  semester,
  displayTitle,
  courses,
  dominantState,
  totalCredits,
  expanded,
  dropTarget,
  onToggleExpanded,
  onDelete,
  onEdit,
  onDragOver,
  onDragLeave,
  onDrop,
  onOpenDashboard,
}: {
  semester: Semester;
  displayTitle: string;
  courses: PlannerCourse[];
  dominantState: PlannerStatusState;
  totalCredits: number;
  expanded: boolean;
  dropTarget: boolean;
  onToggleExpanded: () => void;
  onDelete: () => void;
  onEdit?: () => void;
  onDragOver: (e: DragEvent) => void;
  onDragLeave: () => void;
  onDrop: (e: DragEvent) => void;
  onOpenDashboard?: (course: PlannerCourse) => void;
}) {
  const [hovered, setHovered] = useState(false);
  const palette = plannerStatusPalette(dominantState);

  return (
    <div
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      className="overflow-hidden rounded-xl transition-shadow"
      style={{
        border: dropTarget
          ? "2px solid var(--color-primary)"
          : "1px solid var(--color-chrome-stroke)",
        background: "var(--color-surface)",
        boxShadow: dropTarget
          ? "0 0 0 1px color-mix(in srgb, var(--color-primary) 20%, transparent)"
          : undefined,
      }}
    >
      <div className="flex items-center gap-2 px-2.5 py-2">
        <span
          className="inline-block h-2 w-2 shrink-0 rounded-full"
          style={{ background: palette.dot }}
        />

        <button
          type="button"
          onClick={onToggleExpanded}
          className="flex min-w-0 flex-1 items-center gap-1.5 text-left"
        >
          <span className="truncate text-section-title font-medium">
            {displayTitle}
          </span>
          {semester.isCurrent ? (
            <span className="rounded-full bg-[color-mix(in_srgb,var(--color-primary)_14%,transparent)] px-1.5 py-0.5 text-label font-semibold text-[var(--color-primary)]">
              Now
            </span>
          ) : null}
          <ChevronRight
            className="h-3.5 w-3.5 shrink-0 text-[var(--color-text-light)] transition-transform duration-150"
            style={{ transform: expanded ? "rotate(90deg)" : undefined }}
          />
        </button>

        <span className="shrink-0 text-meta tabular-nums text-[var(--color-text-light)]">
          {Math.round(totalCredits)} cr
        </span>
        <PlannerStatusPill state={dominantState} />

        {hovered ? (
          <span className="flex shrink-0 items-center gap-0.5">
            <button
              type="button"
              className="rounded p-1 text-[var(--color-text-light)] hover:bg-black/5"
              aria-label="Edit semester"
              onClick={(e) => {
                e.stopPropagation();
                onEdit?.();
              }}
            >
              <Pencil className="h-3.5 w-3.5" />
            </button>
            <button
              type="button"
              className="rounded p-1 text-[var(--color-error)] hover:bg-black/5"
              aria-label="Delete semester"
              onClick={(e) => {
                e.stopPropagation();
                onDelete();
              }}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          </span>
        ) : null}
      </div>

      {expanded ? (
        <div className="border-t border-[var(--color-chrome-stroke)]">
          {courses.length === 0 ? (
            <div className="flex items-center gap-2 px-3 py-2.5 text-meta">
              <Inbox className="h-4 w-4 shrink-0 opacity-60" />
              <span>No courses yet — drag from the breakdown</span>
            </div>
          ) : (
            <ul>
              {courses.map((course, index) => (
                <li key={course.id}>
                  {index > 0 ? (
                    <div className="ml-3.5 border-t border-[var(--color-chrome-stroke)]" />
                  ) : null}
                  <SemesterCourseLineRow
                    course={course}
                    onOpen={onOpenDashboard ? () => onOpenDashboard(course) : undefined}
                    onDelete={() => {
                      if (!confirmDelete(course.code || course.title || "course")) return;
                      void ipc
                        .academicsDeleteCourse(course.id)
                        .then(() => showToast("Course removed", "success"))
                        .catch(() => showToast("Could not remove course", "error"));
                    }}
                  />
                </li>
              ))}
            </ul>
          )}
        </div>
      ) : null}
    </div>
  );
}

function SemesterCourseLineRow({
  course,
  onOpen,
  onDelete,
}: {
  course: PlannerCourse;
  onOpen?: () => void;
  onDelete: () => void;
}) {
  const [hovered, setHovered] = useState(false);
  const state = courseStatusState(course);
  const palette = plannerStatusPalette(state);

  return (
    <div
      role={onOpen ? "button" : undefined}
      tabIndex={onOpen ? 0 : undefined}
      onClick={onOpen}
      onKeyDown={(e) => {
        if (onOpen && (e.key === "Enter" || e.key === " ")) {
          e.preventDefault();
          onOpen();
        }
      }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      className="flex items-center gap-2 px-3.5 py-2"
      style={{ cursor: onOpen ? "pointer" : undefined }}
    >
      <span
        className="inline-block h-[7px] w-[7px] shrink-0 rounded-full"
        style={{ background: palette.dot }}
      />
      <span className="shrink-0 text-section-title font-medium text-[var(--color-primary)]">
        {course.code}
      </span>
      <span className="min-w-0 flex-1 truncate text-body">
        {course.title}
      </span>
      {hovered ? (
        <button
          type="button"
          className="shrink-0 rounded text-[var(--color-text-light)] hover:text-[var(--color-text-main)]"
          aria-label="Remove course"
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
        >
          <XCircle className="h-4 w-4" />
        </button>
      ) : course.credits > 0 ? (
        <span className="shrink-0 text-meta tabular-nums text-[var(--color-text-light)]">
          {Math.round(course.credits)} cr
        </span>
      ) : null}
    </div>
  );
}
