import type { CSSProperties, ReactNode } from "react";
import type { AiRuntimeStatus } from "@/lib/ipc";

export const insetPanelStyle: CSSProperties = {
  borderRadius: 10,
  border: "1px solid var(--color-chrome-stroke)",
  background: "var(--color-content-surface)",
  boxShadow: "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
};

export function StatusNote({ children }: { children: ReactNode }) {
  return (
    <p
      className="mt-2 px-2.5 py-2 text-caption leading-relaxed"
      style={insetPanelStyle}
    >
      {children}
    </p>
  );
}

export function aiReadyCount(ai: AiRuntimeStatus | null): { ready: number; total: number } {
  if (!ai) return { ready: 0, total: 2 };
  let ready = 0;
  if (ai.embeddingsReady) ready += 1;
  if (ai.llmReady) ready += 1;
  return { ready, total: 2 };
}

export function themeLabel(value: string | undefined): string {
  switch (value) {
    case "light":
      return "Light";
    case "dark":
      return "Dark";
    default:
      return "System";
  }
}
