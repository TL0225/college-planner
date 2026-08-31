import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
  WeekGrid,
  DayTimeline,
  dateKey,
  fieldControlClass,
  usePlatform,
} from "@/design-system";
import { ipc, formatIpcError, type WebcalUrlResult } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { navigate } from "@/lib/shellNavigate";
import { humanLabel } from "@/lib/copy/humanLabels";
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
  embedGeocodeInNotes,
  parseGeocodeFromNotes,
} from "./locationGeocode";
import {
  CalendarEventPanel,
  anchorFromElement,
  type EventPopoverAnchor,
  type EventFormState,
} from "./CalendarEventPanel";
import { parseRecurrence } from "./recurrence";
import { CalendarPeriodNav } from "./CalendarPeriodNav";

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
  allDay?: boolean;
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
  const { isMac } = usePlatform();
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
  const [eventPopoverAnchor, setEventPopoverAnchor] = useState<EventPopoverAnchor | null>(null);
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
  const [webcalFeed, setWebcalFeed] = useState<WebcalUrlResult | null>(null);
  const [feedBindMode, setFeedBindMode] = useState<"localhost" | "lan">("localhost");
  const [webcalBusy, setWebcalBusy] = useState(false);
  const [icsText, setIcsText] = useState("");
  const [icsNote, setIcsNote] = useState<string | null>(null);
  const [editingEventId, setEditingEventId] = useState<string | null>(null);
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);
  const [eventForm, setEventForm] = useState<EventFormState>({
    title: "",
    startAt: new Date().toISOString().slice(0, 16),
    endAt: new Date().toISOString().slice(0, 16),
    allDay: false,
    location: "",
    color: "",
    recurrence: "none",
    notes: "",
    geocode: null,
  });
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

  useEffect(() => {
    void ipc.calendarGetFeedBindMode().then((mode) => {
      if (mode === "lan" || mode === "localhost") setFeedBindMode(mode);
    });
  }, []);

  const sourceById = useMemo(() => new Map(sources.map((s) => [s.id, s])), [sources]);

  const enabledSourceIds = useMemo(
    () => new Set(sources.filter((s) => s.isEnabled).map((s) => s.id)),
    [sources],
  );

  const calendarSurfaceRef = useRef<HTMLDivElement>(null);

  const DEFAULT_EVENT_COLOR = "#a6813f";

  const resolveDisplayColor = useCallback(
    (event: CalEvent | CalendarEventOccurrence) => {
      if (event.color) return resolveEventColor(event.color);
      const sourceId = "sourceId" in event ? event.sourceId : undefined;
      if (sourceId) {
        const source = sourceById.get(sourceId);
        if (source?.color) return resolveEventColor(source.color);
      }
      return DEFAULT_EVENT_COLOR;
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
    const map = new Map<string, Array<{ id: string; title: string; color?: string }>>();
    for (const e of displayEvents) {
      const key = dateKey(new Date(e.startAt));
      const list = map.get(key) ?? [];
      if (list.length < 3) {
        list.push({
          id: e.occurrenceId,
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
      showToast(`Saved local ICS feed (${result.eventCount} events)`, "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setAppleFeedBusy(false);
    }
  };

  const openAppleCalendar = async () => {
    if (!isMac) return;
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

  const startWebcalFeed = async () => {
    setWebcalBusy(true);
    try {
      const result = await ipc.calendarGetWebcalUrl();
      setWebcalFeed(result);
      showToast("Live webcal feed is running", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setWebcalBusy(false);
    }
  };

  const copyWebcalUrl = async (url?: string) => {
    const target = url ?? webcalFeed?.url;
    if (!target) return;
    try {
      await navigator.clipboard.writeText(target);
      showToast("Webcal URL copied", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const setFeedBind = async (mode: "localhost" | "lan") => {
    try {
      await ipc.calendarSetFeedBindMode(mode);
      setFeedBindMode(mode);
      setWebcalFeed(null);
      showToast(
        mode === "lan"
          ? "LAN mode set — restart the webcal feed to listen on your network"
          : "Localhost mode set — restart the webcal feed",
        "success",
      );
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const closeEventPopover = () => {
    setEventPopoverAnchor(null);
    setEditingEventId(null);
  };

  const resetEventForm = (): EventFormState => ({
    title: "",
    startAt: new Date().toISOString().slice(0, 16),
    endAt: new Date().toISOString().slice(0, 16),
    allDay: false,
    location: "",
    color: "",
    recurrence: "none",
    notes: "",
    geocode: null,
  });

  const toFormDateTime = (iso: string, allDay?: boolean) => {
    if (allDay) return iso.slice(0, 10);
    return toLocalInput(iso);
  };

  const saveEvent = async () => {
    try {
      const wasEdit = Boolean(editingEventId);
      const startIso = eventForm.allDay
        ? new Date(`${eventForm.startAt.slice(0, 10)}T00:00:00`).toISOString()
        : new Date(eventForm.startAt).toISOString();
      const endRaw = eventForm.endAt || eventForm.startAt;
      const endIso = eventForm.allDay
        ? new Date(`${endRaw.slice(0, 10)}T23:59:59`).toISOString()
        : new Date(endRaw).toISOString();
      await ipc.calendarUpsertEvent({
        id: editingEventId ?? undefined,
        title: eventForm.title.trim(),
        startAt: startIso,
        endAt: endIso,
        allDay: eventForm.allDay,
        location: eventForm.location.trim() || undefined,
        color: eventForm.color || undefined,
        recurrence: eventForm.recurrence,
        notes: embedGeocodeInNotes(eventForm.notes, eventForm.geocode) || undefined,
      });
      closeEventPopover();
      setEventForm(resetEventForm());
      showToast(wasEdit ? "Event updated" : "Event saved", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const openAddEventForDay = (
    day?: Date,
    anchor?: EventPopoverAnchor,
    hour?: number,
  ) => {
    const base = day ?? selectedDay ?? new Date();
    const local = new Date(base);
    if (hour === -1) {
      local.setHours(0, 0, 0, 0);
      const dateStr = local.toISOString().slice(0, 10);
      setEditingEventId(null);
      setEventForm({
        ...resetEventForm(),
        allDay: true,
        startAt: dateStr,
        endAt: dateStr,
      });
    } else {
      if (hour !== undefined && hour >= 0) local.setHours(hour, 0, 0, 0);
      else local.setHours(9, 0, 0, 0);
      const isoLocal = new Date(local.getTime() - local.getTimezoneOffset() * 60000)
        .toISOString()
        .slice(0, 16);
      const endLocal = new Date(local.getTime() + 60 * 60 * 1000);
      const endIsoLocal = new Date(endLocal.getTime() - endLocal.getTimezoneOffset() * 60000)
        .toISOString()
        .slice(0, 16);
      setEditingEventId(null);
      setEventForm({
        ...resetEventForm(),
        startAt: isoLocal,
        endAt: endIsoLocal,
      });
    }
    setEventPopoverAnchor(
      anchor ??
        (calendarSurfaceRef.current
          ? anchorFromElement(calendarSurfaceRef.current)
          : { x: window.innerWidth / 2 - 180, y: 140, width: 200, height: 48 }),
    );
  };

  const openEditEvent = (
    e: CalendarEventOccurrence | CalEvent,
    anchor?: EventPopoverAnchor,
  ) => {
    const baseId = "baseId" in e ? e.baseId : e.id;
    const base = eventById.get(baseId) ?? e;
    const notes = "notes" in base ? base.notes ?? "" : "";
    const { geocode, userNotes } = parseGeocodeFromNotes(notes);
    const allDay = Boolean("allDay" in base && base.allDay);
    setEditingEventId(baseId);
    setEventForm({
      title: base.title,
      startAt: toFormDateTime(base.startAt, allDay),
      endAt: toFormDateTime(base.endAt ?? base.startAt, allDay),
      allDay,
      location: base.location || "",
      color: base.color || "",
      recurrence: parseRecurrence(base.recurrence),
      notes: userNotes,
      geocode,
    });
    setEventPopoverAnchor(
      anchor ?? { x: window.innerWidth / 2 - 180, y: 140, width: 200, height: 48 },
    );
  };

  const handleSelectEvent = (occurrenceId: string, anchor: EventPopoverAnchor) => {
    const ev = displayEvents.find((e) => e.occurrenceId === occurrenceId);
    if (!ev) return;
    setSelectedDay(new Date(ev.startAt));
    openEditEvent(ev, anchor);
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

  const goToToday = () => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    setSelectedDay(today);
    if (view === "month") {
      setCursor(new Date(now.getFullYear(), now.getMonth(), 1));
    } else if (view === "week") {
      setWeekAnchor(now);
    } else if (view === "day") {
      setDayCursor(today);
    }
  };

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
    <div className="flex h-full min-h-0 flex-col overflow-hidden">
      <AppPageHeader
        title={title}
        showsTitle={view !== "month" && view !== "week" && view !== "day"}
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
        center={
          view === "month" || view === "week" || view === "day" ? (
            <CalendarPeriodNav
              view={view}
              cursor={cursor}
              weekAnchor={weekAnchor}
              dayCursor={dayCursor}
              onMonthChange={setCursor}
              onWeekChange={setWeekAnchor}
              onDayChange={setDayCursor}
              onSelectToday={goToToday}
            />
          ) : undefined
        }
        actions={
          <div className="flex flex-wrap items-center justify-end gap-2">
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
      {error && <p className="px-3 text-meta text-[var(--color-error)]">{error}</p>}

      {sources.length > 0 && view !== "tasks" && (
        <div className="flex flex-wrap items-center gap-2 px-3 pb-2">
          <span className="text-label font-semibold uppercase tracking-[0.06em]">
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
                className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-label transition-colors ${
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
                      : { background: "color-mix(in srgb, var(--registrar-accent) 30%, transparent)" }
                  }
                />
                {source.name}
              </button>
            );
          })}
          <button
            type="button"
            className="rounded-full border border-dashed border-[var(--color-chrome-stroke)] px-2.5 py-1 text-label text-[var(--color-text-light)] transition-colors hover:bg-[var(--color-row-hover)] hover:text-[var(--color-text-main)]"
            onClick={() => {
              setSourceSyncNote(null);
              setCalendarsSheet(true);
            }}
          >
            Manage…
          </button>
        </div>
      )}

      <div ref={calendarSurfaceRef} className="flex min-h-0 flex-1 flex-col overflow-hidden px-2 pb-2">
        {view === "month" && (
          <div className="relative min-h-0 flex-1">
            <MonthGrid
              cursor={cursor}
              selected={selectedDay}
              countsByDay={countsByDay}
              labelsByDay={labelsByDay}
              onSelectDay={(day, anchor) => {
                setSelectedDay(day);
                openAddEventForDay(day, anchor);
              }}
              onSelectEvent={handleSelectEvent}
            />
          </div>
        )}

        {view === "week" && (
          <div className="relative min-h-0 flex-1">
            <WeekGrid
              anchor={weekAnchor}
              selected={selectedDay}
              eventsByDay={eventsByDay}
              onSelectDay={(day, anchor) => {
                setSelectedDay(day);
                openAddEventForDay(day, anchor);
              }}
              onSelectEvent={handleSelectEvent}
            />
          </div>
        )}

        {view === "day" && (
          <div className="relative min-h-0 flex-1">
            <DayTimeline
              day={dayCursor}
              items={[
                ...expandRecurringEvents(visibleEvents, ...dayVisibleRange(dayCursor)).map((e) => {
                  const base = eventById.get(e.baseId);
                  return {
                    id: e.occurrenceId,
                    title: e.title,
                    startAt: e.startAt,
                    endAt: e.endAt ?? base?.endAt,
                    location: e.location,
                    kind: "event" as const,
                    color: resolveDisplayColor(e),
                    allDay: base?.allDay ?? e.allDay,
                  };
                }),
                ...tasks
                  .filter((t) => t.dueAt)
                  .map((t) => ({
                    id: t.id,
                    title: t.title,
                    startAt: t.dueAt!,
                    kind: "task" as const,
                  })),
              ]}
              onSelectSlot={(hour, anchor) => {
                setSelectedDay(dayCursor);
                openAddEventForDay(dayCursor, anchor, hour);
              }}
              onSelectEvent={handleSelectEvent}
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
                      onClick={() => {
                        const anchor = calendarSurfaceRef.current
                          ? anchorFromElement(calendarSurfaceRef.current)
                          : undefined;
                        openEditEvent(e, anchor);
                      }}
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
              <p className="mb-3 text-meta">
                Saved focus blocks persist across sessions. Suggestions from open tasks appear below
                when you have none saved. On desktop, these are local reminders only — OS Do Not
                Disturb is not enabled yet.
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
                        <div className="text-body font-medium">{b.title}</div>
                        <div className="text-caption">
                          {b.durationMinutes} min
                        </div>
                      </div>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={async () => {
                          if (!confirmDelete(b.title)) return;
                          try {
                            await ipc.calendarDeleteFocusBlock(b.id);
                            await refresh();
                            showToast("Focus block deleted", "success");
                          } catch (err) {
                            showToast(formatIpcError(err), "error");
                          }
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
                    durationMinutes: 45,
                    subtitle: t.dueAt
                      ? `Due ${new Date(t.dueAt).toLocaleDateString()} · 45 min focus`
                      : "45 min focus block",
                    tint: "var(--color-warning)",
                  })),
                  ...todayEvents.slice(0, 2).map((e) => ({
                    key: e.id,
                    title: e.title,
                    durationMinutes: 45,
                    subtitle: `${new Date(e.startAt).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })} · review / prep`,
                    tint: "var(--color-primary)",
                  })),
                ];
                if (blocks.length === 0) return null;
                return (
                  <ul className="space-y-2">
                    <li className="text-label font-semibold uppercase">
                      Suggested
                    </li>
                    {blocks.map((b) => (
                      <li
                        key={b.key}
                        className="flex cursor-pointer items-center justify-between rounded-[10px] border border-dashed border-[var(--color-chrome-stroke)] px-3 py-2 transition-colors hover:bg-[var(--color-content-surface)]"
                        onClick={async () => {
                          try {
                            await ipc.calendarUpsertFocusBlock({
                              title: b.title,
                              durationMinutes: b.durationMinutes,
                            });
                            await refresh();
                            showToast("Focus block saved", "success");
                          } catch (err) {
                            showToast(formatIpcError(err), "error");
                          }
                        }}
                      >
                        <div className="min-w-0">
                          <div className="truncate text-body font-medium">{b.title}</div>
                          <div className="text-caption">{b.subtitle}</div>
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
                        onClick={async () => {
                          try {
                            await ipc.calendarToggleTaskComplete(t.id);
                          } catch (e) {
                            showToast(formatIpcError(e), "error");
                          }
                        }}
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
          <p className="text-meta">
            Subscribe to ICS feeds, connect Google or Outlook via OAuth, or manage local calendars.
            Disabled calendars are hidden from month, week, and day views.
          </p>

          <AppCard title={isMac ? "Add to Apple Calendar" : "Add to calendar app"}>
            <div className="space-y-3">
              <p className="text-meta">
                Subscribe to a live webcal feed while College is running, or save a local ICS file
                under your College data folder for one-time import.
              </p>
              <div className="space-y-2">
                <p className="text-caption font-medium text-[var(--color-text-main)]">
                  Live webcal subscription
                </p>
                <div className="flex flex-wrap gap-2">
                  <SegmentedPills
                    value={feedBindMode}
                    onChange={(mode) => void setFeedBind(mode as "localhost" | "lan")}
                    options={[
                      { id: "localhost", label: "This device" },
                      { id: "lan", label: "LAN devices" },
                    ]}
                  />
                  <Button
                    size="sm"
                    variant="secondary"
                    disabled={webcalBusy}
                    onClick={() => void startWebcalFeed()}
                  >
                    {webcalFeed ? "Refresh webcal feed" : "Start webcal feed"}
                  </Button>
                  {webcalFeed ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => void copyWebcalUrl()}
                    >
                      Copy localhost URL
                    </Button>
                  ) : null}
                  {webcalFeed?.lanWebcalUrl ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => void copyWebcalUrl(webcalFeed.lanWebcalUrl!)}
                    >
                      Copy LAN URL
                    </Button>
                  ) : null}
                </div>
                {webcalFeed ? (
                  <div className="space-y-1 break-all text-caption">
                    <p>
                      {webcalFeed.url}
                      <span className="text-meta">
                        {" "}
                        · port {webcalFeed.port} · {webcalFeed.bindMode}
                      </span>
                    </p>
                    {webcalFeed.lanWebcalUrl ? (
                      <p className="text-meta">
                        LAN ({webcalFeed.localIp}): {webcalFeed.lanWebcalUrl} — allow port{" "}
                        {webcalFeed.port} through Windows Firewall if phones/tablets cannot subscribe.
                      </p>
                    ) : feedBindMode === "lan" ? (
                      <p className="text-meta">
                        LAN mode is on but no network IP was detected. Restart the feed after connecting
                        to Wi‑Fi.
                      </p>
                    ) : null}
                  </div>
                ) : (
                  <p className="text-caption">
                    Starts a local HTTP server. Use <strong>This device</strong> for same-machine
                    calendars, or <strong>LAN devices</strong> for phones/tablets on your Wi‑Fi (College
                    must stay open).
                  </p>
                )}
              </div>
              <div className="space-y-2 border-t border-[var(--color-chrome-stroke)] pt-3">
                <p className="text-caption font-medium text-[var(--color-text-main)]">
                  Local ICS file
                </p>
                <div className="flex flex-wrap gap-2">
                  <Button size="sm" variant="secondary" disabled={appleFeedBusy} onClick={() => void publishAppleFeed()}>
                    Save local ICS feed
                  </Button>
                  {isMac ? (
                    <Button size="sm" disabled={appleFeedBusy} onClick={() => void openAppleCalendar()}>
                      Open in Calendar.app
                    </Button>
                  ) : null}
                  <Button size="sm" variant="secondary" disabled={appleFeedBusy} onClick={() => void watchPublishedFeed()}>
                    Re-import saved feed
                  </Button>
                </div>
                {appleFeed ? (
                  <p className="text-caption">
                    {appleFeed.eventCount} events · {appleFeed.path}
                    {appleFeed.writtenAt
                      ? ` · updated ${new Date(appleFeed.writtenAt).toLocaleString()}`
                      : ""}
                  </p>
                ) : null}
              </div>
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
              <p className="text-caption">
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
                const label = provider === "google" ? humanLabel("google") : humanLabel("outlook");
                const busy = oauthBusy === provider || oauthBusy === `sync-${provider}`;
                return (
                  <div
                    key={provider}
                    className="flex flex-wrap items-center gap-2 rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2.5"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-body font-medium text-[var(--color-text-main)]">
                          {label}
                        </span>
                        {account?.accountEmail ? (
                          <StatusChip title={account.accountEmail} tint="var(--color-success)" filled />
                        ) : configured ? (
                          <StatusChip title="Not connected" />
                        ) : (
                          <StatusChip title="Not set up" tint="var(--color-warning)" />
                        )}
                      </div>
                      {!configured && (
                        <p className="mt-1 text-caption">
                          <button
                            type="button"
                            className="text-[var(--color-primary)] hover:underline"
                            onClick={() => navigate({ hub: "settings", page: "connections" })}
                          >
                            Connect {label}
                          </button>
                          {" "}to sync your events.
                        </p>
                      )}
                      {account?.lastSyncedAt && (
                        <p className="mt-0.5 text-caption">
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
            <p className="text-meta">{sourceSyncNote}</p>
          )}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={openAddSource}>
              Add calendar
            </Button>
          </div>

          {(showSourceForm || editingSourceId !== null) && (
            <div className="space-y-3 border-t border-[var(--color-chrome-stroke)] pt-4">
              <h4 className="text-body font-medium text-[var(--color-text-main)]">
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
              <label className="flex items-center gap-2 text-meta text-[var(--color-text-main)]">
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
          <p className="text-meta">
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
          {icsNote && <p className="text-meta">{icsNote}</p>}
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

      {eventPopoverAnchor && (
        <CalendarEventPanel
          anchor={eventPopoverAnchor}
          title={editingEventId ? "Edit event" : "Add event"}
          form={eventForm}
          onChange={setEventForm}
          editing={Boolean(editingEventId)}
          onSave={() => void saveEvent()}
          onDelete={
            editingEventId
              ? async () => {
                  if (!confirmDelete(eventForm.title || "event")) return;
                  try {
                    await ipc.calendarDeleteEvent(editingEventId);
                    closeEventPopover();
                    setEventForm(resetEventForm());
                    showToast("Event deleted", "success");
                  } catch (e) {
                    showToast(formatIpcError(e), "error");
                  }
                }
              : undefined
          }
          onClose={closeEventPopover}
        />
      )}
    </div>
  );
}
