import { ModalSheet, Button, usePlatform } from "@/design-system";

export function WhatsNewSheet({
  open,
  onDismiss,
}: {
  open: boolean;
  onDismiss: () => void;
}) {
  const { modKey } = usePlatform();
  return (
    <ModalSheet open={open} onOpenChange={(v) => !v && onDismiss()} title="What's new">
      <div className="space-y-4 text-body">
        <p>College has a new layout built for faster navigation.</p>
        <ul className="list-inside list-disc space-y-1 text-meta">
          <li>
            <strong className="text-[var(--color-text-main)]">Home</strong> — your day at a glance
          </li>
          <li>
            <strong className="text-[var(--color-text-main)]">School</strong> — plan, courses, degree
          </li>
          <li>
            <strong className="text-[var(--color-text-main)]">Life</strong> — schedule and money together
          </li>
          <li>
            <strong className="text-[var(--color-text-main)]">Library</strong> — files and identity
          </li>
          <li>
            Search in the header or press <kbd className="rounded border border-[var(--color-chrome-stroke)] bg-[var(--color-shell-chrome)] px-1 py-0.5 text-[11px] font-semibold text-[var(--color-text-light)]">{modKey}+K</kbd> to jump anywhere
          </li>
          <li>Assistant opens from the sparkles button — no longer a top tab</li>
        </ul>
        <Button onClick={onDismiss}>Got it</Button>
      </div>
    </ModalSheet>
  );
}
