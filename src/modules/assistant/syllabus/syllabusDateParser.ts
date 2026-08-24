export function parseLooseDue(hint?: string | null): string | undefined {
  if (!hint?.trim()) return undefined;
  const h = hint.trim();
  const now = new Date();
  const year = now.getFullYear();
  const mdy = h.match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/);
  if (mdy) {
    const m = Number(mdy[1]);
    const d = Number(mdy[2]);
    let y = mdy[3] ? Number(mdy[3]) : year;
    if (y < 100) y += 2000;
    return new Date(y, m - 1, d, 17, 0, 0).toISOString();
  }
  const months: Record<string, number> = {
    jan: 0,
    january: 0,
    feb: 1,
    february: 1,
    mar: 2,
    march: 2,
    apr: 3,
    april: 3,
    may: 4,
    jun: 5,
    june: 5,
    jul: 6,
    july: 6,
    aug: 7,
    august: 7,
    sep: 8,
    sept: 8,
    september: 8,
    oct: 9,
    october: 9,
    nov: 10,
    november: 10,
    dec: 11,
    december: 11,
  };
  const md = h.match(
    /^(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?/i,
  );
  if (md) {
    const monthKey = md[1].toLowerCase().slice(0, 3);
    const month = months[monthKey] ?? months[md[1].toLowerCase()];
    if (month == null) return undefined;
    const day = Number(md[2]);
    const y = md[3] ? Number(md[3]) : year;
    return new Date(y, month, day, 17, 0, 0).toISOString();
  }
  return undefined;
}

export function eventKindTint(kind: string): string {
  switch (kind) {
    case "exam":
      return "var(--color-error)";
    case "quiz":
      return "var(--color-warning)";
    case "project":
      return "var(--color-primary)";
    case "reading":
      return "var(--color-text-light)";
    default:
      return "var(--color-success)";
  }
}
