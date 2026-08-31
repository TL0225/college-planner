import type { RecurrenceKind } from "./recurrence";

export type CalendarEventBase = {
  id: string;
  title: string;
  startAt: string;
  endAt?: string;
  allDay?: boolean;
  location: string;
  provider: string;
  color?: string;
  recurrence?: string;
};

export type CalendarEventOccurrence = CalendarEventBase & {
  occurrenceId: string;
  baseId: string;
};

const MAX_OCCURRENCES = 120;

function endOfDay(d: Date): Date {
  const out = new Date(d);
  out.setHours(23, 59, 59, 999);
  return out;
}

function withTimeFrom(base: Date, template: Date): Date {
  const out = new Date(base);
  out.setHours(
    template.getHours(),
    template.getMinutes(),
    template.getSeconds(),
    template.getMilliseconds(),
  );
  return out;
}

function isWeekday(d: Date): boolean {
  const day = d.getDay();
  return day !== 0 && day !== 6;
}

function pushOccurrence(
  event: CalendarEventBase,
  when: Date,
  index: number,
  out: CalendarEventOccurrence[],
) {
  out.push({
    ...event,
    startAt: when.toISOString(),
    occurrenceId: index === 0 ? event.id : `${event.id}:${index}`,
    baseId: event.id,
  });
}

function advance(current: Date, recurrence: RecurrenceKind, anchor: Date): Date {
  const next = new Date(current);
  switch (recurrence) {
    case "daily":
      next.setDate(next.getDate() + 1);
      break;
    case "weekdays":
      do {
        next.setDate(next.getDate() + 1);
      } while (!isWeekday(next));
      break;
    case "weekly":
      next.setDate(next.getDate() + 7);
      break;
    case "biweekly":
      next.setDate(next.getDate() + 14);
      break;
    case "monthly":
      next.setMonth(next.getMonth() + 1);
      break;
    case "yearly":
      next.setFullYear(next.getFullYear() + 1);
      break;
    default:
      next.setDate(next.getDate() + 1);
  }
  return withTimeFrom(next, anchor);
}

export function expandRecurringEvents(
  events: CalendarEventBase[],
  rangeStart: Date,
  rangeEnd: Date,
): CalendarEventOccurrence[] {
  const end = endOfDay(rangeEnd);
  const out: CalendarEventOccurrence[] = [];

  for (const event of events) {
    const recurrence = (event.recurrence ?? "none") as RecurrenceKind;
    const anchor = new Date(event.startAt);
    if (Number.isNaN(anchor.getTime())) continue;

    if (recurrence === "none") {
      if (anchor >= rangeStart && anchor <= end) {
        pushOccurrence(event, anchor, 0, out);
      }
      continue;
    }

    let current = new Date(anchor);
    let index = 0;

    while (current < rangeStart && index < MAX_OCCURRENCES) {
      current = advance(current, recurrence, anchor);
      index += 1;
    }

    while (current <= end && index < MAX_OCCURRENCES) {
      if (current >= rangeStart) {
        pushOccurrence(event, withTimeFrom(current, anchor), index, out);
      }
      current = advance(current, recurrence, anchor);
      index += 1;
    }
  }

  return out.sort((a, b) => a.startAt.localeCompare(b.startAt));
}

export function monthVisibleRange(cursor: Date): [Date, Date] {
  const year = cursor.getFullYear();
  const month = cursor.getMonth();
  const first = new Date(year, month, 1);
  const startPad = first.getDay();
  const start = new Date(year, month, 1 - startPad);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(start.getDate() + 41);
  return [start, end];
}

export function weekVisibleRange(anchor: Date): [Date, Date] {
  const start = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate());
  start.setDate(start.getDate() - start.getDay());
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(start.getDate() + 6);
  return [start, end];
}

export function dayVisibleRange(day: Date): [Date, Date] {
  const start = new Date(day.getFullYear(), day.getMonth(), day.getDate());
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(start.getDate() + 1);
  end.setMilliseconds(-1);
  return [start, end];
}
