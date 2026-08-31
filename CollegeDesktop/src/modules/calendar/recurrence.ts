export type RecurrenceKind =
  | "none"
  | "daily"
  | "weekdays"
  | "weekly"
  | "biweekly"
  | "monthly"
  | "yearly";

export const RECURRENCE_OPTIONS: Array<{ id: RecurrenceKind; label: string }> = [
  { id: "none", label: "Does not repeat" },
  { id: "daily", label: "Daily" },
  { id: "weekdays", label: "Every weekday (Mon–Fri)" },
  { id: "weekly", label: "Weekly" },
  { id: "biweekly", label: "Every 2 weeks" },
  { id: "monthly", label: "Monthly" },
  { id: "yearly", label: "Yearly" },
];

export function parseRecurrence(value?: string | null): RecurrenceKind {
  const v = value ?? "none";
  if (RECURRENCE_OPTIONS.some((o) => o.id === v)) return v as RecurrenceKind;
  return "none";
}
