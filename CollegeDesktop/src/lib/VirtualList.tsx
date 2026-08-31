import { useMemo, useRef, useState, useEffect, type ReactNode } from "react";

/** Simple fixed-row virtual list for long boards / ledgers. */
export function VirtualList<T>({
  items,
  rowHeight,
  height,
  renderRow,
  className,
  overscan = 6,
}: {
  items: T[];
  rowHeight: number;
  height: number;
  renderRow: (item: T, index: number) => ReactNode;
  className?: string;
  overscan?: number;
}) {
  const scrollerRef = useRef<HTMLDivElement>(null);
  const [scrollTop, setScrollTop] = useState(0);

  useEffect(() => {
    const el = scrollerRef.current;
    if (!el) return;
    const onScroll = () => setScrollTop(el.scrollTop);
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => el.removeEventListener("scroll", onScroll);
  }, []);

  const { start, end, offsetY } = useMemo(() => {
    const startIdx = Math.max(0, Math.floor(scrollTop / rowHeight) - overscan);
    const visible = Math.ceil(height / rowHeight) + overscan * 2;
    const endIdx = Math.min(items.length, startIdx + visible);
    return { start: startIdx, end: endIdx, offsetY: startIdx * rowHeight };
  }, [scrollTop, rowHeight, height, items.length, overscan]);

  const slice = items.slice(start, end);

  return (
    <div ref={scrollerRef} className={className} style={{ height, overflow: "auto" }}>
      <div style={{ height: items.length * rowHeight, position: "relative" }}>
        <div style={{ transform: `translateY(${offsetY}px)` }}>
          {slice.map((item, i) => renderRow(item, start + i))}
        </div>
      </div>
    </div>
  );
}
