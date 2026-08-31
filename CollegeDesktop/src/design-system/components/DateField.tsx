import { fieldControlClass } from "./Button";
import { cn } from "../cn";

export function DateField({
  value,
  onChange,
  className,
  "aria-label": ariaLabel,
}: {
  value: string;
  onChange: (value: string) => void;
  className?: string;
  "aria-label"?: string;
}) {
  return (
    <input
      type="date"
      className={cn(fieldControlClass, "text-body", className)}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      aria-label={ariaLabel ?? "Date"}
    />
  );
}

export function CompactDateField({
  value,
  onChange,
  className,
}: {
  value: string;
  onChange: (value: string) => void;
  className?: string;
}) {
  return (
    <DateField
      value={value}
      onChange={onChange}
      className={cn("h-8 px-2 py-1", className)}
      aria-label="Date"
    />
  );
}
