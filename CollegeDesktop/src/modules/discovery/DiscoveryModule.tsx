import { useCallback, useEffect, useMemo, useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { GitCompare, Copy, Star } from "lucide-react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  ModalSheet,
  SegmentedPills,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { DiscoverySchoolProfile } from "./DiscoverySchoolProfile";
import { DiscoveryCompareTable, useCompareProfiles } from "./DiscoveryCompareTable";
import { buildCompareMarkdown, schoolTuitionUsd } from "./discoveryTypes";

type School = {
  id: string;
  name: string;
  unitId?: string | null;
  state: string;
  city: string;
  website: string;
  isSaved: boolean;
  admitRate?: number | null;
};

type WorkspaceMode = "discover" | "profile" | "compare" | "saved";

const MODE_OPTIONS: Array<{ id: WorkspaceMode; label: string }> = [
  { id: "discover", label: "Discover" },
  { id: "profile", label: "Profile" },
  { id: "compare", label: "Compare" },
  { id: "saved", label: "Saved" },
];

const MAX_COMPARE = 3;

function schoolInitial(name: string): string {
  return name.trim().charAt(0).toUpperCase() || "S";
}

function locationLabel(school: School): string {
  return [school.city, school.state].filter(Boolean).join(", ") || "—";
}

function websiteLabel(website: string): string {
  return website.replace(/^https?:\/\//, "");
}

function openSchoolWebsite(website: string) {
  const url = website.startsWith("http") ? website : `https://${website}`;
  void openUrl(url);
}

function SchoolAvatar({ name }: { name: string }) {
  return (
    <span
      className="flex h-8 w-8 shrink-0 items-center justify-center text-meta font-semibold text-[var(--color-primary)]"
      style={{
        borderRadius: 8,
        border: "1px solid var(--color-chrome-stroke)",
        background: "color-mix(in srgb, var(--color-primary) 10%, var(--color-surface))",
      }}
    >
      {schoolInitial(name)}
    </span>
  );
}

function SchoolHero({ school }: { school: School }) {
  return (
    <div
      className="border-b border-[var(--color-chrome-stroke)] px-4 py-4"
      style={{
        background:
          "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 8%, transparent), transparent)",
      }}
    >
      <div className="flex items-start gap-3">
        <SchoolAvatar name={school.name} />
        <div className="min-w-0 flex-1">
          <h3
            className="text-[var(--color-text-main)]"
            style={{
              font: "var(--type-section-title)",
              fontSize: 18,
              letterSpacing: "-0.02em",
            }}
          >
            {school.name}
          </h3>
          <p className="mt-0.5 text-meta">
            {locationLabel(school) === "—" ? "Location unknown" : locationLabel(school)}
          </p>
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {school.city ? <StatusChip title={school.city} /> : null}
            {school.state ? (
              <StatusChip title={school.state} tint="var(--color-primary)" filled />
            ) : null}
            {school.unitId ? <StatusChip title={`Unit ${school.unitId}`} /> : null}
            {school.website ? (
              <StatusChip title={websiteLabel(school.website)} tint="var(--color-success)" />
            ) : null}
            {school.isSaved ? (
              <StatusChip title="Saved" tint="var(--color-warning)" filled />
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}

export function DiscoveryModule() {
  const [schools, setSchools] = useState<School[]>([]);
  const [mode, setMode] = useState<WorkspaceMode>("discover");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const [compareIds, setCompareIds] = useState<string[]>([]);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [form, setForm] = useState({
    name: "",
    city: "",
    state: "",
    website: "",
  });
  const [fitPrefs, setFitPrefs] = useState({
    preferredStates: "",
    minAcceptanceRate: "",
    maxTuition: "",
  });
  const [tuitionBySchoolId, setTuitionBySchoolId] = useState<Record<string, number | null>>({});

  const load = useCallback(async () => {
    const [rows, settings] = await Promise.all([
      ipc.discoveryListInstitutions(query.trim() || undefined),
      ipc.settingsGet(),
    ]);
    setSchools(rows);
    try {
      const raw = settings.values["discovery.fitPrefs.v1"];
      if (raw) {
        const parsed = JSON.parse(raw) as Partial<typeof fitPrefs>;
        setFitPrefs((prev) => ({ ...prev, ...parsed }));
      }
    } catch {
      /* ignore bad fit prefs */
    }
  }, [query]);

  const { refresh, error } = useLiveQuery(load, ["discovery"]);

  useEffect(() => {
    const maxTuitionRaw = fitPrefs.maxTuition.trim();
    if (!maxTuitionRaw) {
      setTuitionBySchoolId({});
      return;
    }
    let cancelled = false;
    void (async () => {
      const entries = await Promise.all(
        schools.map(async (school) => {
          try {
            const profile = await ipc.discoveryGetProfile(school.id);
            return [school.id, schoolTuitionUsd(profile.cds)] as const;
          } catch {
            return [school.id, null] as const;
          }
        }),
      );
      if (!cancelled) {
        setTuitionBySchoolId(Object.fromEntries(entries));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [schools, fitPrefs.maxTuition]);

  useEffect(() => {
    const onMode = (ev: Event) => {
      const mode = (ev as CustomEvent<{ mode?: WorkspaceMode }>).detail?.mode;
      if (mode === "discover" || mode === "profile" || mode === "compare" || mode === "saved") {
        setMode(mode);
      }
    };
    window.addEventListener("college:discovery-mode", onMode);
    return () => window.removeEventListener("college:discovery-mode", onMode);
  }, []);

  const selectedSchool = schools.find((s) => s.id === selected) ?? null;

  const visibleSchools = useMemo(() => {
    let list = mode === "saved" ? schools.filter((s) => s.isSaved) : schools;
    if (mode === "discover" && fitPrefs.preferredStates.trim()) {
      const states = new Set(
        fitPrefs.preferredStates
          .split(/[,\s]+/)
          .map((s) => s.trim().toUpperCase())
          .filter(Boolean),
      );
      list = list.filter((s) => !s.state || states.has(s.state.toUpperCase()));
    }
    if (mode === "discover" && fitPrefs.minAcceptanceRate.trim()) {
      const minRate = Number(fitPrefs.minAcceptanceRate);
      if (!Number.isNaN(minRate)) {
        const threshold = minRate > 1 ? minRate / 100 : minRate;
        list = list.filter((s) => s.admitRate == null || s.admitRate >= threshold);
      }
    }
    if (mode === "discover" && fitPrefs.maxTuition.trim()) {
      const maxTuition = Number(fitPrefs.maxTuition.replace(/[$,]/g, ""));
      if (!Number.isNaN(maxTuition)) {
        list = list.filter((s) => {
          const tuition = tuitionBySchoolId[s.id];
          if (tuition == null) return true;
          return tuition <= maxTuition;
        });
      }
    }
    return list;
  }, [
    mode,
    schools,
    fitPrefs.preferredStates,
    fitPrefs.minAcceptanceRate,
    fitPrefs.maxTuition,
    tuitionBySchoolId,
  ]);

  const compareSchools = useMemo(
    () =>
      compareIds
        .map((id) => schools.find((s) => s.id === id))
        .filter((s): s is School => s != null),
    [compareIds, schools],
  );

  const compareProfiles = useCompareProfiles(compareIds);

  const copyCompareMarkdown = async () => {
    if (compareProfiles.length < 2) {
      showToast("Add at least 2 schools to compare", "error");
      return;
    }
    try {
      await navigator.clipboard.writeText(buildCompareMarkdown(compareProfiles));
      showToast("Compare summary copied as Markdown", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const toggleSaved = async (school: School) => {
    try {
      await ipc.discoveryUpdateInstitution({ id: school.id, isSaved: !school.isSaved });
      showToast(school.isSaved ? "Removed from saved" : "School saved", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const toggleCompare = (id: string) => {
    setCompareIds((prev) => {
      if (prev.includes(id)) return prev.filter((x) => x !== id);
      if (prev.length >= MAX_COMPARE) {
        showToast(`Compare up to ${MAX_COMPARE} schools`, "error");
        return prev;
      }
      return [...prev, id];
    });
  };

  const deleteSchool = async (school: School) => {
    if (!confirmDelete(school.name)) return;
    try {
      await ipc.discoveryDeleteInstitution(school.id);
      setSelected((prev) => (prev === school.id ? null : prev));
      setCompareIds((prev) => prev.filter((x) => x !== school.id));
      showToast("School deleted", "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const renderSchoolRow = (school: School, opts?: { showCompare?: boolean }) => {
    const inCompare = compareIds.includes(school.id);
    return (
      <ListRow
        key={school.id}
        selected={selected === school.id}
        onClick={() => setSelected(school.id)}
        leading={<SchoolAvatar name={school.name} />}
        title={school.name}
        subtitle={locationLabel(school)}
        trailing={
          <div className="flex items-center gap-1.5">
            {school.isSaved && (
              <Star size={12} fill="currentColor" className="text-[var(--color-warning)]" />
            )}
            {school.state ? (
              <StatusChip title={school.state} tint="var(--color-primary)" filled />
            ) : null}
            {opts?.showCompare ? (
              <span
                onClick={(e) => e.stopPropagation()}
                onKeyDown={(e) => e.stopPropagation()}
              >
                <Button
                  size="sm"
                  variant={inCompare ? "primary" : "ghost"}
                  onClick={() => toggleCompare(school.id)}
                >
                  {inCompare ? "Added" : "Compare"}
                </Button>
              </span>
            ) : null}
          </div>
        }
      />
    );
  };

  const inspectorPanel = selectedSchool ? (
    <div className="flex h-full flex-col">
      <SchoolHero school={selectedSchool} />
      <div className="min-h-0 flex-1 p-4">
        <p className="text-meta leading-relaxed">
          {selectedSchool.website
            ? "Open the school website in your browser, save it for later, or remove it from Discovery."
            : "No website on file for this school."}
        </p>
      </div>
      <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
        <Button
          size="sm"
          variant="ghost"
          aria-label={selectedSchool.isSaved ? "Remove from saved" : "Save school"}
          onClick={() => void toggleSaved(selectedSchool)}
        >
          <Star
            size={14}
            fill={selectedSchool.isSaved ? "currentColor" : "none"}
            className={selectedSchool.isSaved ? "text-[var(--color-warning)]" : undefined}
          />
          {selectedSchool.isSaved ? "Saved" : "Save"}
        </Button>
        <Button
          size="sm"
          variant="secondary"
          disabled={compareIds.includes(selectedSchool.id)}
          onClick={() => toggleCompare(selectedSchool.id)}
        >
          <GitCompare size={14} />
          Add to compare
        </Button>
        <Button
          size="sm"
          disabled={!selectedSchool.website}
          onClick={() => openSchoolWebsite(selectedSchool.website)}
        >
          Open website
        </Button>
        <Button size="sm" variant="danger" onClick={() => void deleteSchool(selectedSchool)}>
          Delete
        </Button>
        <Button size="sm" variant="ghost" onClick={() => setSelected(null)}>
          Close
        </Button>
      </div>
    </div>
  ) : null;

  const discoverContent = (
    <div className="space-y-3">
      <AppCard title="Fit preferences">
        <p className="mb-3 text-meta">
          Filter the Discover list by preferred states.
        </p>
        <div className="grid gap-3 sm:grid-cols-3">
          <FormField label="Preferred states (e.g. CA, NY)">
            <input
              className={fieldControlClass}
              value={fitPrefs.preferredStates}
              onChange={(e) => {
                const next = { ...fitPrefs, preferredStates: e.target.value };
                setFitPrefs(next);
                void ipc.settingsSet("discovery.fitPrefs.v1", JSON.stringify(next));
              }}
            />
          </FormField>
          <FormField label="Min acceptance rate (optional)">
            <input
              className={fieldControlClass}
              placeholder="e.g. 0.25"
              value={fitPrefs.minAcceptanceRate}
              onChange={(e) => {
                const next = { ...fitPrefs, minAcceptanceRate: e.target.value };
                setFitPrefs(next);
                void ipc.settingsSet("discovery.fitPrefs.v1", JSON.stringify(next));
              }}
            />
          </FormField>
          <FormField label="Max tuition (optional)">
            <input
              className={fieldControlClass}
              placeholder="USD"
              value={fitPrefs.maxTuition}
              onChange={(e) => {
                const next = { ...fitPrefs, maxTuition: e.target.value };
                setFitPrefs(next);
                void ipc.settingsSet("discovery.fitPrefs.v1", JSON.stringify(next));
              }}
            />
          </FormField>
        </div>
      </AppCard>
      <TrailingInspector
        open={!!selectedSchool}
        main={
          <AppCard title={`${visibleSchools.length} institutions`}>
        {visibleSchools.length === 0 ? (
          <EmptyState
            title={mode === "saved" ? "No saved schools" : "No schools yet"}
            body={
              mode === "saved"
                ? "Star schools from Discover to collect them here."
                : "Add a school, or load sample data from Settings to explore Discovery."
            }
          />
        ) : (
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {visibleSchools.map((s) => (
              <li key={s.id}>{renderSchoolRow(s, { showCompare: mode === "discover" })}</li>
            ))}
          </ul>
        )}
      </AppCard>
    }>
      {inspectorPanel}
    </TrailingInspector>
    </div>
  );

  const profileContent = selectedSchool ? (
    <DiscoverySchoolProfile
      institutionId={selectedSchool.id}
      onToggleSaved={(school) => void toggleSaved(school)}
      onCompare={(id) => {
        toggleCompare(id);
        setMode("compare");
      }}
      onDelete={(school) => void deleteSchool(school)}
    />
  ) : (
    <AppCard>
      <EmptyState
        title="Select a school"
        body="Choose a school from Discover or Saved to view its profile."
      />
    </AppCard>
  );

  const compareContent = (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusChip
          title={`${compareSchools.length} / ${MAX_COMPARE} selected`}
          tint="var(--color-primary)"
          filled
        />
        {compareIds.length > 0 && (
          <>
            <Button size="sm" variant="secondary" onClick={() => void copyCompareMarkdown()}>
              <Copy size={14} />
              Copy Markdown
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setCompareIds([])}>
              Clear
            </Button>
          </>
        )}
      </div>
      {compareSchools.length >= 2 && <DiscoveryCompareTable institutionIds={compareIds} />}
      {compareSchools.length === 0 ? (
        <AppCard>
          <EmptyState
            title="No schools to compare"
            body='Use "Compare" on school rows in Discover, or add from the inspector.'
          />
        </AppCard>
      ) : (
        <div
          className="grid gap-3"
          style={{
            gridTemplateColumns: `repeat(${Math.min(compareSchools.length, MAX_COMPARE)}, minmax(0, 1fr))`,
          }}
        >
          {compareSchools.map((school) => (
            <AppCard key={school.id} title={school.name}>
              <div className="space-y-3 p-1">
                <div className="flex items-center gap-2">
                  <SchoolAvatar name={school.name} />
                  <div className="min-w-0">
                    <p className="truncate text-section-title font-medium">
                      {school.name}
                    </p>
                    <p className="text-caption">
                      {locationLabel(school)}
                    </p>
                  </div>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {school.state ? (
                    <StatusChip title={school.state} tint="var(--color-primary)" filled />
                  ) : null}
                  {school.website ? (
                    <StatusChip title={websiteLabel(school.website)} tint="var(--color-success)" />
                  ) : (
                    <StatusChip title="No website" />
                  )}
                </div>
                <div className="flex flex-wrap gap-2">
                  {school.website ? (
                    <Button size="sm" onClick={() => openSchoolWebsite(school.website)}>
                      Open website
                    </Button>
                  ) : null}
                  <Button size="sm" variant="ghost" onClick={() => toggleCompare(school.id)}>
                    Remove
                  </Button>
                </div>
              </div>
            </AppCard>
          ))}
        </div>
      )}
      {schools.length > 0 && compareSchools.length < MAX_COMPARE && (
        <AppCard title="Add schools">
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {schools
              .filter((s) => !compareIds.includes(s.id))
              .slice(0, 12)
              .map((s) => (
                <li key={s.id}>
                  <ListRow
                    title={s.name}
                    subtitle={locationLabel(s)}
                    leading={<SchoolAvatar name={s.name} />}
                    trailing={
                      <Button size="sm" variant="ghost" onClick={() => toggleCompare(s.id)}>
                        Add
                      </Button>
                    }
                    onClick={() => toggleCompare(s.id)}
                  />
                </li>
              ))}
          </ul>
        </AppCard>
      )}
    </div>
  );

  const savedContent = (
    <TrailingInspector
      open={!!selectedSchool && selectedSchool.isSaved}
      main={
        <div className="space-y-3">
          {compareIds.length >= 2 && (
            <div className="flex flex-wrap items-center gap-2">
              <Button size="sm" variant="secondary" onClick={() => void copyCompareMarkdown()}>
                <Copy size={14} />
                Copy compare summary
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setMode("compare")}>
                Open compare
              </Button>
            </div>
          )}
          <AppCard title={`${visibleSchools.length} saved`}>
          {visibleSchools.length === 0 ? (
            <EmptyState
              title="No saved schools"
              body="Star schools from Discover to collect them here."
            />
          ) : (
            <ul className="divide-y divide-[var(--color-chrome-stroke)]">
              {visibleSchools.map((s) => (
                <li key={s.id}>{renderSchoolRow(s)}</li>
              ))}
            </ul>
          )}
        </AppCard>
        </div>
      }
    >
      {selectedSchool?.isSaved ? inspectorPanel : null}
    </TrailingInspector>
  );

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title="Discovery"
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <SegmentedPills value={mode} onChange={setMode} options={MODE_OPTIONS} />
            {(mode === "discover" || mode === "saved") && (
              <>
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search schools…"
                  className={fieldControlClass}
                  style={{ width: 220, paddingTop: 6, paddingBottom: 6 }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") void refresh();
                  }}
                />
                <Button size="sm" variant="secondary" onClick={() => void refresh()}>
                  Search
                </Button>
              </>
            )}
            <Button size="sm" onClick={() => setSheetOpen(true)}>
              Add school
            </Button>
          </div>
        }
      />
      {error && <p className="px-3 text-meta text-[var(--color-error)]">{error}</p>}
      <div className="min-h-0 flex-1 overflow-auto p-3 pt-1">
        {mode === "discover" && discoverContent}
        {mode === "profile" && profileContent}
        {mode === "compare" && compareContent}
        {mode === "saved" && savedContent}
      </div>

      <ModalSheet open={sheetOpen} onOpenChange={setSheetOpen} title="Add school">
        <div className="space-y-3">
          <FormField label="Name">
            <input
              className={fieldControlClass}
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
          </FormField>
          <FormField label="City">
            <input
              className={fieldControlClass}
              value={form.city}
              onChange={(e) => setForm({ ...form, city: e.target.value })}
            />
          </FormField>
          <FormField label="State">
            <input
              className={fieldControlClass}
              value={form.state}
              onChange={(e) => setForm({ ...form, state: e.target.value })}
              placeholder="CA"
            />
          </FormField>
          <FormField label="Website">
            <input
              className={fieldControlClass}
              value={form.website}
              onChange={(e) => setForm({ ...form, website: e.target.value })}
              placeholder="example.edu"
            />
          </FormField>
          <Button
            disabled={!form.name.trim()}
            onClick={async () => {
              try {
                await ipc.discoveryUpsertInstitution({
                  name: form.name.trim(),
                  city: form.city.trim() || undefined,
                  stateCode: form.state.trim() || undefined,
                  website: form.website.trim() || undefined,
                });
                setSheetOpen(false);
                setForm({ name: "", city: "", state: "", website: "" });
                await refresh();
                showToast("School saved", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save school
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}
