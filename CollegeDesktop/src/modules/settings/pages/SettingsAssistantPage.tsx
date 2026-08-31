import { useCallback, useEffect, useState } from "react";
import { AppCard, Button, ListRow, ProgressBar, StatusChip } from "@/design-system";
import { ipc, formatIpcError, type LlmModelStatus } from "@/lib/ipc";
import { onLlmDownload } from "@/lib/events";
import { showToast } from "@/lib/toast";
import { insetPanelStyle } from "../shared";
import { useSettings } from "../useSettings";

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function SettingsAssistantPage() {
  const { ai, setAi, assistantTools, toolsExpanded, setToolsExpanded } = useSettings();
  const [llm, setLlm] = useState<LlmModelStatus | null>(null);
  const [downloading, setDownloading] = useState(false);

  const refreshLlm = useCallback(async () => {
    try {
      const status = await ipc.aiLlmStatus();
      setLlm(status);
      setAi(await ipc.aiRuntimeStatus());
    } catch {
      /* ignore */
    }
  }, [setAi]);

  useEffect(() => {
    void refreshLlm();
    let unlisten: (() => void) | undefined;
    void onLlmDownload(() => void refreshLlm()).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, [refreshLlm]);

  const startDownload = async () => {
    setDownloading(true);
    try {
      const status = await ipc.aiLlmDownload();
      setLlm(status);
      setAi(await ipc.aiRuntimeStatus());
      showToast(status.message, status.installed ? "success" : "error");
    } catch (e) {
      showToast(formatIpcError(e), "error");
    } finally {
      setDownloading(false);
    }
  };

  const llmReady = llm?.installed && llm?.serverInstalled;

  return (
    <>
      <AppCard title="On-device assistant brain">
        <p className="mb-3 text-body text-[var(--color-text-light)]">
          College ships with <strong>Gemma 4 E4B Instruct</strong> — Google's latest small
          model (4.5B effective parameters) that runs fully offline on your machine. It powers open-ended questions, tool planning, and chat
          synthesis. No Ollama or cloud API required.
        </p>

        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          <li>
            <ListRow
              title="Model"
              subtitle={llm?.displayName ?? "Gemma 4 E4B Instruct"}
              trailing={
                llmReady ? (
                  <StatusChip title="Installed" tint="var(--color-success)" filled />
                ) : llm?.downloading || downloading ? (
                  <StatusChip title="Downloading…" tint="var(--color-primary)" filled />
                ) : (
                  <StatusChip title="Not installed" tint="var(--color-warning)" />
                )
              }
            />
          </li>
          <li>
            <ListRow
              title="Inference engine"
              trailing={
                llm?.serverInstalled ? (
                  <StatusChip title="Ready" tint="var(--color-success)" filled />
                ) : (
                  <StatusChip title="Pending" tint="var(--color-warning)" />
                )
              }
            />
          </li>
          <li>
            <ListRow
              title="Device"
              trailing={ai?.device ? <StatusChip title={ai.device} filled /> : "—"}
            />
          </li>
        </ul>

        {(llm?.downloading || downloading) && (
          <div className="mt-3 space-y-1.5">
            <ProgressBar value={Math.round((llm?.downloadProgress ?? 0) * 100)} />
            <p className="text-caption text-[var(--color-text-light)]">
              {llm?.bytesTotal
                ? `${formatBytes(llm.bytesDownloaded)} / ${formatBytes(llm.bytesTotal)}`
                : "Downloading…"}
            </p>
          </div>
        )}

        {!llmReady && (
          <div className="mt-3 flex flex-wrap gap-2">
            <Button
              size="sm"
              onClick={() => void startDownload()}
              disabled={downloading || llm?.downloading}
            >
              {downloading || llm?.downloading ? "Downloading…" : "Download on-device model (~4.3 GB)"}
            </Button>
          </div>
        )}

        {llm?.message && (
          <p className="mt-2 px-0.5 text-caption text-[var(--color-text-light)]">{llm.message}</p>
        )}
      </AppCard>

      <AppCard title="Runtime status" className="mt-3">
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          <li>
            <ListRow
              title="Backend"
              trailing={ai?.backend ? <StatusChip title={ai.backend} filled /> : "—"}
            />
          </li>
          <li>
            <ListRow
              title="Embeddings"
              trailing={
                <StatusChip
                  title={ai?.embeddingsBackend ?? "—"}
                  tint={ai?.embeddingsReady ? "var(--color-success)" : "var(--color-warning)"}
                  filled
                />
              }
            />
          </li>
          <li>
            <ListRow
              title="LLM"
              trailing={
                <StatusChip
                  title={ai?.llmReady ? "Ready" : "Not ready"}
                  tint={ai?.llmReady ? "var(--color-success)" : "var(--color-warning)"}
                  filled
                />
              }
            />
          </li>
          {ai?.pingMessage && (
            <li>
              <ListRow title="Status" subtitle={ai.pingMessage} />
            </li>
          )}
        </ul>
        <p className="mt-2 truncate px-2.5 py-2 text-caption" style={insetPanelStyle}>
          {ai?.modelDir ?? "—"}
        </p>
      </AppCard>

      <AppCard title="Tool registry" className="mt-3">
        <button
          type="button"
          className="flex w-full items-center justify-between rounded-[10px] border border-[var(--color-chrome-stroke)] px-2.5 py-2 text-left text-meta font-medium text-[var(--color-text)]"
          style={insetPanelStyle}
          onClick={() => setToolsExpanded((v) => !v)}
        >
          <span>{assistantTools.length} tools available to the assistant</span>
          <span className="text-caption">{toolsExpanded ? "Hide" : "Show"}</span>
        </button>
        {toolsExpanded && (
          <ul
            className="mt-2 max-h-72 divide-y divide-[var(--color-chrome-stroke)] overflow-y-auto rounded-[10px] border border-[var(--color-chrome-stroke)]"
            style={insetPanelStyle}
          >
            {assistantTools.map((tool) => (
              <li key={tool.name} className="px-2.5 py-2">
                <p className="text-meta font-medium text-[var(--color-text)]">{tool.name}</p>
                <p className="mt-0.5 text-caption leading-relaxed">{tool.description}</p>
              </li>
            ))}
          </ul>
        )}
      </AppCard>
    </>
  );
}
