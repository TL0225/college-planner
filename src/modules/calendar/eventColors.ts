import type { CSSProperties } from "react";

export const EVENT_COLOR_PRESETS = [
  { id: "", label: "Default" },
  { id: "blue", label: "Blue", hex: "#3B82F6" },
  { id: "green", label: "Green", hex: "#10B981" },
  { id: "amber", label: "Amber", hex: "#F59E0B" },
  { id: "red", label: "Red", hex: "#EF4444" },
  { id: "purple", label: "Purple", hex: "#8B5CF6" },
  { id: "pink", label: "Pink", hex: "#EC4899" },
] as const;

export function resolveEventColor(color?: string): string | undefined {
  if (!color) return undefined;
  const preset = EVENT_COLOR_PRESETS.find((p) => p.id === color);
  if (preset && "hex" in preset && preset.hex) return preset.hex;
  if (color.startsWith("#")) return color;
  return undefined;
}

export function eventChipStyle(color?: string): CSSProperties | undefined {
  const hex = resolveEventColor(color);
  if (!hex) return undefined;
  return {
    backgroundColor: `${hex}1F`,
    color: hex,
  };
}
