import type { SyllabusSection } from "./types";

const DAY_ALIASES: Record<string, number> = {
  m: 1,
  mon: 1,
  monday: 1,
  t: 2,
  tu: 2,
  tue: 2,
  tues: 2,
  tuesday: 2,
  w: 3,
  wed: 3,
  wednesday: 3,
  r: 4,
  th: 4,
  thu: 4,
  thur: 4,
  thurs: 4,
  thursday: 4,
  f: 5,
  fri: 5,
  friday: 5,
  s: 6,
  sat: 6,
  saturday: 6,
  u: 0,
  su: 0,
  sun: 0,
  sunday: 0,
};

export function parseMeetingWeekdays(meetingDays?: string | null): number[] {
  if (!meetingDays?.trim()) return [];
  const raw = meetingDays.trim();
  const tokens = raw.match(/[A-Za-z]+/g) ?? [];
  const days = new Set<number>();
  for (const token of tokens) {
    const key = token.toLowerCase();
    if (DAY_ALIASES[key] != null) {
      days.add(DAY_ALIASES[key]);
      continue;
    }
    for (const ch of token.toUpperCase()) {
      if (DAY_ALIASES[ch.toLowerCase()] != null) {
        days.add(DAY_ALIASES[ch.toLowerCase()]);
      }
    }
  }
  return [...days].sort((a, b) => a - b);
}

export function nextWeekdayDate(weekday: number, from = new Date()): Date {
  const date = new Date(from);
  date.setHours(0, 0, 0, 0);
  const current = date.getDay();
  let delta = weekday - current;
  if (delta < 0) delta += 7;
  if (delta === 0) delta = 0;
  date.setDate(date.getDate() + delta);
  return date;
}

export type SectionMeetingEventDraft = {
  title: string;
  startAt: string;
  allDay: true;
  recurrence: "weekly";
  location?: string;
  notes: string;
};

export function buildSectionMeetingEvents(input: {
  courseCode: string;
  section: SyllabusSection;
}): SectionMeetingEventDraft[] {
  const weekdays = parseMeetingWeekdays(input.section.meetingDays);
  if (weekdays.length === 0) return [];

  const location = input.section.location?.trim() || undefined;
  const label = input.section.label.trim() || "Section";
  const timeHint = input.section.meetingTime?.trim();

  return weekdays.map((weekday) => {
    const start = nextWeekdayDate(weekday);
    start.setHours(0, 0, 0, 0);
    const title = timeHint
      ? `${input.courseCode}: ${label} (${timeHint})`
      : `${input.courseCode}: ${label}`;
    return {
      title,
      startAt: start.toISOString(),
      allDay: true as const,
      recurrence: "weekly" as const,
      location,
      notes: "[source]=syllabus_section",
    };
  });
}
