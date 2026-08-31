import { useEffect } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { ipc } from "@/lib/ipc";
import {
  applyWindowsPersonalization,
  isWindowsPlatform,
  loadWindowsCapabilities,
  refreshWindowsWidgetFeeds,
  syncWindowsSearchIndex,
} from "@/lib/windowsIntegration";

/**
 * Bootstraps Windows 11 native integrations on startup:
 * capabilities probe, personalization sync, shell refresh, EcoQoS on blur.
 */
export function useWindowsIntegration() {
  useEffect(() => {
    if (!isWindowsPlatform()) return;

    let cancelled = false;

    void (async () => {
      const caps = await loadWindowsCapabilities();
      if (cancelled || !caps) return;

      await applyWindowsPersonalization();
      try {
        await ipc.windowsRefreshShellIntegration();
      } catch {
        /* ignore */
      }

      // Seed widget feeds and search catalog from live data.
      try {
        const [events, tasks, gpa, pipeline, vault] = await Promise.all([
          ipc.calendarListEvents().catch(() => []),
          ipc.calendarListTasks().catch(() => []),
          ipc.academicsGetGpaSummary().catch(() => null),
          ipc.careerPipelineMetrics().catch(() => null),
          ipc.documentsListVault().catch(() => []),
        ]);

        if (!cancelled) {
          await refreshWindowsWidgetFeeds({
            agenda: {
              events: events.slice(0, 3),
              tasks: tasks.filter((t) => !t.isComplete).slice(0, 5),
            },
            gpa: gpa
              ? {
                  gpa: gpa.gpa,
                  credits: gpa.gradedCredits,
                }
              : undefined,
            pipeline: pipeline
              ? {
                  applied: pipeline.applied,
                  interviewing: pipeline.interviewing,
                  offer: pipeline.offer,
                  total: pipeline.total,
                }
              : undefined,
          });

          await syncWindowsSearchIndex(
            vault.slice(0, 200).map((d) => ({
              id: d.id,
              title: d.title,
              path: d.relativePath || d.title,
              category: d.category,
              updatedAt: d.updatedAt,
            })),
          );
        }
      } catch {
        /* ignore bootstrap data errors */
      }
    })();

    const win = getCurrentWindow();
    let unlisten: (() => void) | undefined;
    void win
      .onFocusChanged(({ payload: focused }) => {
        void ipc.windowsSetEfficiencyMode(!focused).catch(() => {});
      })
      .then((fn) => {
        unlisten = fn;
      })
      .catch(() => {});

    const personalizationTimer = window.setInterval(() => {
      void applyWindowsPersonalization();
    }, 60_000);

    return () => {
      cancelled = true;
      unlisten?.();
      window.clearInterval(personalizationTimer);
    };
  }, []);
}
