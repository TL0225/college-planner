import { useState } from "react";
import { ModalSheet, Button, FormField, fieldControlClass } from "@/design-system";
import { ipc } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { formatIpcError } from "@/lib/ipc";

const STEPS = [
  { id: "identity", title: "Identity", hint: "Name, school, and contact" },
  { id: "academic", title: "Academic setup", hint: "Degrees and programs" },
  { id: "history", title: "Academic history", hint: "Transfer credits (optional)" },
  { id: "integrations", title: "Integrations", hint: "LMS and shortcuts" },
  { id: "ready", title: "Ready", hint: "Review and enter workspace" },
] as const;

export function FirstRunWelcome({
  open,
  onDismiss,
  onLoadSample,
}: {
  open: boolean;
  onDismiss: () => void;
  onLoadSample: () => void;
}) {
  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [identity, setIdentity] = useState({
    fullName: "",
    email: "",
    universityName: "",
    phone: "",
  });
  const [lmsUrl, setLmsUrl] = useState("https://canvas.instructure.com");
  const [catalogUrl, setCatalogUrl] = useState("");
  const [loadSample, setLoadSample] = useState(false);

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

  const finish = async () => {
    setBusy(true);
    try {
      await saveIdentity();
      if (lmsUrl.trim()) {
        await ipc.settingsSet("lms.defaultPortalUrl", lmsUrl.trim());
      }
      if (catalogUrl.trim()) {
        await ipc.settingsSet("catalog.portalBaseUrl", catalogUrl.trim());
      }
      if (loadSample) {
        await ipc.demoSeedSampleData();
      }
      await ipc.settingsSet("shell.onboardingStep", String(STEPS.length - 1));
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
      onOpenChange={(v) => !v && onDismiss()}
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
        <p className="text-[12px] text-[var(--color-text-light)]">{current.hint}</p>

        {step === 0 && (
          <div className="space-y-3">
            <FormField label="Full name">
              <input
                className={fieldControlClass}
                value={identity.fullName}
                onChange={(e) => setIdentity((v) => ({ ...v, fullName: e.target.value }))}
              />
            </FormField>
            <FormField label="Email">
              <input
                className={fieldControlClass}
                value={identity.email}
                onChange={(e) => setIdentity((v) => ({ ...v, email: e.target.value }))}
              />
            </FormField>
            <FormField label="University">
              <input
                className={fieldControlClass}
                value={identity.universityName}
                onChange={(e) => setIdentity((v) => ({ ...v, universityName: e.target.value }))}
              />
            </FormField>
            <FormField label="Phone (optional)">
              <input
                className={fieldControlClass}
                value={identity.phone}
                onChange={(e) => setIdentity((v) => ({ ...v, phone: e.target.value }))}
              />
            </FormField>
          </div>
        )}

        {step === 1 && (
          <div className="space-y-3 text-[13px] text-[var(--color-text-main)]">
            <p>
              Set your active program later under Academics → Requirements. You can load demo
              semesters and a CS major audit now, or start with an empty planner.
            </p>
            <label className="flex items-center gap-2 text-[12px]">
              <input
                type="checkbox"
                checked={loadSample}
                onChange={(e) => setLoadSample(e.target.checked)}
              />
              Load sample academic data (recommended for first look)
            </label>
            <FormField label="Course catalog URL (optional)">
              <input
                className={fieldControlClass}
                value={catalogUrl}
                onChange={(e) => setCatalogUrl(e.target.value)}
                placeholder="https://catalog.university.edu"
              />
            </FormField>
          </div>
        )}

        {step === 2 && (
          <p className="text-[13px] leading-relaxed text-[var(--color-text-main)]">
            Transfer equivalencies can be added anytime under College → Transfer. Skip this step if
            you are not bringing credits from another school.
          </p>
        )}

        {step === 3 && (
          <div className="space-y-3">
            <FormField label="Default LMS portal URL">
              <input
                className={fieldControlClass}
                value={lmsUrl}
                onChange={(e) => setLmsUrl(e.target.value)}
              />
            </FormField>
            <p className="text-[12px] text-[var(--color-text-light)]">
              Add web shortcuts anytime in Settings → Shortcuts. They appear in the College sidebar.
            </p>
          </div>
        )}

        {step === 4 && (
          <div className="space-y-3">
            <ul className="list-inside list-disc space-y-1 text-[12px] text-[var(--color-text-light)]">
              <li>
                <kbd className="rounded border border-[var(--color-chrome-stroke)] px-1">⌘K</kbd>{" "}
                command palette
              </li>
              <li>
                <kbd className="rounded border border-[var(--color-chrome-stroke)] px-1">⌘1–7</kbd>{" "}
                switch modules
              </li>
              <li>Your workspace data lives in CollegeDesktop, separate from the Swift app.</li>
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
            <Button variant="ghost" disabled={busy} onClick={onDismiss}>
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
              <Button
                disabled={busy}
                onClick={() => {
                  if (loadSample) onLoadSample();
                  void finish();
                }}
              >
                {busy ? "Setting up…" : "Enter College"}
              </Button>
            )}
          </div>
        </div>
      </div>
    </ModalSheet>
  );
}
