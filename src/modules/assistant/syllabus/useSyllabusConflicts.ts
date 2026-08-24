import { useMemo } from "react";
import { parseLooseDue } from "./syllabusDateParser";
import type { SyllabusDraftEvent } from "./types";

export type CalendarConflictEvent = {
  id: string;
  title: string;
  startAt: string;
  endAt?: string | null;
  location?: string | null;
  allDay: boolean;
};

export type SyllabusConflictLookup = Map<string, CalendarConflictEvent[]>;

function sameCalendarDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function rangesOverlap(
  draftStart: Date,
  draftEnd: Date,
  existingStart: Date,
  existingEnd: Date,
): boolean {
  return existingStart < draftEnd && existingEnd > draftStart;
}

function eventEndAt(startAt: string, endAt?: string | null, allDay?: boolean): Date {
  if (endAt) return new Date(endAt);
  const start = new Date(startAt);
  if (allDay) {
    const end = new Date(start);
    end.setHours(23, 59, 59, 999);
    return end;
  }
  const end = new Date(start);
  end.setHours(end.getHours() + 1);
  return end;
}

export function buildSyllabusConflictLookup(
  draftEvents: SyllabusDraftEvent[],
  calendarEvents: CalendarConflictEvent[],
): SyllabusConflictLookup {
  const lookup: SyllabusConflictLookup = new Map();
  if (draftEvents.length === 0 || calendarEvents.length === 0) return lookup;

  for (const draft of draftEvents) {
    const draftStartIso = parseLooseDue(draft.dueHint);
    if (!draftStartIso) continue;
    const draftStart = new Date(draftStartIso);
    const draftEnd = eventEndAt(draftStartIso, null, true);

    const overlaps = calendarEvents.filter((existing) => {
      const existingStart = new Date(existing.startAt);
      const existingEnd = eventEndAt(existing.startAt, existing.endAt, existing.allDay);
      if (existing.allDay) {
        return sameCalendarDay(draftStart, existingStart);
      }
      return rangesOverlap(draftStart, draftEnd, existingStart, existingEnd);
    });

    if (overlaps.length > 0) {
      lookup.set(draft.id, overlaps);
    }
  }

  return lookup;
}

export function useSyllabusConflicts(
  draftEvents: SyllabusDraftEvent[],
  calendarEvents: CalendarConflictEvent[],
): SyllabusConflictLookup {
  return useMemo(
    () => buildSyllabusConflictLookup(draftEvents, calendarEvents),
    [draftEvents, calendarEvents],
  );
}
