export const PLANNER_DRAG_MIME = "application/x-college-planner-course";

export type PlannerDragPayload = {
  code: string;
  title?: string;
  credits?: number;
  /** When dropping onto a requirement row, set by the drop target. */
  categoryId?: string;
  source?: "requirement" | "planner" | "catalog";
};

export function encodePlannerDragPayload(payload: PlannerDragPayload): string {
  return JSON.stringify({
    code: payload.code.trim().toUpperCase(),
    title: payload.title?.trim() || undefined,
    credits: payload.credits,
    categoryId: payload.categoryId,
    source: payload.source,
  });
}

export function parsePlannerDragPayload(raw: string): PlannerDragPayload | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  try {
    const parsed = JSON.parse(trimmed) as PlannerDragPayload;
    if (parsed.code?.trim()) {
      return {
        code: parsed.code.trim().toUpperCase(),
        title: parsed.title?.trim() || undefined,
        credits: parsed.credits,
        categoryId: parsed.categoryId,
        source: parsed.source,
      };
    }
  } catch {
    // Plain course code fallback (GenEd modal parity).
  }
  if (/^[A-Za-z]{2,4}\s*\d{2,4}[A-Za-z]?$/.test(trimmed.replace(/\s+/g, " "))) {
    return { code: trimmed.replace(/\s+/g, " ").toUpperCase() };
  }
  return trimmed.length <= 12 ? { code: trimmed.toUpperCase() } : null;
}

export function plannerDragDataTransfer(payload: PlannerDragPayload): DataTransfer {
  const encoded = encodePlannerDragPayload(payload);
  const dt = new DataTransfer();
  dt.setData(PLANNER_DRAG_MIME, encoded);
  dt.setData("text/plain", encoded);
  return dt;
}
