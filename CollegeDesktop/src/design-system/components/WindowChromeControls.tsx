import { useCallback, useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Minus, Square, X, Copy } from "lucide-react";

/** Native-feeling window controls for undecorated Windows / custom chrome. */
export function WindowChromeControls() {
  const [maximized, setMaximized] = useState(false);

  useEffect(() => {
    const win = getCurrentWindow();
    void win.isMaximized().then(setMaximized).catch(() => {});
    let unlisten: (() => void) | undefined;
    void win
      .onResized(() => {
        void win.isMaximized().then(setMaximized).catch(() => {});
      })
      .then((fn) => {
        unlisten = fn;
      })
      .catch(() => {});
    return () => unlisten?.();
  }, []);

  const onMinimize = useCallback(() => {
    void getCurrentWindow().minimize();
  }, []);
  const onToggleMax = useCallback(() => {
    void getCurrentWindow().toggleMaximize();
  }, []);
  const onClose = useCallback(() => {
    void getCurrentWindow().close();
  }, []);

  const btn =
    "inline-flex h-8 w-11 items-center justify-center text-[var(--color-text-light)] transition-colors hover:bg-[var(--color-row-hover)] hover:text-[var(--color-text-main)]";

  return (
    <div className="flex shrink-0 items-stretch self-stretch" data-tauri-drag-region="false">
      <button type="button" className={btn} aria-label="Minimize" onClick={onMinimize}>
        <Minus size={14} strokeWidth={2} />
      </button>
      <button
        type="button"
        className={btn}
        aria-label={maximized ? "Restore" : "Maximize"}
        onClick={onToggleMax}
      >
        {maximized ? <Copy size={12} strokeWidth={2} /> : <Square size={12} strokeWidth={2} />}
      </button>
      <button
        type="button"
        className={`${btn} hover:bg-[var(--color-error)] hover:text-white`}
        aria-label="Close"
        onClick={onClose}
      >
        <X size={14} strokeWidth={2} />
      </button>
    </div>
  );
}
