import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { GripHorizontal, X } from "lucide-react";
import { Button, FormField, fieldControlClass } from "@/design-system";
import { ipc } from "@/lib/ipc";
import { clampToBounds, useShellBounds } from "@/lib/shell/ShellBoundsContext";
import { EVENT_COLOR_PRESETS } from "./eventColors";
import type { GeocodeResult } from "./locationGeocode";
import { EventLocationMap } from "./EventLocationMap";
import { RECURRENCE_OPTIONS, type RecurrenceKind } from "./recurrence";
import type { CalendarAnchor } from "./calendarAnchors";

const PANEL_WIDTH = 360;
const POS_KEY = "ui.calendarEventPanel.pos";

export type EventFormState = {
  title: string;
  startAt: string;
  endAt: string;
  allDay: boolean;
  location: string;
  color: string;
  recurrence: RecurrenceKind;
  notes: string;
  geocode: GeocodeResult | null;
};

function readStoredOffset(): { x: number; y: number } {
  try {
    const raw = localStorage.getItem(POS_KEY);
    if (!raw) return { x: 0, y: 0 };
    const parsed = JSON.parse(raw) as { x: number; y: number };
    if (typeof parsed.x === "number" && typeof parsed.y === "number") return parsed;
  } catch {
    /* ignore */
  }
  return { x: 0, y: 0 };
}

function basePosition(anchor: CalendarAnchor, bounds: ReturnType<typeof useShellBounds>) {
  const gap = 8;
  let x = anchor.x + anchor.width + gap;
  let y = anchor.y;
  if (x + PANEL_WIDTH > bounds.left + bounds.width - 8) {
    x = anchor.x - PANEL_WIDTH - gap;
  }
  return { x, y };
}

function LocationField({
  value,
  geocode,
  onChange,
}: {
  value: string;
  geocode: GeocodeResult | null;
  onChange: (location: string, geocode: GeocodeResult | null) => void;
}) {
  const [suggestions, setSuggestions] = useState<GeocodeResult[]>([]);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const debounceRef = useRef<number | null>(null);

  const search = useCallback((q: string) => {
    if (debounceRef.current) window.clearTimeout(debounceRef.current);
    if (q.trim().length < 2) {
      setSuggestions([]);
      setOpen(false);
      return;
    }
    debounceRef.current = window.setTimeout(() => {
      setBusy(true);
      void ipc
        .calendarSearchLocations(q.trim())
        .then((hits) => {
          setSuggestions(
            hits.map((h) => ({ lat: h.lat, lon: h.lon, displayName: h.displayName })),
          );
          setOpen(hits.length > 0);
        })
        .catch(() => setSuggestions([]))
        .finally(() => setBusy(false));
    }, 280);
  }, []);

  useEffect(
    () => () => {
      if (debounceRef.current) window.clearTimeout(debounceRef.current);
    },
    [],
  );

  return (
    <div className="relative">
      <input
        className={fieldControlClass}
        value={value}
        placeholder="Search address or place name…"
        onChange={(e) => {
          onChange(e.target.value, null);
          search(e.target.value);
        }}
        onFocus={() => {
          if (suggestions.length > 0) setOpen(true);
        }}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
      />
      {busy && <p className="mt-1 text-caption text-[var(--color-text-light)]">Searching…</p>}
      {open && suggestions.length > 0 && (
        <ul
          className="absolute z-10 mt-1 max-h-40 w-full overflow-y-auto rounded-[6px] border border-[var(--registrar-rule)] bg-[var(--registrar-surface)] shadow-md"
          role="listbox"
        >
          {suggestions.map((s) => (
            <li key={`${s.lat}-${s.lon}`}>
              <button
                type="button"
                className="w-full px-2.5 py-2 text-left text-caption hover:bg-[var(--color-row-hover)]"
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => {
                  onChange(s.displayName, s);
                  setOpen(false);
                }}
              >
                {s.displayName}
              </button>
            </li>
          ))}
        </ul>
      )}
      {geocode ? <EventLocationMap geocode={geocode} /> : null}
    </div>
  );
}

export function CalendarEventPanel({
  anchor,
  title,
  form,
  onChange,
  editing,
  onSave,
  onDelete,
  onClose,
}: {
  anchor: CalendarAnchor;
  title: string;
  form: EventFormState;
  onChange: (next: EventFormState) => void;
  editing: boolean;
  onSave: () => void;
  onDelete?: () => void;
  onClose: () => void;
}) {
  const bounds = useShellBounds();
  const panelRef = useRef<HTMLDivElement>(null);
  const dragOffsetRef = useRef(readStoredOffset());
  const [pos, setPos] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const base = basePosition(anchor, bounds);
    const offset = dragOffsetRef.current;
    const h = panelRef.current?.offsetHeight ?? 420;
    setPos(clampToBounds(base.x + offset.x, base.y + offset.y, PANEL_WIDTH, h, bounds));
  }, [anchor, bounds]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const onDragStart = (e: React.PointerEvent) => {
    e.preventDefault();
    const startX = e.clientX;
    const startY = e.clientY;
    const orig = { ...dragOffsetRef.current };

    const onMove = (ev: PointerEvent) => {
      const nextOffset = {
        x: orig.x + (ev.clientX - startX),
        y: orig.y + (ev.clientY - startY),
      };
      dragOffsetRef.current = nextOffset;
      const base = basePosition(anchor, bounds);
      const h = panelRef.current?.offsetHeight ?? 420;
      setPos(clampToBounds(base.x + nextOffset.x, base.y + nextOffset.y, PANEL_WIDTH, h, bounds));
    };

    const onUp = () => {
      try {
        localStorage.setItem(POS_KEY, JSON.stringify(dragOffsetRef.current));
      } catch {
        /* ignore */
      }
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  };

  const startInput = form.allDay ? form.startAt.slice(0, 10) : form.startAt;
  const endInput = form.allDay
    ? form.endAt.slice(0, 10) || form.startAt.slice(0, 10)
    : form.endAt || form.startAt;

  return createPortal(
    <div
      ref={panelRef}
      className="fixed z-[65] flex flex-col overflow-hidden"
      style={{
        left: pos.x,
        top: pos.y,
        width: PANEL_WIDTH,
        maxHeight: `min(520px, ${Math.max(200, bounds.height - 16)}px)`,
        borderRadius: "var(--registrar-radius)",
        border: "1px solid var(--registrar-rule)",
        background: "var(--registrar-surface)",
        boxShadow: "0 12px 40px rgba(28, 35, 51, 0.16)",
      }}
      role="dialog"
      aria-label={title}
    >
      <div className="flex shrink-0 items-center gap-1 border-b border-[var(--registrar-rule)] px-2 py-1.5">
        <button
          type="button"
          className="inline-flex h-7 w-7 cursor-grab items-center justify-center rounded-[6px] text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)] active:cursor-grabbing"
          aria-label="Drag panel"
          onPointerDown={onDragStart}
        >
          <GripHorizontal size={14} />
        </button>
        <h3
          className="min-w-0 flex-1 truncate text-body font-semibold"
          style={{ fontFamily: "var(--font-display)", color: "var(--registrar-ink)" }}
        >
          {title}
        </h3>
        <button
          type="button"
          className="inline-flex h-7 w-7 items-center justify-center rounded-[6px] text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)]"
          onClick={onClose}
          aria-label="Close"
        >
          <X size={14} />
        </button>
      </div>
      <div className="min-h-0 flex-1 space-y-2.5 overflow-y-auto p-3">
        <FormField label="Title">
          <input
            className={fieldControlClass}
            value={form.title}
            autoFocus
            onChange={(e) => onChange({ ...form, title: e.target.value })}
          />
        </FormField>
        <label className="flex items-center gap-2 text-body">
          <input
            type="checkbox"
            checked={form.allDay}
            onChange={(e) => {
              const allDay = e.target.checked;
              onChange({
                ...form,
                allDay,
                startAt: allDay ? form.startAt.slice(0, 10) : `${form.startAt.slice(0, 10)}T09:00`,
                endAt: allDay
                  ? (form.endAt || form.startAt).slice(0, 10)
                  : form.endAt || form.startAt,
              });
            }}
          />
          All-day
        </label>
        <div className="grid grid-cols-2 gap-2">
          <FormField label="Starts">
            <input
              className={fieldControlClass}
              type={form.allDay ? "date" : "datetime-local"}
              value={startInput}
              onChange={(e) => onChange({ ...form, startAt: e.target.value })}
            />
          </FormField>
          <FormField label="Ends">
            <input
              className={fieldControlClass}
              type={form.allDay ? "date" : "datetime-local"}
              value={endInput}
              onChange={(e) => onChange({ ...form, endAt: e.target.value })}
            />
          </FormField>
        </div>
        <FormField label="Location">
          <LocationField
            value={form.location}
            geocode={form.geocode}
            onChange={(location, geocode) => onChange({ ...form, location, geocode })}
          />
        </FormField>
        <FormField label="Notes">
          <textarea
            className={`${fieldControlClass} min-h-[56px] resize-y`}
            value={form.notes}
            onChange={(e) => onChange({ ...form, notes: e.target.value })}
          />
        </FormField>
        <FormField label="Color">
          <div className="flex flex-wrap gap-1.5">
            {EVENT_COLOR_PRESETS.map((preset) => {
              const swatch = "hex" in preset ? preset.hex : undefined;
              const selected = form.color === preset.id;
              return (
                <button
                  key={preset.id || "default"}
                  type="button"
                  title={preset.label}
                  onClick={() => onChange({ ...form, color: preset.id })}
                  className={`h-6 w-6 rounded-full border-2 transition-transform ${
                    selected ? "scale-110 border-[var(--registrar-ink)]" : "border-transparent"
                  }`}
                  style={
                    swatch
                      ? { backgroundColor: swatch }
                      : { background: "var(--registrar-accent)", opacity: 0.85 }
                  }
                />
              );
            })}
          </div>
        </FormField>
        <FormField label="Repeats">
          <select
            className={fieldControlClass}
            value={form.recurrence}
            onChange={(e) =>
              onChange({ ...form, recurrence: e.target.value as RecurrenceKind })
            }
          >
            {RECURRENCE_OPTIONS.map((opt) => (
              <option key={opt.id} value={opt.id}>
                {opt.label}
              </option>
            ))}
          </select>
        </FormField>
        <div className="flex flex-wrap gap-2 pt-1">
          <Button size="sm" disabled={!form.title.trim()} onClick={onSave}>
            {editing ? "Save" : "Add"}
          </Button>
          {editing && onDelete ? (
            <Button size="sm" variant="danger" onClick={onDelete}>
              Delete
            </Button>
          ) : null}
          <Button size="sm" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
        </div>
      </div>
    </div>,
    document.body,
  );
}

export { anchorFromElement } from "./calendarAnchors";
export type { CalendarAnchor as EventPopoverAnchor } from "./calendarAnchors";
