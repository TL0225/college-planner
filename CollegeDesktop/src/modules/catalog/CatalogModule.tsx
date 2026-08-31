import { useCallback, useEffect, useState } from "react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  ListRow,
  ModalSheet,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";

type Uni = { id: string; name: string; shortName: string; domain: string };
type Course = {
  id: string;
  code: string;
  title: string;
  credits?: number;
  description: string;
};

export function CatalogModule() {
  const [universities, setUniversities] = useState<Uni[]>([]);
  const [query, setQuery] = useState("");
  const [courses, setCourses] = useState<Course[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [scrapeUrl, setScrapeUrl] = useState("https://example.edu/catalog");
  const [preview, setPreview] = useState<{
    url: string;
    title: string;
    textExcerpt: string;
    status: number;
  } | null>(null);
  const [scrapeBusy, setScrapeBusy] = useState(false);
  const [scrapeError, setScrapeError] = useState<string | null>(null);
  const [ingestNote, setIngestNote] = useState<string | null>(null);
  const [semanticMode, setSemanticMode] = useState(false);
  const [embeddingsAvailable, setEmbeddingsAvailable] = useState(false);
  const [addSheet, setAddSheet] = useState(false);
  const [syncRows, setSyncRows] = useState<
    Array<{
      id: string;
      name: string;
      catalogBaseUrl: string;
      courseCount: number;
      lastSyncedAt?: string | null;
      lastImported: number;
      lastSkipped: number;
      unchanged: boolean;
      lastError?: string | null;
    }>
  >([]);
  const [showCatalogTools, setShowCatalogTools] = useState(false);
  const [syncBusyId, setSyncBusyId] = useState<string | null>(null);
  const [semesters, setSemesters] = useState<Array<{ id: string; label: string }>>([]);
  const [semesterId, setSemesterId] = useState("");
  const [activeUniversityId, setActiveUniversityId] = useState<string | null>(null);
  const [departments, setDepartments] = useState<
    Array<{ id: string; name: string; code: string; courseCount: number }>
  >([]);
  const [activeDepartmentId, setActiveDepartmentId] = useState<string | null>(null);
  const [selectedProgramIds, setSelectedProgramIds] = useState<string[]>([]);

  const load = useCallback(async () => {
    const [u, s, sync, settings, embedStats] = await Promise.all([
      ipc.catalogListUniversities(),
      ipc.academicsListSemesters(),
      ipc.catalogGetSyncDiagnostics().catch(() => ({ universities: [] })),
      ipc.settingsGet().catch(() => ({ values: {} as Record<string, string> })),
      ipc.catalogEmbeddingStats().catch(() => ({ indexedCount: 0, courseCount: 0, modelTag: "" })),
    ]);
    setUniversities(u);
    setSyncRows(sync.universities);
    setSemesters(s.map((x) => ({ id: x.id, label: x.label || `${x.season} ${x.year}` })));
    setSemesterId((prev) => prev || s[0]?.id || "");
    const portal = settings.values["catalog.portalBaseUrl"]?.trim();
    if (portal) setScrapeUrl(portal);
    const rawPrograms = settings.values["catalog.selectedProgramIds.v1"]?.trim();
    const programPrefixes = rawPrograms
      ? rawPrograms
          .split(/[,\s]+/)
          .map((p) => p.trim())
          .filter(Boolean)
      : [];
    setSelectedProgramIds(programPrefixes);
    const hasEmbeddings = embedStats.indexedCount > 0;
    setEmbeddingsAvailable(hasEmbeddings);
    if (!hasEmbeddings && semanticMode) {
      setSemanticMode(false);
    }
    let hits: Course[];
    if (semanticMode && hasEmbeddings && query.trim()) {
      const semanticHits = await ipc.catalogSemanticSearch(query.trim(), 40);
      hits = semanticHits.map((h) => ({
        id: h.id,
        code: h.code,
        title: h.title,
        description: h.description,
      }));
    } else {
      hits = await ipc.catalogSearchCourses(query.trim());
    }
    if (programPrefixes.length > 0 && !query.trim()) {
      const prefixes = programPrefixes.map((p) => p.toUpperCase());
      hits = hits.filter((c) =>
        prefixes.some((prefix) => c.code.toUpperCase().startsWith(prefix)),
      );
    }
    setCourses(hits);
  }, [query, semanticMode, embeddingsAvailable]);

  const loadDepartments = useCallback(async (universityId: string) => {
    setActiveUniversityId(universityId);
    setActiveDepartmentId(null);
    const rows = await ipc.catalogListDepartments(universityId);
    setDepartments(rows);
    setCourses([]);
    setSelected(null);
  }, []);

  const loadDepartmentCourses = useCallback(async (departmentId: string) => {
    setActiveDepartmentId(departmentId);
    setCourses(await ipc.catalogListDepartmentCourses(departmentId));
    setSelected(null);
  }, []);

  const { refresh, error } = useLiveQuery(load, ["catalog", "planner"]);
  const selectedCourse = courses.find((c) => c.id === selected) ?? null;

  useEffect(() => {
    const onCatalogQuery = (ev: Event) => {
      const next = (ev as CustomEvent<{ query?: string }>).detail?.query?.trim();
      if (!next) return;
      setQuery(next);
      void ipc
        .catalogSearchCourses(next)
        .then((hits) => setCourses(hits))
        .catch(() => undefined);
    };
    window.addEventListener("college:catalog-query", onCatalogQuery);
    return () => window.removeEventListener("college:catalog-query", onCatalogQuery);
  }, []);

  const runPreview = async () => {
    setScrapeBusy(true);
    setScrapeError(null);
    try {
      setPreview(await ipc.scraperFetchHtmlPreview(scrapeUrl.trim()));
    } catch (e) {
      setPreview(null);
      setScrapeError(formatIpcError(e));
    } finally {
      setScrapeBusy(false);
    }
  };

  const runIngest = async () => {
    setScrapeBusy(true);
    setScrapeError(null);
    setIngestNote(null);
    try {
      const res = await ipc.catalogIngestUrl({
        url: scrapeUrl.trim(),
        universityId: universities[0]?.id,
      });
      setIngestNote(
        `Imported ${res.imported}, skipped ${res.skipped}${
          res.sourceTitle ? ` · ${res.sourceTitle}` : ""
        }`,
      );
      setPreview(await ipc.scraperFetchHtmlPreview(scrapeUrl.trim()).catch(() => null));
    } catch (e) {
      setScrapeError(formatIpcError(e));
    } finally {
      setScrapeBusy(false);
    }
  };

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title="Browse catalog"
        actions={
          <div className="flex items-center gap-2">
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search courses…"
              className={fieldControlClass}
              style={{ width: 220, paddingTop: 6, paddingBottom: 6 }}
              onKeyDown={(e) => {
                if (e.key === "Enter") void refresh();
              }}
            />
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Search
            </Button>
            {embeddingsAvailable ? (
              <Button
                size="sm"
                variant={semanticMode ? "primary" : "ghost"}
                onClick={() => setSemanticMode((v) => !v)}
              >
                Smart search
              </Button>
            ) : null}
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowCatalogTools((v) => !v)}
            >
              {showCatalogTools ? "Hide tools" : "Catalog tools"}
            </Button>
          </div>
        }
      />
      {error && <p className="px-3 text-meta text-[var(--color-error)]">{error}</p>}
      {selectedProgramIds.length > 0 && (
        <div className="flex flex-wrap items-center gap-1.5 px-3 pb-1">
          <span className="text-caption">Programs:</span>
          {selectedProgramIds.map((id) => (
            <StatusChip key={id} title={id} tint="var(--color-primary)" filled />
          ))}
        </div>
      )}
      <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3 pt-1">
        <div className="grid min-h-[300px] gap-3 lg:grid-cols-3">
          <AppCard title="Universities">
            {universities.length === 0 ? (
              <EmptyState
                title="No universities"
                body="Catalog schools appear after ingest or sample seed."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {universities.map((u) => (
                  <li key={u.id}>
                    <ListRow
                      leading={
                        <span
                          className="flex h-8 w-8 shrink-0 items-center justify-center text-meta font-semibold text-[var(--color-primary)]"
                          style={{
                            borderRadius: 8,
                            border: "1px solid var(--color-chrome-stroke)",
                            background:
                              "color-mix(in srgb, var(--color-primary) 10%, var(--color-surface))",
                          }}
                        >
                          {(u.shortName || u.name).trim().charAt(0).toUpperCase() || "U"}
                        </span>
                      }
                      title={u.name}
                      subtitle={u.shortName || undefined}
                      trailing={
                        u.domain ? <StatusChip title={u.domain} /> : undefined
                      }
                      onClick={() => void loadDepartments(u.id)}
                    />
                  </li>
                ))}
              </ul>
            )}
          </AppCard>

          <AppCard
            title={
              activeUniversityId
                ? `Departments · ${universities.find((u) => u.id === activeUniversityId)?.name ?? ""}`
                : "Departments"
            }
          >
            {!activeUniversityId ? (
              <EmptyState
                title="Select a university"
                body="Choose a school to browse departments and programs."
              />
            ) : departments.length === 0 ? (
              <EmptyState
                title="No departments"
                body="Run catalog ingest or sample seed to populate departments."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {departments.map((d) => (
                  <li key={d.id}>
                    <ListRow
                      title={d.code ? `${d.code} · ${d.name}` : d.name}
                      subtitle={`${d.courseCount} course${d.courseCount === 1 ? "" : "s"}`}
                      onClick={() => void loadDepartmentCourses(d.id)}
                      trailing={
                        activeDepartmentId === d.id ? (
                          <StatusChip title="Active" filled tint="var(--color-primary)" />
                        ) : undefined
                      }
                    />
                  </li>
                ))}
              </ul>
            )}
          </AppCard>

          <TrailingInspector
            open={!!selectedCourse}
            main={
              <AppCard
                title={
                  activeDepartmentId
                    ? `Department courses · ${courses.length}`
                    : semanticMode
                      ? `Semantic results · ${courses.length}`
                      : `Course results · ${courses.length}`
                }
              >
                {courses.length === 0 ? (
                  <EmptyState
                    title="No courses"
                    body="Search, clear the query to browse, or load sample data from Settings."
                  />
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {courses.map((c) => (
                      <li key={c.id}>
                        <ListRow
                          selected={selected === c.id}
                          onClick={() => setSelected(c.id)}
                          leading={
                            <StatusChip title={c.code} tint="var(--color-primary)" filled />
                          }
                          title={c.title}
                          subtitle={
                            c.credits != null ? `${c.credits} credits` : "Credits TBD"
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>
            }
          >
            {selectedCourse && (
              <div className="flex h-full flex-col">
                <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
                  <div className="mb-1.5">
                    <StatusChip
                      title={selectedCourse.code}
                      tint="var(--color-primary)"
                      filled
                    />
                  </div>
                  <h3
                    className="text-[var(--color-text-main)]"
                    style={{
                      font: "var(--type-section-title)",
                      fontSize: 16,
                      letterSpacing: "-0.02em",
                    }}
                  >
                    {selectedCourse.title}
                  </h3>
                  <div className="mt-2">
                    <StatusChip
                      title={
                        selectedCourse.credits != null
                          ? `${selectedCourse.credits} credits`
                          : "Credits TBD"
                      }
                    />
                  </div>
                </div>
                <div className="min-h-0 flex-1 overflow-auto p-4">
                  <p className="text-meta leading-relaxed text-[var(--color-text-main)]">
                    {selectedCourse.description || "No description."}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
                  <Button
                    size="sm"
                    disabled={semesters.length === 0}
                    onClick={() => setAddSheet(true)}
                  >
                    Add to planner
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setSelected(null)}>
                    Close
                  </Button>
                </div>
              </div>
            )}
          </TrailingInspector>
        </div>

        {showCatalogTools && (
        <AppCard title="Catalog sync">
          <p className="mb-3 text-meta leading-relaxed">
            Background-style sync per university using each school&apos;s catalog_base_url. Skips
            unchanged signatures unless you force a re-scrape.
          </p>
          {syncRows.length === 0 ? (
            <EmptyState
              title="No sync targets"
              body="Add a university with a catalog URL, or ingest manually below."
            />
          ) : (
            <ul className="divide-y divide-[var(--color-chrome-stroke)]">
              {syncRows.map((row) => (
                <li key={row.id}>
                  <ListRow
                    title={row.name}
                    subtitle={
                      row.catalogBaseUrl
                        ? `${row.courseCount} courses · ${row.catalogBaseUrl}`
                        : `${row.courseCount} courses · no catalog URL`
                    }
                    trailing={
                      <div className="flex items-center gap-2">
                        {row.lastSyncedAt ? (
                          <StatusChip
                            title={row.unchanged ? "Up to date" : "Synced"}
                            tint={
                              row.lastError
                                ? "var(--color-error)"
                                : row.unchanged
                                  ? "var(--color-success)"
                                  : "var(--color-primary)"
                            }
                            filled
                          />
                        ) : (
                          <StatusChip title="Never synced" />
                        )}
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={!row.catalogBaseUrl || syncBusyId === row.id}
                          onClick={async () => {
                            setSyncBusyId(row.id);
                            try {
                              const res = await ipc.catalogSyncUniversity({
                                universityId: row.id,
                              });
                              showToast(
                                res.unchanged
                                  ? `${row.name} unchanged`
                                  : `Imported ${res.imported}, skipped ${res.skipped}`,
                                res.unchanged ? "success" : "success",
                              );
                              await refresh();
                            } catch (e) {
                              showToast(formatIpcError(e), "error");
                            } finally {
                              setSyncBusyId(null);
                            }
                          }}
                        >
                          {syncBusyId === row.id ? "Syncing…" : "Sync"}
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={!row.catalogBaseUrl || syncBusyId === row.id}
                          onClick={async () => {
                            setSyncBusyId(row.id);
                            try {
                              const res = await ipc.catalogSyncUniversity({
                                universityId: row.id,
                                force: true,
                              });
                              showToast(
                                `Force sync: ${res.imported} imported, ${res.skipped} skipped`,
                                "success",
                              );
                              await refresh();
                            } catch (e) {
                              showToast(formatIpcError(e), "error");
                            } finally {
                              setSyncBusyId(null);
                            }
                          }}
                        >
                          Force
                        </Button>
                      </div>
                    }
                  />
                </li>
              ))}
            </ul>
          )}
        </AppCard>
        )}

        {showCatalogTools && (
        <AppCard title="Scrape preview">
          <div className="mb-3 flex flex-wrap gap-2">
            <input
              className={fieldControlClass}
              style={{ minWidth: 280, flex: 1 }}
              value={scrapeUrl}
              onChange={(e) => setScrapeUrl(e.target.value)}
              placeholder="https://…"
            />
            <Button
              size="sm"
              disabled={scrapeBusy || !scrapeUrl.trim()}
              onClick={() => void runPreview()}
            >
              {scrapeBusy ? "Working…" : "Fetch preview"}
            </Button>
            <Button
              size="sm"
              variant="secondary"
              disabled={scrapeBusy || !scrapeUrl.trim()}
              onClick={() => void runIngest()}
            >
              Ingest courses
            </Button>
          </div>
          {scrapeError && <p className="text-meta text-[var(--color-error)]">{scrapeError}</p>}
          {ingestNote && (
            <p className="mb-2 text-meta text-[var(--color-success)]">{ingestNote}</p>
          )}
          {preview ? (
            <div className="space-y-2">
              <ListRow
                title={preview.title || preview.url}
                subtitle={preview.url}
                trailing={
                  <StatusChip
                    title={`HTTP ${preview.status}`}
                    tint={
                      preview.status >= 200 && preview.status < 300
                        ? "var(--color-success)"
                        : "var(--color-error)"
                    }
                    filled
                  />
                }
              />
              <pre
                className="max-h-48 overflow-auto whitespace-pre-wrap p-3 text-caption leading-relaxed text-[var(--color-text-light)]"
                style={{
                  borderRadius: 10,
                  border: "1px solid var(--color-chrome-stroke)",
                  background: "var(--color-shell-chrome)",
                  boxShadow: "inset 0 1px 0 color-mix(in srgb, white 25%, transparent)",
                }}
              >
                {preview.textExcerpt || "(empty excerpt)"}
              </pre>
            </div>
          ) : (
            <EmptyState
              title="Polite HTML preview"
              body="Fetches a page excerpt through the Rust scraper (rate-limited). Useful for validating catalog URLs before ingest."
            />
          )}
        </AppCard>
        )}
      </div>

      <ModalSheet open={addSheet} onOpenChange={setAddSheet} title="Add to planner">
        <div className="space-y-3">
          <p className="text-meta">
            {selectedCourse
              ? `${selectedCourse.code} — ${selectedCourse.title}`
              : "Select a course first."}
          </p>
          <FormField label="Semester">
            <select
              className={fieldControlClass}
              value={semesterId}
              onChange={(e) => setSemesterId(e.target.value)}
            >
              {semesters.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </FormField>
          <Button
            disabled={!selectedCourse || !semesterId}
            onClick={async () => {
              if (!selectedCourse) return;
              try {
                await ipc.academicsUpsertCourse({
                  semesterId,
                  code: selectedCourse.code,
                  title: selectedCourse.title,
                  credits: selectedCourse.credits ?? 3,
                  status: "planned",
                });
                setAddSheet(false);
                showToast("Added to planner", "success");
              } catch (e) {
                showToast(formatIpcError(e), "error");
              }
            }}
          >
            Save to plan
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}
