import type { ReactNode } from "react";

/** Inline `code` and **bold** spans — no block parsing. */
function renderInline(text: string): ReactNode[] {
  const parts: ReactNode[] = [];
  const re = /(\*\*(.+?)\*\*|`([^`]+)`)/g;
  let last = 0;
  let key = 0;
  let match: RegExpExecArray | null;

  while ((match = re.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(text.slice(last, match.index));
    }
    if (match[0].startsWith("**")) {
      parts.push(
        <strong key={key++} className="font-semibold text-[var(--color-text-main)]">
          {match[2]}
        </strong>,
      );
    } else {
      parts.push(
        <code
          key={key++}
          className="rounded-[5px] bg-[var(--color-shell-chrome)] px-1 py-px font-mono text-[12px] text-[var(--color-text-main)]"
        >
          {match[3]}
        </code>,
      );
    }
    last = re.lastIndex;
  }

  if (last < text.length) {
    parts.push(text.slice(last));
  }

  return parts.length ? parts : [text];
}

function isBulletLine(line: string): boolean {
  return /^[-•]\s/.test(line);
}

function bulletText(line: string): string {
  return line.replace(/^[-•]\s+/, "");
}

/**
 * Minimal markdown for assistant replies: paragraphs, `- ` / `• ` bullets, **bold**, `code`.
 * No external markdown dependency.
 */
export function SimpleMarkdown({ content }: { content: string }) {
  const lines = content.split("\n");
  const blocks: ReactNode[] = [];
  let bullets: string[] = [];
  let key = 0;

  const flushBullets = () => {
    if (!bullets.length) return;
    blocks.push(
      <ul key={key++} className="my-1 space-y-0.5">
        {bullets.map((item, i) => (
          <li key={i} className="flex gap-2 pl-0.5">
            <span className="shrink-0 text-[var(--color-text-light)]">•</span>
            <span className="min-w-0">{renderInline(item)}</span>
          </li>
        ))}
      </ul>,
    );
    bullets = [];
  };

  for (const line of lines) {
    if (isBulletLine(line)) {
      bullets.push(bulletText(line));
      continue;
    }
    if (line.trim() === "") {
      flushBullets();
      continue;
    }
    flushBullets();
    blocks.push(
      <p key={key++} className="my-0.5 leading-relaxed">
        {renderInline(line)}
      </p>,
    );
  }
  flushBullets();

  return <div className="space-y-0.5">{blocks}</div>;
}
