import { useState } from "react";
import { Button } from "./Button";
import { spacing } from "../tokens";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";

export type GuidedAction = {
  label: string;
  onClick: () => void;
  variant?: "primary" | "secondary";
};

export function GuidedEmptyState({
  title,
  subtitle,
  primaryAction,
  secondaryAction,
  showDemoSeed = false,
  onDemoSeeded,
}: {
  title: string;
  subtitle?: string;
  primaryAction?: GuidedAction;
  secondaryAction?: GuidedAction;
  /** Show a "Try demo data" button that seeds sample data in-context. */
  showDemoSeed?: boolean;
  onDemoSeeded?: () => void;
}) {
  const [seeding, setSeeding] = useState(false);

  const tryDemo = async () => {
    setSeeding(true);
    try {
      await ipc.demoSeedSampleData();
      showToast("Example semester loaded", "success");
      onDemoSeeded?.();
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setSeeding(false);
    }
  };

  return (
    <div
      className="flex flex-col items-start justify-center"
      style={{ gap: spacing.sm, padding: `${spacing.lg}px 0` }}
    >
      <h3
        className="font-semibold tracking-tight"
        style={{ fontFamily: "var(--font-display)", fontSize: 17, color: "var(--registrar-ink)" }}
      >
        {title}
      </h3>
      {subtitle && (
        <p className="max-w-md text-body leading-relaxed text-[var(--color-text-light)]">{subtitle}</p>
      )}
      <div className="flex flex-wrap gap-2 pt-1">
        {showDemoSeed && (
          <Button size="sm" disabled={seeding} onClick={() => void tryDemo()}>
            {seeding ? "Loading…" : "Try demo data"}
          </Button>
        )}
        {primaryAction && (
          <Button
            size="sm"
            variant={primaryAction.variant === "secondary" ? "secondary" : undefined}
            onClick={primaryAction.onClick}
          >
            {primaryAction.label}
          </Button>
        )}
        {secondaryAction && (
          <Button
            size="sm"
            variant={secondaryAction.variant === "secondary" ? "secondary" : "ghost"}
            onClick={secondaryAction.onClick}
          >
            {secondaryAction.label}
          </Button>
        )}
      </div>
    </div>
  );
}
