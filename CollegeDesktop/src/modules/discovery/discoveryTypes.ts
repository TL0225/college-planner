export type DiscoveryInstitution = {
  id: string;
  name: string;
  unitId?: string | null;
  state: string;
  city: string;
  website: string;
  isSaved: boolean;
};

export type DiscoveryCdsSnapshot = {
  unitId: string;
  academicYear: number;
  sourceUrl: string;
  applicants?: number | null;
  admits?: number | null;
  enrolled?: number | null;
  admitRate?: number | null;
  yield?: number | null;
  factorImportance: Record<string, string>;
  testPolicyNote?: string | null;
  satEbrw25?: number | null;
  satEbrw75?: number | null;
  satMath25?: number | null;
  satMath75?: number | null;
  actComposite25?: number | null;
  actComposite75?: number | null;
  percentSubmittingSat?: number | null;
  percentSubmittingAct?: number | null;
  hsGpaAverage?: number | null;
  hsGpaDistribution: Record<string, number>;
  earlyDecisionApplicants?: number | null;
  earlyDecisionAdmits?: number | null;
  inStateTuition?: number | null;
  outOfStateTuition?: number | null;
};

export type DiscoveryProfile = {
  institution: DiscoveryInstitution;
  cds?: DiscoveryCdsSnapshot | null;
};

export type ProfileSection = "overview" | "admissions" | "cost" | "outcomes" | "perspectives";

export type CoverageStatus = "complete" | "partial" | "missing";

export function academicYearLabel(year: number): string {
  const next = String(year + 1).slice(-2);
  return `${year}–${next}`;
}

export function formatPercent(value?: number | null, digits = 0): string {
  if (value == null || Number.isNaN(value)) return "—";
  return `${(value * 100).toFixed(digits)}%`;
}

export function formatCount(value?: number | null): string {
  if (value == null || Number.isNaN(value)) return "—";
  return value.toLocaleString();
}

export function formatRange(low?: number | null, high?: number | null): string {
  if (low == null || high == null) return "—";
  return `${low}–${high}`;
}

export function factorLabel(key: string): string {
  return key
    .replace(/([A-Z])/g, " $1")
    .replace(/^./, (c) => c.toUpperCase())
    .trim();
}

export function admissionsCoverage(cds?: DiscoveryCdsSnapshot | null): CoverageStatus {
  if (cds?.admitRate != null && cds.applicants != null) return "complete";
  if (cds?.admitRate != null || cds?.applicants != null) return "partial";
  return "missing";
}

/** CDS-backed cost/outcomes coverage when snapshot fields exist. */
export function costCoverage(cds?: DiscoveryCdsSnapshot | null): CoverageStatus {
  if (cds?.hsGpaAverage != null || cds?.applicants != null) return "partial";
  return "missing";
}

export function outcomesCoverage(cds?: DiscoveryCdsSnapshot | null): CoverageStatus {
  if (cds?.enrolled != null || cds?.satMath25 != null) return cds?.yield != null ? "complete" : "partial";
  return "missing";
}

export function satEbrwMid50(cds?: DiscoveryCdsSnapshot | null): string {
  return formatRange(cds?.satEbrw25, cds?.satEbrw75);
}

/** Prefer in-state tuition when CDS cost fields are present. */
export function schoolTuitionUsd(cds?: DiscoveryCdsSnapshot | null): number | null {
  if (!cds) return null;
  if (cds.inStateTuition != null && !Number.isNaN(cds.inStateTuition)) {
    return cds.inStateTuition;
  }
  if (cds.outOfStateTuition != null && !Number.isNaN(cds.outOfStateTuition)) {
    return cds.outOfStateTuition;
  }
  return null;
}

export function buildCompareMarkdown(profiles: DiscoveryProfile[]): string {
  const lines = ["# School comparison", ""];
  lines.push("| School | Admit rate | SAT EBRW mid-50 | HS GPA avg |");
  lines.push("| --- | --- | --- | --- |");
  for (const { institution, cds } of profiles) {
    const admit = formatPercent(cds?.admitRate, 1);
    const sat = satEbrwMid50(cds);
    const gpa = cds?.hsGpaAverage != null ? cds.hsGpaAverage.toFixed(2) : "—";
    lines.push(`| ${institution.name} | ${admit} | ${sat} | ${gpa} |`);
  }
  lines.push("");
  lines.push("_Metrics from Common Data Set where available._");
  return lines.join("\n");
}
