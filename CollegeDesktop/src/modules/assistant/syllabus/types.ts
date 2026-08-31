export type SyllabusAnalysisPhase = "idle" | "extracting" | "ready" | "failed";

export type SyllabusDraftEvent = {
  id: string;
  title: string;
  kind: string;
  startAt?: string | null;
  endAt?: string | null;
  location?: string | null;
  dueHint?: string | null;
  included: boolean;
};

export type SyllabusGradingCategory = {
  name: string;
  weightPercent?: number | null;
};

export type SyllabusInstructor = {
  name?: string | null;
  email?: string | null;
  officeHours?: string | null;
  contact?: string | null;
};

export type SyllabusSection = {
  id: string;
  label: string;
  meetingDays?: string | null;
  meetingTime?: string | null;
  location?: string | null;
};

export type SyllabusAnalyzeResult = {
  events: SyllabusDraftEvent[];
  grading: SyllabusGradingCategory[];
  instructor: SyllabusInstructor;
  sections: SyllabusSection[];
  assignments: Array<{ title: string; dueHint?: string | null; line: string }>;
  courseHint?: string | null;
  courseTitle?: string | null;
  rawLineCount: number;
  contentHash: string;
  warnings: string[];
  ocrAttempted?: boolean;
  extractedTextPreview?: string | null;
  extractedText?: string | null;
  sourcePath?: string | null;
};
