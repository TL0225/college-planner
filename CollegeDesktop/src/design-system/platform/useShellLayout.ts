import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";

export type Density = "compact" | "default" | "comfortable";
export type DensityPreference = Density | "auto";
export type ShellBreakpoint = "narrow" | "medium" | "wide";

export type ShellLayoutState = {
  width: number;
  height: number;
  density: Density;
  breakpoint: ShellBreakpoint;
  sidebarCollapsed: boolean;
  inspectorOverlay: boolean;
};

function breakpointFor(width: number): ShellBreakpoint {
  if (width < 1024) return "narrow";
  if (width < 1440) return "medium";
  return "wide";
}

export function resolveDensity(pref: DensityPreference, width: number): Density {
  if (pref !== "auto") return pref;
  if (width < 1024) return "compact";
  if (width >= 1440) return "comfortable";
  return "default";
}

export function useShellLayout(resolvedDensity: Density = "default"): ShellLayoutState {
  const [size, setSize] = useState({ width: 1280, height: 800 });

  useEffect(() => {
    const win = getCurrentWindow();
    const sync = () => {
      void win.innerSize().then((s) => {
        setSize({ width: s.width, height: s.height });
      });
    };
    sync();
    let unlisten: (() => void) | undefined;
    void win.onResized(sync).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, []);

  const breakpoint = breakpointFor(size.width);

  return {
    width: size.width,
    height: size.height,
    density: resolvedDensity,
    breakpoint,
    sidebarCollapsed: size.width < 1024,
    inspectorOverlay: size.width < 1100,
  };
}

export function densityScale(density: Density): number {
  switch (density) {
    case "compact":
      return 0.92;
    case "comfortable":
      return 1.08;
    default:
      return 1;
  }
}
