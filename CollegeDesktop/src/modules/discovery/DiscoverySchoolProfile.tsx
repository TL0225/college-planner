import { useCallback, useEffect, useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { GitCompare, Star } from "lucide-react";
import {
  AppCard,
  Button,
  EmptyState,
  MetricTile,
  SegmentedPills,
  StatusChip,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { DiscoveryCdsCard } from "./DiscoveryCdsCard";
import {
  academicYearLabel,
  admissionsCoverage,
  costCoverage,
  formatCount,
  formatRange,
  formatPercent,
  outcomesCoverage,
  type CoverageStatus,
  type DiscoveryInstitution,
  type DiscoveryProfile,
  type ProfileSection,
} from "./discoveryTypes";

const SECTION_OPTIONS: Array<{ id: ProfileSection; label: string }> = [
  { id: "overview", label: "Overview" },
  { id: "admissions", label: "Admissions" },
  { id: "cost", label: "Cost" },
  { id: "outcomes", label: "Outcomes" },
  { id: "perspectives", label: "Perspectives" },
];

function coverageChip(status: CoverageStatus): { title: string; tint?: string; filled?: boolean } {
  switch (status) {
    case "complete":
      return { title: "Complete", tint: "var(--color-success)", filled: true };
    case "partial":
      return { title: "Partial", tint: "var(--color-warning)", filled: true };
    case "missing":
      return { title: "Missing" };
  }
}

function CoveragePill({ title, status }: { title: string; status: CoverageStatus }) {
  const chip = coverageChip(status);
  return (
    <div className="flex items-center gap-1.5">
      <span className="text-[10px] font-medium text-[var(--color-text-light)]">{title}</span>
      <StatusChip title={chip.title} tint={chip.tint} filled={chip.filled} />
    </div>
  );
}

function locationLabel(school: DiscoveryInstitution): string {
  return [school.city, school.state].filter(Boolean).join(", ") || "—";
}

function OverviewSection({ profile }: { profile: DiscoveryProfile }) {
  const { institution, cds } = profile;
  const items = [
    { label: "Admission rate", value: formatPercent(cds?.admitRate, 1) },
    { label: "Applicants", value: formatCount(cds?.applicants) },
    { label: "Admitted", value: formatCount(cds?.admits) },
    { label: "Yield", value: formatPercent(cds?.yield, 1) },
  ];

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {items.map((item) => (
          <MetricTile key={item.label} label={item.label} value={item.value} />
        ))}
      </div>

      <AppCard title="School">
        <div className="space-y-2 p-1 text-[12px]">
          <p className="text-[var(--color-text-main)]">{institution.name}</p>
          <p className="text-[var(--color-text-light)]">{locationLabel(institution)}</p>
          {institution.unitId ? (
            <StatusChip title={`Unit ID ${institution.unitId}`} tint="var(--color-primary)" />
          ) : null}
          {cds ? (
            <p className="text-[11px] text-[var(--color-text-light)]">
              CDS data available for {academicYearLabel(cds.academicYear)} cycle.
            </p>
          ) : (
            <p className="text-[11px] text-[var(--color-text-light)]">
              No Common Data Set on file for this school yet.
            </p>
          )}
        </div>
      </AppCard>
    </div>
  );
}

function AdmissionsSection({ profile }: { profile: DiscoveryProfile }) {
  const { cds } = profile;

  if (!cds) {
    return (
      <AppCard>
        <EmptyState
          title="No CDS profile"
          body="Common Data Set class profile is not available for this school. Load sample data from Settings to explore seeded demo schools."
        />
      </AppCard>
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
        These figures are from the institution&apos;s published Common Data Set. They describe a
        past admissions cycle and do not confirm current deadlines or your chances.
      </p>
      <DiscoveryCdsCard cds={cds} />
    </div>
  );
}

function CostSection({ profile }: { profile: DiscoveryProfile }) {
  const { institution, cds } = profile;
  const year = cds ? academicYearLabel(cds.academicYear) : "—";

  return (
    <div className="space-y-3">
      <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
        Cost metrics come from CDS snapshots when available. Add CDS data under Discovery → school profile.
      </p>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <MetricTile
          label="HS GPA average"
          value={cds?.hsGpaAverage != null ? cds.hsGpaAverage.toFixed(2) : "—"}
        />
        <MetricTile label="Applicants" value={formatCount(cds?.applicants)} />
        <MetricTile label="Admit rate" value={formatPercent(cds?.admitRate, 1)} />
      </div>
      <AppCard title="Cost notes">
        <div className="space-y-2 p-1 text-[12px] text-[var(--color-text-light)]">
          <p>
            {cds
              ? `CDS ${year} snapshot loaded for ${institution.name}.`
              : `No CDS cost section ingested for ${institution.name} yet.`}
          </p>
          <StatusChip
            title={cds ? "CDS loaded" : "Missing CDS"}
            tint={cds ? "var(--color-success)" : "var(--color-warning)"}
            filled
          />
        </div>
      </AppCard>
    </div>
  );
}

function OutcomesSection({ profile }: { profile: DiscoveryProfile }) {
  const { institution, cds } = profile;
  const year = cds ? academicYearLabel(cds.academicYear) : "—";

  return (
    <div className="space-y-3">
      <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
        Outcomes derive from CDS enrollment and test-profile fields when present.
      </p>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <MetricTile label="Enrolled" value={formatCount(cds?.enrolled)} accent="var(--color-success)" />
        <MetricTile label="Yield" value={formatPercent(cds?.yield, 1)} />
        <MetricTile
          label="SAT Math mid-50"
          value={cds ? formatRange(cds.satMath25, cds.satMath75) : "—"}
        />
      </div>
      <AppCard title="Outcomes notes">
        <div className="space-y-2 p-1 text-[12px] text-[var(--color-text-light)]">
          <p>
            {cds
              ? `Using CDS ${year} data for ${institution.name}.`
              : `No outcomes CDS loaded for ${institution.name}.`}
          </p>
          <StatusChip
            title={cds ? "CDS outcomes" : "Missing CDS"}
            tint={cds ? "var(--color-success)" : "var(--color-warning)"}
            filled
          />
        </div>
      </AppCard>
    </div>
  );
}

function PerspectivesSection({
  profile,
  onOpenAdmissions,
}: {
  profile: DiscoveryProfile;
  onOpenAdmissions: () => void;
}) {
  const { cds } = profile;

  return (
    <div className="space-y-3">
      {cds ? (
        <AppCard title="Enrichment loaded">
          <div className="space-y-2 p-1">
            <div className="flex flex-wrap gap-1.5">
              <StatusChip title="Common Data Set profile" tint="var(--color-success)" filled />
            </div>
            <p className="text-[12px] leading-relaxed text-[var(--color-text-light)]">
              CDS class profile, test mid-50%, and factor highlights are on the Admissions tab.
            </p>
            <Button size="sm" variant="secondary" onClick={onOpenAdmissions}>
              Open Admissions tab
            </Button>
          </div>
        </AppCard>
      ) : (
        <AppCard title="Perspectives">
          <EmptyState
            title="Enrichment not loaded"
            body="Site crawl, accreditation, and narrative enrichment are not available in the desktop app yet. CDS data will appear here when seeded."
          />
        </AppCard>
      )}

      {cds ? (
        <AppCard title="CDS snapshot">
          <div className="space-y-2 p-1">
            <p className="text-[13px] font-medium text-[var(--color-text-main)]">
              Common Data Set [{academicYearLabel(cds.academicYear)}]
            </p>
            {cds.admitRate != null && (
              <p className="text-[12px] text-[var(--color-text-light)]">
                Admit rate: {formatPercent(cds.admitRate, 1)}
              </p>
            )}
            {cds.hsGpaAverage != null && (
              <p className="text-[12px] text-[var(--color-text-light)]">
                HS GPA average: {cds.hsGpaAverage.toFixed(2)}
              </p>
            )}
            <Button size="sm" variant="ghost" onClick={onOpenAdmissions}>
              Full class profile on Admissions tab
            </Button>
          </div>
        </AppCard>
      ) : null}
    </div>
  );
}

export function DiscoverySchoolProfile({
  institutionId,
  onToggleSaved,
  onCompare,
  onDelete,
}: {
  institutionId: string;
  onToggleSaved: (school: DiscoveryInstitution) => void;
  onCompare: (id: string) => void;
  onDelete: (school: DiscoveryInstitution) => void;
}) {
  const [section, setSection] = useState<ProfileSection>("overview");
  const [profile, setProfile] = useState<DiscoveryProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setProfile(await ipc.discoveryGetProfile(institutionId));
      setError(null);
    } catch (e) {
      setProfile(null);
      setError(formatIpcError(e));
    } finally {
      setLoading(false);
    }
  }, [institutionId]);

  useEffect(() => {
    void load();
  }, [load]);

  useLiveQuery(load, ["discovery"]);

  if (loading) {
    return (
      <AppCard className="h-full">
        <EmptyState title="Loading school…" body="Fetching profile and CDS data." />
      </AppCard>
    );
  }

  if (error || !profile) {
    return (
      <AppCard className="h-full">
        <EmptyState title="Could not load profile" body={error ?? "Unknown error"} />
      </AppCard>
    );
  }

  const { institution, cds } = profile;
  const admissionsStatus = admissionsCoverage(cds);
  const costStatus = costCoverage(cds);
  const outcomesStatus = outcomesCoverage(cds);

  return (
    <AppCard className="flex h-full flex-col">
      <div
        className="border-b border-[var(--color-chrome-stroke)] px-4 py-4"
        style={{
          background:
            "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 8%, transparent), transparent)",
        }}
      >
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h3
              className="text-[var(--color-text-main)]"
              style={{
                font: "var(--type-section-title)",
                fontSize: 18,
                letterSpacing: "-0.02em",
              }}
            >
              {institution.name}
            </h3>
            <p className="mt-0.5 text-[12px] text-[var(--color-text-light)]">
              {locationLabel(institution) === "—" ? "Location unknown" : locationLabel(institution)}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="ghost" onClick={() => onToggleSaved(institution)}>
              <Star
                size={14}
                fill={institution.isSaved ? "currentColor" : "none"}
                className={institution.isSaved ? "text-[var(--color-warning)]" : undefined}
              />
              {institution.isSaved ? "Saved" : "Save"}
            </Button>
            <Button size="sm" variant="secondary" onClick={() => onCompare(institution.id)}>
              <GitCompare size={14} />
              Compare
            </Button>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap gap-3">
          <CoveragePill title="Cost" status={costStatus} />
          <CoveragePill title="Admissions" status={admissionsStatus} />
          <CoveragePill title="Outcomes" status={outcomesStatus} />
          <CoveragePill title="Academics" status="missing" />
        </div>
      </div>

      <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-2">
        <SegmentedPills value={section} onChange={setSection} options={SECTION_OPTIONS} />
      </div>

      <div className="min-h-0 flex-1 overflow-auto p-4">
        {section === "overview" && <OverviewSection profile={profile} />}
        {section === "admissions" && <AdmissionsSection profile={profile} />}
        {section === "cost" && <CostSection profile={profile} />}
        {section === "outcomes" && <OutcomesSection profile={profile} />}
        {section === "perspectives" && (
          <PerspectivesSection profile={profile} onOpenAdmissions={() => setSection("admissions")} />
        )}
      </div>

      <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
        <Button
          size="sm"
          disabled={!institution.website}
          onClick={() => {
            const url = institution.website.startsWith("http")
              ? institution.website
              : `https://${institution.website}`;
            void openUrl(url);
          }}
        >
          Open website
        </Button>
        <Button size="sm" variant="danger" onClick={() => onDelete(institution)}>
          Delete
        </Button>
      </div>
    </AppCard>
  );
}
