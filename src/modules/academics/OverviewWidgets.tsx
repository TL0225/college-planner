import {
  CalendarDays,
  Briefcase,
  FolderOpen,
  Compass,
  Sparkles,
  Wallet,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  MetricTile,
  ModalSheet,
  ProgressBar,
  StatusChip,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import type {
  AuditSummary,
  FinanceDashboardSummary,
  GpaSummary,
  PipelineMetrics,
} from "@/lib/ipc";
import { shellNavigate } from "@/lib/shellNavigate";

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
  { label: "Calendar", icon: CalendarDays, module: "calendar", page: "month" },
  { label: "Career", icon: Briefcase, module: "career", page: "applications" },
  { label: "Documents", icon: FolderOpen, module: "documents", page: "all" },
  { label: "Discovery", icon: Compass, module: "college", page: "discovery" },
  { label: "Assistant", icon: Sparkles, module: "assistant", page: "chat" },
  { label: "Finance", icon: Wallet, module: "finance", page: "dashboard" },
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
      className="mt-2 text-[12px] font-medium text-[var(--color-primary)] hover:underline"
    >
      {children}
    </button>
  );
}

function AcademicsWidget({ summary }: { summary: AuditSummary | null }) {
  const completed = summary?.completedCredits ?? 0;
  const planned = summary?.plannedCredits ?? 0;
  const total = completed + planned;
  const ratio = total > 0 ? completed / total : 0;

  return (
    <AppCard title="Academics">
      <div className="grid gap-2 sm:grid-cols-3">
        <MetricTile
          label="Completed"
          value={summary ? completed.toFixed(1) : "—"}
          accent="var(--color-success)"
        />
        <MetricTile label="Planned" value={summary ? planned.toFixed(1) : "—"} />
        <MetricTile
          label="Courses"
          value={summary?.courseCount ?? "—"}
          accent="var(--color-primary)"
        />
      </div>
      {total > 0 && (
        <div className="mt-3">
          <div className="mb-1.5 flex items-center justify-between text-[11px] text-[var(--color-text-light)]">
            <span>Credit progress</span>
            <span className="tabular-nums">
              {completed.toFixed(1)} / {total.toFixed(1)} cr
            </span>
          </div>
          <ProgressBar value={ratio} tint="var(--color-success)" height={6} />
        </div>
      )}
      <WidgetLink onClick={() => shellNavigate("college", "planner")}>
        Open planner →
      </WidgetLink>
    </AppCard>
  );
}

function GpaWidget({ gpa }: { gpa: GpaSummary | null }) {
  return (
    <AppCard title="GPA">
      <MetricTile
        label="Cumulative GPA"
        value={gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"}
        accent="var(--color-success)"
      />
      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        <StatusChip
          title={`${gpa?.gradedCourses ?? 0} graded courses`}
          tint="var(--color-primary)"
          filled
        />
        {gpa != null && gpa.gradedCredits > 0 && (
          <StatusChip title={`${gpa.gradedCredits.toFixed(1)} cr graded`} />
        )}
      </div>
      <WidgetLink onClick={() => shellNavigate("college", "degree")}>
        View requirements →
      </WidgetLink>
    </AppCard>
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
  return (
    <AppCard title="Academic calendar">
      <div className="grid gap-2 sm:grid-cols-2">
        <MetricTile label="Credits completed" value={summary ? summary.completedCredits.toFixed(1) : "—"} />
        <MetricTile label="Cumulative GPA" value={gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"} />
      </div>
      <WidgetLink onClick={() => shellNavigate("college", "planner")}>
        Open planner →
      </WidgetLink>
    </AppCard>
  );
}

function WeekAheadWidget({ events }: { events: OverviewEventRow[] }) {
  return (
    <AppCard title="Week ahead">
      {events.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">Nothing scheduled in the next 7 days.</p>
      ) : (
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {events.map((e) => (
            <li key={e.id}>
              <ListRow
                title={e.title}
                subtitle={formatEventDay(e.startAt)}
                trailing={
                  <StatusChip
                    title={new Date(e.startAt).toLocaleTimeString(undefined, {
                      hour: "numeric",
                      minute: "2-digit",
                    })}
                  />
                }
              />
            </li>
          ))}
        </ul>
      )}
      <WidgetLink onClick={() => shellNavigate("calendar", "week")}>
        Open week view →
      </WidgetLink>
    </AppCard>
  );
}

function DeadlinesWidget({ tasks }: { tasks: OverviewTaskRow[] }) {
  return (
    <AppCard title="Deadlines">
      {tasks.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">
          No tasks due in the next 14 days.
        </p>
      ) : (
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {tasks.map((t) => (
            <li key={t.id}>
              <ListRow
                title={t.title}
                trailing={
                  t.dueAt ? (
                    <StatusChip
                      title={new Date(t.dueAt).toLocaleDateString(undefined, {
                        month: "short",
                        day: "numeric",
                      })}
                      tint="var(--color-warning)"
                      filled
                    />
                  ) : undefined
                }
              />
            </li>
          ))}
        </ul>
      )}
      <WidgetLink onClick={() => shellNavigate("calendar", "tasks")}>
        View all tasks →
      </WidgetLink>
    </AppCard>
  );
}

function QuickLaunchRow() {
  return (
    <AppCard title="Quick launch" className="md:col-span-2 xl:col-span-3">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        {QUICK_LAUNCH_TILES.map((tile) => {
          const Icon = tile.icon;
          return (
            <button
              key={tile.label}
              type="button"
              onClick={() => shellNavigate(tile.module, tile.page)}
              className="flex flex-col items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] px-3 py-3 text-center transition-colors hover:bg-[var(--color-row-hover)]"
              style={{
                background:
                  "linear-gradient(180deg, color-mix(in srgb, var(--color-primary) 4%, var(--color-content-surface)), var(--color-content-surface))",
                boxShadow: "inset 0 1px 0 color-mix(in srgb, white 35%, transparent)",
              }}
            >
              <span
                className="flex h-9 w-9 items-center justify-center rounded-[10px] text-[var(--color-primary)]"
                style={{
                  border: "1px solid var(--color-chrome-stroke)",
                  background: "color-mix(in srgb, var(--color-primary) 10%, var(--color-surface))",
                }}
              >
                <Icon size={16} strokeWidth={2} />
              </span>
              <span className="text-[12px] font-semibold text-[var(--color-text-main)]">
                {tile.label}
              </span>
            </button>
          );
        })}
      </div>
    </AppCard>
  );
}

function navigateDiscoverySaved() {
  shellNavigate("college", "discovery");
  window.dispatchEvent(
    new CustomEvent("college:discovery-mode", { detail: { mode: "saved" } }),
  );
}

function DiscoverySavedWidget({ count }: { count: number }) {
  return (
    <AppCard title="Discovery saved">
      <MetricTile label="Saved schools" value={count} accent="var(--color-primary)" />
      <WidgetLink onClick={navigateDiscoverySaved}>
        Open saved schools →
      </WidgetLink>
    </AppCard>
  );
}

function AdvisorPrepWidget({ prep }: { prep: AdvisorPrepSummary }) {
  const ratio = prep.total > 0 ? prep.completed / prep.total : 0;

  return (
    <AppCard title="Advisor prep">
      <div className="mb-2 flex items-center justify-between gap-2">
        <StatusChip
          title={`${prep.completed}/${prep.total} ready`}
          tint="var(--color-success)"
          filled={prep.completed === prep.total}
        />
      </div>
      <ProgressBar value={ratio} tint="var(--color-success)" height={6} />
      <p className="mt-2 text-[12px] text-[var(--color-text-light)]">
        Checklist progress for your next advisor meeting.
      </p>
      <WidgetLink onClick={() => shellNavigate("profile", "advisor")}>
        Open checklist →
      </WidgetLink>
    </AppCard>
  );
}

function TodayScheduleWidget({ events }: { events: OverviewEventRow[] }) {
  return (
    <AppCard title="Today">
      {events.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">Nothing scheduled today.</p>
      ) : (
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {events.map((e) => (
            <li key={e.id}>
              <ListRow
                title={e.title}
                trailing={
                  <StatusChip
                    title={new Date(e.startAt).toLocaleTimeString(undefined, {
                      hour: "numeric",
                      minute: "2-digit",
                    })}
                  />
                }
              />
            </li>
          ))}
        </ul>
      )}
      <WidgetLink onClick={() => shellNavigate("calendar", "day")}>
        Open calendar →
      </WidgetLink>
    </AppCard>
  );
}

function OpenTasksWidget({ tasks, count }: { tasks: OverviewTaskRow[]; count: number }) {
  return (
    <AppCard title="Open tasks">
      <div className="mb-2">
        <StatusChip title={`${count} open`} tint="var(--color-warning)" filled />
      </div>
      {tasks.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">No open tasks.</p>
      ) : (
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {tasks.map((t) => (
            <li key={t.id}>
              <ListRow
                title={t.title}
                trailing={
                  t.dueAt ? (
                    <StatusChip
                      title={new Date(t.dueAt).toLocaleDateString(undefined, {
                        month: "short",
                        day: "numeric",
                      })}
                      tint="var(--color-warning)"
                      filled
                    />
                  ) : undefined
                }
              />
            </li>
          ))}
        </ul>
      )}
      <WidgetLink onClick={() => shellNavigate("calendar", "tasks")}>
        View all tasks →
      </WidgetLink>
    </AppCard>
  );
}

function CareerSummaryWidget({
  career,
  followUps,
}: {
  career: PipelineMetrics | null;
  followUps: CareerFollowUpRow[];
}) {
  const applied = career?.applied ?? 0;
  const interviewing = career?.interviewing ?? 0;
  const offer = career?.offer ?? 0;
  const hasActivity = (career?.total ?? 0) > 0 || followUps.length > 0;

  return (
    <AppCard title="Career">
      {!hasActivity ? (
        <p className="text-[12px] text-[var(--color-text-light)]">
          Track your first application to see pipeline counts and follow-ups here.
        </p>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-2">
            <MetricTile label="Applied" value={applied} accent="var(--color-primary)" />
            <MetricTile label="Interview" value={interviewing} accent="var(--color-warning)" />
            <MetricTile label="Offer" value={offer} accent="var(--color-success)" />
          </div>
          {followUps.length > 0 && (
            <ul className="mt-3 divide-y divide-[var(--color-chrome-stroke)]">
              {followUps.slice(0, 2).map((row) => (
                <li key={row.id}>
                  <ListRow title={row.company} subtitle={row.roleTitle} />
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      <WidgetLink onClick={() => shellNavigate("career", "applications")}>
        Open applications →
      </WidgetLink>
    </AppCard>
  );
}

function RecentDocumentsWidget({ docs }: { docs: RecentDocumentRow[] }) {
  return (
    <AppCard title="Recent documents">
      {docs.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">No vault files yet.</p>
      ) : (
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {docs.map((d) => (
            <li key={d.id}>
              <ListRow
                title={d.title}
                trailing={
                  <StatusChip
                    title={new Date(d.updatedAt).toLocaleDateString(undefined, {
                      month: "short",
                      day: "numeric",
                    })}
                  />
                }
              />
            </li>
          ))}
        </ul>
      )}
      <WidgetLink onClick={() => shellNavigate("documents", "all")}>
        Open documents →
      </WidgetLink>
    </AppCard>
  );
}

function CareerFollowUpsWidget({ rows }: { rows: CareerFollowUpRow[] }) {
  return (
    <AppCard title="Career follow-ups">
      {rows.length === 0 ? (
        <p className="text-[12px] text-[var(--color-text-light)]">
          No applications waiting on a follow-up.
        </p>
      ) : (
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {rows.map((row) => (
            <li key={row.id}>
              <ListRow
                title={row.company}
                subtitle={row.roleTitle}
                trailing={
                  row.appliedAt ? (
                    <StatusChip
                      title={new Date(row.appliedAt).toLocaleDateString(undefined, {
                        month: "short",
                        day: "numeric",
                      })}
                      tint="var(--color-warning)"
                      filled
                    />
                  ) : undefined
                }
              />
            </li>
          ))}
        </ul>
      )}
      <WidgetLink onClick={() => shellNavigate("career", "applications")}>
        Open applications →
      </WidgetLink>
    </AppCard>
  );
}

function CareerPipelineWidget({ career }: { career: PipelineMetrics | null }) {
  const stages = [
    { key: "interested", label: "Interested", tint: "var(--color-primary)" },
    { key: "applied", label: "Applied", tint: "var(--color-warning)" },
    { key: "interviewing", label: "Interviewing", tint: "var(--color-success)" },
    { key: "offer", label: "Offer", tint: "var(--color-success)" },
  ] as const;

  return (
    <AppCard title="Career pipeline">
      <div className="flex flex-wrap gap-2">
        {stages.map((stage) => (
          <StatusChip
            key={stage.key}
            title={`${stage.label} ${career?.[stage.key] ?? 0}`}
            tint={stage.tint}
            filled={(career?.[stage.key] ?? 0) > 0}
          />
        ))}
      </div>
      <p className="mt-2.5 text-[12px] text-[var(--color-text-light)]">
        {career?.total ?? 0} total applications tracked
      </p>
      <WidgetLink onClick={() => shellNavigate("career", "applications")}>
        Open applications →
      </WidgetLink>
    </AppCard>
  );
}

function NetWorthWidget({ finance }: { finance: FinanceDashboardSummary | null }) {
  const formatted = finance
    ? finance.netWorth.toLocaleString(undefined, { style: "currency", currency: "USD" })
    : "—";

  return (
    <AppCard title="Net worth">
      <MetricTile label="Total" value={formatted} accent="var(--color-primary)" />
      {finance && (
        <div className="mt-2.5 flex flex-wrap gap-2">
          <StatusChip title={`${finance.accountCount} accounts`} filled />
          <StatusChip title={`${finance.transactionCount} transactions`} />
          <StatusChip title={`${finance.budgetCount} budgets`} />
        </div>
      )}
      <WidgetLink onClick={() => shellNavigate("finance", "dashboard")}>
        Open finance →
      </WidgetLink>
    </AppCard>
  );
}

function DocumentsWidget({ count }: { count: number }) {
  return (
    <AppCard title="Documents">
      <MetricTile label="Vault files" value={count} accent="var(--color-primary)" />
      <WidgetLink onClick={() => shellNavigate("documents", "all")}>
        Open documents →
      </WidgetLink>
    </AppCard>
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
  return (
    <AppCard title="Needs attention">
      <MetricTile
        label="Items"
        value={total}
        accent={total > 0 ? "var(--color-warning)" : "var(--color-success)"}
      />
      <p className="mt-2 text-[12px] text-[var(--color-text-light)]">
        {openTaskCount} open task{openTaskCount === 1 ? "" : "s"} · {deadlineCount} due within 14
        days
      </p>
      <WidgetLink onClick={() => shellNavigate("calendar", "tasks")}>Open tasks →</WidgetLink>
    </AppCard>
  );
}

function WeatherWidget() {
  const [weather, setWeather] = useState<{
    temperatureF: number;
    summary: string;
    windMph?: number | null;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = (lat: number, lon: number) => {
      void ipc
        .platformFetchWeather(lat, lon)
        .then(setWeather)
        .catch((e) => setError(formatIpcError(e)));
    };
    if (typeof navigator !== "undefined" && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => load(pos.coords.latitude, pos.coords.longitude),
        () => load(40.7128, -74.006),
        { timeout: 4000, maximumAge: 600_000 },
      );
    } else {
      load(40.7128, -74.006);
    }
  }, []);

  return (
    <AppCard title="Weather">
      {error ? (
        <p className="text-[12px] text-[var(--color-text-light)]">{error}</p>
      ) : weather ? (
        <>
          <MetricTile
            label={weather.summary}
            value={`${Math.round(weather.temperatureF)}°F`}
            accent="var(--color-primary)"
          />
          {weather.windMph != null && (
            <p className="mt-2 text-[11px] text-[var(--color-text-light)]">
              Wind {Math.round(weather.windMph)} mph · Open-Meteo
            </p>
          )}
        </>
      ) : (
        <p className="text-[12px] text-[var(--color-text-light)]">Loading conditions…</p>
      )}
    </AppCard>
  );
}

function GettingStartedWidget({ onLoadSample }: { onLoadSample: () => void }) {
  return (
    <AppCard title="Getting started" className="md:col-span-2 xl:col-span-3">
      <EmptyState
        title="Your workspace is empty"
        body="Load demo content or start building your academic plan."
        action={
          <div className="space-y-3">
            <ul className="list-inside list-disc space-y-1 text-[12px] text-[var(--color-text-light)]">
              <li>Settings → Load sample data to explore with demo semesters, events, and career rows</li>
              <li>College → Planner to add your first semester and courses</li>
            </ul>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={onLoadSample}>
                Load sample data
              </Button>
              <Button
                size="sm"
                variant="secondary"
                onClick={() => shellNavigate("college", "planner")}
              >
                Open planner
              </Button>
              <Button
                size="sm"
                variant="secondary"
                onClick={() => shellNavigate("settings", "general")}
              >
                Settings
              </Button>
            </div>
          </div>
        }
      />
    </AppCard>
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
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {show("quickLaunch") && <QuickLaunchRow />}
        {show("weekAhead") && <WeekAheadWidget events={data.weekAheadEvents} />}
        {show("academicCalendar") && (
          <AcademicCalendarWidget summary={data.summary} gpa={data.gpa} />
        )}
        {show("deadlines") && <DeadlinesWidget tasks={data.deadlineTasks} />}
        {show("academics") && <AcademicsWidget summary={data.summary} />}
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
      </div>

      <ModalSheet open={customizeOpen} onOpenChange={setCustomizeOpen} title="Overview widgets">
        <p className="mb-3 text-[12px] text-[var(--color-text-light)]">
          Toggle which widgets appear on College Overview (Swift dashboard.widgets.v1 parity).
        </p>
        <ul className="space-y-2">
          {(Object.keys(WIDGET_LABELS) as OverviewWidgetId[]).map((id) => (
            <li
              key={id}
              className="flex items-center justify-between gap-3 rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2"
            >
              <span className="text-[13px] text-[var(--color-text-main)]">{WIDGET_LABELS[id]}</span>
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
