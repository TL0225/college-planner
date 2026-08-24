import { parseLooseDue } from "./syllabusDateParser";
import type { SyllabusDraftEvent } from "./types";

export type WorkloadProfile = {
  weeklyCounts: number[];
  peakText: string;
  levelText: "LOW" | "MED" | "HIGH";
  levelTint: string;
};

function startOfWeek(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  d.setDate(d.getDate() + diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

function weekIndex(base: Date, date: Date): number {
  const msPerWeek = 7 * 24 * 60 * 60 * 1000;
  const diff = startOfWeek(date).getTime() - startOfWeek(base).getTime();
  return Math.max(1, Math.floor(diff / msPerWeek) + 1);
}

export function computeWorkloadProfile(events: SyllabusDraftEvent[]): WorkloadProfile | null {
  const dated = events
    .map((e) => ({ event: e, start: parseLooseDue(e.dueHint) }))
    .filter((row): row is { event: SyllabusDraftEvent; start: string } => !!row.start);
  if (dated.length < 3) return null;

  dated.sort((a, b) => a.start.localeCompare(b.start));
  const base = new Date(dated[0].start);
  const countsByWeek = new Map<number, number>();
  let maxWeek = 1;

  for (const row of dated) {
    const idx = weekIndex(base, new Date(row.start));
    countsByWeek.set(idx, (countsByWeek.get(idx) ?? 0) + 1);
    maxWeek = Math.max(maxWeek, idx);
  }

  const weeklyCounts = Array.from({ length: maxWeek }, (_, i) => countsByWeek.get(i + 1) ?? 0);
  const maxCount = Math.max(...weeklyCounts);
  if (maxCount <= 0) return null;

  const peakWeeks = weeklyCounts
    .map((count, index) => (count === maxCount ? index + 1 : null))
    .filter((v): v is number => v != null);
  const firstPeak = peakWeeks[0] ?? 1;
  const lastPeak = peakWeeks[peakWeeks.length - 1] ?? firstPeak;
  const peakText =
    firstPeak !== lastPeak ? `Week ${firstPeak}-${lastPeak}` : `Week ${firstPeak}`;

  let levelText: WorkloadProfile["levelText"] = "LOW";
  let levelTint = "var(--color-success)";
  if (maxCount >= 6) {
    levelText = "HIGH";
    levelTint = "var(--color-warning)";
  } else if (maxCount >= 4) {
    levelText = "MED";
    levelTint = "var(--color-primary)";
  }

  return { weeklyCounts, peakText, levelText, levelTint };
}
