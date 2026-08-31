import { humanLabel } from "@/lib/copy/humanLabels";
import { StatusChip } from "./StatusChip";

const STATUS_TINTS: Record<string, string> = {
  satisfied: "var(--color-success)",
  in_progress: "var(--color-primary)",
  not_started: "var(--color-text-light)",
  checking: "var(--color-warning)",
  google: "var(--color-primary)",
  outlook: "var(--color-primary)",
};

export function HumanStatusChip({
  value,
  tint,
  filled = false,
  className,
}: {
  value: string;
  tint?: string;
  filled?: boolean;
  className?: string;
}) {
  const title = humanLabel(value);
  const resolvedTint = tint ?? STATUS_TINTS[value] ?? "var(--color-text-light)";
  return <StatusChip title={title} tint={resolvedTint} filled={filled} className={className} />;
}
