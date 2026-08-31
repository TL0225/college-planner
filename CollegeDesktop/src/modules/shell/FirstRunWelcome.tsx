import { useState } from "react";
import { ModalSheet, Button, FormField, fieldControlClass, usePlatform } from "@/design-system";
import { ipc } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { formatIpcError } from "@/lib/ipc";

const STEPS = [
  { id: "identity", title: "About you", hint: "Tell us a bit about yourself" },
  { id: "demo", title: "See it in action", hint: "Start with a ready-made example semester" },
  { id: "ready", title: "You're ready", hint: "Your schedule, courses, and tasks are on Home" },
] as const;

export function FirstRunWelcome({
  open,
  onDismiss,
  onComplete,
}: {
  open: boolean;
  onDismiss: () => void;
  /** Called after demo seed (if enabled) so parent can refresh data. */
  onComplete?: () => void;
}) {
  const { modKey } = usePlatform();
  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [showContact, setShowContact] = useState(false);
  const [identity, setIdentity] = useState({
    fullName: "",
    email: "",
    universityName: "",
    phone: "",
  });
  const [loadSample, setLoadSample] = useState(true);

  const saveIdentity = async () => {
    if (identity.fullName.trim()) {
      await ipc.profileUpsertIdentity({
        fullName: identity.fullName.trim(),
        email: identity.email.trim(),
        universityName: identity.universityName.trim(),
        major: "",
        graduationYear: undefined,
      });
    }
    if (identity.phone.trim()) {
      await ipc.settingsSet("profile.phone", identity.phone.trim());
    }
  };

  const finish = async (seedDemo: boolean) => {
    setBusy(true);
    try {
      await saveIdentity();
      if (seedDemo) {
        await ipc.demoSeedSampleData();
      }
      await ipc.settingsSet("shell.onboarded", "true");
      onComplete?.();
      onDismiss();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const skip = async () => {
    setBusy(true);
    try {
      await saveIdentity();
      if (step >= 1 && loadSample) {
        await ipc.demoSeedSampleData();
        onComplete?.();
      }
      await ipc.settingsSet("shell.onboarded", "true");
      onDismiss();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const current = STEPS[step];

  return (
    <ModalSheet
      open={open}
      onOpenChange={(v) => !v && void skip()}
      title={`Welcome · ${current.title}`}
    >
      <div className="space-y-4">
        <div className="flex gap-1">
          {STEPS.map((s, i) => (
            <div
              key={s.id}
              className="h-1 flex-1 rounded-full"
              style={{
                background:
                  i <= step ? "var(--color-primary)" : "var(--color-chrome-stroke)",
              }}
            />
          ))}
        </div>
        <p className="text-meta">{current.hint}</p>

        {step === 0 && (
          <div className="space-y-3">
            <FormField label="Your name">
              <input
                className={fieldControlClass}
                value={identity.fullName}
                onChange={(e) => setIdentity((v) => ({ ...v, fullName: e.target.value }))}
                placeholder="Alex Johnson"
                autoFocus
              />
            </FormField>
            <FormField label="School">
              <input
                className={fieldControlClass}
                value={identity.universityName}
                onChange={(e) => setIdentity((v) => ({ ...v, universityName: e.target.value }))}
                placeholder="State University"
              />
            </FormField>
            {!showContact ? (
              <button
                type="button"
                className="text-meta text-[var(--color-primary)] hover:underline"
                onClick={() => setShowContact(true)}
              >
                Add email or phone (optional)
              </button>
            ) : (
              <>
                <FormField label="Email (optional)">
                  <input
                    className={fieldControlClass}
                    value={identity.email}
                    onChange={(e) => setIdentity((v) => ({ ...v, email: e.target.value }))}
                  />
                </FormField>
                <FormField label="Phone (optional)">
                  <input
                    className={fieldControlClass}
                    value={identity.phone}
                    onChange={(e) => setIdentity((v) => ({ ...v, phone: e.target.value }))}
                  />
                </FormField>
              </>
            )}
          </div>
        )}

        {step === 1 && (
          <div className="space-y-4">
            <label className="flex cursor-pointer items-start gap-3 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] p-4">
              <input
                type="checkbox"
                className="mt-1"
                checked={loadSample}
                onChange={(e) => setLoadSample(e.target.checked)}
              />
              <div>
                <div className="text-body font-medium text-[var(--color-text-main)]">
                  Start with example semester
                </div>
                <p className="mt-1 text-meta leading-relaxed">
                  See a full schedule, courses, tasks, and career applications right away. You can
                  clear it anytime.
                </p>
              </div>
            </label>
          </div>
        )}

        {step === 2 && (
          <div className="space-y-3">
            <p className="text-body leading-relaxed">
              Your schedule, courses, and tasks are on <strong>Home</strong>. Connect calendars and
              course portals later under Settings when you&apos;re ready.
            </p>
            <ul className="list-inside list-disc space-y-1 text-meta">
              <li>
                <kbd className="rounded border border-[var(--color-chrome-stroke)] px-1">{modKey}+K</kbd>{" "}
                search anything
              </li>
              <li>
                <kbd className="rounded border border-[var(--color-chrome-stroke)] px-1">{modKey}+J</kbd>{" "}
                ask the assistant
              </li>
            </ul>
          </div>
        )}

        <div className="flex flex-wrap justify-between gap-2">
          <Button
            variant="secondary"
            disabled={step === 0 || busy}
            onClick={() => setStep((s) => Math.max(0, s - 1))}
          >
            Back
          </Button>
          <div className="flex gap-2">
            <Button variant="ghost" disabled={busy} onClick={() => void skip()}>
              Skip for now
            </Button>
            {step < STEPS.length - 1 ? (
              <Button
                disabled={busy}
                onClick={async () => {
                  if (step === 0) await saveIdentity().catch(() => undefined);
                  setStep((s) => s + 1);
                }}
              >
                Next
              </Button>
            ) : (
              <Button disabled={busy} onClick={() => void finish(loadSample)}>
                {busy ? "Setting up…" : "Go to Today"}
              </Button>
            )}
          </div>
        </div>
      </div>
    </ModalSheet>
  );
}
