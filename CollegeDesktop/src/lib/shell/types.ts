import type { HubId, ModuleId } from "@/design-system/tokens";

export type { HubId, ModuleId } from "@/design-system/tokens";

export type ShellRecent = {
  module: ModuleId;
  page: string;
  title: string;
};

export type NavigateTarget = {
  hub: ModuleId;
  page?: string;
  title?: string;
  openAi?: boolean;
};

export const HUB_IDS = new Set<string>(["home", "school", "career", "life", "library", "settings"]);

export const PILL_HUB_IDS: HubId[] = ["home", "school", "career", "life", "library"];

export const IA_VERSION = 2;

/** Legacy 7-hub module ids (pre Path D). */
export type LegacyModuleId =
  | "college"
  | "finance"
  | "calendar"
  | "documents"
  | "assistant"
  | "profile";
