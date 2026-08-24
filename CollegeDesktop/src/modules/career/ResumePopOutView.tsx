import { ResumeLiveBuilder } from "./ResumeLiveBuilder";

/** Standalone resume builder window (`/?popout=resume`). */
export function ResumePopOutView() {
  return (
    <div className="flex h-screen flex-col bg-[var(--color-content-bg)]">
      <header className="border-b border-[var(--color-chrome-stroke)] px-4 py-2.5">
        <h1 className="text-[14px] font-semibold text-[var(--color-text-main)]">Resume builder</h1>
        <p className="text-[11px] text-[var(--color-text-light)]">
          Pop-out window — edits sync with the main College app via shared profile data.
        </p>
      </header>
      <div className="min-h-0 flex-1 overflow-auto p-3">
        <ResumeLiveBuilder />
      </div>
    </div>
  );
}
