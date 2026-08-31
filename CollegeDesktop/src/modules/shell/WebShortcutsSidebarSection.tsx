import { Link2 } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

export type WebShortcut = { id: string; title: string; url: string };

export function WebShortcutsSidebarSection({
  shortcuts,
  onManage,
}: {
  shortcuts: WebShortcut[];
  onManage: () => void;
}) {
  if (shortcuts.length === 0) return null;
  return (
    <div className="mt-2 border-t border-[var(--color-chrome-stroke)] px-2 pt-2">
      <div className="mb-1.5 px-1 text-label font-semibold uppercase tracking-[0.05em]">
        Web shortcuts
      </div>
      <ul className="space-y-0.5">
        {shortcuts.slice(0, 8).map((s) => (
          <li key={s.id}>
            <button
              type="button"
              className="flex w-full items-center gap-2 rounded-[8px] px-2 py-1.5 text-left text-meta text-[var(--color-text-main)] hover:bg-[var(--color-row-hover)]"
              onClick={() => void openUrl(s.url)}
            >
              <Link2 size={13} className="shrink-0 text-[var(--color-text-light)]" />
              <span className="truncate">{s.title}</span>
            </button>
          </li>
        ))}
      </ul>
      <button
        type="button"
        className="mt-1 w-full rounded-[8px] px-2 py-1.5 text-left text-caption text-[var(--color-primary)] hover:bg-[var(--color-row-hover)]"
        onClick={onManage}
      >
        Manage shortcuts…
      </button>
    </div>
  );
}
