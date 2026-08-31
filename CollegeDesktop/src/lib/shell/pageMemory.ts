import type { ModuleId } from "./types";
import { defaultPageFor } from "./defaults";

export const PAGES_BY_MODULE_KEY = "shell.pagesByModule";

export function readPagesByModule(values: Record<string, string>): Partial<Record<ModuleId, string>> {
  try {
    const raw = values[PAGES_BY_MODULE_KEY];
    if (!raw) return {};
    const parsed = JSON.parse(raw) as Record<string, string>;
    if (!parsed || typeof parsed !== "object") return {};
    return parsed as Partial<Record<ModuleId, string>>;
  } catch {
    return {};
  }
}

export function resolveModulePage(
  pages: Partial<Record<ModuleId, string>>,
  module: ModuleId,
  explicitPage?: string,
): string {
  if (explicitPage) return explicitPage;
  return pages[module] ?? defaultPageFor(module);
}
