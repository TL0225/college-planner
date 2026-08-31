import { createContext, useContext } from "react";
import type { ModuleId } from "./types";

export type ShellNavigationValue = {
  module: ModuleId;
  page: string;
  /** Navigate to a hub, optionally a specific page. Omit page to restore the last page for that hub. */
  go: (hub: ModuleId, page?: string, title?: string) => void;
  /** Switch hubs and restore the last page visited in that hub. */
  switchModule: (hub: ModuleId) => void;
  /** Change page within the current hub (persisted per hub). */
  switchPage: (page: string) => void;
  /** Open settings (restores last settings page) or return to the previous hub if already in settings. */
  openSettings: () => void;
};

const ShellNavigationContext = createContext<ShellNavigationValue | null>(null);

export function useShellNavigation(): ShellNavigationValue {
  const ctx = useContext(ShellNavigationContext);
  if (!ctx) {
    throw new Error("useShellNavigation must be used within ShellNavigationProvider");
  }
  return ctx;
}

export function useShellNavigationOptional(): ShellNavigationValue | null {
  return useContext(ShellNavigationContext);
}

export const ShellNavigationProvider = ShellNavigationContext.Provider;
