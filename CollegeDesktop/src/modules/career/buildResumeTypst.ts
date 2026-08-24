import { save } from "@tauri-apps/plugin-dialog";
import { tempDir, join } from "@tauri-apps/api/path";
import { convertFileSrc } from "@tauri-apps/api/core";
import { ipc } from "../../lib/ipc";
import type { BuildResumeMarkdownInput, ResumeExportSection } from "./buildResumeMarkdown";
import { resolveSectionOrder } from "./buildResumeMarkdown";

export type BuildResumeTypstInput = BuildResumeMarkdownInput;

function formatResumeDate(value?: string | null): string {
  if (!value) return "";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString(undefined, { month: "short", year: "numeric" });
}

function formatExperienceDates(start?: string | null, end?: string | null): string {
  const startLabel = formatResumeDate(start);
  const endLabel = end ? formatResumeDate(end) : "Present";
  if (!startLabel && !end) return "";
  if (!startLabel) return endLabel;
  return `${startLabel} – ${endLabel}`;
}

function summaryToBullets(summary: string): string[] {
  const lines = summary
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length === 0) return [];
  return lines.map((line) => line.replace(/^[-*•]\s+/, ""));
}

function joinContactParts(parts: string[]): string {
  return parts.filter((p) => p.trim()).join(" · ");
}

/** Escape user text for Typst markup mode (outside of code blocks). */
export function escapeTypstMarkup(text: string): string {
  return text
    .replace(/\\/g, "\\\\")
    .replace(/#/g, "\\#")
    .replace(/\$/g, "\\$")
    .replace(/@/g, "\\@")
    .replace(/_/g, "\\_")
    .replace(/\*/g, "\\*")
    .replace(/\[/g, "\\[")
    .replace(/\]/g, "\\]")
    .replace(/</g, "\\<")
    .replace(/>/g, "\\>");
}

function typstLine(text: string): string {
  return escapeTypstMarkup(text);
}

function typstBullets(bullets: string[]): string[] {
  return bullets.map((bullet) => `- ${typstLine(bullet)}`);
}

export async function compileResumeTypstToPdf(typstSource: string): Promise<"cancelled" | "ok"> {
  const pdfPath = await save({
    title: "Save compiled resume PDF",
    defaultPath: "resume-draft.pdf",
    filters: [{ name: "PDF", extensions: ["pdf"] }],
  });
  if (!pdfPath) return "cancelled";

  await ipc.careerCompileTypstPdf(typstSource, pdfPath);
  return "ok";
}

/** Compile Typst to a temp PDF for in-pane preview (requires local typst CLI). */
export async function compileResumeTypstPdfPreview(typstSource: string): Promise<string | null> {
  if (!typstSource.trim()) return null;
  const dir = await tempDir();
  const pdfPath = await join(dir, `college-resume-preview-${Date.now()}.pdf`);
  await ipc.careerCompileTypstPdf(typstSource, pdfPath);
  return convertFileSrc(pdfPath);
}

export function buildResumeTypst(input: BuildResumeTypstInput): string {
  const { identity, experiences, achievements, tailoring } = input;
  const skills = (input.skills ?? []).map((s) => s.trim()).filter(Boolean);
  const projects = input.projects ?? [];
  const includeBrag = input.includeBragBook !== false;
  const bragEntries = includeBrag ? (input.bragEntries ?? []) : [];

  const lines: string[] = [
    '#set page(paper: "us-letter", margin: (x: 0.75in, y: 0.75in))',
    '#set text(font: "New Computer Modern", size: 10.5pt)',
    "#set par(justify: true, spacing: 0.65em)",
    '#show heading.where(level: 1): set text(size: 17pt, weight: "bold")',
    '#show heading.where(level: 2): set text(size: 12pt, weight: "bold")',
    '#show heading.where(level: 3): set text(size: 11pt, weight: "bold")',
    "",
  ];

  const name = identity.fullName.trim() || "Resume Draft";
  lines.push(`= ${typstLine(name)}`);
  lines.push("");

  const contact = joinContactParts([
    identity.email.trim(),
    identity.universityName.trim(),
    identity.major.trim(),
    identity.graduationYear != null ? `Class of ${identity.graduationYear}` : "",
  ]);
  if (contact) {
    lines.push(typstLine(contact));
    lines.push("");
  }

  const role = tailoring?.targetRole.trim() ?? "";
  const company = tailoring?.targetCompany.trim() ?? "";
  const tailoringNotes = tailoring?.notes?.trim() ?? "";
  if (role || company || tailoringNotes) {
    lines.push("#block(inset: 8pt, fill: luma(245), radius: 4pt)[");
    if (role || company) {
      const target = [role, company ? `@ ${company}` : ""].filter(Boolean).join(" ");
      lines.push(`  *Target:* ${typstLine(target)}`);
    }
    if (tailoringNotes) {
      for (const noteLine of tailoringNotes.split(/\r?\n/)) {
        const trimmed = noteLine.trim();
        if (trimmed) lines.push(`  ${typstLine(trimmed)}`);
      }
    }
    lines.push("]");
    lines.push("");
  }

  const hasEducation =
    identity.universityName.trim() || identity.major.trim() || identity.graduationYear != null;

  const sectionBlocks: Record<ResumeExportSection, string[]> = {
    education: hasEducation
      ? (() => {
          const block: string[] = ["== Education", ""];
          const schoolLine = [identity.universityName.trim(), identity.major.trim()]
            .filter(Boolean)
            .join(" — ");
          if (schoolLine) block.push(`*${typstLine(schoolLine)}*`);
          if (identity.graduationYear != null) {
            block.push(`Expected graduation: ${identity.graduationYear}`);
          }
          block.push("");
          return block;
        })()
      : [],
    experience:
      experiences.length > 0
        ? (() => {
            const block: string[] = ["== Experience", ""];
            for (const exp of experiences) {
              const heading = [exp.title.trim(), exp.organization.trim()].filter(Boolean).join(" — ");
              block.push(`=== ${typstLine(heading || "Experience")}`);
              const dates = formatExperienceDates(exp.startDate, exp.endDate);
              if (dates) {
                block.push(`_${typstLine(dates)}_`);
                block.push("");
              }
              const bullets = summaryToBullets(exp.summary);
              if (bullets.length > 0) {
                block.push(...typstBullets(bullets));
              }
              block.push("");
            }
            return block;
          })()
        : [],
    projects:
      projects.length > 0
        ? (() => {
            const block: string[] = ["== Projects", ""];
            for (const project of projects) {
              const title = project.title.trim() || "Project";
              const link = project.link?.trim() ?? "";
              block.push(`=== ${typstLine(title)}`);
              if (link) {
                block.push(`_${typstLine(link)}_`);
                block.push("");
              }
              const bullets = summaryToBullets(project.summary);
              if (bullets.length > 0) {
                block.push(...typstBullets(bullets));
              }
              block.push("");
            }
            return block;
          })()
        : [],
    skills:
      skills.length > 0 || achievements.length > 0
        ? (() => {
            const block: string[] = [];
            if (skills.length > 0) {
              block.push("== Skills", "", typstLine(skills.join(" · ")), "");
            }
            if (achievements.length > 0) {
              block.push("== Achievements", "");
              for (const ach of achievements) {
                const title = ach.title.trim() || "Achievement";
                const issuer = ach.issuer.trim();
                const notes = ach.notes.trim();
                const prefix = issuer
                  ? `*${typstLine(title)}* (${typstLine(issuer)})`
                  : `*${typstLine(title)}*`;
                block.push(notes ? `- ${prefix} — ${typstLine(notes)}` : `- ${prefix}`);
              }
              block.push("");
            }
            return block;
          })()
        : [],
    brag:
      bragEntries.length > 0
        ? (() => {
            const block: string[] = ["== Highlights", ""];
            for (const entry of bragEntries) {
              block.push(`=== ${typstLine(entry.title.trim() || "Highlight")}`);
              const when = formatResumeDate(entry.occurredAt);
              if (when) {
                block.push(`_${typstLine(when)}_`);
                block.push("");
              }
              const summary = entry.summary.trim();
              if (summary) {
                block.push(...typstBullets(summaryToBullets(summary)));
              }
              const evidence = entry.evidenceNote.trim();
              if (evidence) {
                block.push("");
                block.push(`_Evidence: ${typstLine(evidence)}_`);
              }
              block.push("");
            }
            return block;
          })()
        : [],
  };

  for (const section of resolveSectionOrder(input)) {
    lines.push(...sectionBlocks[section]);
  }

  return lines.join("\n").trimEnd() + "\n";
}
