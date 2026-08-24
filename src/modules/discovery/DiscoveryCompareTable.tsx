import { useCallback, useEffect, useState } from "react";
import { AppCard, EmptyState } from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import {
  formatPercent,
  satEbrwMid50,
  type DiscoveryProfile,
} from "./discoveryTypes";

type Props = {
  institutionIds: string[];
};

export function DiscoveryCompareTable({ institutionIds }: Props) {
  const [profiles, setProfiles] = useState<DiscoveryProfile[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (institutionIds.length < 2) {
      setProfiles([]);
      setError(null);
      return;
    }
    setLoading(true);
    try {
      const loaded = await Promise.all(
        institutionIds.map((id) => ipc.discoveryGetProfile(id)),
      );
      setProfiles(loaded);
      setError(null);
    } catch (e) {
      setProfiles([]);
      setError(formatIpcError(e));
    } finally {
      setLoading(false);
    }
  }, [institutionIds]);

  useEffect(() => {
    void load();
  }, [load]);

  if (institutionIds.length < 2) return null;

  if (loading) {
    return (
      <AppCard title="CDS comparison">
        <EmptyState title="Loading profiles…" body="Fetching Common Data Set metrics." />
      </AppCard>
    );
  }

  if (error) {
    return (
      <AppCard title="CDS comparison">
        <EmptyState title="Could not load comparison" body={error} />
      </AppCard>
    );
  }

  return (
    <AppCard title="CDS comparison">
      <div className="overflow-x-auto p-1">
        <table className="w-full min-w-[480px] border-collapse text-[12px]">
          <thead>
            <tr className="border-b border-[var(--color-chrome-stroke)] text-left">
              <th className="px-2 py-2 font-semibold text-[var(--color-text-light)]">Name</th>
              <th className="px-2 py-2 font-semibold text-[var(--color-text-light)]">
                Admit rate
              </th>
              <th className="px-2 py-2 font-semibold text-[var(--color-text-light)]">
                SAT mid-50 (EBRW)
              </th>
              <th className="px-2 py-2 font-semibold text-[var(--color-text-light)]">
                HS GPA avg
              </th>
            </tr>
          </thead>
          <tbody>
            {profiles.map(({ institution, cds }) => (
              <tr
                key={institution.id}
                className="border-b border-[var(--color-chrome-stroke)] last:border-b-0"
              >
                <td className="px-2 py-2.5 font-medium text-[var(--color-text-main)]">
                  {institution.name}
                </td>
                <td className="px-2 py-2.5 tabular-nums text-[var(--color-text-main)]">
                  {formatPercent(cds?.admitRate, 1)}
                </td>
                <td className="px-2 py-2.5 tabular-nums text-[var(--color-text-main)]">
                  {satEbrwMid50(cds)}
                </td>
                <td className="px-2 py-2.5 tabular-nums text-[var(--color-text-main)]">
                  {cds?.hsGpaAverage != null ? cds.hsGpaAverage.toFixed(2) : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="px-1 pb-1 text-[11px] text-[var(--color-text-light)]">
        Loaded via Common Data Set profile for each school.
      </p>
    </AppCard>
  );
}

export function useCompareProfiles(institutionIds: string[]) {
  const [profiles, setProfiles] = useState<DiscoveryProfile[]>([]);

  useEffect(() => {
    if (institutionIds.length < 2) {
      setProfiles([]);
      return;
    }
    let cancelled = false;
    void Promise.all(institutionIds.map((id) => ipc.discoveryGetProfile(id)))
      .then((loaded) => {
        if (!cancelled) setProfiles(loaded);
      })
      .catch(() => {
        if (!cancelled) setProfiles([]);
      });
    return () => {
      cancelled = true;
    };
  }, [institutionIds]);

  return profiles;
}
