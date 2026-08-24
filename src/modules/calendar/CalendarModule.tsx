import { useCallback, useEffect, useMemo, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  ModalSheet,
  MonthGrid,
  SegmentedPills,
  StatusChip,
  TrailingInspector,
  WeekGrid,
  DayTimeline,
  dateKey,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";
import {
  dayVisibleRange,
  expandRecurringEvents,
  monthVisibleRange,
  weekVisibleRange,
  type CalendarEventOccurrence,
} from "./expandRecurring";
import { EVENT_COLOR_PRESETS, resolveEventColor } from "./eventColors";
import {
  appleMapsUrl,
  embedGeocodeInNotes,
  googleMapsUrl,
  openStreetMapUrl,
  parseGeocodeFromNotes,
  type GeocodeResult,
} from "./locationGeocode";
import { EventLocationMap } from "./EventLocationMap";

type CalSource = {
  id: string;
  name: string;
  color: string;
  icsUrl: string;
  lastSyncedAt?: string | null;
  isEnabled: boolean;
  sortOrder: number;
};

type CalEvent = {
  id: string;
  title: string;
  startAt: string;
  endAt?: string;
  location: string;
  notes?: string;
  provider: string;
  color?: string;
  recurrence?: string;
  sourceId?: string | null;
};

type CalTask = {
  id: string;
  title: string;
  dueAt?: string;
  isComplete: boolean;
};

function toLocalInput(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return new Date().toISOString().slice(0, 16);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function CalendarModule({ page = "month" }: { page?: string }) {
  const sourceFilterId = page.startsWith("source-") ? page.slice(7) : null;
  const view =
    page === "tasks"
      ? "tasks"
      : sourceFilterId
        ? "month"
        : page === "agenda"
        ? "agenda"
        : page === "week"
          ? "week"
          : page === "day"
            ? "day"
            : "month";
  const [events, setEvents] = useState<CalEvent[]>([]);
  const [sources, setSources] = useState<CalSource[]>([]);
  const [tasks, setTasks] = useState<CalTask[]>([]);
  const [cursor, setCursor] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });
  const [weekAnchor, setWeekAnchor] = useState(() => new Date());
  const [dayCursor, setDayCursor] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  });
  const [selectedDay, setSelectedDay] = useState<Date | null>(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  });
  const [agendaFilter, setAgendaFilter] = useState<"upcoming" | "all">("upcoming");
  const [eventSheet, setEventSheet] = useState(false);
  const [taskSheet, setTaskSheet] = useState(false);
  const [icsSheet, setIcsSheet] = useState(false);
  const [calendarsSheet, setCalendarsSheet] = useState(false);
  const [editingSourceId, setEditingSourceId] = useState<string | null>(null);
  const [showSourceForm, setShowSourceForm] = useState(false);
  const [sourceForm, setSourceForm] = useState({
    name: "",
    color: "blue",
    icsUrl: "",
    isEnabled: true,
  });
  const [sourceSyncNote, setSourceSyncNote] = useState<string | null>(null);
  const [oauthStatus, setOauthStatus] = useState<{
    accounts: Array<{
      id: string;
      provider: string;
      accountEmail: string;
      sourceId?: string | null;
      lastSyncedAt?: string | null;
    }>;
    googleConfigured: boolean;
    outlookConfigured: boolean;
  } | null>(null);
  const [oauthBusy, setOauthBusy] = useState<string | null>(null);
  const [appleFeed, setAppleFeed] = useState<{
    path: string;
    eventCount: number;
    writtenAt: string;
  } | null>(null);
  const [appleFeedBusy, setAppleFeedBusy] = useState(false);
  const [icsText, setIcsText] = useState("");
  const [icsNote, setIcsNote] = useState<string | null>(null);
  const [editingEventId, setEditingEventId] = useState<string | null>(null);
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);
  const [eventForm, setEventForm] = useState({
    title: "",
    startAt: new Date().toISOString().slice(0, 16),
    location: "",
    color: "",
    recurrence: "none" as "none" | "weekly" | "monthly",
    notes: "",
    geocode: null as GeocodeResult | null,
  });
  const [geocodeBusy, setGeocodeBusy] = useState(false);
  const [taskForm, setTaskForm] = useState({
    title: "",
    dueAt: toLocalInput(new Date(Date.now() + 86400000 * 3).toISOString()),
  });
  const [focusBlocks, setFocusBlocks] = useState<
    Array<{ id: string; title: string; durationMinutes: number; sortOrder: number }>
  >([]);
  const [focusDraft, setFocusDraft] = useState({ title: "", durationMinutes: 45 });

  const load = useCallback(async () => {
    const [e, t, s, oauth, blocks] = await Promise.all([
      ipc.calendarListEvents(),
      ipc.calendarListTasks(),
      ipc.calendarListSources(),
      ipc.calendarOauthStatus(),
      ipc.calendarListFocusBlocks().catch(() => []),
    ]);
    setEvents(e);
    setTasks(t);
    setSources(s);
    setOauthStatus(oauth);
    setFocusBlocks(blocks);
  }, []);

  const { refresh, error } = useLiveQuery(load, ["calendar", "planner"]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const status = await ipc.calendarOauthStatus();
        if (cancelled || !status.accounts.length) return;
        const staleMs = 6 * 60 * 60 * 1000;
        const now = Date.now();
        const needsSync = status.accounts.some((a) => {
          if (!a.lastSyncedAt) return true;
          const t = Date.parse(a.lastSyncedAt);
          return Number.isNaN(t) || now - t > staleMs;
        });
        if (!needsSync) return;
        const res = await ipc.calendarOauthSyncAll();
        if (cancelled) return;
        if (res.imported > 0) {
          setSourceSyncNote(
            `Background sync: ${res.imported} cloud event${res.imported === 1 ? "" : "s"} updated.`,
          );
          await refresh();
        }
      } catch {
        /* optional background sync */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [refresh]);

  const sourceById = useMemo(() => new Map(sources.map((s) => [s.id, s])), [sources]);

  const enabledSourceIds = useMemo(
    () => new Set(sources.filter((s) => s.isEnabled).map((s) => s.id)),
    [sources],
  );

  const resolveDisplayColor = useCallback(
    (event: CalEvent | CalendarEventOccurrence) => {
      if (event.color) return resolveEventColor(event.color);
      const sourceId = "sourceId" in event ? event.sourceId : undefined;
      if (sourceId) {
        const source = sourceById.get(sourceId);
        if (source?.color) return resolveEventColor(source.color);
      }
      return undefined;
    },
    [sourceById],
  );

  const visibleEvents = useMemo(() => {
    let list = events;
    if (sourceFilterId) {
      list = list.filter((e) => e.sourceId === sourceFilterId);
    } else if (enabledSourceIds.size > 0) {
      list = list.filter((e) => !e.sourceId || enabledSourceIds.has(e.sourceId));
    }
    return list;
  }, [events, enabledSourceIds, sourceFilterId]);

  const visibleRange = useMemo((): [Date, Date] => {
    if (view === "week") return weekVisibleRange(weekAnchor);
    if (view === "day") return dayVisibleRange(dayCursor);
    if (view === "month") return monthVisibleRange(cursor);
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(start);
    end.setFullYear(end.getFullYear() + 1);
    return [start, end];
  }, [view, cursor, weekAnchor, dayCursor]);

  const displayEvents = useMemo(
    () => expandRecurringEvents(visibleEvents, visibleRange[0], visibleRange[1]),
    [visibleEvents, visibleRange],
  );

  const eventById = useMemo(() => new Map(visibleEvents.map((e) => [e.id, e])), [visibleEvents]);

  const countsByDay = useMemo(() => {
    const map = new Map<string, number>();
    for (const e of displayEvents) {
      const key = dateKey(new Date(e.startAt));
      map.set(key, (map.get(key) ?? 0) + 1);
    }
    for (const t of tasks) {
      if (!t.dueAt) continue;
      const key = dateKey(new Date(t.dueAt));
      map.set(key, (map.get(key) ?? 0) + 1);
    }
    return map;
  }, [displayEvents, tasks]);

  const labelsByDay = useMemo(() => {
    const map = new Map<string, Array<{ title: string; color?: string }>>();
    for (const e of displayEvents) {
      const key = dateKey(new Date(e.startAt));
      const list = map.get(key) ?? [];
      if (list.length < 2) {
        list.push({
          title: e.title,
          color: resolveDisplayColor(e),
        });
      }
      map.set(key, list);
    }
    return map;
  }, [displayEvents, resolveDisplayColor]);

  const eventsByDay = useMemo(() => {
    const map = new Map<
      string,
      Array<{ id: string; title: string; startAt: string; color?: string }>
    >();
    for (const e of displayEvents) {
      const key = dateKey(new Date(e.startAt));
      const list = map.get(key) ?? [];
      list.push({
        id: e.occurrenceId,
        title: e.title,
        startAt: e.startAt,
        color: resolveDisplayColor(e),
      });
      map.set(key, list);
    }
    for (const [, list] of map) {
      list.sort((a, b) => a.startAt.localeCompare(b.startAt));
    }
    return map;
  }, [displayEvents, resolveDisplayColor]);

  const dayEvents = useMemo(() => {
    if (!selectedDay) return [];
    const key = dateKey(selectedDay);
    return displayEvents
      .filter((e) => dateKey(new Date(e.startAt)) === key)
      .sort((a, b) => a.startAt.localeCompare(b.startAt));
  }, [displayEvents, selectedDay]);

  const dayTasks = useMemo(() => {
    if (!selectedDay) return [];
    const key = dateKey(selectedDay);
    return tasks.filter((t) => t.dueAt && dateKey(new Date(t.dueAt)) === key);
  }, [tasks, selectedDay]);

  const agendaEvents = useMemo(() => {
    const sorted = [...visibleEvents].sort((a, b) => a.startAt.localeCompare(b.startAt));
    if (agendaFilter === "all") return sorted;
    const now = Date.now();
    return sorted.filter((e) => new Date(e.startAt).getTime() >= now - 3600_000);
  }, [visibleEvents, agendaFilter]);

  const openAddSource = () => {
    setEditingSourceId(null);
    setSourceForm({ name: "", color: "blue", icsUrl: "", isEnabled: true });
    setSourceSyncNote(null);
    setShowSourceForm(true);
    setCalendarsSheet(true);
  };

  const openEditSource = (source: CalSource) => {
    setEditingSourceId(source.id);
    setSourceForm({
      name: source.name,
      color: source.color || "blue",
      icsUrl: source.icsUrl,
      isEnabled: source.isEnabled,
    });
    setSourceSyncNote(null);
    setShowSourceForm(true);
    setCalendarsSheet(true);
  };

  const toggleSourceEnabled = async (source: CalSource) => {
    try {
      await ipc.calendarUpsertSource({
        id: source.id,
        name: source.name,
        color: source.color,
        icsUrl: source.icsUrl,
        isEnabled: !source.isEnabled,
      });
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const oauthAccountFor = (provider: "google" | "outlook") =>
    oauthStatus?.accounts.find((a) => a.provider === provider);

  const connectOAuth = async (provider: "google" | "outlook") => {
    setOauthBusy(provider);
    try {
      const begin = await ipc.calendarOauthBegin(provider);
      showToast(`Waiting for ${provider} sign-in in your browser…`, "success");
      await openUrl(begin.authUrl);
      const account = await ipc.calendarOauthComplete(begin.state);
      showToast(`Connected ${account.accountEmail || provider}`, "success");
      const sync = await ipc.calendarOauthSync({ provider });
      setSourceSyncNote(`Synced ${sync.imported} events from ${provider}.`);
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setOauthBusy(null);
    }
  };

  const syncOAuth = async (provider: "google" | "outlook", accountId: string) => {
    setOauthBusy(`sync-${provider}`);
    try {
      const res = await ipc.calendarOauthSync({ accountId });
      setSourceSyncNote(`Synced ${res.imported} events from ${provider}.`);
      showToast(`Synced ${res.imported} events`, "success");
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setOauthBusy(null);
    }
  };

  const syncAllOAuth = async () => {
    if (!oauthStatus?.accounts.length) return;
    setOauthBusy("sync-all");
    try {
      const res = await ipc.calendarOauthSyncAll();
      const errNote = res.errors.length ? ` (${res.errors.length} error${res.errors.length === 1 ? "" : "s"})` : "";
      setSourceSyncNote(
        `Synced ${res.imported} events across ${res.accounts} account${res.accounts === 1 ? "" : "s"}${errNote}.`,
      );
      showToast(
        res.errors.length
          ? `Synced ${res.imported} events; ${res.errors[0]}`
          : `Synced ${res.imported} events from ${res.accounts} account(s)`,
        res.errors.length ? "error" : "success",
      );
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setOauthBusy(null);
    }
  };

  const pushLocalOAuth = async () => {
    if (!oauthStatus?.accounts.length) return;
    setOauthBusy("push-all");
    try {
      let pushed = 0;
      let skipped = 0;
      const errors: string[] = [];
      for (const account of oauthStatus.accounts) {
        const res = await ipc.calendarOauthPushLocal({ accountId: account.id });
        pushed += res.pushed;
        skipped += res.skipped;
        errors.push(...res.errors);
      }
      setSourceSyncNote(
        `Pushed ${pushed} local event(s) to cloud${skipped ? ` · ${skipped} skipped` : ""}.`,
      );
      showToast(
        errors.length
          ? `Pushed ${pushed}; ${errors[0]}`
          : `Pushed ${pushed} local event(s) to Google/Outlook`,
        errors.length ? "error" : "success",
      );
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setOauthBusy(null);
    }
  };

  const disconnectOAuth = async (accountId: string, label: string) => {

    if (!confirmDelete(`${label} connection`)) return;
    setOauthBusy(`disconnect-${accountId}`);
    try {
      await ipc.calendarOauthDisconnect(accountId);
      showToast(`Disconnected ${label}`, "success");
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setOauthBusy(null);
    }
  };

  const publishAppleFeed = async () => {
    setAppleFeedBusy(true);
    try {
      const result = await ipc.calendarPublishSubscribeFeed();
      setAppleFeed(result);
      showToast(`Published ${result.eventCount} events to subscribe feed`, "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setAppleFeedBusy(false);
    }
  };

  const openAppleCalendar = async () => {
    setAppleFeedBusy(true);
    try {
      const result = await ipc.calendarOpenAppleCalendarFeed();
      setAppleFeed(result);
      showToast("Opened Calendar.app with College feed", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setAppleFeedBusy(false);
    }
  };

  const watchPublishedFeed = async () => {
    setAppleFeedBusy(true);
    try {
      const result = await ipc.platformSyncPublishedCalendarFeed();
      setSourceSyncNote(
        `Watched feed: imported ${result.imported}, skipped ${result.skipped}.`,
      );
      showToast(`Imported ${result.imported} events from published feed`, "success");
      await refresh();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setAppleFeedBusy(false);
    }
  };

  const openAddEventForDay = () => {
    const base = selectedDay ?? new Date();
    const local = new Date(base);
    local.setHours(9, 0, 0, 0);
    const isoLocal = new Date(local.getTime() - local.getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16);
    setEditingEventId(null);
    setEventForm({
      title: "",
      startAt: isoLocal,
      location: "",
      color: "",
      recurrence: "none",
      notes: "",
      geocode: null,
    });
    setEventSheet(true);
  };

  const openEditEvent = (e: CalendarEventOccurrence | CalEvent) => {
    const baseId = "baseId" in e ? e.baseId : e.id;
    const base = eventById.get(baseId) ?? e;
    const notes = "notes" in base ? base.notes ?? "" : "";
    const { geocode, userNotes } = parseGeocodeFromNotes(notes);
    setEditingEventId(baseId);
    setEventForm({
      title: base.title,
      startAt: toLocalInput(base.startAt),
      location: base.location || "",
      color: base.color || "",
      recurrence: (base.recurrence as "none" | "weekly" | "monthly") || "none",
      notes: userNotes,
      geocode,
    });
    setEventSheet(true);
  };

  const openAddTask = () => {
    setEditingTaskId(null);
    setTaskForm({
      title: "",
      dueAt: toLocalInput(new Date(Date.now() + 86400000 * 3).toISOString()),
    });
    setTaskSheet(true);
  };

  const openEditTask = (t: CalTask) => {
    setEditingTaskId(t.id);
    setTaskForm({
      title: t.title,
      dueAt: t.dueAt
        ? toLocalInput(t.dueAt)
        : toLocalInput(new Date(Date.now() + 86400000).toISOString()),
    });
    setTaskSheet(true);
  };

  useEffect(() => {
    const onQuick = (ev: Event) => {
      const kind = (ev as CustomEvent<{ kind?: string }>).detail?.kind;
      if (kind === "task") openAddTask();
      if (kind === "event") openAddEventForDay();
    };
    window.addEventListener("college:quick-add", onQuick);
    return () => window.removeEventListener("college:quick-add", onQuick);
  }, []);

  const dayInspector = selectedDay ? (
    <div className="flex h-full flex-col">
      <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
        <h3
          className="text-[var(--color-text-main)]"
          style={{ font: "var(--type-section-title)", fontSize: 15, letterSpacing: "-0.015em" }}
        >
          {selectedDay.toLocaleDateString(undefined, {
            weekday: "long",
            month: "long",
            day: "numeric",
          })}
        </h3>
        <p className="mt-0.5 text-[11px] text-[var(--color-text-light)]">
          {dayEvents.length} event{dayEvents.length === 1 ? "" : "s"} · {dayTasks.length} task
          {dayTasks.length === 1 ? "" : "s"}
        </p>
      </div>
      <div className="min-h-0 flex-1 space-y-4 overflow-auto p-4">
      <div>
        <div className="mb-1.5 text-[10px] font-semibold uppercase tracking-[0.07em] text-[var(--color-text-light)]">
          Events
        </div>
        {dayEvents.length === 0 ? (
          <p className="text-[12px] text-[var(--color-text-light)]">Nothing scheduled.</p>
        ) : (
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {dayEvents.map((e) => (
              <li key={e.occurrenceId}>
                <ListRow
                  title={e.title}
                  subtitle={`${new Date(e.startAt).toLocaleTimeString(undefined, {
                    hour: "numeric",
                    minute: "2-digit",
                  })}${e.location ? ` · ${e.location}` : ""}`}
                  onClick={() => openEditEvent(e)}
                />
              </li>
            ))}
          </ul>
        )}
      </div>
      {dayTasks.length > 0 && (
        <div>
          <div className="mb-1.5 text-[10px] font-semibold uppercase tracking-[0.07em] text-[var(--color-text-light)]">
            Tasks due
          </div>
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {dayTasks.map((t) => (
              <li key={t.id}>
                <ListRow
                  title={t.title}
                  trailing={t.isComplete ? "Done" : "Open"}
                  onClick={() => openEditTask(t)}
                />
              </li>
            ))}
          </ul>
        </div>
      )}
      </div>
      <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
        <Button size="sm" onClick={openAddEventForDay}>
          Add event
        </Button>
        {dayEvents[0] && (
          <Button size="sm" variant="secondary" onClick={() => openEditEvent(dayEvents[0]!)}>
            Edit first
          </Button>
        )}
        {dayEvents[0] && (
          <Button
            size="sm"
            variant="danger"
            onClick={async () => {
              const ev = dayEvents[0]!;
              if (!confirmDelete(ev.title || "event")) return;
              try {
                await ipc.calendarDeleteEvent(ev.baseId);
                showToast("Event deleted", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Delete first
          </Button>
        )}
        <Button size="sm" variant="ghost" onClick={() => setSelectedDay(null)}>
          Close
        </Button>
      </div>
    </div>
  ) : null;

  const title =
    view === "month"
      ? "Month"
      : view === "week"
        ? "Week"
        : view === "day"
          ? "Day"
          : view === "agenda"
            ? "Agenda"
            : "Tasks";

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={title}
        leading={
          view === "agenda" ? (
            <SegmentedPills
              value={agendaFilter}
              onChange={setAgendaFilter}
              options={[
                { id: "upcoming", label: "Upcoming" },
                { id: "all", label: "All" },
              ]}
            />
          ) : undefined
        }
        actions={
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                setSourceSyncNote(null);
                setCalendarsSheet(true);
              }}
            >
              Calendars
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setIcsSheet(true)}>
              Import ICS
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={async () => {
                try {
                  const picked = await save({
                    title: "Export calendar",
                    defaultPath: "college-calendar.ics",
                    filters: [{ name: "iCalendar", extensions: ["ics"] }],
                  });
                  if (!picked) return;
                  const res = await ipc.calendarExportIcsPath(picked);
                  setIcsNote(`Exported ${res.eventCount} events to ${res.path}`);
                  setIcsSheet(true);
                } catch (e) {
                  setIcsNote(formatIpcError(e));
                  setIcsSheet(true);
                }
              }}
            >
              Export ICS
            </Button>
            {view === "tasks" ? (
              <Button size="sm" onClick={openAddTask}>
                Add task
              </Button>
            ) : (
              <Button size="sm" onClick={openAddEventForDay}>
                Add event
              </Button>
            )}
          </div>
        }
      />
      {error && <p className="px-3 text-[12px] text-[var(--color-error)]">{error}</p>}

      {sources.length > 0 && view !== "tasks" && (
        <div className="flex flex-wrap items-center gap-2 px-3 pb-2">
          <span className="text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--color-text-light)]">
            Calendars
          </span>
          {sources.map((source) => {
            const swatch = resolveEventColor(source.color);
            return (
              <button
                key={source.id}
                type="button"
                title={source.isEnabled ? `Hide ${source.name}` : `Show ${source.name}`}
                onClick={() => void toggleSourceEnabled(source)}
                className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium transition-colors ${
                  source.isEnabled
                    ? "border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] text-[var(--color-text-main)]"
                    : "border-[var(--color-chrome-stroke)] bg-transparent text-[var(--color-text-light)] opacity-60"
                }`}
              >
                <span
                  className={`h-2.5 w-2.5 shrink-0 rounded-full border ${
                    source.isEnabled ? "border-transparent" : "border-[var(--color-chrome-stroke)]"
                  }`}
                  style={
                    swatch
                      ? { backgroundColor: swatch }
                      : { background: "var(--color-primary-soft)" }
                  }
                />
                {source.name}
              </button>
            );
          })}
          <button
            type="button"
            className="rounded-full border border-dashed border-[var(--color-chrome-stroke)] px-2.5 py-1 text-[11px] font-medium text-[var(--color-text-light)] transition-colors hover:bg-[var(--color-row-hover)] hover:text-[var(--color-text-main)]"
            onClick={() => {
              setSourceSyncNote(null);
              setCalendarsSheet(true);
            }}
          >
            Manage…
          </button>
        </div>
      )}

      <div className="min-h-0 flex-1 overflow-hidden px-3 pb-3">
        {view === "month" && (
          <TrailingInspector
            open={!!selectedDay}
            main={
              <div className="h-full p-3">
              <MonthGrid
                cursor={cursor}
                selected={selectedDay}
                countsByDay={countsByDay}
                labelsByDay={labelsByDay}
                onCursorChange={setCursor}
                onSelectDay={setSelectedDay}
              />
              </div>
            }
          >
            {dayInspector}
          </TrailingInspector>
        )}

        {view === "week" && (
          <TrailingInspector
            open={!!selectedDay}
            main={
              <div className="h-full p-3">
              <WeekGrid
                anchor={weekAnchor}
                selected={selectedDay}
                eventsByDay={eventsByDay}
                onAnchorChange={setWeekAnchor}
                onSelectDay={setSelectedDay}
              />
              </div>
            }
          >
            {dayInspector}
          </TrailingInspector>
        )}

        {view === "day" && (
          <div className="min-h-0 flex-1 p-3">
            <DayTimeline
              day={dayCursor}
              items={[
                ...expandRecurringEvents(visibleEvents, ...dayVisibleRange(dayCursor)).map((e) => ({
                  id: e.occurrenceId,
                  title: e.title,
                  startAt: e.startAt,
                  location: e.location,
                  kind: "event" as const,
                  color: resolveDisplayColor(e),
                })),
                ...tasks
                  .filter((t) => t.dueAt)
                  .map((t) => ({
                    id: t.id,
                    title: t.title,
                    startAt: t.dueAt!,
                    kind: "task" as const,
                  })),
              ]}
              onPrev={() => {
                const d = new Date(dayCursor);
                d.setDate(d.getDate() - 1);
                setDayCursor(d);
              }}
              onNext={() => {
                const d = new Date(dayCursor);
                d.setDate(d.getDate() + 1);
                setDayCursor(d);
              }}
              onToday={() => {
                const now = new Date();
                setDayCursor(new Date(now.getFullYear(), now.getMonth(), now.getDate()));
              }}
            />
          </div>
        )}

        {view === "agenda" && (
          <AppCard title="Schedule">
            {agendaEvents.length === 0 ? (
              <EmptyState title="No events" body="Add a local event to get started." />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {agendaEvents.map((e) => (
                  <li key={e.id}>
                    <ListRow
                      title={e.title}
                      subtitle={`${new Date(e.startAt).toLocaleString()} · ${e.provider}${
                        e.location ? ` · ${e.location}` : ""
                      }`}
                      onClick={() => openEditEvent(e)}
                    />
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        )}

        {view === "tasks" && (
          <>
            <AppCard title="Study focus">
              <p className="mb-3 text-[12px] text-[var(--color-text-light)]">
                Saved focus blocks persist across sessions (Swift parity). Suggestions from open
                tasks appear below when you have none saved.
              </p>
              <div className="mb-3 flex flex-wrap gap-2">
                <input
                  className={fieldControlClass}
                  placeholder="Focus title"
                  value={focusDraft.title}
                  onChange={(e) => setFocusDraft((v) => ({ ...v, title: e.target.value }))}
                  style={{ minWidth: 160, flex: 1 }}
                />
                <input
                  type="number"
                  className={fieldControlClass}
                  min={5}
                  max={480}
                  value={focusDraft.durationMinutes}
                  onChange={(e) =>
                    setFocusDraft((v) => ({
                      ...v,
                      durationMinutes: Number(e.target.value) || 45,
                    }))
                  }
                  style={{ width: 72 }}
                />
                <Button
                  size="sm"
                  disabled={!focusDraft.title.trim()}
                  onClick={async () => {
                    try {
                      await ipc.calendarUpsertFocusBlock({
                        title: focusDraft.title.trim(),
                        durationMinutes: focusDraft.durationMinutes,
                      });
                      setFocusDraft({ title: "", durationMinutes: 45 });
                      await refresh();
                      showToast("Focus block saved", "success");
                    } catch (err) {
                      showToast(formatIpcError(err), "error");
                    }
                  }}
                >
                  Save block
                </Button>
              </div>
              {focusBlocks.length === 0 ? (
                <EmptyState
                  title="No saved focus blocks"
                  body="Add a block above, or use suggested sessions from tasks and today's schedule."
                />
              ) : (
                <ul className="mb-3 space-y-2">
                  {focusBlocks.map((b) => (
                    <li
                      key={b.id}
                      className="flex items-center justify-between rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                    >
                      <div>
                        <div className="text-[13px] font-medium">{b.title}</div>
                        <div className="text-[11px] text-[var(--color-text-light)]">
                          {b.durationMinutes} min
                        </div>
                      </div>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={async () => {
                          if (!confirmDelete(b.title)) return;
                          await ipc.calendarDeleteFocusBlock(b.id);
                          await refresh();
                        }}
                      >
                        Delete
                      </Button>
                    </li>
                  ))}
                </ul>
              )}
              {focusBlocks.length === 0 &&
                (() => {
                const open = tasks.filter((t) => !t.isComplete);
                const today = new Date();
                const todayEvents = displayEvents.filter((e) => {
                  const d = new Date(e.startAt);
                  return (
                    d.getFullYear() === today.getFullYear() &&
                    d.getMonth() === today.getMonth() &&
                    d.getDate() === today.getDate()
                  );
                });
                const blocks = [
                  ...open.slice(0, 3).map((t) => ({
                    key: t.id,
                    title: t.title,
                    subtitle: t.dueAt
                      ? `Due ${new Date(t.dueAt).toLocaleDateString()} · 45 min focus`
                      : "45 min focus block",
                    tint: "var(--color-warning)",
                  })),
                  ...todayEvents.slice(0, 2).map((e) => ({
                    key: e.id,
                    title: e.title,
                    subtitle: `${new Date(e.startAt).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })} · review / prep`,
                    tint: "var(--color-primary)",
                  })),
                ];
                if (blocks.length === 0) return null;
                return (
                  <ul className="space-y-2">
                    <li className="text-[11px] font-semibold uppercase text-[var(--color-text-light)]">
                      Suggested
                    </li>
                    {blocks.map((b) => (
                      <li
                        key={b.key}
                        className="flex items-center justify-between rounded-[10px] border border-dashed border-[var(--color-chrome-stroke)] px-3 py-2"
                      >
                        <div className="min-w-0">
                          <div className="truncate text-[13px] font-medium">{b.title}</div>
                          <div className="text-[11px] text-[var(--color-text-light)]">{b.subtitle}</div>
                        </div>
                        <StatusChip title="Suggested" tint={b.tint} />
                      </li>
                    ))}
                  </ul>
                );
              })()}
            </AppCard>
            <AppCard title="Tasks & deadlines">
            {tasks.length === 0 ? (
              <EmptyState title="No tasks" body="Capture due work alongside your calendar." />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {tasks.map((t) => (
                  <li key={t.id} className="flex items-center gap-2">
                    <div className="min-w-0 flex-1">
                      <ListRow
                        leading={
                          <span
                            className={`h-2 w-2 rounded-full ${
                              t.isComplete
                                ? "bg-[var(--color-success)]"
                                : "bg-[var(--color-warning)]"
                            }`}
                          />
                        }
                        title={t.title}
                        subtitle={
                          t.dueAt ? `Due ${new Date(t.dueAt).toLocaleDateString()}` : undefined
                        }
                        trailing={t.isComplete ? "Done" : "Mark done"}
                        onClick={() => void ipc.calendarToggleTaskComplete(t.id)}
                      />
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => openEditTask(t)}
                    >
                      Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        if (!confirmDelete(t.title || "task")) return;
                        void ipc
                          .calendarDeleteTask(t.id)
                          .then(() => showToast("Task deleted", "success"))
                          .catch((e) => showToast(formatIpcError(e), "error"));
                      }}
                    >
                      Delete
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
          </>
        )}
      </div>

      <ModalSheet
        open={eventSheet}
        onOpenChange={setEventSheet}
        title={editingEventId ? "Edit event" : "Add event"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={eventForm.title}
              onChange={(e) => setEventForm({ ...eventForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Starts">
            <input
              className={fieldControlClass}
              type="datetime-local"
              value={eventForm.startAt}
              onChange={(e) => setEventForm({ ...eventForm, startAt: e.target.value })}
            />
          </FormField>
          <FormField label="Location">
            <div className="flex gap-2">
              <input
                className={`${fieldControlClass} min-w-0 flex-1`}
                value={eventForm.location}
                onChange={(e) =>
                  setEventForm({ ...eventForm, location: e.target.value, geocode: null })
                }
              />
              <Button
                type="button"
                size="sm"
                variant="secondary"
                disabled={!eventForm.location.trim() || geocodeBusy}
                onClick={async () => {
                  const query = eventForm.location.trim();
                  if (!query) return;
                  setGeocodeBusy(true);
                  try {
                    const result = await ipc.calendarGeocodeLocation(query);
                    setEventForm((prev) => ({
                      ...prev,
                      geocode: {
                        lat: result.lat,
                        lon: result.lon,
                        displayName: result.displayName,
                      },
                    }));
                    showToast("Location resolved", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  } finally {
                    setGeocodeBusy(false);
                  }
                }}
              >
                {geocodeBusy ? "Looking up…" : "Look up location"}
              </Button>
            </div>
          </FormField>
          {eventForm.location.trim() && (
            <LocationMapPreview
              query={eventForm.location.trim()}
              geocode={eventForm.geocode}
            />
          )}
          <FormField label="Color">
            <div className="flex flex-wrap gap-2">
              {EVENT_COLOR_PRESETS.map((preset) => {
                const swatch = "hex" in preset ? preset.hex : undefined;
                const selected = eventForm.color === preset.id;
                return (
                  <button
                    key={preset.id || "default"}
                    type="button"
                    title={preset.label}
                    onClick={() => setEventForm({ ...eventForm, color: preset.id })}
                    className={`h-7 w-7 rounded-full border-2 transition-transform ${
                      selected
                        ? "scale-110 border-[var(--color-text-main)]"
                        : "border-transparent hover:scale-105"
                    }`}
                    style={
                      swatch
                        ? { backgroundColor: swatch }
                        : {
                            background:
                              "linear-gradient(135deg, var(--color-primary-soft), var(--color-content-surface))",
                            border: "1px solid var(--color-chrome-stroke)",
                          }
                    }
                  />
                );
              })}
            </div>
          </FormField>
          <FormField label="Repeats">
            <select
              className={fieldControlClass}
              value={eventForm.recurrence}
              onChange={(e) =>
                setEventForm({
                  ...eventForm,
                  recurrence: e.target.value as "none" | "weekly" | "monthly",
                })
              }
            >
              <option value="none">Does not repeat</option>
              <option value="weekly">Weekly</option>
              <option value="monthly">Monthly</option>
            </select>
          </FormField>
          <Button
            disabled={!eventForm.title.trim()}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingEventId);
                await ipc.calendarUpsertEvent({
                  id: editingEventId ?? undefined,
                  title: eventForm.title.trim(),
                  startAt: new Date(eventForm.startAt).toISOString(),
                  location: eventForm.location.trim() || undefined,
                  color: eventForm.color || undefined,
                  recurrence: eventForm.recurrence,
                  notes: embedGeocodeInNotes(eventForm.notes, eventForm.geocode) || undefined,
                });
                setEventSheet(false);
                setEditingEventId(null);
                setEventForm({
                  title: "",
                  startAt: new Date().toISOString().slice(0, 16),
                  location: "",
                  color: "",
                  recurrence: "none",
                  notes: "",
                  geocode: null,
                });
                showToast(wasEdit ? "Event updated" : "Event saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save event
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={taskSheet}
        onOpenChange={setTaskSheet}
        title={editingTaskId ? "Edit task" : "Add task"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={taskForm.title}
              onChange={(e) => setTaskForm({ ...taskForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Due">
            <input
              className={fieldControlClass}
              type="datetime-local"
              value={taskForm.dueAt}
              onChange={(e) => setTaskForm({ ...taskForm, dueAt: e.target.value })}
            />
          </FormField>
          <Button
            disabled={!taskForm.title.trim()}
            onClick={async () => {
              try {
                const wasEdit = Boolean(editingTaskId);
                await ipc.calendarUpsertTask({
                  id: editingTaskId ?? undefined,
                  title: taskForm.title.trim(),
                  dueAt: new Date(taskForm.dueAt).toISOString(),
                });
                setTaskSheet(false);
                setEditingTaskId(null);
                setTaskForm({
                  title: "",
                  dueAt: toLocalInput(new Date(Date.now() + 86400000 * 3).toISOString()),
                });
                showToast(wasEdit ? "Task updated" : "Task saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save task
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet open={calendarsSheet} onOpenChange={setCalendarsSheet} title="Calendars">
        <div className="space-y-4">
          <p className="text-[12px] text-[var(--color-text-light)]">
            Subscribe to ICS feeds, connect Google or Outlook via OAuth, or manage local calendars.
            Disabled calendars are hidden from month, week, and day views.
          </p>

          <AppCard title="Apple Calendar (EventKit substitute)">
            <div className="space-y-3">
              <p className="text-[12px] text-[var(--color-text-light)]">
                Publish a stable ICS feed under your College data folder, then open Calendar.app on
                macOS to subscribe or import. This replaces native EventKit two-way sync for now.
              </p>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="secondary" disabled={appleFeedBusy} onClick={() => void publishAppleFeed()}>
                  Publish feed
                </Button>
                <Button size="sm" disabled={appleFeedBusy} onClick={() => void openAppleCalendar()}>
                  Open in Calendar.app
                </Button>
                <Button size="sm" variant="secondary" disabled={appleFeedBusy} onClick={() => void watchPublishedFeed()}>
                  Watch published feed
                </Button>
              </div>
              {appleFeed ? (
                <p className="text-[11px] text-[var(--color-text-light)]">
                  {appleFeed.eventCount} events · {appleFeed.path}
                  {appleFeed.writtenAt
                    ? ` · updated ${new Date(appleFeed.writtenAt).toLocaleString()}`
                    : ""}
                </p>
              ) : null}
            </div>
          </AppCard>

          <AppCard title="Cloud calendars">
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <Button
                size="sm"
                variant="secondary"
                disabled={!oauthStatus?.accounts.length || oauthBusy === "sync-all"}
                onClick={() => void syncAllOAuth()}
              >
                {oauthBusy === "sync-all" ? "Syncing…" : "Sync all cloud calendars"}
              </Button>
              <Button
                size="sm"
                variant="secondary"
                disabled={!oauthStatus?.accounts.length || oauthBusy === "push-all"}
                onClick={() => void pushLocalOAuth()}
              >
                {oauthBusy === "push-all" ? "Pushing…" : "Push local events to cloud"}
              </Button>
              <p className="text-[11px] text-[var(--color-text-light)]">
                Pull (−7d→+90d) or push College-local events (EventKit write substitute). Tokens refresh
                automatically.
              </p>
            </div>
            <div className="space-y-3">
              {(["google", "outlook"] as const).map((provider) => {
                const account = oauthAccountFor(provider);
                const configured =
                  provider === "google"
                    ? oauthStatus?.googleConfigured
                    : oauthStatus?.outlookConfigured;
                const label = provider === "google" ? "Google" : "Outlook";
                const busy = oauthBusy === provider || oauthBusy === `sync-${provider}`;
                return (
                  <div
                    key={provider}
                    className="flex flex-wrap items-center gap-2 rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2.5"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-[13px] font-medium text-[var(--color-text-main)]">
                          {label}
                        </span>
                        {account?.accountEmail ? (
                          <StatusChip title={account.accountEmail} tint="var(--color-success)" filled />
                        ) : configured ? (
                          <StatusChip title="Not connected" />
                        ) : (
                          <StatusChip title="Add Client ID in Settings" tint="var(--color-warning)" />
                        )}
                      </div>
                      {!configured && (
                        <p className="mt-1 text-[11px] text-[var(--color-text-light)]">
                          Settings → Calendar OAuth → paste your {label} Client ID, then return here.
                        </p>
                      )}
                      {account?.lastSyncedAt && (
                        <p className="mt-0.5 text-[11px] text-[var(--color-text-light)]">
                          Last sync {new Date(account.lastSyncedAt).toLocaleString()}
                        </p>
                      )}
                    </div>
                    {account ? (
                      <>
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={busy}
                          onClick={() => void syncOAuth(provider, account.id)}
                        >
                          Sync
                        </Button>
                        <Button
                          size="sm"
                          variant="danger"
                          disabled={busy}
                          onClick={() => void disconnectOAuth(account.id, label)}
                        >
                          Disconnect
                        </Button>
                      </>
                    ) : (
                      <Button
                        size="sm"
                        disabled={!configured || busy}
                        onClick={() => void connectOAuth(provider)}
                      >
                        Connect {label}
                      </Button>
                    )}
                  </div>
                );
              })}
            </div>
          </AppCard>

          <AppCard title={`${sources.length} calendar${sources.length === 1 ? "" : "s"}`}>
            {sources.length === 0 ? (
              <EmptyState title="No calendars" body="Add a calendar to get started." />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {sources.map((source) => {
                  const swatch = resolveEventColor(source.color);
                  return (
                    <li key={source.id} className="flex items-center gap-2 py-1">
                      <button
                        type="button"
                        title={source.isEnabled ? "Disable calendar" : "Enable calendar"}
                        onClick={() => void toggleSourceEnabled(source)}
                        className={`h-3 w-3 shrink-0 rounded-full border ${
                          source.isEnabled ? "border-transparent" : "border-[var(--color-chrome-stroke)] opacity-40"
                        }`}
                        style={
                          swatch
                            ? { backgroundColor: swatch }
                            : { background: "var(--color-primary-soft)" }
                        }
                      />
                      <div className="min-w-0 flex-1">
                        <ListRow
                          title={source.name}
                          subtitle={
                            source.icsUrl
                              ? `${source.icsUrl.replace(/^https?:\/\//, "").slice(0, 48)}${
                                  source.lastSyncedAt
                                    ? ` · synced ${new Date(source.lastSyncedAt).toLocaleString()}`
                                    : ""
                                }`
                              : "Local only"
                          }
                          onClick={() => openEditSource(source)}
                        />
                      </div>
                      {source.icsUrl.trim() && (
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={async () => {
                            try {
                              const res = await ipc.calendarSyncIcsUrl(source.id);
                              setSourceSyncNote(
                                `Synced ${res.imported} events (${res.skipped} skipped).`,
                              );
                              showToast(`Synced ${res.imported} events`, "success");
                            } catch (e) {
                              showToast(formatIpcError(e), "error");
                            }
                          }}
                        >
                          Sync
                        </Button>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </AppCard>
          {sourceSyncNote && (
            <p className="text-[12px] text-[var(--color-text-light)]">{sourceSyncNote}</p>
          )}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={openAddSource}>
              Add calendar
            </Button>
          </div>

          {(showSourceForm || editingSourceId !== null) && (
            <div className="space-y-3 border-t border-[var(--color-chrome-stroke)] pt-4">
              <h4 className="text-[13px] font-medium text-[var(--color-text-main)]">
                {editingSourceId ? "Edit calendar" : "New calendar"}
              </h4>
              <FormField label="Name">
                <input
                  className={fieldControlClass}
                  value={sourceForm.name}
                  onChange={(e) => setSourceForm({ ...sourceForm, name: e.target.value })}
                />
              </FormField>
              <FormField label="Color">
                <div className="flex flex-wrap gap-2">
                  {EVENT_COLOR_PRESETS.filter((p) => p.id).map((preset) => {
                    const swatch = "hex" in preset ? preset.hex : undefined;
                    const selected = sourceForm.color === preset.id;
                    return (
                      <button
                        key={preset.id}
                        type="button"
                        title={preset.label}
                        onClick={() => setSourceForm({ ...sourceForm, color: preset.id })}
                        className={`h-7 w-7 rounded-full border-2 transition-transform ${
                          selected
                            ? "scale-110 border-[var(--color-text-main)]"
                            : "border-transparent hover:scale-105"
                        }`}
                        style={swatch ? { backgroundColor: swatch } : undefined}
                      />
                    );
                  })}
                </div>
              </FormField>
              <FormField label="ICS subscription URL (optional)">
                <input
                  className={fieldControlClass}
                  value={sourceForm.icsUrl}
                  onChange={(e) => setSourceForm({ ...sourceForm, icsUrl: e.target.value })}
                  placeholder="https://calendar.google.com/calendar/ical/…"
                />
              </FormField>
              <label className="flex items-center gap-2 text-[12px] text-[var(--color-text-main)]">
                <input
                  type="checkbox"
                  checked={sourceForm.isEnabled}
                  onChange={(e) =>
                    setSourceForm({ ...sourceForm, isEnabled: e.target.checked })
                  }
                />
                Show on calendar views
              </label>
              <div className="flex flex-wrap gap-2">
                <Button
                  disabled={!sourceForm.name.trim()}
                  onClick={async () => {
                    try {
                      const wasEdit = Boolean(editingSourceId);
                      await ipc.calendarUpsertSource({
                        id: editingSourceId ?? undefined,
                        name: sourceForm.name.trim(),
                        color: sourceForm.color,
                        icsUrl: sourceForm.icsUrl.trim(),
                        isEnabled: sourceForm.isEnabled,
                      });
                      setEditingSourceId(null);
                      setShowSourceForm(false);
                      setSourceForm({ name: "", color: "blue", icsUrl: "", isEnabled: true });
                      showToast(wasEdit ? "Calendar updated" : "Calendar added", "success");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    }
                  }}
                >
                  Save calendar
                </Button>
                {editingSourceId && editingSourceId !== "cal-src-personal" && (
                  <Button
                    size="sm"
                    variant="danger"
                    onClick={async () => {
                      if (!confirmDelete(sourceForm.name || "calendar")) return;
                      try {
                        await ipc.calendarDeleteSource(editingSourceId);
                        setEditingSourceId(null);
                        setSourceForm({ name: "", color: "blue", icsUrl: "", isEnabled: true });
                        showToast("Calendar deleted", "success");
                      } catch (e) {
                        showToast(formatIpcError(e), "error");
                      }
                    }}
                  >
                    Delete
                  </Button>
                )}
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setEditingSourceId(null);
                    setShowSourceForm(false);
                    setSourceForm({ name: "", color: "blue", icsUrl: "", isEnabled: true });
                  }}
                >
                  Cancel edit
                </Button>
              </div>
            </div>
          )}
        </div>
      </ModalSheet>

      <ModalSheet open={icsSheet} onOpenChange={setIcsSheet} title="Import ICS">
        <div className="space-y-3">
          <p className="text-[12px] text-[var(--color-text-light)]">
            Choose a `.ics` file or paste VEVENT text. Rows need SUMMARY + DTSTART.
          </p>
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              try {
                const picked = await open({
                  multiple: false,
                  directory: false,
                  title: "Import calendar",
                  filters: [{ name: "iCalendar", extensions: ["ics", "ical"] }],
                });
                if (!picked || typeof picked !== "string") return;
                const res = await ipc.calendarImportIcsPath(picked);
                setIcsNote(`Imported ${res.imported}, skipped ${res.skipped} from file.`);
              } catch (e) {
                setIcsNote(formatIpcError(e));
              }
            }}
          >
            Choose .ics file…
          </Button>
          <FormField label="Or paste ICS text">
            <textarea
              className={fieldControlClass}
              rows={10}
              value={icsText}
              onChange={(e) => setIcsText(e.target.value)}
              placeholder={"BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Office hours\nDTSTART:20260301T150000Z\nEND:VEVENT\nEND:VCALENDAR"}
            />
          </FormField>
          {icsNote && <p className="text-[12px] text-[var(--color-text-light)]">{icsNote}</p>}
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!icsText.trim()}
              onClick={async () => {
                try {
                  const res = await ipc.calendarImportIcs(icsText);
                  setIcsNote(`Imported ${res.imported}, skipped ${res.skipped}.`);
                  setIcsText("");
                } catch (e) {
                  setIcsNote(formatIpcError(e));
                }
              }}
            >
              Import pasted text
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={async () => {
                try {
                  const text = await ipc.calendarExportIcs();
                  await navigator.clipboard.writeText(text);
                  setIcsNote(
                    `Copied ${text.split("BEGIN:VEVENT").length - 1} events to clipboard.`,
                  );
                } catch (e) {
                  setIcsNote(formatIpcError(e));
                }
              }}
            >
              Copy export
            </Button>
          </div>
        </div>
      </ModalSheet>
    </div>
  );
}

function LocationMapPreview({
  query,
  geocode,
}: {
  query: string;
  geocode?: GeocodeResult | null;
}) {
  const displayLabel = geocode?.displayName ?? query;
  const appleUrl = appleMapsUrl(query, geocode);
  const googleUrl = googleMapsUrl(query, geocode);
  const osmUrl = openStreetMapUrl(query, geocode);

  return (
    <div className="overflow-hidden rounded-[12px] border border-[var(--color-chrome-stroke)]">
      {geocode && (
        <div className="border-b border-[var(--color-chrome-stroke)]">
          <EventLocationMap geocode={geocode} />
        </div>
      )}
      <div
        className="px-3 py-3"
        style={
          geocode
            ? undefined
            : {
                background:
                  "linear-gradient(145deg, color-mix(in srgb, var(--color-primary) 12%, var(--color-surface)), color-mix(in srgb, var(--color-success) 6%, var(--color-content-surface)))",
              }
        }
      >
        {!geocode && (
          <div className="relative px-1 py-2">
            <div
              className="pointer-events-none absolute inset-0 opacity-[0.12]"
              style={{
                backgroundImage:
                  "linear-gradient(var(--color-chrome-stroke) 1px, transparent 1px), linear-gradient(90deg, var(--color-chrome-stroke) 1px, transparent 1px)",
                backgroundSize: "24px 24px",
              }}
            />
            <div className="relative flex items-start gap-3">
              <span
                className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] text-[13px] font-semibold text-[var(--color-primary)]"
                aria-hidden
              >
                ⌖
              </span>
              <p className="text-[11px] text-[var(--color-text-light)]">
                Look up the address to show an OpenStreetMap preview.
              </p>
            </div>
          </div>
        )}
        <div className={geocode ? "" : "relative mt-1"}>
          <p className="text-[13px] font-semibold text-[var(--color-text-main)]">{displayLabel}</p>
          {geocode && (
            <div className="mt-1.5 flex flex-wrap gap-1.5">
              <StatusChip title={`${geocode.lat.toFixed(5)}° lat`} />
              <StatusChip title={`${geocode.lon.toFixed(5)}° lon`} />
            </div>
          )}
          {geocode && (
            <p className="mt-1.5 text-[11px] text-[var(--color-text-light)]">
              OpenStreetMap preview — open in a map app for turn-by-turn directions.
            </p>
          )}
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            <Button size="sm" variant="secondary" onClick={() => void openUrl(appleUrl)}>
              Apple Maps
            </Button>
            <Button size="sm" variant="secondary" onClick={() => void openUrl(googleUrl)}>
              Google Maps
            </Button>
            <Button size="sm" variant="ghost" onClick={() => void openUrl(osmUrl)}>
              OpenStreetMap
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
