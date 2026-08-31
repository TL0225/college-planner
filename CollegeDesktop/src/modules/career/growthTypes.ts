import { colors } from "@/design-system";

export type BragEntryRow = {
  id: string;
  title: string;
  occurredAt?: string | null;
  summary: string;
  evidenceNote: string;
};

export type NetworkContactRow = {
  id: string;
  name: string;
  organization: string;
  roleTitle: string;
  email: string;
  lastContactAt?: string | null;
  notes: string;
};

export type InterviewPrepRow = {
  id: string;
  applicationId?: string | null;
  company: string;
  roleTitle: string;
  scheduledAt?: string | null;
  status: string;
  notes: string;
  questions: string;
};

export type CareerAppLink = {
  id: string;
  company: string;
  roleTitle: string;
};

export const interviewStatuses = ["upcoming", "completed", "cancelled"] as const;

export const interviewStatusLabels: Record<(typeof interviewStatuses)[number], string> = {
  upcoming: "Upcoming",
  completed: "Completed",
  cancelled: "Cancelled",
};

export const interviewStatusColor: Record<(typeof interviewStatuses)[number], string> = {
  upcoming: colors.careerLaneInterviewing,
  completed: colors.careerLaneAccepted,
  cancelled: colors.careerLaneRejected,
};
