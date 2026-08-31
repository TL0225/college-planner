import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  FormField,
  fieldControlClass,
} from "@/design-system";
import { useSettings } from "../useSettings";

export function SettingsShortcutsPage() {
  const { shortcuts, saveShortcuts, shortcutDraft, setShortcutDraft } = useSettings();

  return (
    <AppCard title="Web shortcuts">
      <p className="mb-3 text-meta leading-relaxed">
        Quick links surfaced in the sidebar and navigation shortcuts.
      </p>
      {shortcuts.length === 0 ? (
        <EmptyState title="No shortcuts" body="Add your registrar, email, or LMS links below." />
      ) : (
        <ul className="mb-3 divide-y divide-[var(--color-chrome-stroke)]">
          {shortcuts.map((s) => (
            <li key={s.id} className="flex items-center gap-2 py-2">
              <div className="min-w-0 flex-1">
                <ListRow title={s.title} subtitle={s.url} />
              </div>
              <Button
                size="sm"
                variant="danger"
                onClick={() =>
                  void saveShortcuts(shortcuts.filter((x) => x.id !== s.id))
                }
              >
                Remove
              </Button>
            </li>
          ))}
        </ul>
      )}
      <div className="grid gap-2 sm:grid-cols-2">
        <FormField label="Title">
          <input
            className={fieldControlClass}
            value={shortcutDraft.title}
            onChange={(e) => setShortcutDraft((d) => ({ ...d, title: e.target.value }))}
          />
        </FormField>
        <FormField label="URL">
          <input
            className={fieldControlClass}
            value={shortcutDraft.url}
            onChange={(e) => setShortcutDraft((d) => ({ ...d, url: e.target.value }))}
          />
        </FormField>
      </div>
      <Button
        size="sm"
        className="mt-3"
        disabled={!shortcutDraft.title.trim() || !shortcutDraft.url.trim()}
        onClick={() => {
          const next = [
            ...shortcuts,
            {
              id: crypto.randomUUID(),
              title: shortcutDraft.title.trim(),
              url: shortcutDraft.url.trim(),
            },
          ];
          void saveShortcuts(next);
          setShortcutDraft({ title: "", url: "" });
        }}
      >
        Add shortcut
      </Button>
    </AppCard>
  );
}
