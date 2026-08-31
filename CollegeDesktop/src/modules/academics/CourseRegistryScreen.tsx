import { useState, useMemo } from "react";
import {
  BookOpen,
  CheckCircle2,
  Clock,
  Filter,
  Plus,
  Search,
  Trash2,
  TrendingUp,
} from "lucide-react";
import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  MetricTile,
  ModalSheet,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError, type PlannerCourse, type Semester } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";

export function CourseRegistryScreen({
  semesters,
  courses,
  onOpenDashboard,
  onRefresh,
}: {
  semesters: Semester[];
  courses: PlannerCourse[];
  onOpenDashboard: (course: PlannerCourse) => void;
  onRefresh: () => void;
}) {
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [semesterFilter, setSemesterFilter] = useState<string>("all");
  const [isAddOpen, setIsAddOpen] = useState(false);

  const [addCode, setAddCode] = useState("");
  const [addTitle, setAddTitle] = useState("");
  const [addCredits, setAddCredits] = useState("3");
  const [addSemesterId, setAddSemesterId] = useState(() => semesters[0]?.id ?? "");
  const [addStatus, setAddStatus] = useState("planned");

  const semesterMap = useMemo(() => {
    const map = new Map<string, string>();
    for (const s of semesters) {
      map.set(s.id, s.label || `${s.season} ${s.year}`);
    }
    return map;
  }, [semesters]);

  const filteredCourses = useMemo(() => {
    return courses.filter((c) => {
      if (statusFilter !== "all" && (c.status || "planned").toLowerCase() !== statusFilter) {
        return false;
      }
      if (semesterFilter !== "all" && c.semesterId !== semesterFilter) {
        return false;
      }
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        return (
          c.code.toLowerCase().includes(q) ||
          c.title.toLowerCase().includes(q) ||
          (c.grade && c.grade.toLowerCase().includes(q))
        );
      }
      return true;
    });
  }, [courses, statusFilter, semesterFilter, searchQuery]);

  const stats = useMemo(() => {
    let completedCr = 0;
    let inProgressCr = 0;
    let plannedCr = 0;
    let totalGradedPoints = 0;
    let totalGradedCr = 0;

    const gradePoints: Record<string, number> = {
      "A+": 4.0,
      A: 4.0,
      "A-": 3.7,
      "B+": 3.3,
      B: 3.0,
      "B-": 2.7,
      "C+": 2.3,
      C: 2.0,
      "C-": 1.7,
      "D+": 1.3,
      D: 1.0,
      F: 0.0,
    };

    for (const c of courses) {
      const cr = c.credits ?? 3;
      const st = (c.status || "planned").toLowerCase();
      if (st === "completed") {
        completedCr += cr;
        if (c.grade && gradePoints[c.grade] !== undefined) {
          totalGradedPoints += gradePoints[c.grade] * cr;
          totalGradedCr += cr;
        }
      } else if (st === "in-progress" || st === "inprogress") {
        inProgressCr += cr;
      } else if (st === "planned") {
        plannedCr += cr;
      }
    }

    const calculatedGpa = totalGradedCr > 0 ? (totalGradedPoints / totalGradedCr).toFixed(2) : "—";

    return {
      total: courses.length,
      completedCr,
      inProgressCr,
      plannedCr,
      calculatedGpa,
    };
  }, [courses]);

  const handleAddCourse = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!addCode.trim() || !addTitle.trim() || !addSemesterId) {
      showToast("Please fill in course code, title, and semester", "error");
      return;
    }
    try {
      await ipc.academicsUpsertCourse({
        semesterId: addSemesterId,
        code: addCode.trim().toUpperCase(),
        title: addTitle.trim(),
        credits: parseFloat(addCredits) || 3,
        status: addStatus,
      });
      showToast("Course added to registry", "success");
      setIsAddOpen(false);
      setAddCode("");
      setAddTitle("");
      onRefresh();
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const handleUpdateStatus = async (course: PlannerCourse, newStatus: string) => {
    try {
      await ipc.academicsUpdateCourseStatus(course.id, newStatus);
      showToast(`Updated to ${newStatus}`, "success");
      onRefresh();
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const handleUpdateGrade = async (course: PlannerCourse, newGrade: string) => {
    try {
      await ipc.academicsUpdateCourseGrade(course.id, newGrade.trim() || null);
      showToast("Grade updated", "success");
      onRefresh();
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const handleDeleteCourse = async (course: PlannerCourse) => {
    if (!confirmDelete(`course ${course.code} (${course.title})`)) return;
    try {
      await ipc.academicsDeleteCourse(course.id);
      showToast("Course deleted", "success");
      onRefresh();
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  return (
    <div className="flex h-full min-h-0 flex-col overflow-y-auto p-6 space-y-6">
      {/* Metric Summary Strip */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <MetricTile
          label="Total Courses"
          value={stats.total}
          hint={`${stats.completedCr + stats.inProgressCr + stats.plannedCr} total credits`}
          icon={<BookOpen size={16} />}
          accent="var(--color-primary)"
        />
        <MetricTile
          label="Completed"
          value={`${stats.completedCr} cr`}
          hint="Satisfied credits"
          icon={<CheckCircle2 size={16} />}
          accent="var(--color-success)"
        />
        <MetricTile
          label="In-Progress"
          value={`${stats.inProgressCr} cr`}
          hint="Enrolled this term"
          icon={<Clock size={16} />}
          accent="var(--color-warning)"
        />
        <MetricTile
          label="Course GPA"
          value={stats.calculatedGpa}
          hint="Weighted cumulative"
          icon={<TrendingUp size={16} />}
          accent="var(--color-primary)"
        />
      </div>

      {/* Filter & Action Toolbar */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] p-3">
        <div className="flex flex-wrap items-center gap-2 flex-1 min-w-[280px]">
          <div className="relative flex-1 min-w-[180px] max-w-sm">
            <Search
              size={14}
              className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-light)]"
            />
            <input
              type="text"
              placeholder="Search code, title, or grade…"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)] py-1.5 pl-8 pr-3 text-body outline-none focus:border-[var(--color-primary)]"
            />
          </div>

          <div className="flex items-center gap-1.5">
            <Filter size={13} className="text-[var(--color-text-light)] ml-1" />
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              aria-label="Filter courses by status"
              className="rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)] px-2.5 py-1.5 text-caption font-medium outline-none"
            >
              <option value="all">All Statuses</option>
              <option value="completed">Completed</option>
              <option value="in-progress">In Progress</option>
              <option value="planned">Planned</option>
              <option value="dropped">Dropped</option>
            </select>

            <select
              value={semesterFilter}
              onChange={(e) => setSemesterFilter(e.target.value)}
              aria-label="Filter courses by semester"
              className="rounded-lg border border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)] px-2.5 py-1.5 text-caption font-medium outline-none"
            >
              <option value="all">All Semesters</option>
              {semesters.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label || `${s.season} ${s.year}`}
                </option>
              ))}
            </select>
          </div>
        </div>

        <Button onClick={() => setIsAddOpen(true)}>
          <Plus size={14} />
          <span>Add Course</span>
        </Button>
      </div>

      {/* Course List Card */}
      <AppCard title={`Registered Courses (${filteredCourses.length})`}>
        {filteredCourses.length === 0 ? (
          <EmptyState
            title="No courses found"
            body={
              courses.length === 0
                ? "You haven't added any courses to your academic plan yet."
                : "No courses match the current search filters."
            }
            action={
              <Button size="sm" onClick={() => setIsAddOpen(true)}>
                <Plus size={13} />
                <span>Add Your First Course</span>
              </Button>
            }
          />
        ) : (
          <div className="divide-y divide-[var(--color-chrome-stroke)]">
            {filteredCourses.map((course) => {
              const semLabel = semesterMap.get(course.semesterId) || "Unassigned";
              const status = (course.status || "planned").toLowerCase();
              const statusTone =
                status === "completed"
                  ? "var(--color-success)"
                  : status === "in-progress" || status === "inprogress"
                    ? "var(--color-primary)"
                    : status === "dropped"
                      ? "var(--color-error)"
                      : "var(--color-text-light)";

              return (
                <div
                  key={course.id}
                  className="flex flex-wrap items-center justify-between gap-3 py-3.5 transition hover:bg-[var(--color-row-hover)] px-2 rounded-lg"
                >
                  <div className="flex items-start gap-3 min-w-[240px] flex-1">
                    <div className="flex h-10 w-16 shrink-0 flex-col items-center justify-center rounded-md bg-[var(--color-shell-chrome)] text-center font-bold">
                      <span className="text-[12px] font-bold text-[var(--color-primary)]">
                        {course.code}
                      </span>
                      <span className="text-[10px] text-[var(--color-text-light)]">
                        {course.credits ?? 3} cr
                      </span>
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => onOpenDashboard(course)}
                          className="text-left font-semibold text-[var(--color-text-main)] hover:text-[var(--color-primary)] hover:underline truncate"
                        >
                          {course.title}
                        </button>
                      </div>
                      <p className="mt-0.5 text-caption text-[var(--color-text-light)]">
                        {semLabel}
                      </p>
                    </div>
                  </div>

                  {/* Status, Grade, and Actions */}
                  <div className="flex items-center gap-2.5 shrink-0">
                    <select
                      value={course.status || "planned"}
                      onChange={(e) => handleUpdateStatus(course, e.target.value)}
                      aria-label={`Change status for ${course.code}`}
                      className="rounded-md border border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)] px-2 py-1 text-caption font-semibold outline-none"
                      style={{ color: statusTone }}
                    >
                      <option value="planned">Planned</option>
                      <option value="in-progress">In Progress</option>
                      <option value="completed">Completed</option>
                      <option value="dropped">Dropped</option>
                    </select>

                    <div className="flex items-center gap-1 rounded-md border border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)] px-2 py-1">
                      <span className="text-[10px] font-bold uppercase text-[var(--color-text-light)]">
                        Grade
                      </span>
                      <input
                        type="text"
                        maxLength={3}
                        defaultValue={course.grade || ""}
                        placeholder="—"
                        onBlur={(e) => handleUpdateGrade(course, e.target.value)}
                        className="w-8 text-center text-caption font-bold bg-transparent outline-none uppercase text-[var(--color-text-main)]"
                      />
                    </div>

                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => onOpenDashboard(course)}
                      className="text-caption"
                    >
                      Dashboard
                    </Button>

                    <button
                      type="button"
                      onClick={() => handleDeleteCourse(course)}
                      className="p-1.5 text-[var(--color-text-light)] hover:text-[var(--color-error)] transition"
                      title="Delete course"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </AppCard>

      {/* Add Course Modal */}
      <ModalSheet open={isAddOpen} onOpenChange={setIsAddOpen} title="Add Course to Registry">
        <form onSubmit={handleAddCourse} className="space-y-4">
          <FormField label="Semester">
            <select
              className={fieldControlClass}
              value={addSemesterId}
              onChange={(e) => setAddSemesterId(e.target.value)}
              required
            >
              {semesters.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label || `${s.season} ${s.year}`}
                </option>
              ))}
            </select>
          </FormField>

          <FormField label="Course Code (e.g. CS 101, MATH 240)">
            <input
              className={fieldControlClass}
              placeholder="CS 101"
              value={addCode}
              onChange={(e) => setAddCode(e.target.value)}
              required
            />
          </FormField>

          <FormField label="Course Title">
            <input
              className={fieldControlClass}
              placeholder="Introduction to Computer Science"
              value={addTitle}
              onChange={(e) => setAddTitle(e.target.value)}
              required
            />
          </FormField>

          <div className="grid grid-cols-2 gap-3">
            <FormField label="Credits">
              <input
                type="number"
                step="0.5"
                min="0"
                className={fieldControlClass}
                value={addCredits}
                onChange={(e) => setAddCredits(e.target.value)}
                required
              />
            </FormField>

            <FormField label="Status">
              <select
                className={fieldControlClass}
                value={addStatus}
                onChange={(e) => setAddStatus(e.target.value)}
              >
                <option value="planned">Planned</option>
                <option value="in-progress">In Progress</option>
                <option value="completed">Completed</option>
              </select>
            </FormField>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="ghost" onClick={() => setIsAddOpen(false)}>
              Cancel
            </Button>
            <Button type="submit">Add Course</Button>
          </div>
        </form>
      </ModalSheet>
    </div>
  );
}
