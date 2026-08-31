import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export type DbChangePayload = {
  domain: string;
  revision: number;
};

export async function onDbChange(
  handler: (payload: DbChangePayload) => void,
): Promise<UnlistenFn> {
  return listen<DbChangePayload>("db:change", (event) => handler(event.payload));
}

export async function onSyncStatus(
  handler: (payload: { domain: string; status: string }) => void,
): Promise<UnlistenFn> {
  return listen("sync:status", (event) =>
    handler(event.payload as { domain: string; status: string }),
  );
}

export type AssistantToolEvent = { name: string; summary: string };
export type AssistantChunkEvent = { chunk: string; done: boolean };

export async function onAssistantTool(
  handler: (payload: AssistantToolEvent) => void,
): Promise<UnlistenFn> {
  return listen<AssistantToolEvent>("assistant:tool", (event) => handler(event.payload));
}

export type AssistantNavigateEvent = { module: string; page: string };

export async function onAssistantNavigate(
  handler: (payload: AssistantNavigateEvent) => void,
): Promise<UnlistenFn> {
  return listen<AssistantNavigateEvent>("assistant:navigate", (event) =>
    handler(event.payload),
  );
}

export type AssistantOpenDocumentEvent = { documentId: string };

export async function onAssistantOpenDocument(
  handler: (payload: AssistantOpenDocumentEvent) => void,
): Promise<UnlistenFn> {
  return listen<AssistantOpenDocumentEvent>("assistant:open-document", (event) =>
    handler(event.payload),
  );
}

export async function onAssistantChunk(
  handler: (payload: AssistantChunkEvent) => void,
): Promise<UnlistenFn> {
  return listen<AssistantChunkEvent>("assistant:chunk", (event) => handler(event.payload));
}

export type LlmDownloadEvent = {
  progress: number;
  bytesDownloaded: number;
  bytesTotal: number | null;
  done: boolean;
  error?: string | null;
};

export async function onLlmDownload(
  handler: (payload: LlmDownloadEvent) => void,
): Promise<UnlistenFn> {
  return listen<LlmDownloadEvent>("ai:llm-download", (event) => handler(event.payload));
}
