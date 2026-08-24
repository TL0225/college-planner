import { useCallback, useEffect, useMemo, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import {
  AppCard,
  Button,
  EmptyState,
  FormField,
  StatusChip,
  TrailingInspector,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError, type PlannerCourse } from "@/lib/ipc";
import { showToast } from "@/lib/toast";
import type {
  SyllabusAnalysisPhase,
  SyllabusAnalyzeResult,
  SyllabusDraftEvent,
  SyllabusSection,
} from "./types";
import { eventKindTint, parseLooseDue } from "./syllabusDateParser";
import { useSyllabusConflicts } from "./useSyllabusConflicts";
import { ConflictSheet } from "./ConflictSheet";
import { computeWorkloadProfile } from "./workloadProfile";
import { buildSectionMeetingEvents } from "./sectionMeetingEvents";

type ReviewTab = "events" | "professor" | "pdf";

export function SyllabusReviewPage() {
  const [phase, setPhase] = useState<SyllabusAnalysisPhase>("idle");
  const [tab, setTab] = useState<ReviewTab>("events");
  const [courses, setCourses] = useState<PlannerCourse[]>([]);
  const [selectedCourseId, setSelectedCourseId] = useState("");
  const [pasteText, setPasteText] = useState("");
  const [result, setResult] = useState<SyllabusAnalyzeResult | null>(null);
  const [events, setEvents] = useState<SyllabusDraftEvent[]>([]);
  const [sortNewest, setSortNewest] = useState(false);
  const [showRawText, setShowRawText] = useState(false);
  const [busy, setBusy] = useState(false);
  const [vaultSyllabi, setVaultSyllabi] = useState<
    Array<{ id: string; title: string; hasFile: boolean }>
  >([]);
  const [calendarEvents, setCalendarEvents] = useState<
    Array<{
      id: string;
      title: string;
      startAt: string;
      endAt?: string;
      allDay: boolean;
      location: string;
    }>
  >([]);
  const [conflictSheetEventId, setConflictSheetEventId] = useState<string | null>(null);
  const [selectedSectionId, setSelectedSectionId] = useState<string | null>(null);
  const [sourcePdfPath, setSourcePdfPath] = useState<string | null>(null);
  const [sourceVaultDocId, setSourceVaultDocId] = useState<string | null>(null);
  const [analysisPass, setAnalysisPass] = useState(1);
  const [pdfSrc, setPdfSrc] = useState<string | null>(null);

  const selectedCourse = courses.find((c) => c.id === selectedCourseId) ?? null;

  const loadMeta = useCallback(async () => {
    const [courseRows, vault, events] = await Promise.all([
      ipc.academicsListCourses(),
      ipc.documentsListVault().catch(() => []),
      ipc.calendarListEvents().catch(() => []),
    ]);
    setCourses(courseRows);
    setSelectedCourseId((prev) => prev || courseRows[0]?.id || "");
    setCalendarEvents(
      events.map((e) => ({
        id: e.id,
        title: e.title,
        startAt: e.startAt,
        endAt: e.endAt,
        allDay: e.allDay,
        location: e.location,
      })),
    );
    setVaultSyllabi(
      vault
        .filter((d) => d.category === "syllabus" && d.hasFile)
        .map((d) => ({ id: d.id, title: d.title, hasFile: d.hasFile })),
    );
  }, []);

  useEffect(() => {
    void loadMeta();
  }, [loadMeta]);

  const applyAnalysis = (analysis: SyllabusAnalyzeResult, pass = 1) => {
    setResult(analysis);
    setAnalysisPass(pass);
    setEvents(
      analysis.events.map((e) => ({
        ...e,
        included: e.included !== false,
      })),
    );
    setSelectedSectionId(analysis.sections[0]?.id ?? null);
    setPhase("ready");
    const drafts = analysis.events
      .filter((e) => e.kind === "homework" || e.kind === "assignment" || e.kind === "project" || e.kind === "exam")
      .slice(0, 24)
      .map((e) => ({
        title: e.title,
        dueAt: e.startAt ?? e.dueHint ?? null,
        courseCode: analysis.courseHint ?? null,
        kind: e.kind,
      }));
    void ipc
      .settingsSet("assistant.syllabusDeadlineDrafts.v1", JSON.stringify(drafts))
      .catch(() => {
        /* non-fatal */
      });
  };

  const analyzeText = async (text: string, pass = 1) => {
    setPhase("extracting");
    try {
      applyAnalysis(await ipc.syllabusAnalyzeText(text), pass);
    } catch (e) {
      setPhase("failed");
      showToast(formatIpcError(e), "error");
    }
  };

  const analyzePdfPath = async (path: string, vaultDocId?: string | null) => {
    setSourcePdfPath(path);
    setSourceVaultDocId(vaultDocId ?? null);
    setAnalysisPass(1);
    setPhase("extracting");
    try {
      applyAnalysis(await ipc.syllabusAnalyzePdfPath(path), 1);
    } catch (e) {
      setPhase("failed");
      showToast(formatIpcError(e), "error");
    }
  };

  const sortedEvents = useMemo(() => {
    const rows = [...events];
    rows.sort((a, b) => {
      const da = parseLooseDue(a.dueHint) ?? "";
      const db = parseLooseDue(b.dueHint) ?? "";
      return sortNewest ? db.localeCompare(da) : da.localeCompare(db);
    });
    return rows;
  }, [events, sortNewest]);

  const selectedCount = events.filter((e) => e.included).length;

  const conflictLookup = useSyllabusConflicts(events, calendarEvents);
  const workloadProfile = useMemo(() => computeWorkloadProfile(events), [events]);
  const selectedSection =
    result?.sections.find((s) => s.id === selectedSectionId) ?? result?.sections[0] ?? null;
  const conflictSheetEvents = conflictSheetEventId
    ? (conflictLookup.get(conflictSheetEventId) ?? [])
    : [];
  const conflictSheetTitle =
    sortedEvents.find((e) => e.id === conflictSheetEventId)?.title ?? "Calendar conflicts";

  const showPdfTab = Boolean(
    result?.sourcePath || sourcePdfPath || sourceVaultDocId,
  );

  useEffect(() => {
    if (tab !== "pdf" || !showPdfTab) {
      setPdfSrc(null);
      return;
    }
    let cancelled = false;
    void (async () => {
      const path =
        result?.sourcePath ??
        sourcePdfPath ??
        (sourceVaultDocId
          ? await ipc.syllabusResolvePdfPath({ vaultDocId: sourceVaultDocId })
          : null);
      if (cancelled || !path) {
        if (!cancelled) setPdfSrc(null);
        return;
      }
      setPdfSrc(convertFileSrc(path));
    })();
    return () => {
      cancelled = true;
    };
  }, [tab, showPdfTab, result?.sourcePath, sourcePdfPath, sourceVaultDocId]);

  const refineWithAi = async () => {
    const text = result?.extractedText?.trim();
    if (!text) {
      showToast("No extracted text to refine — try pasted text", "error");
      return;
    }
    await analyzeText(text, 2);
  };

  const importSelected = async () => {
    if (!selectedCourse) {
      showToast("Select a planner course first", "error");
      return;
    }
    const picked = events.filter((e) => e.included);
    if (picked.length === 0) {
      showToast("Select at least one event", "error");
      return;
    }
    setBusy(true);
    try {
      let imported = 0;
      for (const e of picked) {
        const startAt = parseLooseDue(e.dueHint);
        if (!startAt) continue;
        const title = `${selectedCourse.code}: ${e.title}`;
        await ipc.calendarUpsertEvent({
          title,
          startAt,
          allDay: true,
          courseId: selectedCourse.id,
          semesterId: selectedCourse.semesterId,
          notes: `[source]=syllabus_pdf`,
        });
        imported += 1;
      }
      if (result?.grading.length) {
        await ipc.settingsSet(
          `course.grading.${selectedCourse.id}`,
          JSON.stringify(result.grading),
        );
      }
      if (result?.instructor.name || result?.instructor.email) {
        const professor = [result.instructor.name, result.instructor.email]
          .filter(Boolean)
          .join(" · ");
        await ipc.settingsSet(`course.professor.${selectedCourse.code}`, professor);
      }
      showToast(`Imported ${imported} calendar event${imported === 1 ? "" : "s"}`, "success");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  const toggleAll = (included: boolean) => {
    setEvents((prev) => prev.map((e) => ({ ...e, included })));
  };

  const applySectionMeetings = async (section: SyllabusSection) => {
    if (!selectedCourse) {
      showToast("Select a planner course first", "error");
      return;
    }
    const drafts = buildSectionMeetingEvents({
      courseCode: selectedCourse.code,
      section,
    });
    if (drafts.length === 0) {
      showToast("No meeting days detected for this section", "error");
      return;
    }
    setBusy(true);
    try {
      for (const draft of drafts) {
        await ipc.calendarUpsertEvent({
          title: draft.title,
          startAt: draft.startAt,
          allDay: true,
          recurrence: draft.recurrence,
          location: draft.location,
          courseId: selectedCourse.id,
          semesterId: selectedCourse.semesterId,
          notes: draft.notes,
        });
      }
      const refreshed = await ipc.calendarListEvents().catch(() => []);
      setCalendarEvents(
        refreshed.map((e) => ({
          id: e.id,
          title: e.title,
          startAt: e.startAt,
          endAt: e.endAt,
          allDay: e.allDay,
          location: e.location,
        })),
      );
      showToast(
        `Created ${drafts.length} recurring meeting event${drafts.length === 1 ? "" : "s"}`,
        "success",
      );
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-hidden px-3 pb-3 pt-1">
      <AppCard title="Analyze syllabus">
        <div className="grid gap-3 lg:grid-cols-2">
          <FormField label="Planner course">
            <select
              className={fieldControlClass}
              value={selectedCourseId}
              onChange={(e) => setSelectedCourseId(e.target.value)}
            >
              {courses.length === 0 ? <option value="">No courses — add in Planner</option> : null}
              {courses.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.code} · {c.title}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Vault syllabus PDF">
            <select
              className={fieldControlClass}
              defaultValue=""
              onChange={(e) => {
                const id = e.target.value;
                if (!id) return;
                void (async () => {
                  const path = await ipc.documentsResolvePath(id);
                  if (!path) {
                    showToast("Could not resolve vault file", "error");
                    return;
                  }
                  await analyzePdfPath(path, id);
                })();
                e.target.value = "";
              }}
            >
              <option value="">Choose vault PDF…</option>
              {vaultSyllabi.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.title}
                </option>
              ))}
            </select>
          </FormField>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={async () => {
              const picked = await open({
                multiple: false,
                filters: [{ name: "PDF", extensions: ["pdf"] }],
              });
              if (typeof picked === "string") await analyzePdfPath(picked);
            }}
          >
            Pick PDF…
          </Button>
          <Button
            size="sm"
            disabled={!pasteText.trim() || phase === "extracting"}
            onClick={() => void analyzeText(pasteText)}
          >
            Analyze pasted text
          </Button>
        </div>
        <FormField label="Or paste syllabus text">
          <textarea
            className={`${fieldControlClass} mt-3`}
            rows={6}
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            placeholder="Course header, grading table, dated assignments…"
          />
        </FormField>
      </AppCard>

      {phase === "extracting" ? (
        <AppCard title="Analyzing">
          <p className="text-[13px] text-[var(--color-text-light)]">
            Extracting syllabus structure…
          </p>
        </AppCard>
      ) : null}

      {phase === "failed" ? (
        <AppCard title="Analysis failed">
          <EmptyState
            title="Could not analyze syllabus"
            body="Try pasted text or a text-based PDF. Scan/image PDFs need OCR (not in this sprint)."
          />
        </AppCard>
      ) : null}

      {phase === "ready" && result ? (
        <div className="min-h-0 flex-1">
          <TrailingInspector
            open
            main={
              <AppCard className="flex h-full min-h-[420px] flex-col" title="Review">
                <div className="mb-3 flex flex-wrap items-center gap-2 border-b border-[var(--color-chrome-stroke)] pb-2">
                  <Button
                    size="sm"
                    variant={tab === "events" ? "secondary" : "ghost"}
                    onClick={() => setTab("events")}
                  >
                    Events
                  </Button>
                  <Button
                    size="sm"
                    variant={tab === "professor" ? "secondary" : "ghost"}
                    onClick={() => setTab("professor")}
                  >
                    Professor
                  </Button>
                  {showPdfTab ? (
                    <Button
                      size="sm"
                      variant={tab === "pdf" ? "secondary" : "ghost"}
                      onClick={() => setTab("pdf")}
                    >
                      PDF
                    </Button>
                  ) : null}
                  <span className="ml-auto text-[11px] text-[var(--color-text-light)]">
                    {analysisPass > 1 ? "Pass 2 · " : ""}
                    {selectedCount} selected · {result.rawLineCount} lines scanned
                  </span>
                </div>

                {tab === "pdf" ? (
                  pdfSrc ? (
                    <iframe
                      title="Syllabus PDF"
                      src={pdfSrc}
                      className="min-h-0 flex-1 rounded-lg border border-[var(--color-chrome-stroke)]"
                    />
                  ) : (
                    <EmptyState title="PDF unavailable" body="Could not resolve the source PDF path." />
                  )
                ) : tab === "professor" ? (
                  <div className="space-y-3">
                    <FormField label="Instructor">
                      <input
                        className={fieldControlClass}
                        readOnly
                        value={result.instructor.name ?? "—"}
                      />
                    </FormField>
                    <FormField label="Email">
                      <input
                        className={fieldControlClass}
                        readOnly
                        value={result.instructor.email ?? "—"}
                      />
                    </FormField>
                    <FormField label="Office hours">
                      <input
                        className={fieldControlClass}
                        readOnly
                        value={result.instructor.officeHours ?? "—"}
                      />
                    </FormField>
                    <Button
                      size="sm"
                      disabled={!selectedCourse || busy}
                      onClick={async () => {
                        if (!selectedCourse || !result.instructor.name) return;
                        const professor = [result.instructor.name, result.instructor.email]
                          .filter(Boolean)
                          .join(" · ");
                        await ipc.settingsSet(`course.professor.${selectedCourse.code}`, professor);
                        showToast("Professor synced to course", "success");
                      }}
                    >
                      Sync to course
                    </Button>
                  </div>
                ) : (
                  <>
                    <div className="mb-2 flex flex-wrap items-center gap-2">
                      <Button size="sm" variant="ghost" onClick={() => toggleAll(true)}>
                        Select all
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => toggleAll(false)}>
                        Clear
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setSortNewest((v) => !v)}
                      >
                        Sort {sortNewest ? "oldest" : "newest"}
                      </Button>
                      <Button size="sm" disabled={!selectedCount || busy} onClick={() => void importSelected()}>
                        Import {selectedCount} event{selectedCount === 1 ? "" : "s"}
                      </Button>
                    </div>
                    {sortedEvents.length === 0 ? (
                      <EmptyState title="No events" body="No dated syllabus lines were detected." />
                    ) : (
                      <ul className="min-h-0 flex-1 divide-y divide-[var(--color-chrome-stroke)] overflow-auto rounded-lg border border-[var(--color-chrome-stroke)]">
                        {sortedEvents.map((e) => {
                          const conflictCount = conflictLookup.get(e.id)?.length ?? 0;
                          return (
                          <li key={e.id} className="flex items-start gap-3 px-3 py-2.5">
                            <input
                              type="checkbox"
                              checked={e.included}
                              onChange={(ev) =>
                                setEvents((prev) =>
                                  prev.map((row) =>
                                    row.id === e.id ? { ...row, included: ev.target.checked } : row,
                                  ),
                                )
                              }
                              className="mt-1"
                            />
                            <div className="min-w-0 flex-1">
                              <div className="flex flex-wrap items-center gap-1.5">
                                <StatusChip title={e.kind} tint={eventKindTint(e.kind)} filled />
                                {e.dueHint ? <StatusChip title={e.dueHint} /> : null}
                                {conflictCount > 0 ? (
                                  <StatusChip
                                    title={`${conflictCount} conflict${conflictCount === 1 ? "" : "s"}`}
                                    tint="var(--color-warning)"
                                    filled
                                  />
                                ) : null}
                              </div>
                              <div className="mt-1 text-[13px] font-medium">{e.title}</div>
                              {conflictCount > 0 ? (
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  className="mt-1 !px-0"
                                  onClick={() => setConflictSheetEventId(e.id)}
                                >
                                  View conflicts
                                </Button>
                              ) : null}
                            </div>
                          </li>
                          );
                        })}
                      </ul>
                    )}
                  </>
                )}
              </AppCard>
            }
          >
            <div className="flex h-full flex-col gap-3 p-1">
              <AppCard title={result.courseHint ?? result.courseTitle ?? "Course"}>
                <p className="text-[12px] text-[var(--color-text-light)]">
                  {selectedCourse
                    ? `${selectedCourse.code} · ${selectedCourse.title}`
                    : "Select a course to import events"}
                </p>
                {result.warnings.map((w) => (
                  <p key={w} className="mt-2 text-[11px] text-[var(--color-warning)]">
                    {w}
                  </p>
                ))}
              </AppCard>

              <AppCard title="Grading">
                {result.grading.length === 0 ? (
                  <p className="text-[12px] text-[var(--color-text-light)]">No weights detected.</p>
                ) : (
                  <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                    {result.grading.map((g) => (
                      <li
                        key={g.name}
                        className="flex items-center justify-between py-1.5 text-[13px]"
                      >
                        <span>{g.name}</span>
                        <span className="tabular-nums text-[var(--color-text-light)]">
                          {g.weightPercent != null ? `${g.weightPercent}%` : "—"}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </AppCard>

              <AppCard title="Sections">
                {result.sections.length === 0 ? (
                  <p className="text-[12px] text-[var(--color-text-light)]">No meeting times found.</p>
                ) : (
                  <div className="space-y-2">
                    <FormField label="Your section">
                      <select
                        className={fieldControlClass}
                        value={selectedSection?.id ?? ""}
                        onChange={(e) => setSelectedSectionId(e.target.value || null)}
                      >
                        {result.sections.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.label}
                          </option>
                        ))}
                      </select>
                    </FormField>
                    {selectedSection ? (
                      <>
                        <div className="text-[12px] text-[var(--color-text-light)]">
                          {[selectedSection.meetingDays, selectedSection.meetingTime, selectedSection.location]
                            .filter(Boolean)
                            .join(" · ") || "—"}
                        </div>
                        <Button
                          size="sm"
                          disabled={!selectedCourse || busy}
                          onClick={() => void applySectionMeetings(selectedSection)}
                        >
                          Create recurring class events
                        </Button>
                      </>
                    ) : null}
                    <ul className="space-y-2 border-t border-[var(--color-chrome-stroke)] pt-2">
                      {result.sections.map((s) => (
                        <li key={s.id} className="text-[12px]">
                          <div className="font-medium">{s.label}</div>
                          <div className="text-[var(--color-text-light)]">
                            {[s.meetingDays, s.meetingTime, s.location].filter(Boolean).join(" · ") ||
                              "—"}
                          </div>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </AppCard>

              <AppCard title="Workload intensity">
                {workloadProfile ? (
                  <div className="space-y-3">
                    <div className="flex items-end justify-between gap-2">
                      <div>
                        <div className="text-[10px] font-semibold uppercase tracking-[0.05em] text-[var(--color-text-light)]">
                          Peak stress
                        </div>
                        <div className="text-[18px] font-bold tracking-[-0.02em]">
                          {workloadProfile.peakText}
                        </div>
                      </div>
                      <StatusChip
                        title={workloadProfile.levelText}
                        tint={workloadProfile.levelTint}
                        filled
                      />
                    </div>
                    <WorkloadBarChart values={workloadProfile.weeklyCounts} />
                    <div className="flex justify-between text-[10px] text-[var(--color-text-light)]">
                      <span>Week 1</span>
                      <span>Peak</span>
                      <span>Finals</span>
                    </div>
                  </div>
                ) : (
                  <p className="text-[12px] text-[var(--color-text-light)]">
                    {phase === "ready"
                      ? "Not enough dated items to estimate workload."
                      : "Waiting for analysis…"}
                  </p>
                )}
              </AppCard>

              {result.extractedTextPreview ? (
                <AppCard title="Extracted text">
                  <div className="mb-2 flex flex-wrap justify-end gap-2">
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={busy || !result.extractedText?.trim()}
                      onClick={() => void refineWithAi()}
                    >
                      Refine with AI{analysisPass > 1 ? " (pass 2)" : ""}
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => setShowRawText((v) => !v)}>
                      {showRawText ? "Hide" : "Show"}
                    </Button>
                  </div>
                  {showRawText ? (
                    <pre className="max-h-40 overflow-auto whitespace-pre-wrap text-[11px] text-[var(--color-text-light)]">
                      {result.extractedTextPreview}
                    </pre>
                  ) : (
                    <p className="text-[12px] text-[var(--color-text-light)]">
                      Preview available ({result.extractedTextPreview.length} chars)
                    </p>
                  )}
                </AppCard>
              ) : null}
            </div>
          </TrailingInspector>
        </div>
      ) : null}

      <ConflictSheet
        open={conflictSheetEventId != null}
        onOpenChange={(open) => {
          if (!open) setConflictSheetEventId(null);
        }}
        title={conflictSheetTitle}
        events={conflictSheetEvents}
      />
    </div>
  );
}

function WorkloadBarChart({ values }: { values: number[] }) {
  const max = Math.max(...values, 1);
  return (
    <div className="flex h-16 items-end gap-1">
      {values.map((count, index) => {
        const height = Math.max(8, Math.round((count / max) * 100));
        return (
          <div
            key={`wk-${index}`}
            className="flex-1 rounded-t-sm"
            style={{
              height: `${height}%`,
              background: `linear-gradient(180deg, var(--color-primary), color-mix(in srgb, var(--color-primary) 55%, transparent))`,
              opacity: count === max ? 1 : 0.72,
            }}
            title={`Week ${index + 1}: ${count} item${count === 1 ? "" : "s"}`}
          />
        );
      })}
    </div>
  );
}
