import { openUrl } from "@tauri-apps/plugin-opener";
import { ExternalLink } from "lucide-react";
import { AppCard, Button, StatusChip } from "@/design-system";
import {
  academicYearLabel,
  factorLabel,
  formatCount,
  formatPercent,
  formatRange,
  type DiscoveryCdsSnapshot,
} from "./discoveryTypes";

function FactRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3 py-1">
      <span className="text-[12px] text-[var(--color-text-light)]">{label}</span>
      <span className="text-[12px] font-medium tabular-nums text-[var(--color-text-main)]">
        {value}
      </span>
    </div>
  );
}

export function DiscoveryCdsCard({ cds }: { cds: DiscoveryCdsSnapshot }) {
  const factors = Object.entries(cds.factorImportance).sort(([a], [b]) => a.localeCompare(b));

  return (
    <AppCard title="CDS class profile">
      <div className="space-y-3 p-1">
        <p className="text-[11px] leading-relaxed text-[var(--color-text-light)]">
          Common Data Set [{academicYearLabel(cds.academicYear)}] — official institution
          publication.
        </p>

        <div className="divide-y divide-[var(--color-chrome-stroke)] rounded-lg border border-[var(--color-chrome-stroke)] px-3">
          {cds.admitRate != null && (
            <FactRow label="Admit rate (CDS C1)" value={formatPercent(cds.admitRate, 1)} />
          )}
          {cds.applicants != null && (
            <FactRow label="Applicants" value={formatCount(cds.applicants)} />
          )}
          {cds.admits != null && <FactRow label="Admits" value={formatCount(cds.admits)} />}
          {cds.enrolled != null && (
            <FactRow label="Enrolled" value={formatCount(cds.enrolled)} />
          )}
          {cds.yield != null && <FactRow label="Yield" value={formatPercent(cds.yield, 1)} />}
          {cds.satEbrw25 != null && cds.satEbrw75 != null && (
            <FactRow
              label="SAT EBRW mid-50%"
              value={formatRange(cds.satEbrw25, cds.satEbrw75)}
            />
          )}
          {cds.satMath25 != null && cds.satMath75 != null && (
            <FactRow
              label="SAT Math mid-50%"
              value={formatRange(cds.satMath25, cds.satMath75)}
            />
          )}
          {cds.actComposite25 != null && cds.actComposite75 != null && (
            <FactRow
              label="ACT composite mid-50%"
              value={formatRange(cds.actComposite25, cds.actComposite75)}
            />
          )}
          {cds.percentSubmittingSat != null && (
            <FactRow
              label="Submitting SAT"
              value={formatPercent(cds.percentSubmittingSat, 0)}
            />
          )}
          {cds.percentSubmittingAct != null && (
            <FactRow
              label="Submitting ACT"
              value={formatPercent(cds.percentSubmittingAct, 0)}
            />
          )}
          {cds.hsGpaAverage != null && (
            <FactRow label="HS GPA average" value={cds.hsGpaAverage.toFixed(2)} />
          )}
        </div>

        {factors.length > 0 && (
          <div>
            <p className="mb-2 text-[11px] font-medium uppercase tracking-[0.05em] text-[var(--color-text-light)]">
              Factor highlights
            </p>
            <div className="flex flex-wrap gap-1.5">
              {factors.map(([key, value]) => (
                <StatusChip key={key} title={`${factorLabel(key)}: ${value}`} />
              ))}
            </div>
          </div>
        )}

        {cds.testPolicyNote ? (
          <p className="text-[11px] leading-relaxed text-[var(--color-text-light)]">
            {cds.testPolicyNote}
          </p>
        ) : null}

        {(cds.earlyDecisionApplicants != null || cds.earlyDecisionAdmits != null) && (
          <div className="rounded-lg border border-[var(--color-chrome-stroke)] px-3 py-2">
            <p className="mb-1 text-[11px] font-medium text-[var(--color-text-main)]">
              Early decision
            </p>
            {cds.earlyDecisionApplicants != null && (
              <FactRow label="Applicants" value={formatCount(cds.earlyDecisionApplicants)} />
            )}
            {cds.earlyDecisionAdmits != null && (
              <FactRow label="Admits" value={formatCount(cds.earlyDecisionAdmits)} />
            )}
          </div>
        )}

        {cds.sourceUrl ? (
          <Button
            size="sm"
            variant="secondary"
            onClick={() => void openUrl(cds.sourceUrl)}
          >
            <ExternalLink size={14} />
            Common Data Set [{academicYearLabel(cds.academicYear)}]
          </Button>
        ) : null}
      </div>
    </AppCard>
  );
}
