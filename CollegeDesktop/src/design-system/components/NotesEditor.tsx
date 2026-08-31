import { fieldControlClass } from "./Button";
import { cn } from "../cn";

function countWords(value: string): number {
  const trimmed = value.trim();
  return trimmed ? trimmed.split(/\s+/).length : 0;
}

export function NotesEditor({
  value,
  onChange,
  placeholder,
  disabled,
  className,
  minRows = 3,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
  className?: string;
  minRows?: number;
}) {
  const wordCount = countWords(value);

  return (
    <div
      className={cn(
        "overflow-hidden rounded-[10px] border border-[color-mix(in_srgb,var(--color-text-main)_8%,var(--color-chrome-stroke))]",
        "bg-[color-mix(in_srgb,var(--color-text-main)_2%,transparent)]",
        "shadow-[inset_0_1px_0_color-mix(in_srgb,white_35%,transparent)]",
        "focus-within:border-[color-mix(in_srgb,var(--color-primary)_55%,var(--color-chrome-stroke))]",
        "focus-within:ring-2 focus-within:ring-[color-mix(in_srgb,var(--color-primary)_25%,transparent)]",
        disabled && "pointer-events-none opacity-45",
        className,
      )}
    >
      <textarea
        className={cn(
          fieldControlClass,
          "resize-y border-0 bg-transparent shadow-none",
          "text-body placeholder:text-meta",
          "focus:border-transparent focus:ring-0",
        )}
        rows={minRows}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
      />
      <div className="flex items-center justify-end border-t border-[color-mix(in_srgb,var(--color-text-main)_6%,var(--color-chrome-stroke))] px-3 py-1.5">
        <span className="text-meta tabular-nums text-[var(--color-text-light)]">
          {wordCount} {wordCount === 1 ? "word" : "words"}
        </span>
      </div>
    </div>
  );
}
