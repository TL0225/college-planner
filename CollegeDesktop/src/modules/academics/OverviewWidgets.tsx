import {
  AlertCircle,
  Briefcase,
  CalendarCheck,
  CalendarDays,
  CheckCircle2,
  CloudSun,
  Compass,
  FileText,
  FolderOpen,
  GraduationCap,
  MapPin,
  Send,
  Sparkles,
  Wallet,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useState, type ReactNode } from "react";
import {
  Button,
  CreditRing,
  GuidedEmptyState,
  FormField,
  ModalSheet,
  OverviewWidgetBadge,
  OverviewWidgetCard,
  OverviewWidgetEmpty,
  OverviewWidgetGridLayout,
  OverviewWidgetHeader,
  OverviewWidgetRow,
  ProgressBar,
  fieldControlClass,
  overviewCategoryAccent,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import type {
  AuditSummary,
  FinanceDashboardSummary,
  GpaSummary,
  PipelineMetrics,
} from "@/lib/ipc";
import { navigate } from "@/lib/shellNavigate";

function WidgetShell({
  widgetId,
  title,
  accent,
  icon,
  trailing,
  children,
  className,
}: {
  widgetId: string;
  title: string;
  accent: string;
  icon: ReactNode;
  trailing?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <OverviewWidgetCard widgetId={widgetId} title={title} className={className}>
      <OverviewWidgetHeader title={title} accent={accent} icon={icon} trailing={trailing} />
      <div className="mt-4 flex min-h-0 flex-1 flex-col">{children}</div>
    </OverviewWidgetCard>
  );
}
export type OverviewEventRow = { id: string; title: string; startAt: string };

export type OverviewTaskRow = { id: string; title: string; dueAt?: string };

export type CareerFollowUpRow = {
  id: string;
  company: string;
  roleTitle: string;
  appliedAt?: string;
};

export type RecentDocumentRow = { id: string; title: string; updatedAt: string };

export type AdvisorPrepSummary = {
  completed: number;
  total: number;
};

export type OverviewWidgetsData = {
  summary: AuditSummary | null;
  gpa: GpaSummary | null;
  todayEvents: OverviewEventRow[];
  weekAheadEvents: OverviewEventRow[];
  deadlineTasks: OverviewTaskRow[];
  openTasks: OverviewTaskRow[];
  openTaskCount: number;
  career: PipelineMetrics | null;
  finance: FinanceDashboardSummary | null;
  vaultCount: number;
  savedSchoolCount: number;
  advisorPrep: AdvisorPrepSummary | null;
  careerFollowUps: CareerFollowUpRow[];
  recentDocuments: RecentDocumentRow[];
  isWorkspaceEmpty: boolean;
  onLoadSample: () => void;
};

const DASHBOARD_WIDGETS_KEY = "dashboard.widgets.v1";
const WEATHER_LOCATION_KEY = "weather.location.v1";

type WeatherLocationPref = {
  lat: number;
  lon: number;
  label: string;
  mode: "approx" | "city" | "denied";
};

function parseWeatherLocation(raw: string | undefined): WeatherLocationPref | null {
  if (!raw?.trim()) return null;
  try {
    const v = JSON.parse(raw) as Partial<WeatherLocationPref>;
    if (
      typeof v.lat !== "number" ||
      typeof v.lon !== "number" ||
      typeof v.label !== "string" ||
      (v.mode !== "approx" && v.mode !== "city" && v.mode !== "denied")
    ) {
      return null;
    }
    return { lat: v.lat, lon: v.lon, label: v.label, mode: v.mode };
  } catch {
    return null;
  }
}

export type OverviewWidgetId =
  | "quickLaunch"
  | "weekAhead"
  | "academicCalendar"
  | "deadlines"
  | "academics"
  | "gpa"
  | "todaySchedule"
  | "openTasks"
  | "careerPipeline"
  | "careerFollowUps"
  | "careerSummary"
  | "recentDocuments"
  | "netWorth"
  | "documents"
  | "discovery"
  | "advisorPrep"
  | "needsAttention"
  | "weather";

const WIDGET_LABELS: Record<OverviewWidgetId, string> = {
  quickLaunch: "Quick launch",
  weekAhead: "Week ahead",
  academicCalendar: "Academic calendar",
  deadlines: "Deadlines",
  academics: "Academics",
  gpa: "GPA",
  todaySchedule: "Today's schedule",
  openTasks: "Open tasks",
  careerPipeline: "Career pipeline",
  careerFollowUps: "Career follow-ups",
  careerSummary: "Career summary",
  recentDocuments: "Recent documents",
  netWorth: "Net worth",
  documents: "Documents",
  discovery: "Saved schools",
  advisorPrep: "Advisor prep",
  needsAttention: "Needs attention",
  weather: "Weather",
};

const DEFAULT_WIDGET_VISIBILITY: Record<OverviewWidgetId, boolean> = {
  quickLaunch: true,
  weekAhead: true,
  academicCalendar: true,
  deadlines: true,
  academics: true,
  gpa: true,
  todaySchedule: true,
  openTasks: true,
  careerPipeline: true,
  careerFollowUps: false,
  careerSummary: true,
  recentDocuments: true,
  netWorth: true,
  documents: true,
  discovery: true,
  advisorPrep: true,
  needsAttention: true,
  weather: true,
};

function parseWidgetVisibility(raw?: string): Record<OverviewWidgetId, boolean> {
  if (!raw) return { ...DEFAULT_WIDGET_VISIBILITY };
  try {
    const parsed = JSON.parse(raw) as Partial<Record<OverviewWidgetId, boolean>>;
    return { ...DEFAULT_WIDGET_VISIBILITY, ...parsed };
  } catch {
    return { ...DEFAULT_WIDGET_VISIBILITY };
  }
}

const QUICK_LAUNCH_TILES = [
  { label: "Schedule", icon: CalendarDays, hub: "life" as const, page: "schedule" },
  { label: "Career", icon: Briefcase, hub: "career" as const, page: "pipeline" },
  { label: "Library", icon: FolderOpen, hub: "library" as const, page: "all" },
  { label: "Discover", icon: Compass, hub: "school" as const, page: "discover" },
  { label: "Assistant", icon: Sparkles, hub: "home" as const, page: "today", openAi: true },
  { label: "Money", icon: Wallet, hub: "life" as const, page: "money" },
] as const;

function WidgetLink({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="mt-2 text-link text-meta hover:underline"
    >
      {children}
    </button>
  );
}

function AcademicsWidget({ summary, gpa }: { summary: AuditSummary | null; gpa: GpaSummary | null }) {
  const accent = overviewCategoryAccent.academic;
  const completed = summary?.completedCredits ?? 0;
  const planned = summary?.plannedCredits ?? 0;
  const required =
    summary?.totalRequiredCredits != null && summary.totalRequiredCredits > 0
      ? summary.totalRequiredCredits
      : completed + planned;
  const fraction = required > 0 ? completed / required : 0;

  return (
    <WidgetShell
      widgetId="academics"
      title="Academic Journey"
      accent={accent}
      icon={<GraduationCap size={14} strokeWidth={2.25} />}
      trailing={
        <button
          type="button"
          onClick={() => navigate({ hub: "school", page: "plan" })}
          className="text-meta font-medium text-[var(--color-primary)] hover:underline"
        >
          View Full Planner
        </button>
      }
    >
      {!summary ? (
        <OverviewWidgetEmpty
          title="No degree configured"
          message="Add your major in Profile."
          accent={accent}
          icon={<GraduationCap size={18} />}
        />
      ) : (
        <div className="flex flex-col items-center gap-3">
          <CreditRing fraction={fraction} color={accent} />
          <div className="text-center">
            <p className="text-section-title">Degree Progress</p>
            <p className="text-caption">
              {required > 0
                ? `${completed.toFixed(0)}/${required.toFixed(0)} Credits`
                : `${completed.toFixed(0)} Credits completed`}
            </p>
          </div>
          {gpa?.gpa != null && (
            <div className="flex w-full items-center justify-between border-t border-[var(--color-chrome-stroke)] pt-3">
              <div>
                <p className="text-label font-medium uppercase tracking-wide text-[var(--color-text-light)]">
                  Cumulative GPA
                </p>
                <p
                  className="text-section-title font-bold tabular-nums"
                  style={{
                    fontSize: 18,
                    color:
                      gpa.gpa >= 3.5
                        ? "var(--color-success)"
                        : gpa.gpa >= 2
                          ? "var(--color-primary)"
                          : "var(--color-error)",
                  }}
                >
                  {gpa.gpa.toFixed(2)}
                </p>
              </div>
              <div className="text-right">
                <p className="text-label font-medium uppercase tracking-wide text-[var(--color-text-light)]">
                  Courses
                </p>
                <p
                  className="text-section-title font-bold tabular-nums text-[var(--color-text-main)]"
                  style={{ fontSize: 18 }}
                >
                  {summary.courseCount}
                </p>
              </div>
            </div>
          )}
        </div>
      )}
    </WidgetShell>
  );
}

function GpaWidget({ gpa }: { gpa: GpaSummary | null }) {
  const accent = overviewCategoryAccent.academic;
  return (
    <WidgetShell
      widgetId="gpa"
      title="GPA"
      accent={accent}
      icon={<GraduationCap size={14} strokeWidth={2.25} />}
    >
      {gpa?.gpa == null ? (
        <OverviewWidgetEmpty
          title="No graded courses"
          message="Letter grades on planner courses populate GPA."
          accent={accent}
          icon={<GraduationCap size={18} />}
        />
      ) : (
        <OverviewWidgetRow accent={accent}>
          <div className="text-center">
            <p
              className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]"
              style={{ fontSize: 30 }}
            >
              {gpa.gpa.toFixed(2)}
            </p>
            <p className="text-label font-bold uppercase tracking-wide">
              Cumulative · {gpa.gradedCourses} courses
            </p>
          </div>
        </OverviewWidgetRow>
      )}
      <WidgetLink onClick={() => navigate({ hub: "school", page: "degree" })}>View requirements →</WidgetLink>
    </WidgetShell>
  );
}

function formatEventDay(startAt: string): string {
  const date = new Date(startAt);
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  if (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate()
  ) {
    return "Today";
  }
  if (
    date.getFullYear() === tomorrow.getFullYear() &&
    date.getMonth() === tomorrow.getMonth() &&
    date.getDate() === tomorrow.getDate()
  ) {
    return "Tomorrow";
  }
  return date.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

function AcademicCalendarWidget({
  summary,
  gpa,
}: {
  summary: AuditSummary | null;
  gpa: GpaSummary | null;
}) {
  const accent = overviewCategoryAccent.information;
  return (
    <WidgetShell
      widgetId="academicCalendar"
      title="Academic Calendar"
      accent={accent}
      icon={<CalendarDays size={14} strokeWidth={2.25} />}
    >
      <div className="grid grid-cols-2 gap-2.5">
        <OverviewWidgetRow accent={accent}>
          <p className="text-label font-bold uppercase tracking-wide">
            Credits completed
          </p>
          <p className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]">
            {summary ? summary.completedCredits.toFixed(1) : "—"}
          </p>
        </OverviewWidgetRow>
        <OverviewWidgetRow accent={accent}>
          <p className="text-label font-bold uppercase tracking-wide">
            Cumulative GPA
          </p>
          <p className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]">
            {gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"}
          </p>
        </OverviewWidgetRow>
      </div>
      <WidgetLink onClick={() => navigate({ hub: "school", page: "plan" })}>Open planner →</WidgetLink>
    </WidgetShell>
  );
}

function WeekAheadWidget({ events }: { events: OverviewEventRow[] }) {
  const accent = overviewCategoryAccent.academic;
  return (
    <WidgetShell
      widgetId="weekAhead"
      title="Week Ahead"
      accent={accent}
      icon={<CalendarDays size={14} strokeWidth={2.25} />}
    >
      {events.length === 0 ? (
        <OverviewWidgetEmpty
          title="Nothing this week"
          message="Events in the next 7 days will appear here."
          accent={accent}
          icon={<CalendarDays size={18} />}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {events.map((e) => (
            <OverviewWidgetRow key={e.id} accent={accent}>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="truncate text-section-title">
                    {e.title}
                  </p>
                  <p className="text-label">
                    {formatEventDay(e.startAt)}
                  </p>
                </div>
                <span className="shrink-0 text-caption tabular-nums">
                  {new Date(e.startAt).toLocaleTimeString(undefined, {
                    hour: "numeric",
                    minute: "2-digit",
                  })}
                </span>
              </div>
            </OverviewWidgetRow>
          ))}
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "life", page: "week" })}>Open week view →</WidgetLink>
    </WidgetShell>
  );
}

function deadlineUrgency(dueAt?: string): { label: string; color: string } {
  if (!dueAt) return { label: "SOON", color: overviewCategoryAccent.productivity };
  const due = new Date(dueAt);
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(due);
  end.setHours(0, 0, 0, 0);
  const days = Math.round((end.getTime() - start.getTime()) / 86_400_000);
  if (days <= 0) return { label: "TODAY", color: "var(--color-error)" };
  if (days === 1) return { label: "TOMORROW", color: "var(--color-error)" };
  if (days <= 3) return { label: `${days} DAYS`, color: "var(--color-warning)" };
  if (days <= 7) return { label: "NEXT WEEK", color: "var(--color-primary)" };
  return {
    label: due.toLocaleDateString(undefined, { month: "short", day: "numeric" }).toUpperCase(),
    color: "var(--color-success)",
  };
}

function DeadlinesWidget({ tasks }: { tasks: OverviewTaskRow[] }) {
  const accent = overviewCategoryAccent.productivity;
  return (
    <WidgetShell
      widgetId="deadlines"
      title="Upcoming Deadlines"
      accent={accent}
      icon={<AlertCircle size={14} strokeWidth={2.25} />}
    >
      {tasks.length === 0 ? (
        <OverviewWidgetEmpty
          title="No upcoming deadlines"
          message="Tasks with due dates will appear here."
          accent="var(--color-success)"
          icon={<CalendarCheck size={18} />}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {tasks.slice(0, 4).map((t) => {
            const urgency = deadlineUrgency(t.dueAt);
            return (
              <OverviewWidgetRow key={t.id} accent={urgency.color}>
                <div className="flex items-start gap-2.5">
                  <span
                    className="mt-1.5 h-2 w-2 shrink-0 rounded-full"
                    style={{ background: urgency.color }}
                  />
                  <p className="min-w-0 flex-1 truncate text-section-title">
                    {t.title}
                  </p>
                  <OverviewWidgetBadge text={urgency.label} color={urgency.color} />
                </div>
              </OverviewWidgetRow>
            );
          })}
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "life", page: "tasks" })}>View all tasks →</WidgetLink>
    </WidgetShell>
  );
}

function QuickLaunchRow() {
  const accent = overviewCategoryAccent.custom;
  return (
    <WidgetShell
      widgetId="quickLaunch"
      title="Quick Launch"
      accent={accent}
      icon={<Sparkles size={14} strokeWidth={2.25} />}
      className="min-[700px]:col-span-2"
    >
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        {QUICK_LAUNCH_TILES.map((tile) => {
          const Icon = tile.icon;
          return (
            <button
              key={tile.label}
              type="button"
              onClick={() =>
                navigate({
                  hub: tile.hub,
                  page: tile.page,
                  ...("openAi" in tile && tile.openAi ? { openAi: true } : {}),
                })
              }
              className="flex flex-col items-center gap-1.5 rounded-[14px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-2 py-3 transition hover:bg-[var(--color-row-hover)]"
            >
              <span
                className="flex h-9 w-9 items-center justify-center rounded-full"
                style={{
                  background: `color-mix(in srgb, ${accent} 12%, transparent)`,
                  color: accent,
                }}
              >
                <Icon size={16} strokeWidth={2} />
              </span>
              <span className="text-label font-semibold text-[var(--color-text-main)]">
                {tile.label}
              </span>
            </button>
          );
        })}
      </div>
    </WidgetShell>
  );
}

function navigateDiscoverySaved() {
  navigate({ hub: "school", page: "discover" });
  window.dispatchEvent(
    new CustomEvent("college:discovery-mode", { detail: { mode: "saved" } }),
  );
}

function DiscoverySavedWidget({ count }: { count: number }) {
  const accent = overviewCategoryAccent.information;
  return (
    <WidgetShell
      widgetId="discovery"
      title="Saved Schools"
      accent={accent}
      icon={<Compass size={14} strokeWidth={2.25} />}
    >
      <OverviewWidgetRow accent={accent}>
        <p
          className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]"
          style={{ fontSize: 30 }}
        >
          {count}
        </p>
        <p className="text-label font-bold uppercase tracking-wide">
          Saved schools
        </p>
      </OverviewWidgetRow>
      <WidgetLink onClick={navigateDiscoverySaved}>Open saved schools →</WidgetLink>
    </WidgetShell>
  );
}

function AdvisorPrepWidget({ prep }: { prep: AdvisorPrepSummary }) {
  const accent = overviewCategoryAccent.academic;
  const ratio = prep.total > 0 ? prep.completed / prep.total : 0;
  return (
    <WidgetShell
      widgetId="advisorPrep"
      title="Advisor Prep"
      accent={accent}
      icon={<GraduationCap size={14} strokeWidth={2.25} />}
      trailing={
        <OverviewWidgetBadge
          text={`${prep.completed}/${prep.total}`}
          color={prep.completed === prep.total ? "var(--color-success)" : accent}
        />
      }
    >
      <ProgressBar value={ratio} tint="var(--color-success)" height={6} />
      <p className="mt-2 text-meta">
        Checklist progress for your next advisor meeting.
      </p>
      <WidgetLink onClick={() => navigate({ hub: "library", page: "identity" })}>Open checklist →</WidgetLink>
    </WidgetShell>
  );
}

function TodayScheduleWidget({ events }: { events: OverviewEventRow[] }) {
  const accent = overviewCategoryAccent.productivity;
  return (
    <WidgetShell
      widgetId="todaySchedule"
      title="Today's Schedule"
      accent={accent}
      icon={<CalendarDays size={14} strokeWidth={2.25} />}
    >
      {events.length === 0 ? (
        <OverviewWidgetEmpty
          title="Nothing scheduled today"
          message="Today's calendar events appear here."
          accent={accent}
          icon={<CalendarDays size={18} />}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {events.map((e) => (
            <OverviewWidgetRow key={e.id} accent={accent}>
              <div className="flex items-center justify-between gap-2">
                <p className="min-w-0 truncate text-section-title">
                  {e.title}
                </p>
                <span className="shrink-0 text-caption tabular-nums">
                  {new Date(e.startAt).toLocaleTimeString(undefined, {
                    hour: "numeric",
                    minute: "2-digit",
                  })}
                </span>
              </div>
            </OverviewWidgetRow>
          ))}
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "life", page: "day" })}>Open calendar →</WidgetLink>
    </WidgetShell>
  );
}

function OpenTasksWidget({ tasks, count }: { tasks: OverviewTaskRow[]; count: number }) {
  const accent = overviewCategoryAccent.productivity;
  return (
    <WidgetShell
      widgetId="openTasks"
      title="My Tasks"
      accent={accent}
      icon={<CheckCircle2 size={14} strokeWidth={2.25} />}
      trailing={<OverviewWidgetBadge text={`${count} OPEN`} color={accent} />}
    >
      {tasks.length === 0 ? (
        <OverviewWidgetEmpty
          title="No open tasks"
          message="Incomplete tasks will show up here."
          accent={accent}
          icon={<CheckCircle2 size={18} />}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {tasks.map((t) => {
            const urgency = deadlineUrgency(t.dueAt);
            return (
              <OverviewWidgetRow key={t.id} accent={urgency.color}>
                <div className="flex items-start justify-between gap-2">
                  <p className="min-w-0 flex-1 truncate text-section-title">
                    {t.title}
                  </p>
                  {t.dueAt ? (
                    <OverviewWidgetBadge text={urgency.label} color={urgency.color} />
                  ) : null}
                </div>
              </OverviewWidgetRow>
            );
          })}
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "life", page: "tasks" })}>View all tasks →</WidgetLink>
    </WidgetShell>
  );
}

function CareerSummaryWidget({
  career,
  followUps,
}: {
  career: PipelineMetrics | null;
  followUps: CareerFollowUpRow[];
}) {
  const accent = overviewCategoryAccent.productivity;
  const applied = career?.applied ?? 0;
  const interviewing = career?.interviewing ?? 0;
  const offer = career?.offer ?? 0;
  const hasActivity = (career?.total ?? 0) > 0 || followUps.length > 0;

  const metric = (label: string, value: number, color: string) => (
    <OverviewWidgetRow accent={color}>
      <div className="text-center">
        <p
          className="text-page-title font-extrabold tabular-nums"
          style={{ color, fontSize: 30 }}
        >
          {value}
        </p>
        <p className="text-label font-extrabold uppercase tracking-wide text-[var(--color-text-light)]">
          {label}
        </p>
      </div>
    </OverviewWidgetRow>
  );

  return (
    <WidgetShell
      widgetId="careerSummary"
      title="Career"
      accent={accent}
      icon={<Briefcase size={14} strokeWidth={2.25} />}
      trailing={
        hasActivity ? (
          <button
            type="button"
            onClick={() => navigate({ hub: "career", page: "pipeline" })}
            className="text-meta font-medium text-[var(--color-primary)] hover:underline"
          >
            Open
          </button>
        ) : undefined
      }
    >
      {!hasActivity ? (
        <button type="button" onClick={() => navigate({ hub: "career", page: "pipeline" })} className="w-full">
          <OverviewWidgetEmpty
            title="Track your first application"
            message="Applications, interviews, and follow-ups show up here."
            accent={accent}
            icon={<Briefcase size={18} />}
          />
        </button>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-2">
            {metric("Applied", applied, "var(--color-primary)")}
            {metric("Interview", interviewing, "#bf5af2")}
            {metric("Offer", offer, "var(--color-success)")}
          </div>
          {followUps.length > 0 && (
            <div className="mt-3">
              <p className="mb-2 text-label font-extrabold uppercase tracking-wide text-[var(--color-text-light)]">
                Follow-ups
              </p>
              <div className="flex flex-col gap-2">
                {followUps.slice(0, 2).map((row) => (
                  <OverviewWidgetRow key={row.id} accent={accent}>
                    <div className="flex items-center gap-2.5">
                      <span
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
                        style={{
                          background: `color-mix(in srgb, ${accent} 12%, transparent)`,
                          color: accent,
                        }}
                      >
                        <Send size={14} />
                      </span>
                      <div className="min-w-0">
                        <p className="truncate text-section-title">
                          {row.company}
                        </p>
                        <p className="truncate text-caption">
                          {row.roleTitle}
                        </p>
                      </div>
                    </div>
                  </OverviewWidgetRow>
                ))}
              </div>
            </div>
          )}
        </>
      )}
    </WidgetShell>
  );
}

function RecentDocumentsWidget({ docs }: { docs: RecentDocumentRow[] }) {
  const accent = overviewCategoryAccent.productivity;
  return (
    <WidgetShell
      widgetId="recentDocuments"
      title="Recent Documents"
      accent={accent}
      icon={<FileText size={14} strokeWidth={2.25} />}
    >
      {docs.length === 0 ? (
        <OverviewWidgetEmpty
          title="No vault files yet"
          message="Imported documents appear here."
          accent={accent}
          icon={<FolderOpen size={18} />}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {docs.map((d) => (
            <OverviewWidgetRow key={d.id} accent={accent}>
              <div className="flex items-center justify-between gap-2">
                <p className="min-w-0 truncate text-section-title">
                  {d.title}
                </p>
                <OverviewWidgetBadge
                  text={new Date(d.updatedAt).toLocaleDateString(undefined, {
                    month: "short",
                    day: "numeric",
                  }).toUpperCase()}
                  color={accent}
                />
              </div>
            </OverviewWidgetRow>
          ))}
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "library", page: "all" })}>Open documents →</WidgetLink>
    </WidgetShell>
  );
}

function CareerFollowUpsWidget({ rows }: { rows: CareerFollowUpRow[] }) {
  const accent = "#ff9f0a";
  return (
    <WidgetShell
      widgetId="careerFollowUps"
      title="Career Follow-ups"
      accent={accent}
      icon={<Send size={14} strokeWidth={2.25} />}
    >
      {rows.length === 0 ? (
        <OverviewWidgetEmpty
          title="No follow-ups pending"
          message="Applications waiting on a follow-up appear here."
          accent={accent}
          icon={<Send size={18} />}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {rows.map((row) => (
            <OverviewWidgetRow key={row.id} accent={accent}>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="truncate text-section-title">
                    {row.company}
                  </p>
                  <p className="truncate text-caption">{row.roleTitle}</p>
                </div>
                {row.appliedAt ? (
                  <OverviewWidgetBadge
                    text={new Date(row.appliedAt).toLocaleDateString(undefined, {
                      month: "short",
                      day: "numeric",
                    }).toUpperCase()}
                    color={accent}
                  />
                ) : null}
              </div>
            </OverviewWidgetRow>
          ))}
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "career", page: "pipeline" })}>Open applications →</WidgetLink>
    </WidgetShell>
  );
}

function CareerPipelineWidget({ career }: { career: PipelineMetrics | null }) {
  const accent = "#bf5af2";
  const stages = [
    { key: "interested", label: "Interested", tint: "var(--color-primary)" },
    { key: "applied", label: "Applied", tint: "var(--color-warning)" },
    { key: "interviewing", label: "Interviewing", tint: "var(--color-success)" },
    { key: "offer", label: "Offer", tint: "var(--color-success)" },
  ] as const;

  return (
    <WidgetShell
      widgetId="careerPipeline"
      title="Career Pipeline"
      accent={accent}
      icon={<Briefcase size={14} strokeWidth={2.25} />}
    >
      <div className="flex flex-col gap-2.5">
        {stages.map((stage) => (
          <OverviewWidgetRow key={stage.key} accent={stage.tint}>
            <div className="flex items-center justify-between gap-2">
              <span className="text-section-title">
                {stage.label}
              </span>
              <span className="tabular-nums text-section-title">
                {career?.[stage.key] ?? 0}
              </span>
            </div>
          </OverviewWidgetRow>
        ))}
      </div>
      <p className="mt-2.5 text-meta">
        {career?.total ?? 0} total applications tracked
      </p>
      <WidgetLink onClick={() => navigate({ hub: "career", page: "pipeline" })}>
        Open applications →
      </WidgetLink>
    </WidgetShell>
  );
}

function NetWorthWidget({ finance }: { finance: FinanceDashboardSummary | null }) {
  const accent = overviewCategoryAccent.information;
  const formatted = finance
    ? finance.netWorth.toLocaleString(undefined, { style: "currency", currency: "USD" })
    : "—";

  return (
    <WidgetShell
      widgetId="netWorth"
      title="Net Worth"
      accent={accent}
      icon={<Wallet size={14} strokeWidth={2.25} />}
    >
      <OverviewWidgetRow accent={accent}>
        <p className="text-label font-bold uppercase tracking-wide">
          Total
        </p>
        <p
          className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]"
          style={{ fontSize: 28 }}
        >
          {formatted}
        </p>
      </OverviewWidgetRow>
      {finance && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          <OverviewWidgetBadge text={`${finance.accountCount} ACCOUNTS`} color={accent} />
          <OverviewWidgetBadge text={`${finance.transactionCount} TX`} color={accent} />
        </div>
      )}
      <WidgetLink onClick={() => navigate({ hub: "life", page: "money" })}>Open finance →</WidgetLink>
    </WidgetShell>
  );
}

function DocumentsWidget({ count }: { count: number }) {
  const accent = overviewCategoryAccent.productivity;
  return (
    <WidgetShell
      widgetId="documents"
      title="Documents"
      accent={accent}
      icon={<FolderOpen size={14} strokeWidth={2.25} />}
    >
      <OverviewWidgetRow accent={accent}>
        <p
          className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]"
          style={{ fontSize: 30 }}
        >
          {count}
        </p>
        <p className="text-label font-bold uppercase tracking-wide">
          Vault files
        </p>
      </OverviewWidgetRow>
      <WidgetLink onClick={() => navigate({ hub: "library", page: "all" })}>Open documents →</WidgetLink>
    </WidgetShell>
  );
}

function NeedsAttentionWidget({
  openTaskCount,
  deadlineCount,
}: {
  openTaskCount: number;
  deadlineCount: number;
}) {
  const total = openTaskCount + deadlineCount;
  const accent = total > 0 ? "var(--color-warning)" : "var(--color-success)";
  return (
    <WidgetShell
      widgetId="needsAttention"
      title="Needs Attention"
      accent={accent}
      icon={<Zap size={14} strokeWidth={2.25} />}
    >
      <OverviewWidgetRow accent={accent}>
        <p
          className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]"
          style={{ fontSize: 30 }}
        >
          {total}
        </p>
        <p className="text-caption">
          {openTaskCount} open task{openTaskCount === 1 ? "" : "s"} · {deadlineCount} due within 14 days
        </p>
      </OverviewWidgetRow>
      <WidgetLink onClick={() => navigate({ hub: "life", page: "tasks" })}>Open tasks →</WidgetLink>
    </WidgetShell>
  );
}

function WeatherWidget() {
  const accent = overviewCategoryAccent.information;
  const [weather, setWeather] = useState<{
    temperatureF: number;
    summary: string;
    windMph?: number | null;
  } | null>(null);
  const [locationLabel, setLocationLabel] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [promptOpen, setPromptOpen] = useState(false);
  const [cityQuery, setCityQuery] = useState("");
  const [busy, setBusy] = useState(false);

  const loadWeather = useCallback(async (pref: WeatherLocationPref) => {
    setLocationLabel(pref.label);
    setError(null);
    setWeather(null);
    if (pref.mode === "denied") return;
    try {
      const snap = await ipc.platformFetchWeather(pref.lat, pref.lon);
      setWeather(snap);
    } catch (e) {
      setError(formatIpcError(e));
    }
  }, []);

  const persistAndLoad = useCallback(
    async (pref: WeatherLocationPref) => {
      await ipc.settingsSet(WEATHER_LOCATION_KEY, JSON.stringify(pref));
      setPromptOpen(false);
      await loadWeather(pref);
    },
    [loadWeather],
  );

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const settings = await ipc.settingsGet();
        if (cancelled) return;
        const pref = parseWeatherLocation(settings.values[WEATHER_LOCATION_KEY]);
        if (!pref) {
          setPromptOpen(true);
          return;
        }
        await loadWeather(pref);
      } catch (e) {
        if (!cancelled) setError(formatIpcError(e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [loadWeather]);

  const useApprox = async () => {
    setBusy(true);
    try {
      const approx = await ipc.platformApproxLocation();
      await persistAndLoad({
        lat: approx.lat,
        lon: approx.lon,
        label: approx.label,
        mode: "approx",
      });
    } catch (e) {
      setError(formatIpcError(e));
    } finally {
      setBusy(false);
    }
  };

  const useCity = async () => {
    const q = cityQuery.trim();
    if (!q) return;
    setBusy(true);
    try {
      const geo = await ipc.calendarGeocodeLocation(q);
      await persistAndLoad({
        lat: geo.lat,
        lon: geo.lon,
        label: geo.displayName,
        mode: "city",
      });
    } catch (e) {
      setError(formatIpcError(e));
    } finally {
      setBusy(false);
    }
  };

  const skipLocation = async () => {
    setBusy(true);
    try {
      await persistAndLoad({
        lat: 40.7128,
        lon: -74.006,
        label: "Location off",
        mode: "denied",
      });
    } catch (e) {
      setError(formatIpcError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <WidgetShell
        widgetId="weather"
        title="Weather"
        accent={accent}
        icon={<CloudSun size={14} strokeWidth={2.25} />}
        trailing={
          <button
            type="button"
            className="text-label font-semibold text-[var(--color-primary)] hover:underline"
            onClick={() => setPromptOpen(true)}
          >
            Location
          </button>
        }
      >
        {error ? (
          <p className="text-meta">{error}</p>
        ) : weather ? (
          <OverviewWidgetRow accent={accent}>
            {locationLabel && (
              <p className="flex items-center gap-1 text-label font-bold uppercase tracking-wide">
                <MapPin size={10} strokeWidth={2.5} />
                {locationLabel}
              </p>
            )}
            <p className="text-label font-bold uppercase tracking-wide">
              {weather.summary}
            </p>
            <p
              className="text-page-title font-extrabold tabular-nums text-[var(--color-text-main)]"
              style={{ fontSize: 30 }}
            >
              {Math.round(weather.temperatureF)}°F
            </p>
            {weather.windMph != null && (
              <p className="text-caption">
                Wind {Math.round(weather.windMph)} mph
              </p>
            )}
          </OverviewWidgetRow>
        ) : promptOpen ? (
          <OverviewWidgetEmpty
            title="Choose a location"
            accent={accent}
            icon={<MapPin size={18} />}
          />
        ) : locationLabel === "Location off" ? (
          <OverviewWidgetEmpty
            title="Weather needs a location"
            accent={accent}
            icon={<CloudSun size={18} />}
          />
        ) : (
          <OverviewWidgetEmpty
            title="Loading conditions…"
            accent={accent}
            icon={<CloudSun size={18} />}
          />
        )}
      </WidgetShell>

      <ModalSheet
        open={promptOpen}
        onOpenChange={(open) => {
          if (!busy) setPromptOpen(open);
        }}
        title="Weather location"
        width={440}
      >
        <div className="space-y-4">
          <div className="flex items-start gap-3">
            <div
              className="flex h-10 w-10 shrink-0 items-center justify-center text-[var(--color-primary)]"
              style={{
                borderRadius: 12,
                background: "color-mix(in srgb, var(--color-primary) 16%, transparent)",
              }}
            >
              <MapPin size={18} strokeWidth={2.25} />
            </div>
            <div className="min-w-0 space-y-1">
              <p className="text-section-title font-semibold text-[var(--color-text-main)]">
                Where should we show weather?
              </p>
              <p className="text-meta leading-relaxed">
                College never uses the browser location prompt. Pick an approximate area from your
                network, or search for a city. You can change this anytime from the weather widget.
              </p>
            </div>
          </div>

          <Button className="w-full" disabled={busy} onClick={() => void useApprox()}>
            {busy ? "Working…" : "Use approximate location"}
          </Button>

          <div className="space-y-2">
            <FormField label="Or search a city">
              <input
                className={fieldControlClass}
                placeholder="e.g. Austin, TX"
                value={cityQuery}
                onChange={(e) => setCityQuery(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") void useCity();
                }}
                disabled={busy}
              />
            </FormField>
            <Button
              variant="secondary"
              className="w-full"
              disabled={busy || !cityQuery.trim()}
              onClick={() => void useCity()}
            >
              Use this city
            </Button>
          </div>

          <button
            type="button"
            className="w-full text-center text-meta font-medium hover:text-[var(--color-text-main)]"
            disabled={busy}
            onClick={() => void skipLocation()}
          >
            Not now
          </button>
        </div>
      </ModalSheet>
    </>
  );
}

function GettingStartedWidget({ onLoadSample }: { onLoadSample: () => void }) {
  const accent = overviewCategoryAccent.custom;
  return (
    <WidgetShell
      widgetId="gettingStarted"
      title="Getting Started"
      accent={accent}
      icon={<Sparkles size={14} strokeWidth={2.25} />}
      className="min-[700px]:col-span-2"
    >
      <GuidedEmptyState
        title="Your workspace is empty"
        subtitle="Try demo data or start building your academic plan."
        showDemoSeed
        onDemoSeeded={onLoadSample}
        primaryAction={{
          label: "Open academic plan",
          onClick: () => navigate({ hub: "school", page: "plan" }),
          variant: "secondary",
        }}
      />
    </WidgetShell>
  );
}

export function OverviewWidgetGrid({ data }: { data: OverviewWidgetsData }) {
  const [customizeOpen, setCustomizeOpen] = useState(false);
  const [visibility, setVisibility] = useState(DEFAULT_WIDGET_VISIBILITY);

  const loadVisibility = useCallback(async () => {
    const settings = await ipc.settingsGet();
    setVisibility(parseWidgetVisibility(settings.values[DASHBOARD_WIDGETS_KEY]));
  }, []);

  useEffect(() => {
    void loadVisibility();
  }, [loadVisibility]);

  const show = (id: OverviewWidgetId) => visibility[id] !== false;

  const saveVisibility = async (next: Record<OverviewWidgetId, boolean>) => {
    setVisibility(next);
    await ipc.settingsSet(DASHBOARD_WIDGETS_KEY, JSON.stringify(next));
  };

  return (
    <div className="space-y-3">
      <div className="flex justify-end px-1">
        <Button size="sm" variant="secondary" onClick={() => setCustomizeOpen(true)}>
          Customize widgets
        </Button>
      </div>
      <OverviewWidgetGridLayout>
        {show("quickLaunch") && <QuickLaunchRow />}
        {show("weekAhead") && <WeekAheadWidget events={data.weekAheadEvents} />}
        {show("academicCalendar") && (
          <AcademicCalendarWidget summary={data.summary} gpa={data.gpa} />
        )}
        {show("deadlines") && <DeadlinesWidget tasks={data.deadlineTasks} />}
        {show("academics") && <AcademicsWidget summary={data.summary} gpa={data.gpa} />}
        {show("gpa") && <GpaWidget gpa={data.gpa} />}
        {show("todaySchedule") && <TodayScheduleWidget events={data.todayEvents} />}
        {show("openTasks") && (
          <OpenTasksWidget tasks={data.openTasks} count={data.openTaskCount} />
        )}
        {show("careerPipeline") && <CareerPipelineWidget career={data.career} />}
        {show("careerSummary") && (
          <CareerSummaryWidget career={data.career} followUps={data.careerFollowUps} />
        )}
        {show("careerFollowUps") && <CareerFollowUpsWidget rows={data.careerFollowUps} />}
        {show("recentDocuments") && <RecentDocumentsWidget docs={data.recentDocuments} />}
        {show("netWorth") && <NetWorthWidget finance={data.finance} />}
        {show("documents") && <DocumentsWidget count={data.vaultCount} />}
        {show("discovery") && <DiscoverySavedWidget count={data.savedSchoolCount} />}
        {show("advisorPrep") && data.advisorPrep ? (
          <AdvisorPrepWidget prep={data.advisorPrep} />
        ) : null}
        {show("needsAttention") && (
          <NeedsAttentionWidget
            openTaskCount={data.openTaskCount}
            deadlineCount={data.deadlineTasks.length}
          />
        )}
        {show("weather") && <WeatherWidget />}
        {data.isWorkspaceEmpty && show("quickLaunch") && (
          <GettingStartedWidget onLoadSample={data.onLoadSample} />
        )}
      </OverviewWidgetGridLayout>

      <ModalSheet open={customizeOpen} onOpenChange={setCustomizeOpen} title="Overview widgets">
        <p className="mb-3 text-meta">
          Toggle which widgets appear on the School Overview dashboard.
        </p>
        <ul className="space-y-2">
          {(Object.keys(WIDGET_LABELS) as OverviewWidgetId[]).map((id) => (
            <li
              key={id}
              className="flex items-center justify-between gap-3 rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2"
            >
              <span className="text-body">{WIDGET_LABELS[id]}</span>
              <input
                type="checkbox"
                checked={visibility[id] !== false}
                onChange={(e) => void saveVisibility({ ...visibility, [id]: e.target.checked })}
              />
            </li>
          ))}
        </ul>
      </ModalSheet>
    </div>
  );
}
