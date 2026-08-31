import type { NavigateTarget } from "./types";

const NAVIGATE_EVENT = "college:navigate";

/** Dispatch a shell navigation event. Omit `page` to restore the last page visited in that hub. */
export function navigate(target: NavigateTarget) {
  window.dispatchEvent(
    new CustomEvent(NAVIGATE_EVENT, {
      detail: target,
    }),
  );
}

export { NAVIGATE_EVENT };
