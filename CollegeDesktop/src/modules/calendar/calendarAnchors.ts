export type CalendarAnchor = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export function anchorFromElement(el: HTMLElement): CalendarAnchor {
  const r = el.getBoundingClientRect();
  return { x: r.left, y: r.top, width: r.width, height: r.height };
}

export const DEFAULT_EVENT_COLOR = "#a6813f";

export const accentSoft = "color-mix(in srgb, var(--registrar-accent) 14%, transparent)";
