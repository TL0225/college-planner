import { createContext, useContext, useEffect, useState, type ReactNode } from "react";

export type ShellBounds = {
  left: number;
  top: number;
  width: number;
  height: number;
};

const ShellBoundsContext = createContext<ShellBounds | null>(null);

export function ShellBoundsProvider({
  children,
  rootRef,
}: {
  children: ReactNode;
  rootRef: React.RefObject<HTMLElement | null>;
}) {
  const [bounds, setBounds] = useState<ShellBounds>({
    left: 0,
    top: 0,
    width: typeof window !== "undefined" ? window.innerWidth : 1280,
    height: typeof window !== "undefined" ? window.innerHeight : 800,
  });

  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;

    const sync = () => {
      const r = el.getBoundingClientRect();
      setBounds({ left: r.left, top: r.top, width: r.width, height: r.height });
    };

    sync();
    const ro = new ResizeObserver(sync);
    ro.observe(el);
    window.addEventListener("resize", sync);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", sync);
    };
  }, [rootRef]);

  return <ShellBoundsContext.Provider value={bounds}>{children}</ShellBoundsContext.Provider>;
}

export function useShellBounds(): ShellBounds {
  const ctx = useContext(ShellBoundsContext);
  if (!ctx) {
    return {
      left: 0,
      top: 0,
      width: typeof window !== "undefined" ? window.innerWidth : 1280,
      height: typeof window !== "undefined" ? window.innerHeight : 800,
    };
  }
  return ctx;
}

export function clampToBounds(
  x: number,
  y: number,
  panelW: number,
  panelH: number,
  bounds: ShellBounds,
  margin = 8,
): { x: number; y: number } {
  const minX = bounds.left + margin;
  const minY = bounds.top + margin;
  const maxX = bounds.left + bounds.width - panelW - margin;
  const maxY = bounds.top + bounds.height - panelH - margin;
  return {
    x: Math.min(Math.max(x, minX), Math.max(minX, maxX)),
    y: Math.min(Math.max(y, minY), Math.max(minY, maxY)),
  };
}
