import type { PlannerCourse } from "@/lib/ipc";

export type PlannerStatusState = "completed" | "in_progress" | "planned" | "remaining";

const PALETTE: Record<
  PlannerStatusState,
  { dot: string; pillBg: string; pillFg: string; label: string }
> = {
  completed: {
    dot: "var(--color-success)",
    pillBg: "color-mix(in srgb, var(--color-success) 14%, transparent)",
    pillFg: "color-mix(in srgb, var(--color-success) 85%, transparent)",
    label: "Completed",
  },
  in_progress: {
    dot: "var(--color-warning)",
    pillBg: "color-mix(in srgb, var(--color-warning) 14%, transparent)",
    pillFg: "color-mix(in srgb, var(--color-warning) 85%, transparent)",
    label: "In Progress",
  },
  planned: {
    dot: "var(--color-primary)",
    pillBg: "color-mix(in srgb, var(--color-primary) 14%, transparent)",
    pillFg: "color-mix(in srgb, var(--color-primary) 85%, transparent)",
    label: "Planned",
  },
  remaining: {
    dot: "color-mix(in srgb, var(--color-text-light) 55%, transparent)",
    pillBg: "color-mix(in srgb, var(--color-text-light) 10%, transparent)",
    pillFg: "var(--color-text-light)",
    label: "Remaining",
  },
};

export function plannerStatusPalette(state: PlannerStatusState) {
  return PALETTE[state];
}

export function courseStatusState(course: Pick<PlannerCourse, "status">): PlannerStatusState {
  const raw = course.status.trim().toLowerCase();
  if (raw === "completed") return "completed";
  if (raw === "in_progress" || raw === "in progress" || raw === "in-progress") return "in_progress";
  if (raw === "dropped" || raw === "failed" || raw === "not planned" || raw === "not-planned") {
    return "remaining";
  }
  return "planned";
}

export function semesterDominantState(courses: PlannerCourse[]): PlannerStatusState {
  if (courses.length === 0) return "planned";
  const states = courses.map(courseStatusState);
  if (states.every((s) => s === "completed")) return "completed";
  if (states.some((s) => s === "in_progress")) return "in_progress";
  if (states.some((s) => s === "completed")) return "in_progress";
  return "planned";
}

export function semesterTotalCredits(courses: PlannerCourse[]): number {
  return courses.reduce((sum, course) => {
    const raw = course.status.trim().toLowerCase();
    if (raw === "dropped" || raw === "failed" || raw === "not planned" || raw === "not-planned") {
      return sum;
    }
    return sum + course.credits;
  }, 0);
}
