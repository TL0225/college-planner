import { useState } from "react";
import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  MetricTile,
  StatusChip,
  FormField,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import { StatusNote } from "../shared";
import { useSettings } from "../useSettings";

export function SettingsAcademicsPage() {
  const [showDiagnostics, setShowDiagnostics] = useState(false);
  const {
    settings,
    setPref,
    seedStatus,
    setSeedStatus,
    scrapeUrl,
    setScrapeUrl,
    scrapeStatus,
    setScrapeStatus,
    catalogEmbedStats,
    catalogReindexBusy,
    setCatalogReindexBusy,
    catalogReindexNote,
    setCatalogReindexNote,
    setCatalogEmbedStats,
    catalogSyncRows,
    syncBusyId,
    setSyncBusyId,
    refresh,
  } = useSettings();

  return (
    <>
      <AppCard title="Sample data">
        <p className="mb-3 text-meta leading-relaxed">
          Load demo planner, catalog courses, requirements, transfer maps, calendar, career,
          finance, vault, discovery, and profile rows.
        </p>
        <Button
          size="sm"
          onClick={async () => {
            setSeedStatus("Seeding…");
            try {
              await ipc.demoSeedSampleData();
              setSeedStatus(
                "Loaded. Try Academics → Requirements, Catalog, or Finance → Budgets.",
              );
            } catch (e) {
              setSeedStatus(formatIpcError(e));
            }
          }}
        >
          Load sample data
        </Button>
        {seedStatus && <StatusNote>{seedStatus}</StatusNote>}
      </AppCard>

      <AppCard title="Course catalog">
        <p className="mb-3 text-meta leading-relaxed">
          Update your school&apos;s course catalog from the latest data.
        </p>
        <Button
          size="sm"
          disabled={catalogSyncRows.length === 0 || syncBusyId !== null}
          onClick={async () => {
            const row = catalogSyncRows[0];
            if (!row) return;
            setSyncBusyId(row.id);
            try {
              await ipc.catalogSyncUniversity({ universityId: row.id, force: false });
              await refresh();
              showToast(`Updated ${row.name}`, "success");
            } catch (e) {
              showToast(formatIpcError(e), "error");
            } finally {
              setSyncBusyId(null);
            }
          }}
        >
          {syncBusyId ? "Updating…" : "Update course catalog"}
        </Button>
        <Button
          size="sm"
          variant="ghost"
          className="ml-2"
          onClick={() => setShowDiagnostics((v) => !v)}
        >
          {showDiagnostics ? "Hide diagnostics" : "Advanced diagnostics"}
        </Button>
      </AppCard>

      {showDiagnostics && (
        <>
      <AppCard title="Scraper connectivity">
        <div className="mb-2 flex gap-2">
          <input
            className={fieldControlClass}
            value={scrapeUrl}
            onChange={(e) => setScrapeUrl(e.target.value)}
          />
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              setScrapeStatus("Fetching…");
              try {
                const res = await ipc.scraperFetchHtmlPreview(scrapeUrl.trim());
                setScrapeStatus(`HTTP ${res.status} · ${res.title || res.url}`);
              } catch (e) {
                setScrapeStatus(formatIpcError(e));
              }
            }}
          >
            Test
          </Button>
        </div>
        {scrapeStatus ? (
          <div className="flex flex-wrap gap-1.5">
            <StatusChip
              title={scrapeStatus}
              tint={
                scrapeStatus.startsWith("HTTP")
                  ? "var(--color-success)"
                  : scrapeStatus === "Fetching…"
                    ? "var(--color-text-light)"
                    : "var(--color-error)"
              }
              filled
            />
          </div>
        ) : (
          <EmptyState
            title="Network check"
            body="Validates the polite Rust scraper path used by Catalog ingest."
          />
        )}
      </AppCard>

      <AppCard title="Catalog programs">
        <p className="mb-2 text-meta leading-relaxed">
          Comma-separated program codes to prioritize in Catalog browse (
          <code className="text-caption">catalog.selectedProgramIds.v1</code>).
        </p>
        <FormField label="Selected programs">
          <input
            className={fieldControlClass}
            value={settings["catalog.selectedProgramIds.v1"] ?? ""}
            placeholder="BS-CS, BA-MATH, minor-DS"
            onChange={(e) => void setPref("catalog.selectedProgramIds.v1", e.target.value)}
          />
        </FormField>
      </AppCard>

      <AppCard title="Catalog vector index">
        <p className="mb-3 text-meta leading-relaxed">
          Course embeddings power semantic search in Catalog. Reindex after large ingests or when
          you change the local AI / ONNX embedding backend (
          {catalogEmbedStats?.modelTag ?? "—"}).
        </p>
        <div className="mb-3 flex flex-wrap gap-2">
          <MetricTile
            label="Indexed"
            value={
              catalogEmbedStats
                ? `${catalogEmbedStats.indexedCount} / ${catalogEmbedStats.courseCount}`
                : "—"
            }
          />
        </div>
        <Button
          size="sm"
          disabled={catalogReindexBusy}
          onClick={async () => {
            setCatalogReindexBusy(true);
            setCatalogReindexNote("Reindexing…");
            try {
              const res = await ipc.catalogReindexEmbeddings(500);
              setCatalogReindexNote(
                `Indexed ${res.indexed} courses (${res.modelTag})`,
              );
              setCatalogEmbedStats(await ipc.catalogEmbeddingStats());
              showToast(`Indexed ${res.indexed} catalog courses`, "success");
            } catch (e) {
              setCatalogReindexNote(formatIpcError(e));
              showToast(formatIpcError(e), "error");
            } finally {
              setCatalogReindexBusy(false);
            }
          }}
        >
          {catalogReindexBusy ? "Reindexing…" : "Reindex embeddings"}
        </Button>
        {catalogReindexNote ? (
          <p className="mt-2 text-meta">{catalogReindexNote}</p>
        ) : null}
      </AppCard>

      <AppCard title="Catalog sync diagnostics">
        {catalogSyncRows.length === 0 ? (
          <EmptyState
            title="No universities"
            body="Load sample data or add schools in Catalog to see sync status."
          />
        ) : (
          <ul className="divide-y divide-[var(--color-chrome-stroke)]">
            {catalogSyncRows.map((row) => (
              <li key={row.id} className="flex flex-wrap items-center gap-2 py-2">
                <div className="min-w-0 flex-1">
                  <ListRow
                    title={row.name}
                    subtitle={`${row.courseCount} courses${
                      row.lastSyncedAt
                        ? ` · synced ${new Date(row.lastSyncedAt).toLocaleString()}`
                        : ""
                    }`}
                  />
                  {row.lastError ? (
                    <p className="mt-1 text-caption text-[var(--color-error)]">{row.lastError}</p>
                  ) : null}
                </div>
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={syncBusyId === row.id}
                  onClick={async () => {
                    setSyncBusyId(row.id);
                    try {
                      await ipc.catalogSyncUniversity({ universityId: row.id, force: false });
                      await refresh();
                      showToast(`Synced ${row.name}`, "success");
                    } catch (e) {
                      showToast(formatIpcError(e), "error");
                    } finally {
                      setSyncBusyId(null);
                    }
                  }}
                >
                  Sync
                </Button>
              </li>
            ))}
          </ul>
        )}
      </AppCard>
        </>
      )}
    </>
  );
}
