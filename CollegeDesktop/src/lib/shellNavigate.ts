import { NAVIGATE_EVENT, navigate } from "./shell/navigate";
import type { NavigateTarget } from "./shell/types";

export type ShellNavigateDetail = NavigateTarget & {
  /** @deprecated use hub — still accepted on college:navigate events from legacy emitters */
  module?: string;
};

export { NAVIGATE_EVENT, navigate };
export type { NavigateTarget };
