import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { ChevronDown } from "lucide-react";
import { cn } from "../cn";
import { Button } from "./Button";

export type FilterOption = {
  id: string;
  label: string;
};

export function FilterMenu({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: FilterOption[];
  onChange: (id: string) => void;
}) {
  const selected = options.find((o) => o.id === value);
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger asChild>
        <Button variant="secondary" className="gap-1">
          <span className="text-chrome">{label}:</span>
          <span>{selected?.label ?? value}</span>
          <ChevronDown size={12} />
        </Button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          className={cn(
            "z-50 min-w-[140px] rounded-[10px] border border-[var(--color-chrome-stroke)]",
            "bg-[var(--color-content-surface)] p-1 shadow-[var(--shadow-elevated)]",
          )}
          sideOffset={4}
        >
          {options.map((opt) => (
            <DropdownMenu.Item
              key={opt.id}
              className={cn(
                "cursor-pointer rounded-[6px] px-2.5 py-1.5 text-body outline-none",
                "data-[highlighted]:bg-[var(--color-row-hover)]",
                value === opt.id && "font-semibold text-[var(--color-primary)]",
              )}
              onSelect={() => onChange(opt.id)}
            >
              {opt.label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
