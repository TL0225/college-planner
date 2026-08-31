import {
  Plus,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Button,
  EmptyState,
  StatusChip,
  useReduceMotion,
  RegistrarHeroBlock,
  LedgerStat,
  RegistrarSection,
  JumpRow,
  RegistrarMetricRow,
  RegistrarPage,
} from "@/design-system";
import {
  ipc,
  formatIpcError,
  type AuditSummary,
  type FinanceDashboardSummary,
  type GpaSummary,
  type PipelineMetrics,
} from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import type { ModuleId } from "@/design-system/tokens";
import type { ShellRecent } from "@/lib/shell/types";
import {
  dayVisibleRange,
  expandRecurringEvents,
  weekVisibleRange,
  type CalendarEventOccurrence,
} from "@/modules/calendar/expandRecurring";

type TaskItem = {
  id: string;
  title: string;
  dueAt?: string | null;
  isComplete: boolean;
  priority?: string | null;
  courseCode?: string | null;
};

type VaultDoc = {
  id: string;
  title: string;
  category: string;
  updatedAt: string;
};

function deadlineUrgency(dueAt?: string | null): { label: string; color: string } {
  if (!dueAt) return { label: "UPCOMING", color: "var(--color-text-light)" };
  const due = new Date(dueAt);
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(due);
  end.setHours(0, 0, 0, 0);
  const days = Math.round((end.getTime() - start.getTime()) / 86_400_000);
  if (days < 0) return { label: "OVERDUE", color: "var(--color-error)" };
  if (days === 0) return { label: "TODAY", color: "var(--color-error)" };
  if (days === 1) return { label: "TOMORROW", color: "var(--color-warning)" };
  if (days <= 3) return { label: `${days} DAYS`, color: "var(--color-warning)" };
  if (days <= 7) return { label: "THIS WEEK", color: "var(--color-primary)" };
  return {
    label: due.toLocaleDateString(undefined, { month: "short", day: "numeric" }).toUpperCase(),
    color: "var(--color-success)",
  };
}

export function HomeModule({
  page,
  recents = [],
  onNavigate,
  onQuickAdd,
  onClearRecents,
}: {
  page: string;
  recents?: ShellRecent[];
  onNavigate: (hub: ModuleId, page?: string, title?: string) => void;
  onQuickAdd: (kind: "event" | "expense" | "task") => void;
  onClearRecents?: () => void;
}) {
  const [gpa, setGpa] = useState<GpaSummary | null>(null);
  const [audit, setAudit] = useState<AuditSummary | null>(null);
  const [tasks, setTasks] = useState<TaskItem[]>([]);
  const [events, setEvents] = useState<CalendarEventOccurrence[]>([]);
  const [pipeline, setPipeline] = useState<PipelineMetrics | null>(null);
  const [finance, setFinance] = useState<FinanceDashboardSummary | null>(null);
  const [vaultDocs, setVaultDocs] = useState<VaultDoc[]>([]);
  const [goalSettings, setGoalSettings] = useState<Record<string, string>>({});

  const loadData = useCallback(async () => {
    try {
      const [gpaRes, auditRes, taskList, rawEvents, pipeRes, finRes, vaultRes, settingsRes] =
        await Promise.all([
          ipc.academicsGetGpaSummary().catch(() => null),
          ipc.academicsGetAuditSummary().catch(() => null),
          ipc.calendarListTasks().catch(() => []),
          ipc.calendarListEvents().catch(() => []),
          ipc.careerPipelineMetrics().catch(() => null),
          ipc.financeDashboardSummary().catch(() => null),
          ipc.documentsListVault().catch(() => []),
          ipc.settingsGet().catch(() => ({ values: {} as Record<string, string> })),
        ]);

      setGpa(gpaRes);
      setAudit(auditRes);
      setTasks(taskList as TaskItem[]);
      setPipeline(pipeRes);
      setFinance(finRes);
      setVaultDocs(vaultRes as VaultDoc[]);
      setGoalSettings(settingsRes.values);

      const now = new Date();
      const [wStart, wEnd] = weekVisibleRange(now);
      const expanded = expandRecurringEvents(rawEvents, wStart, wEnd);
      setEvents(expanded);
    } catch (e) {
      console.warn("Failed to load home dashboard data", e);
    }
  }, []);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const toggleTask = async (taskId: string, currentStatus: boolean) => {
    try {
      await ipc.calendarToggleTaskComplete(taskId);
      setTasks((prev) =>
        prev.map((t) => (t.id === taskId ? { ...t, isComplete: !currentStatus } : t)),
      );
      showToast(currentStatus ? "Task reopened" : "Task completed!", "success");
    } catch (err) {
      showToast(formatIpcError(err), "error");
    }
  };

  const todayEvents = useMemo(() => {
    const now = new Date();
    const [dStart, dEnd] = dayVisibleRange(now);
    return events.filter((e) => {
      const evDate = new Date(e.startAt);
      return evDate >= dStart && evDate <= dEnd;
    });
  }, [events]);

  const weekAheadEvents = useMemo(() => {
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setDate(now.getDate() + 1);
    tomorrow.setHours(0, 0, 0, 0);

    const sevenDays = new Date(now);
    sevenDays.setDate(now.getDate() + 7);
    sevenDays.setHours(23, 59, 59, 999);

    return events.filter((e) => {
      const evDate = new Date(e.startAt);
      return evDate >= tomorrow && evDate <= sevenDays;
    });
  }, [events]);

  const openTasks = useMemo(() => {
    return tasks
      .filter((t) => !t.isComplete)
      .sort((a, b) => {
        if (!a.dueAt) return 1;
        if (!b.dueAt) return -1;
        return a.dueAt.localeCompare(b.dueAt);
      });
  }, [tasks]);

  return (
    <RegistrarPage>
        {page === "today" && (
          <HomeTodayView
            gpa={gpa}
            audit={audit}
            todayEvents={todayEvents}
            weekAheadEvents={weekAheadEvents}
            openTasks={openTasks}
            pipeline={pipeline}
            onNavigate={onNavigate}
            onToggleTask={toggleTask}
            onQuickAdd={onQuickAdd}
          />
        )}

        {page === "week" && (
          <HomeWeekView
            events={events}
            tasks={tasks}
            onNavigate={onNavigate}
            onToggleTask={toggleTask}
          />
        )}

        {page === "goals" && (
          <HomeGoalsView
            audit={audit}
            gpa={gpa}
            pipeline={pipeline}
            finance={finance}
            goalSettings={goalSettings}
            onNavigate={onNavigate}
          />
        )}

        {page === "recents" && (
          <HomeRecentsView
            recents={recents}
            vaultDocs={vaultDocs}
            onNavigate={onNavigate}
            onClearRecents={onClearRecents}
          />
        )}
    </RegistrarPage>
  );
}

/* =========================================================================
   1. TODAY VIEW (Curated, digestible glance-and-go dashboard)
   ========================================================================= */

function HomeTodayView({
  gpa,
  audit,
  todayEvents,
  weekAheadEvents,
  openTasks,
  pipeline,
  onNavigate,
  onToggleTask,
  onQuickAdd,
}: {
  gpa: GpaSummary | null;
  audit: AuditSummary | null;
  todayEvents: CalendarEventOccurrence[];
  weekAheadEvents: CalendarEventOccurrence[];
  openTasks: TaskItem[];
  pipeline: PipelineMetrics | null;
  onNavigate: (hub: ModuleId, page?: string, title?: string) => void;
  onToggleTask: (taskId: string, currentStatus: boolean) => void;
  onQuickAdd: (kind: "event" | "expense" | "task") => void;
}) {
  const completedCredits = audit?.completedCredits ?? 0;
  const reduceMotion = useReduceMotion();

  const nextDeadline = openTasks.find((t) => !!t.dueAt) ?? openTasks[0] ?? null;
  const nextEventToday = useMemo(() => {
    const now = Date.now();
    const upcoming = todayEvents
      .slice()
      .sort((a, b) => a.startAt.localeCompare(b.startAt))
      .find((e) => new Date(e.endAt ?? e.startAt).getTime() >= now);
    return upcoming ?? todayEvents[0] ?? null;
  }, [todayEvents]);

  const hero: TodayHero = nextDeadline
    ? { kind: "deadline", task: nextDeadline }
    : nextEventToday
      ? { kind: "event", event: nextEventToday }
      : { kind: "free" };

  return (
    <div className="space-y-10">
      <TodayHeroBlock hero={hero} reduceMotion={reduceMotion} onQuickAdd={onQuickAdd} onNavigate={onNavigate} />

      {/* Ledger strip — replaces the 4-card stat grid. One rule-bounded row, mono figures. */}
      <div
        className="flex flex-col sm:flex-row"
        style={{ borderTop: "1px solid var(--registrar-rule)", borderBottom: "1px solid var(--registrar-rule)" }}
      >
        <LedgerStat
          label="GPA"
          value={gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"}
          hint={`${completedCredits.toFixed(0)} credits`}
          onClick={() => onNavigate("school", "plan", "Plan")}
        />
        <LedgerStat
          label="Today"
          value={String(todayEvents.length)}
          hint={todayEvents.length === 1 ? "event" : "events"}
          onClick={() => onNavigate("life", "schedule", "Schedule")}
        />
        <LedgerStat
          label="Open tasks"
          value={String(openTasks.length)}
          hint={openTasks.length > 0 ? "due" : undefined}
          onClick={() => onNavigate("life", "tasks", "Tasks")}
        />
        <LedgerStat
          label="Applications"
          value={String(pipeline?.total ?? 0)}
          hint={pipeline?.interviewing ? `${pipeline.interviewing} interviewing` : "tracked"}
          onClick={() => onNavigate("career", "pipeline", "Applications")}
          last
        />
      </div>

      <div className="grid grid-cols-1 gap-10 lg:grid-cols-12">
        {/* Left Column: Schedule & Week Preview */}
        <div className="space-y-8 lg:col-span-7">
          <RegistrarSection title="Today's schedule" actionLabel="Full day" onAction={() => onNavigate("life", "day", "Day")}>
            {todayEvents.length === 0 ? (
              <EmptyState
                title="Open today"
                body="Nothing on the books. Add a class, a study block, or a meeting."
                action={
                  <Button size="sm" variant="secondary" onClick={() => onQuickAdd("event")}>
                    <Plus size={13} />
                    <span>Add event</span>
                  </Button>
                }
              />
            ) : (
              <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
                {todayEvents.map((ev) => {
                  const start = new Date(ev.startAt);
                  const end = ev.endAt ? new Date(ev.endAt) : null;
                  const timeStr = start.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
                  const endTimeStr = end
                    ? end.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
                    : null;
                  return (
                    <div
                      key={ev.occurrenceId}
                      className="flex items-baseline gap-4 py-3"
                      style={{ borderBottom: "1px solid var(--registrar-rule)" }}
                    >
                      <div
                        className="w-24 shrink-0 text-[12.5px] tabular-nums"
                        style={{ fontFamily: "var(--font-mono)", color: "var(--registrar-ink)" }}
                      >
                        {timeStr}
                        {endTimeStr && <span className="opacity-60">–{endTimeStr}</span>}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-body font-medium" style={{ color: "var(--registrar-ink)" }}>
                          {ev.title}
                        </p>
                        {ev.location && (
                          <p className="mt-0.5 truncate text-caption text-[var(--color-text-light)]">
                            {ev.location}
                          </p>
                        )}
                      </div>
                      {ev.provider && <StatusChip title={ev.provider} />}
                    </div>
                  );
                })}
              </div>
            )}
          </RegistrarSection>

          <RegistrarSection title="Week ahead" actionLabel="Week view" onAction={() => onNavigate("life", "week", "Week")}>
            {weekAheadEvents.length === 0 ? (
              <p className="text-body text-[var(--color-text-light)]">Nothing on the calendar for the next 7 days.</p>
            ) : (
              <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
                {weekAheadEvents.slice(0, 5).map((ev) => {
                  const evDate = new Date(ev.startAt);
                  const dayLabel = evDate.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
                  const timeStr = evDate.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
                  return (
                    <div
                      key={ev.occurrenceId}
                      className="flex items-center justify-between gap-3 py-2.5 text-body"
                      style={{ borderBottom: "1px solid var(--registrar-rule)" }}
                    >
                      <div className="min-w-0 flex-1 pr-3">
                        <span className="font-medium" style={{ color: "var(--registrar-ink)" }}>{ev.title}</span>
                        {ev.location && (
                          <span className="ml-2 text-caption text-[var(--color-text-light)]">· {ev.location}</span>
                        )}
                      </div>
                      <div
                        className="shrink-0 whitespace-nowrap text-[12px] tabular-nums text-[var(--color-text-light)]"
                        style={{ fontFamily: "var(--font-mono)" }}
                      >
                        {dayLabel} · {timeStr}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </RegistrarSection>
        </div>

        {/* Right Column: Deadlines & Quick Jump */}
        <div className="space-y-8 lg:col-span-5">
          <RegistrarSection
            title="Deadlines"
            actionLabel={`All (${openTasks.length})`}
            onAction={() => onNavigate("life", "tasks", "Tasks")}
          >
            {openTasks.length === 0 ? (
              <EmptyState
                title="Clear through the week"
                body="Nothing outstanding — add a deadline as soon as one's assigned."
                action={
                  <Button size="sm" variant="secondary" onClick={() => onQuickAdd("task")}>
                    <Plus size={13} />
                    <span>Add task</span>
                  </Button>
                }
              />
            ) : (
              <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
                {openTasks.slice(0, 6).map((task) => {
                  const urgency = deadlineUrgency(task.dueAt);
                  return (
                    <div
                      key={task.id}
                      className="flex items-start gap-3 py-2.5"
                      style={{ borderBottom: "1px solid var(--registrar-rule)" }}
                    >
                      <input
                        type="checkbox"
                        checked={task.isComplete}
                        onChange={() => onToggleTask(task.id, task.isComplete)}
                        className="mt-1 h-3.5 w-3.5 shrink-0 rounded-none border-[var(--registrar-rule)] text-[var(--registrar-accent)] focus:ring-0"
                        title="Mark complete"
                      />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-body font-medium" style={{ color: "var(--registrar-ink)" }}>
                          {task.title}
                        </p>
                        {task.courseCode && (
                          <span
                            className="mt-0.5 inline-block text-[11px]"
                            style={{ fontFamily: "var(--font-mono)", color: "var(--color-text-light)" }}
                          >
                            {task.courseCode}
                          </span>
                        )}
                      </div>
                      <span
                        className="shrink-0 whitespace-nowrap text-[11px] font-semibold uppercase tracking-wide"
                        style={{ fontFamily: "var(--font-mono)", color: urgency.color }}
                      >
                        {urgency.label}
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
          </RegistrarSection>

          <RegistrarSection title="Jump to">
            <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
              <JumpRow label="Academic plan" hint="Semesters & degree" onClick={() => onNavigate("school", "plan", "Plan")} />
              <JumpRow label="Job tracker" hint="Applications & pipeline" onClick={() => onNavigate("career", "pipeline", "Applications")} />
              <JumpRow label="Finances" hint="Budgets & cash flow" onClick={() => onNavigate("life", "money", "Money")} />
              <JumpRow label="Files" hint="Syllabi & documents" onClick={() => onNavigate("library", "all", "All files")} last />
            </div>
          </RegistrarSection>
        </div>
      </div>
    </div>
  );
}

type TodayHero =
  | { kind: "deadline"; task: TaskItem }
  | { kind: "event"; event: CalendarEventOccurrence }
  | { kind: "free" };

function TodayHeroBlock({
  hero,
  reduceMotion,
  onQuickAdd,
  onNavigate,
}: {
  hero: TodayHero;
  reduceMotion: boolean;
  onQuickAdd: (kind: "event" | "expense" | "task") => void;
  onNavigate: (hub: ModuleId, page?: string, title?: string) => void;
}) {
  let eyebrow = "Free today";
  let heading = "Nothing due, nothing scheduled.";
  let meta: string | null = "A clean slate — good time to get ahead.";
  let action: { label: string; onClick: () => void } | null = {
    label: "Add something",
    onClick: () => onQuickAdd("event"),
  };

  if (hero.kind === "deadline") {
    const urgency = deadlineUrgency(hero.task.dueAt);
    eyebrow = urgency.label;
    heading = hero.task.title;
    meta = hero.task.courseCode ?? null;
    action = { label: "Open deadlines", onClick: () => onNavigate("life", "tasks", "Tasks") };
  } else if (hero.kind === "event") {
    const start = new Date(hero.event.startAt);
    const timeStr = start.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    eyebrow = `Next up · ${timeStr}`;
    heading = hero.event.title;
    meta = hero.event.location ?? null;
    action = { label: "Open schedule", onClick: () => onNavigate("life", "schedule", "Schedule") };
  }

  return (
    <RegistrarHeroBlock
      eyebrow={eyebrow}
      heading={heading}
      meta={meta}
      action={action}
      reduceMotion={reduceMotion}
    />
  );
}

/* =========================================================================
   2. WEEK VIEW
   ========================================================================= */

function HomeWeekView({
  events,
  tasks,
  onNavigate,
  onToggleTask,
}: {
  events: CalendarEventOccurrence[];
  tasks: TaskItem[];
  onNavigate: (hub: ModuleId, page?: string, title?: string) => void;
  onToggleTask: (taskId: string, currentStatus: boolean) => void;
}) {
  const reduceMotion = useReduceMotion();

  const daysOfWeek = useMemo(() => {
    const now = new Date();
    const [start] = weekVisibleRange(now);
    const days: Array<{ date: Date; isToday: boolean; dateStr: string; label: string }> = [];

    for (let i = 0; i < 7; i++) {
      const d = new Date(start);
      d.setDate(start.getDate() + i);
      const isToday =
        d.getFullYear() === now.getFullYear() &&
        d.getMonth() === now.getMonth() &&
        d.getDate() === now.getDate();

      days.push({
        date: d,
        isToday,
        dateStr: d.toISOString().slice(0, 10),
        label: d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" }),
      });
    }
    return days;
  }, []);

  const openWeekTasks = useMemo(
    () => tasks.filter((t) => !t.isComplete && t.dueAt),
    [tasks],
  );

  const weekRangeLabel =
    daysOfWeek.length >= 2
      ? `${daysOfWeek[0]!.label} – ${daysOfWeek[daysOfWeek.length - 1]!.label}`
      : null;

  const todayItemCount = useMemo(() => {
    const today = daysOfWeek.find((d) => d.isToday);
    if (!today) return 0;
    const dayEvents = events.filter((e) => {
      const evDate = new Date(e.startAt);
      return (
        evDate.getFullYear() === today.date.getFullYear() &&
        evDate.getMonth() === today.date.getMonth() &&
        evDate.getDate() === today.date.getDate()
      );
    });
    const dayTasks = openWeekTasks.filter((t) => {
      const tDate = new Date(t.dueAt!);
      return (
        tDate.getFullYear() === today.date.getFullYear() &&
        tDate.getMonth() === today.date.getMonth() &&
        tDate.getDate() === today.date.getDate()
      );
    });
    return dayEvents.length + dayTasks.length;
  }, [daysOfWeek, events, openWeekTasks]);

  return (
    <div className="space-y-10">
      <RegistrarHeroBlock
        eyebrow="This week"
        heading={`${events.length} events · ${openWeekTasks.length} due`}
        meta={weekRangeLabel}
        action={{ label: "Open calendar", onClick: () => onNavigate("life", "week", "Week") }}
        reduceMotion={reduceMotion}
      />

      <div
        className="flex flex-col sm:flex-row"
        style={{ borderTop: "1px solid var(--registrar-rule)", borderBottom: "1px solid var(--registrar-rule)" }}
      >
        <LedgerStat
          label="Events"
          value={String(events.length)}
          hint="this week"
          onClick={() => onNavigate("life", "week", "Week")}
        />
        <LedgerStat
          label="Deadlines"
          value={String(openWeekTasks.length)}
          hint={openWeekTasks.length === 1 ? "due" : "due"}
          onClick={() => onNavigate("life", "tasks", "Tasks")}
        />
        <LedgerStat
          label="Today"
          value={String(todayItemCount)}
          hint={todayItemCount === 1 ? "item" : "items"}
          onClick={() => onNavigate("life", "day", "Day")}
        />
        <LedgerStat
          label="Days"
          value="7"
          hint="in view"
          onClick={() => onNavigate("life", "week", "Week")}
          last
        />
      </div>

      <RegistrarSection title="By day" actionLabel="Full calendar" onAction={() => onNavigate("life", "week", "Week")}>
        <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
          {daysOfWeek.map((day, dayIdx) => {
            const dayEvents = events.filter((e) => {
              const evDate = new Date(e.startAt);
              return (
                evDate.getFullYear() === day.date.getFullYear() &&
                evDate.getMonth() === day.date.getMonth() &&
                evDate.getDate() === day.date.getDate()
              );
            });

            const dayTasks = openWeekTasks.filter((t) => {
              const tDate = new Date(t.dueAt!);
              return (
                tDate.getFullYear() === day.date.getFullYear() &&
                tDate.getMonth() === day.date.getMonth() &&
                tDate.getDate() === day.date.getDate()
              );
            });

            const isLastDay = dayIdx === daysOfWeek.length - 1;
            const dayEmpty = dayEvents.length === 0 && dayTasks.length === 0;

            return (
              <div key={day.dateStr}>
                <div
                  className="px-0 py-2.5 text-[12px] font-semibold uppercase tracking-[0.06em]"
                  style={{
                    fontFamily: "var(--font-mono)",
                    color: day.isToday ? "var(--registrar-accent)" : "var(--color-text-light)",
                    borderBottom: "1px solid var(--registrar-rule)",
                  }}
                >
                  {day.label}
                  {day.isToday ? " · today" : ""}
                </div>

                {dayEmpty ? (
                  <p className="py-2.5 text-caption text-[var(--color-text-light)]">Nothing scheduled</p>
                ) : (
                  <>
                    {dayEvents.map((ev) => {
                      const start = new Date(ev.startAt);
                      const timeStr = start.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
                      return (
                        <div
                          key={ev.occurrenceId}
                          className="flex items-baseline gap-4 py-2.5"
                          style={{ borderBottom: "1px solid var(--registrar-rule)" }}
                        >
                          <div
                            className="w-20 shrink-0 text-[12px] tabular-nums"
                            style={{ fontFamily: "var(--font-mono)", color: "var(--registrar-ink)" }}
                          >
                            {timeStr}
                          </div>
                          <p className="min-w-0 flex-1 truncate text-body font-medium" style={{ color: "var(--registrar-ink)" }}>
                            {ev.title}
                          </p>
                        </div>
                      );
                    })}
                    {dayTasks.map((t) => (
                      <div
                        key={t.id}
                        className="flex items-start gap-3 py-2.5"
                        style={{ borderBottom: "1px solid var(--registrar-rule)" }}
                      >
                        <input
                          type="checkbox"
                          checked={t.isComplete}
                          onChange={() => onToggleTask(t.id, t.isComplete)}
                          className="mt-1 h-3.5 w-3.5 shrink-0 rounded-none border-[var(--registrar-rule)] text-[var(--registrar-accent)] focus:ring-0"
                          title="Mark complete"
                        />
                        <p className="min-w-0 flex-1 truncate text-body font-medium" style={{ color: "var(--registrar-ink)" }}>
                          {t.title}
                        </p>
                      </div>
                    ))}
                  </>
                )}

                {isLastDay && dayEmpty && (
                  <div style={{ borderBottom: "1px solid var(--registrar-rule)" }} />
                )}
              </div>
            );
          })}
        </div>
      </RegistrarSection>
    </div>
  );
}

/* =========================================================================
   3. GOALS VIEW
   ========================================================================= */

function HomeGoalsView({
  audit,
  gpa,
  pipeline,
  finance,
  goalSettings,
  onNavigate,
}: {
  audit: AuditSummary | null;
  gpa: GpaSummary | null;
  pipeline: PipelineMetrics | null;
  finance: FinanceDashboardSummary | null;
  goalSettings: Record<string, string>;
  onNavigate: (hub: ModuleId, page?: string, title?: string) => void;
}) {
  const reduceMotion = useReduceMotion();
  const completedCredits = audit?.completedCredits ?? 0;
  const plannedCredits = audit?.plannedCredits ?? 0;
  const totalRequired =
    audit?.totalRequiredCredits != null && audit.totalRequiredCredits > 0
      ? audit.totalRequiredCredits
      : completedCredits + plannedCredits;
  const creditRatio = totalRequired > 0 ? completedCredits / totalRequired : 0;

  const appGoalRaw = goalSettings["career.appGoal"]?.trim();
  const parsedAppGoal = appGoalRaw ? Number.parseInt(appGoalRaw, 10) : NaN;
  const appGoal = Number.isFinite(parsedAppGoal) && parsedAppGoal > 0 ? parsedAppGoal : null;
  const currentApps = pipeline?.total ?? 0;

  const gpaTargetRaw = goalSettings["academics.gpaTarget"]?.trim();
  const gpaTarget = gpaTargetRaw ? Number.parseFloat(gpaTargetRaw) : null;
  const gpaTargetLabel =
    goalSettings["academics.gpaTargetLabel"]?.trim() ||
    (gpaTarget != null && !Number.isNaN(gpaTarget) ? `Target ${gpaTarget.toFixed(2)}` : null);

  const creditPct = totalRequired > 0 ? `${(creditRatio * 100).toFixed(0)}%` : "—";
  const heroHeading =
    totalRequired > 0
      ? `${creditPct} toward degree`
      : gpa?.gpa != null
        ? `${gpa.gpa.toFixed(2)} cumulative GPA`
        : "Set your semester targets";

  const netWorthLabel =
    finance?.netWorth != null
      ? finance.netWorth.toLocaleString(undefined, { style: "currency", currency: "USD" })
      : "—";

  return (
    <div className="space-y-10">
      <RegistrarHeroBlock
        eyebrow="Semester goals"
        heading={heroHeading}
        meta={
          gpaTargetLabel ??
          (appGoal != null ? `${currentApps} of ${appGoal} applications` : null)
        }
        action={{ label: "Open degree audit", onClick: () => onNavigate("school", "degree", "Degree") }}
        reduceMotion={reduceMotion}
      />

      <div
        className="flex flex-col sm:flex-row"
        style={{ borderTop: "1px solid var(--registrar-rule)", borderBottom: "1px solid var(--registrar-rule)" }}
      >
        <LedgerStat
          label="Credits"
          value={creditPct}
          hint={totalRequired > 0 ? `${completedCredits.toFixed(0)} / ${totalRequired.toFixed(0)}` : undefined}
          onClick={() => onNavigate("school", "degree", "Degree")}
        />
        <LedgerStat
          label="GPA"
          value={gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"}
          hint={gpaTargetLabel ?? undefined}
          onClick={() => onNavigate("school", "plan", "Plan")}
        />
        <LedgerStat
          label="Applications"
          value={String(currentApps)}
          hint={pipeline?.interviewing ? `${pipeline.interviewing} interviewing` : "tracked"}
          onClick={() => onNavigate("career", "pipeline", "Applications")}
        />
        <LedgerStat
          label="Net worth"
          value={netWorthLabel}
          hint={finance?.accountCount ? `${finance.accountCount} accounts` : undefined}
          onClick={() => onNavigate("life", "money", "Money")}
          last
        />
      </div>

      <div className="grid grid-cols-1 gap-10 lg:grid-cols-2">
        <RegistrarSection title="Degree progress" actionLabel="Degree audit" onAction={() => onNavigate("school", "degree", "Degree")}>
          <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
            <RegistrarMetricRow
              label="Credits completed"
              value={completedCredits.toFixed(1)}
              hint={totalRequired > 0 ? `of ${totalRequired.toFixed(0)} required` : undefined}
            />
            <RegistrarMetricRow
              label="Cumulative GPA"
              value={gpa?.gpa != null ? gpa.gpa.toFixed(2) : "—"}
              hint={gpaTargetLabel ?? undefined}
            />
            <RegistrarMetricRow
              label="Courses completed"
              value={String(audit?.courseCount ?? 0)}
              hint="in planner"
              last
            />
          </div>
        </RegistrarSection>

        <RegistrarSection title="Career pipeline" actionLabel="Open pipeline" onAction={() => onNavigate("career", "pipeline", "Applications")}>
          <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
            <RegistrarMetricRow
              label="Applications tracked"
              value={String(currentApps)}
              hint={appGoal != null ? `goal: ${appGoal}` : undefined}
            />
            <RegistrarMetricRow label="Applied" value={String(pipeline?.applied ?? 0)} />
            <RegistrarMetricRow label="Interviewing" value={String(pipeline?.interviewing ?? 0)} />
            <RegistrarMetricRow label="Offers" value={String(pipeline?.offer ?? 0)} last />
          </div>
        </RegistrarSection>

        <RegistrarSection title="Finances" actionLabel="View finances" onAction={() => onNavigate("life", "money", "Money")}>
          <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
            <RegistrarMetricRow label="Net worth" value={netWorthLabel} />
            <RegistrarMetricRow
              label="Transactions"
              value={String(finance?.transactionCount ?? 0)}
              hint={finance?.accountCount ? `${finance.accountCount} accounts` : undefined}
              last
            />
          </div>
        </RegistrarSection>

        <RegistrarSection title="Portfolio">
          <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
            <JumpRow label="Files" hint="Syllabi & documents" onClick={() => onNavigate("library", "all", "All files")} />
            <JumpRow label="Resume builder" hint="Career" onClick={() => onNavigate("career", "resume", "Resumes")} />
            <JumpRow label="Portfolio" hint="Verified record" onClick={() => onNavigate("library", "portfolio", "Portfolio")} last />
          </div>
        </RegistrarSection>
      </div>
    </div>
  );
}

/* =========================================================================
   4. RECENTS VIEW
   ========================================================================= */

function HomeRecentsView({
  recents,
  vaultDocs,
  onNavigate,
  onClearRecents,
}: {
  recents: ShellRecent[];
  vaultDocs: VaultDoc[];
  onNavigate: (hub: ModuleId, page?: string, title?: string) => void;
  onClearRecents?: () => void;
}) {
  const reduceMotion = useReduceMotion();
  const lastRecent = recents[0] ?? null;
  const recentDocs = vaultDocs.slice(0, 6);

  return (
    <div className="space-y-10">
      <RegistrarHeroBlock
        eyebrow="Recents"
        heading={lastRecent ? lastRecent.title || lastRecent.page : "Pick up where you left off"}
        meta={lastRecent ? `${lastRecent.module} hub` : "Your navigation history lives here"}
        action={
          lastRecent
            ? {
                label: "Go back",
                onClick: () => onNavigate(lastRecent.module, lastRecent.page, lastRecent.title),
              }
            : null
        }
        reduceMotion={reduceMotion}
      />

      <div
        className="flex flex-col sm:flex-row"
        style={{ borderTop: "1px solid var(--registrar-rule)", borderBottom: "1px solid var(--registrar-rule)" }}
      >
        <LedgerStat
          label="Screens"
          value={String(recents.length)}
          hint={recents.length === 1 ? "visited" : "visited"}
          onClick={() => recents[0] && onNavigate(recents[0].module, recents[0].page, recents[0].title)}
        />
        <LedgerStat
          label="Documents"
          value={String(vaultDocs.length)}
          hint={vaultDocs.length === 1 ? "file" : "files"}
          onClick={() => onNavigate("library", "all", "All files")}
        />
        <LedgerStat
          label="Last hub"
          value={lastRecent?.module ?? "—"}
          hint={lastRecent?.page}
          onClick={() => lastRecent && onNavigate(lastRecent.module, lastRecent.page, lastRecent.title)}
        />
        <LedgerStat
          label="Updated"
          value={
            recentDocs[0]
              ? new Date(recentDocs[0].updatedAt).toLocaleDateString(undefined, { month: "short", day: "numeric" })
              : "—"
          }
          hint="latest file"
          onClick={() => onNavigate("library", "all", "All files")}
          last
        />
      </div>

      <RegistrarSection
        title="Recent screens"
        actionLabel={recents.length > 0 && onClearRecents ? "Clear" : undefined}
        onAction={onClearRecents}
      >
        {recents.length === 0 ? (
          <EmptyState
            title="No recent pages"
            body="Pages you visit will show up here — School, Career, Life, and Library."
          />
        ) : (
          <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
            {recents.map((item, idx) => (
              <JumpRow
                key={`${item.module}-${item.page}-${idx}`}
                label={item.title || item.page}
                hint={`${item.module} hub`}
                onClick={() => onNavigate(item.module, item.page, item.title)}
                last={idx === recents.length - 1}
              />
            ))}
          </div>
        )}
      </RegistrarSection>

      <RegistrarSection title="Recent files" actionLabel="All files" onAction={() => onNavigate("library", "all", "All files")}>
        {recentDocs.length === 0 ? (
          <p className="text-body text-[var(--color-text-light)]">No documents uploaded yet.</p>
        ) : (
          <div style={{ borderTop: "1px solid var(--registrar-rule)" }}>
            {recentDocs.map((doc, idx) => (
              <JumpRow
                key={doc.id}
                label={doc.title}
                hint={`${doc.category || "General"} · ${new Date(doc.updatedAt).toLocaleDateString()}`}
                onClick={() => onNavigate("library", "all", "All files")}
                last={idx === recentDocs.length - 1}
              />
            ))}
          </div>
        )}
      </RegistrarSection>
    </div>
  );
}
