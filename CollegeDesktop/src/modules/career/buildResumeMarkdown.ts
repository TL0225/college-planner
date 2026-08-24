import type { ProfileIdentity } from "@/lib/ipc";

export type ResumeDraftExperience = {
  title: string;
  organization: string;
  startDate?: string | null;
  endDate?: string | null;
  summary: string;
};

export type ResumeDraftAchievement = {
  title: string;
  issuer: string;
  notes: string;
};

export type ResumeDraftBragEntry = {
  title: string;
  occurredAt?: string | null;
  summary: string;
  evidenceNote: string;
};

export type ResumeDraftProject = {
  title: string;
  summary: string;
  link?: string;
};

export type ResumeProfileTailoring = {
  targetRole: string;
  targetCompany: string;
  notes?: string;
};

export type ResumeExportSection = "experience" | "education" | "skills" | "projects" | "brag";

export const DEFAULT_RESUME_SECTION_ORDER: ResumeExportSection[] = [
  "experience",
  "education",
  "skills",
  "projects",
  "brag",
];

export type BuildResumeMarkdownInput = {
  identity: ProfileIdentity;
  experiences: ResumeDraftExperience[];
  achievements: ResumeDraftAchievement[];
  skills?: string[];
  projects?: ResumeDraftProject[];
  bragEntries?: ResumeDraftBragEntry[];
  includeBragBook?: boolean;
  tailoring?: ResumeProfileTailoring | null;
  sectionOrder?: ResumeExportSection[];
};

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

export function resolveSectionOrder(input: BuildResumeMarkdownInput): ResumeExportSection[] {
  const includeBrag = input.includeBragBook !== false;
  const base = input.sectionOrder?.length
    ? [...input.sectionOrder]
    : [...DEFAULT_RESUME_SECTION_ORDER];
  return base.filter((section) => includeBrag || section !== "brag");
}

export function buildResumeMarkdown(input: BuildResumeMarkdownInput): string {
  const { identity, experiences, achievements, tailoring } = input;
  const skills = (input.skills ?? []).map((s) => s.trim()).filter(Boolean);
  const projects = input.projects ?? [];
  const includeBrag = input.includeBragBook !== false;
  const bragEntries = includeBrag ? (input.bragEntries ?? []) : [];

  const lines: string[] = [];
  const name = identity.fullName.trim() || "Resume Draft";
  lines.push(`# ${name}`);
  lines.push("");

  const contact = joinContactParts([
    identity.email.trim(),
    identity.universityName.trim(),
    identity.major.trim(),
    identity.graduationYear != null ? `Class of ${identity.graduationYear}` : "",
  ]);
  if (contact) {
    lines.push(contact);
    lines.push("");
  }

  const role = tailoring?.targetRole.trim() ?? "";
  const company = tailoring?.targetCompany.trim() ?? "";
  const tailoringNotes = tailoring?.notes?.trim() ?? "";
  if (role || company || tailoringNotes) {
    if (role || company) {
      const target = [role, company ? `@ ${company}` : ""].filter(Boolean).join(" ");
      lines.push(`> **Target:** ${target}`);
    }
    if (tailoringNotes) {
      for (const noteLine of tailoringNotes.split(/\r?\n/)) {
        const trimmed = noteLine.trim();
        if (trimmed) lines.push(`> ${trimmed}`);
      }
    }
    lines.push("");
  }

  const hasEducation =
    identity.universityName.trim() || identity.major.trim() || identity.graduationYear != null;

  const sectionBlocks: Record<ResumeExportSection, string[]> = {
    education: hasEducation
      ? (() => {
          const block: string[] = ["## Education", ""];
          const schoolLine = [identity.universityName.trim(), identity.major.trim()]
            .filter(Boolean)
            .join(" — ");
          if (schoolLine) block.push(`**${schoolLine}**`);
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
            const block: string[] = ["## Experience", ""];
            for (const exp of experiences) {
              const heading = [exp.title.trim(), exp.organization.trim()].filter(Boolean).join(" — ");
              block.push(`### ${heading || "Experience"}`);
              const dates = formatExperienceDates(exp.startDate, exp.endDate);
              if (dates) {
                block.push(`*${dates}*`);
                block.push("");
              }
              for (const bullet of summaryToBullets(exp.summary)) {
                block.push(`- ${bullet}`);
              }
              block.push("");
            }
            return block;
          })()
        : [],
    projects:
      projects.length > 0
        ? (() => {
            const block: string[] = ["## Projects", ""];
            for (const project of projects) {
              const title = project.title.trim() || "Project";
              const link = project.link?.trim() ?? "";
              block.push(link ? `### [${title}](${link})` : `### ${title}`);
              for (const bullet of summaryToBullets(project.summary)) {
                block.push(`- ${bullet}`);
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
              block.push("## Skills", "", skills.join(" · "), "");
            }
            if (achievements.length > 0) {
              block.push("## Achievements", "");
              for (const ach of achievements) {
                const title = ach.title.trim() || "Achievement";
                const issuer = ach.issuer.trim();
                const notes = ach.notes.trim();
                const prefix = issuer ? `**${title}** (${issuer})` : `**${title}**`;
                block.push(notes ? `- ${prefix} — ${notes}` : `- ${prefix}`);
              }
              block.push("");
            }
            return block;
          })()
        : [],
    brag:
      bragEntries.length > 0
        ? (() => {
            const block: string[] = ["## Highlights", ""];
            for (const entry of bragEntries) {
              block.push(`### ${entry.title.trim() || "Highlight"}`);
              const when = formatResumeDate(entry.occurredAt);
              if (when) {
                block.push(`*${when}*`);
                block.push("");
              }
              const summary = entry.summary.trim();
              if (summary) {
                for (const bullet of summaryToBullets(summary)) {
                  block.push(`- ${bullet}`);
                }
              }
              const evidence = entry.evidenceNote.trim();
              if (evidence) {
                block.push("");
                block.push(`_Evidence: ${evidence}_`);
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
