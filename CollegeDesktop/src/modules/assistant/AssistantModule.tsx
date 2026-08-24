import { useCallback, useEffect, useRef, useState } from "react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  MetricTile,
  SegmentedPills,
  StatusChip,
  fieldControlClass,
} from "@/design-system";
import { ipc, formatIpcError, type AiRuntimeStatus, type AuditSummary } from "@/lib/ipc";
import { onAssistantChunk, onAssistantNavigate, onAssistantTool, type AssistantToolEvent } from "@/lib/events";
import { showToast } from "@/lib/toast";
import { shellNavigate } from "@/lib/shellNavigate";
import { SimpleMarkdown } from "./simpleMarkdown";
import { SyllabusReviewPage } from "./syllabus/SyllabusReviewPage";

type AgentRole = "general" | "academics" | "career" | "finance";

type PendingAction = {
  kind: string;
  title: string;
  dueAt?: string | null;
  company?: string | null;
  startAt?: string | null;
  semesterName?: string | null;
  courseCode?: string | null;
  courseName?: string | null;
  credits?: number | null;
  year?: number | null;
  season?: string | null;
  existingTitle?: string | null;
  applicationId?: string | null;
  status?: string | null;
  navigateModule?: string | null;
  navigatePage?: string | null;
  settingKey?: string | null;
  settingValue?: string | null;
  summaryBody?: string | null;
  profileName?: string | null;
  profileMajor?: string | null;
  profileUniversity?: string | null;
  profileEmail?: string | null;
};

const TOOL_LABELS: Record<string, string> = {
  get_audit_summary: "Reading planner…",
  get_gpa: "Reading GPA…",
  list_open_tasks: "Reading tasks…",
  list_events: "Reading calendar…",
  career_pipeline_metrics: "Reading career pipeline…",
  finance_dashboard: "Reading finance…",
  vault_semantic_search: "Searching vault…",
  create_task: "Preparing task…",
  create_calendar_event: "Preparing event…",
  add_course_to_plan: "Preparing course add…",
  add_semester: "Preparing semester…",
  remove_course_from_plan: "Preparing course removal…",
  update_task: "Preparing task update…",
  update_job_application_status: "Preparing status update…",
  delete_task: "Preparing task deletion…",
  delete_calendar_event: "Preparing event deletion…",
  update_calendar_event: "Preparing event update…",
  track_job_application: "Preparing job tracker…",
  open_settings_section: "Opening settings…",
  update_app_setting: "Preparing setting change…",
  save_web_learning: "Preparing memory save…",
  get_job_resume_match: "Reading resume match…",
  get_student_learning_profile: "Reading learning profile…",
  explain_sap_policy: "Explaining SAP policy…",
  draft_semester_plan: "Drafting semester plan…",
  open_document: "Opening document…",
  open_resume_builder: "Opening resume builder…",
  update_profile: "Preparing profile update…",
  sync_syllabus_deadlines: "Preparing syllabus sync…",
  draft_weekly_schedule: "Drafting weekly schedule…",
  resolve_event_location: "Resolving event location…",
  screen_aid_eligibility: "Screening aid eligibility…",
  estimate_aid_range: "Estimating aid range…",
  assess_requirement_risk: "Assessing requirement risk…",
  simulate_course_swap: "Simulating course swap…",
  suggest_courses_for_skill_gaps: "Suggesting courses…",
  assess_registration_workload: "Assessing workload…",
  propose_syllabus_deadline_sync: "Reading syllabus deadlines…",
  compare_award_letter_to_planner: "Comparing award letter…",
  extract_aid_document_facts: "Reading aid doc checklist…",
  navigate_to_page: "Navigating…",
};

function toolChipLabel(entry: AssistantToolEvent): string {
  if (entry.summary && TOOL_LABELS[entry.name] !== entry.summary) {
    return entry.summary.length > 48 ? `${entry.summary.slice(0, 48)}…` : entry.summary;
  }
  return TOOL_LABELS[entry.name] ?? entry.name;
}

const AGENT_ROLE_OPTIONS: Array<{ id: AgentRole; label: string }> = [
  { id: "general", label: "General" },
  { id: "academics", label: "Academics" },
  { id: "career", label: "Career" },
  { id: "finance", label: "Finance" },
];

type ChatMessage = {
  role: "user" | "assistant";
  content: string;
  createdAt: string;
  /** Set on assistant rows from localAnswer or ai_chat_completion. */
  source?: "local" | "model";
};

type TranscriptItem =
  | { kind: "day"; label: string; key: string }
  | { kind: "message"; message: ChatMessage; index: number };

function createMessage(role: ChatMessage["role"], content: string): ChatMessage {
  return { role, content, createdAt: new Date().toISOString() };
}

function isSameCalendarDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function daySeparatorLabel(iso: string): string {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  if (isSameCalendarDay(d, today)) return "Today";
  if (isSameCalendarDay(d, yesterday)) return "Yesterday";
  return d.toLocaleDateString(undefined, {
    weekday: "long",
    month: "short",
    day: "numeric",
    year: d.getFullYear() !== today.getFullYear() ? "numeric" : undefined,
  });
}

function buildTranscriptItems(messages: ChatMessage[]): TranscriptItem[] {
  const items: TranscriptItem[] = [];
  let lastDayKey: string | null = null;

  for (let i = 0; i < messages.length; i++) {
    const m = messages[i]!;
    const dayKey = new Date(m.createdAt).toDateString();
    if (dayKey !== lastDayKey) {
      items.push({ kind: "day", label: daySeparatorLabel(m.createdAt), key: dayKey });
      lastDayKey = dayKey;
    }
    items.push({ kind: "message", message: m, index: i });
  }

  return items;
}

type AppSnapshot = {
  summary: AuditSummary | null;
  gpaLine: string | null;
  courseLines: string[];
  eventLines: string[];
  taskLines: string[];
  careerLine: string | null;
  appLines: string[];
  vaultLines: string[];
  financeLine: string | null;
  financeAccountLines: string[];
  isEmpty: boolean;
  openTaskCount: number;
  eventCount: number;
  appCount: number;
};

async function loadSnapshot(): Promise<AppSnapshot> {
  const [summary, courses, events, tasks, apps, metrics, gpa, vault, financeSummary, financeAccounts] =
    await Promise.all([
      ipc.academicsGetAuditSummary().catch(() => null),
      ipc.academicsListCourses().catch(() => []),
      ipc.calendarListEvents().catch(() => []),
      ipc.calendarListTasks().catch(() => []),
      ipc.careerListApplications().catch(() => []),
      ipc.careerPipelineMetrics().catch(() => null),
      ipc.academicsGetGpaSummary().catch(() => null),
      ipc.documentsListVault().catch(() => []),
      ipc.financeDashboardSummary().catch(() => null),
      ipc.financeListAccounts().catch(() => []),
    ]);

  const courseLines = courses
    .slice(0, 12)
    .map(
      (c) =>
        `${c.code} (${c.status.replace("_", " ")}, ${c.credits} cr${c.grade ? `, ${c.grade}` : ""})`,
    );
  const eventLines = events
    .slice(0, 5)
    .map((e) => `${e.title} · ${new Date(e.startAt).toLocaleString()}`);
  const taskLines = tasks
    .slice(0, 6)
    .map((t) => `${t.title}${t.isComplete ? " (done)" : ""}`);
  const appLines = apps
    .slice(0, 8)
    .map((a) => `${a.roleTitle} @ ${a.company} [${a.status}]`);
  const careerLine = metrics
    ? `Pipeline: ${metrics.total} apps — interested ${metrics.interested}, applied ${metrics.applied}, interviewing ${metrics.interviewing}, offer ${metrics.offer}.`
    : null;
  const gpaLine =
    gpa?.gpa != null
      ? `GPA ${gpa.gpa.toFixed(2)} across ${gpa.gradedCourses} graded courses (${gpa.gradedCredits} cr).`
      : null;
  const vaultLines = vault
    .slice(0, 8)
    .map((d) => `${d.title} [${d.category}]`);

  const financeLine = financeSummary
    ? `Net worth: ${financeSummary.netWorth.toLocaleString(undefined, {
        style: "currency",
        currency: "USD",
      })} — ${financeSummary.accountCount} accounts, ${financeSummary.transactionCount} transactions, ${financeSummary.budgetCount} budgets.`
    : null;
  const financeAccountLines = financeAccounts
    .slice(0, 8)
    .map(
      (a) =>
        `${a.name} (${a.accountType}): ${a.balance.toLocaleString(undefined, {
          style: "currency",
          currency: a.currency || "USD",
        })}`,
    );

  const openTaskCount = tasks.filter((t) => !t.isComplete).length;
  const isEmpty =
    (summary?.courseCount ?? 0) === 0 &&
    (summary?.semesterCount ?? 0) === 0 &&
    courses.length === 0 &&
    events.length === 0 &&
    tasks.length === 0 &&
    (metrics?.total ?? 0) === 0 &&
    (financeSummary?.accountCount ?? 0) === 0 &&
    (financeSummary?.transactionCount ?? 0) === 0;

  return {
    summary,
    gpaLine,
    courseLines,
    eventLines,
    taskLines,
    careerLine,
    appLines,
    vaultLines,
    financeLine,
    financeAccountLines,
    isEmpty,
    openTaskCount,
    eventCount: events.length,
    appCount: metrics?.total ?? apps.length,
  };
}

/** Structured local/model rows that should render as tool-style result cards. */
function looksLikeToolResult(content: string): boolean {
  const t = content.trimStart();
  return (
    /^Pipeline:/i.test(t) ||
    /^GPA\s/i.test(t) ||
    /^Net worth:/i.test(t) ||
    /^Finance summary:/i.test(t) ||
    /^You currently have \*\*\d+/i.test(t) ||
    /^Vault documents:/i.test(t) ||
    /^Open tasks & deadlines:/i.test(t) ||
    /^Upcoming events:/i.test(t) ||
    /^Career pipeline/i.test(t)
  );
}

const ROLE_QUICK_PROMPTS: Record<AgentRole, string[]> = {
  general: [
    "What credits do I have?",
    "What’s my GPA?",
    "What’s on my calendar?",
    "How’s my career pipeline?",
  ],
  academics: [
    "What credits do I have?",
    "What’s my GPA?",
    "How’s my degree progress?",
    "List my courses",
  ],
  career: [
    "How’s my career pipeline?",
    "List my applications",
    "Who am I interviewing with?",
    "What roles am I tracking?",
  ],
  finance: [
    "What’s my net worth?",
    "List my accounts",
    "How many transactions do I have?",
    "What budgets am I tracking?",
  ],
};

/** Fast local answers for common questions when models aren't installed. */
function localAnswer(question: string, snap: AppSnapshot, role: AgentRole): string | null {
  const q = question.toLowerCase();

  if (snap.isEmpty) {
    if (
      q.includes("credit") ||
      q.includes("course") ||
      q.includes("semester") ||
      q.includes("degree") ||
      q.includes("deadline") ||
      q.includes("event") ||
      q.includes("job") ||
      q.includes("career") ||
      q.includes("application") ||
      q.includes("budget") ||
      q.includes("finance") ||
      q.includes("net worth") ||
      q.includes("account") ||
      q.includes("transaction")
    ) {
      return (
        "Your College workspace is empty right now — no semesters, courses, career apps, or finance rows yet.\n\n" +
        "To explore with demo data: open Settings → Load sample data, then ask again.\n" +
        "Or add a semester/course in College → Planner and I’ll report live totals."
      );
    }
  }

  if (
    q.includes("net worth") ||
    q.includes("budget") ||
    q.includes("finance") ||
    q.includes("spending") ||
    q.includes("transaction") ||
    (q.includes("account") && !q.includes("application")) ||
    (role === "finance" &&
      (q.includes("money") || q.includes("balance") || q.includes("worth") || q.includes("list")))
  ) {
    if (!snap.financeLine && !snap.financeAccountLines.length) {
      if (
        role === "finance" ||
        q.includes("net worth") ||
        q.includes("budget") ||
        q.includes("finance") ||
        q.includes("transaction")
      ) {
        return "No finance data yet. Add accounts under Finance, or load sample data from Settings.";
      }
    } else {
      const accounts =
        snap.financeAccountLines.length > 0
          ? `\n\nAccounts:\n• ${snap.financeAccountLines.join("\n• ")}`
          : "";
      return `${snap.financeLine ?? "Finance summary"}${accounts}`;
    }
  }

  if (
    q.includes("gpa") ||
    q.includes("grade point") ||
    q.includes("grades") ||
    (role === "academics" &&
      (q.includes("credit") || q.includes("degree") || q.includes("course") || q.includes("semester")))
  ) {
    if (role === "academics" && (q.includes("credit") || q.includes("degree") || q.includes("course"))) {
      const s = snap.summary;
      if (s) {
        const courseDetail =
          snap.courseLines.length > 0
            ? `\n\nCourses on your plan:\n• ${snap.courseLines.join("\n• ")}`
            : "";
        return (
          `You currently have **${s.completedCredits} completed credits** and **${s.plannedCredits} planned credits** ` +
          `(${s.courseCount} courses across ${s.semesterCount} semesters).` +
          (snap.gpaLine ? `\n\n${snap.gpaLine}` : "") +
          courseDetail
        );
      }
    }
    if (q.includes("gpa") || q.includes("grade point") || q.includes("grades")) {
      if (!snap.gpaLine) {
        return "No graded completed courses yet. Set grades under College → Planner (completed courses), then ask again.";
      }
      return snap.gpaLine;
    }
  }

  if (q.includes("vault") || q.includes("document") || q.includes("syllabus file") || q.includes("resume file")) {
    if (!snap.vaultLines.length) {
      return "Vault is empty. Import a file under Documents, or load sample data from Settings.";
    }
    return `Vault documents:\n• ${snap.vaultLines.join("\n• ")}`;
  }

  if (q.includes("credit") || q.includes("how many course") || q.includes("degree progress")) {
    const s = snap.summary;
    if (!s) return "I couldn’t read your academics summary yet. Try refreshing after adding courses.";
    const courseDetail =
      snap.courseLines.length > 0
        ? `\n\nCourses on your plan:\n• ${snap.courseLines.join("\n• ")}`
        : "";
    return (
      `You currently have **${s.completedCredits} completed credits** and **${s.plannedCredits} planned credits** ` +
      `(${s.courseCount} courses across ${s.semesterCount} semesters).` +
      courseDetail
    );
  }

  if (q.includes("deadline") || q.includes("task") || q.includes("todo")) {
    if (!snap.taskLines.length) {
      return "No tasks on your calendar yet. Add one under Calendar → Tasks, or load sample data from Settings.";
    }
    return `Open tasks & deadlines:\n• ${snap.taskLines.join("\n• ")}`;
  }

  if (q.includes("event") || q.includes("calendar") || q.includes("schedule")) {
    if (!snap.eventLines.length) {
      return "No upcoming events yet. Add one under Calendar → Month/Agenda, or load sample data from Settings.";
    }
    return `Upcoming events:\n• ${snap.eventLines.join("\n• ")}`;
  }

  if (
    q.includes("job") ||
    q.includes("career") ||
    q.includes("application") ||
    q.includes("interview") ||
    (role === "career" && (q.includes("role") || q.includes("pipeline") || q.includes("list")))
  ) {
    if (!snap.careerLine && !snap.appLines.length) {
      if (
        role === "career" ||
        q.includes("job") ||
        q.includes("career") ||
        q.includes("application") ||
        q.includes("interview")
      ) {
        return "No applications tracked yet. Add roles under Career, or load sample data from Settings.";
      }
    } else if (
      role === "career" ||
      q.includes("job") ||
      q.includes("career") ||
      q.includes("application") ||
      q.includes("interview") ||
      q.includes("pipeline") ||
      q.includes("role")
    ) {
      const apps =
        snap.appLines.length > 0 ? `\n\n• ${snap.appLines.join("\n• ")}` : "";
      return `${snap.careerLine ?? "Career pipeline"}${apps}`;
    }
  }

  return null;
}

function AssistantResultCard({
  content,
  source,
}: {
  content: string;
  source: "local" | "model";
}) {
  const chipTitle = source === "local" ? "Local data" : "Model";
  const chipTint = source === "local" ? "var(--color-success)" : "var(--color-primary)";

  return (
    <div
      className="max-w-[min(100%,640px)] overflow-hidden rounded-[16px] shadow-[var(--shadow-elevated)] ring-1 ring-[var(--color-chrome-stroke)]"
      style={{
        background:
          "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 6%, var(--color-surface)), var(--color-surface))",
      }}
    >
      <div className="flex flex-wrap items-center gap-1.5 border-b border-[var(--color-chrome-stroke)] px-3.5 py-2">
        <StatusChip title={chipTitle} tint={chipTint} filled />
        <StatusChip title="Tool result" />
      </div>
      <div className="px-3.5 py-2.5 text-[13px] leading-relaxed text-[var(--color-text-main)]">
        <SimpleMarkdown content={content} />
      </div>
    </div>
  );
}

export function AssistantModule({ page = "chat" }: { page?: string }) {
  const view = page === "syllabus" ? "syllabus" : "chat";
  const [status, setStatus] = useState<AiRuntimeStatus | null>(null);
  const [input, setInput] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([
    createMessage(
      "assistant",
      "Ask about credits, deadlines, or career prep. I read your live College data. If everything looks empty, load sample data from Settings first.",
    ),
  ]);
  const [busy, setBusy] = useState(false);
  const [emptyWorkspace, setEmptyWorkspace] = useState(true);
  const [workspaceStats, setWorkspaceStats] = useState({
    courses: 0,
    openTasks: 0,
    events: 0,
    apps: 0,
    completedCredits: 0,
  });
  const listRef = useRef<HTMLUListElement>(null);
  const [agentRole, setAgentRole] = useState<AgentRole>("general");
  const [attachments, setAttachments] = useState<Array<{ id: string; title: string }>>([]);
  const [webMemory, setWebMemory] = useState("");
  const [webMemoryDraft, setWebMemoryDraft] = useState("");
  const [toolTrace, setToolTrace] = useState<AssistantToolEvent[]>([]);
  const [streamingContent, setStreamingContent] = useState("");
  const [pendingAction, setPendingAction] = useState<PendingAction | null>(null);
  const turnAbortRef = useRef<AbortController | null>(null);

  const refreshEmpty = useCallback(async () => {
    const snap = await loadSnapshot();
    setEmptyWorkspace(snap.isEmpty);
    setWorkspaceStats({
      courses: snap.summary?.courseCount ?? 0,
      openTasks: snap.openTaskCount,
      events: snap.eventCount,
      apps: snap.appCount,
      completedCredits: snap.summary?.completedCredits ?? 0,
    });
  }, []);

  useEffect(() => {
    void ipc.aiRuntimeStatus().then(setStatus);
    void refreshEmpty();
    void ipc.settingsGet().then((s) => {
      const mem = s.values["assistant.webMemory"] || "";
      setWebMemory(mem);
      setWebMemoryDraft(mem);
    });
    let unlistenNavigate: (() => void) | undefined;
    void onAssistantNavigate((payload) => {
      shellNavigate(payload.module, payload.page);
      showToast(`Opened ${payload.module}`, "success");
    }).then((fn) => {
      unlistenNavigate = fn;
    });
    return () => {
      unlistenNavigate?.();
    };
  }, [refreshEmpty]);

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, busy, toolTrace, streamingContent, pendingAction]);

  useEffect(() => {
    if (!busy) return;
    let unlistenTool: (() => void) | undefined;
    let unlistenChunk: (() => void) | undefined;
    void (async () => {
      unlistenTool = await onAssistantTool((payload) => {
        setToolTrace((prev) => {
          const idx = prev.findIndex((p) => p.name === payload.name);
          if (idx >= 0) {
            const next = [...prev];
            next[idx] = payload;
            return next;
          }
          return [...prev, payload];
        });
      });
      unlistenChunk = await onAssistantChunk((payload) => {
        if (payload.done) return;
        if (payload.chunk) {
          setStreamingContent((prev) => prev + payload.chunk);
        }
      });
    })();
    return () => {
      unlistenTool?.();
      unlistenChunk?.();
    };
  }, [busy]);

  const cancelTurn = useCallback(async () => {
    turnAbortRef.current?.abort();
    try {
      await ipc.assistantCancelTurn();
    } catch {
      /* ignore */
    }
    setBusy(false);
    setToolTrace([]);
    setStreamingContent("");
  }, []);

  const sendText = useCallback(
    async (text: string) => {
      const trimmed = text.trim();
      if (!trimmed || busy) return;
      const next = [...messages, createMessage("user", trimmed)];
      setMessages(next);
      setInput("");
      setBusy(true);
      setToolTrace([]);
      setStreamingContent("");
      setPendingAction(null);
      turnAbortRef.current = new AbortController();
      try {
        const snap = await loadSnapshot();
        setEmptyWorkspace(snap.isEmpty);
        const direct = localAnswer(trimmed, snap, agentRole);
        if (direct) {
          setMessages([
            ...next,
            { ...createMessage("assistant", direct), source: "local" },
          ]);
          return;
        }
        const res = await ipc.assistantTurn({
          messages: next.map((m) => ({ role: m.role, content: m.content })),
          agentRole,
          attachmentIds: attachments.map((a) => a.id),
          webMemory: webMemory.trim() || undefined,
        });
        if (res.toolTrace.length) {
          setToolTrace(res.toolTrace.map((t) => ({ name: t.name, summary: t.summary })));
        }
        if (res.pendingAction) {
          setPendingAction(res.pendingAction);
        }
        setMessages([
          ...next,
          { ...createMessage("assistant", res.content), source: "model" },
        ]);
      } catch (e) {
        const msg = formatIpcError(e);
        if (msg !== "Turn cancelled") {
          setMessages([...next, createMessage("assistant", msg)]);
        }
      } finally {
        setBusy(false);
        setToolTrace([]);
        setStreamingContent("");
        turnAbortRef.current = null;
      }
    },
    [busy, messages, agentRole, attachments, webMemory],
  );

  const confirmCreateTask = async () => {
    if (!pendingAction || pendingAction.kind !== "createTask") return;
    try {
      await ipc.calendarUpsertTask({ title: pendingAction.title, dueAt: pendingAction.dueAt ?? undefined });
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Task created: ${pendingAction.title}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Created task **${pendingAction.title}** on your calendar.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmCreateEvent = async () => {
    if (!pendingAction || pendingAction.kind !== "createEvent") return;
    try {
      const start = pendingAction.startAt ?? new Date(Date.now() + 60 * 60 * 1000).toISOString();
      const end = new Date(new Date(start).getTime() + 60 * 60 * 1000).toISOString();
      await ipc.calendarUpsertEvent({
        title: pendingAction.title,
        startAt: start,
        endAt: end,
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Event created: ${pendingAction.title}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Scheduled **${pendingAction.title}** on your calendar.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmCreateApplication = async () => {
    if (!pendingAction || pendingAction.kind !== "createApplication") return;
    const company = pendingAction.company?.trim() || pendingAction.title;
    try {
      await ipc.careerUpsertApplication({
        company,
        roleTitle: pendingAction.title,
        status: "interested",
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Tracking job at ${company}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Added **${pendingAction.title}** at **${company}** to your career pipeline.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const resolveSemesterId = async (semesterName?: string | null): Promise<string | null> => {
    const semesters = await ipc.academicsListSemesters();
    if (semesters.length === 0) return null;
    if (!semesterName?.trim()) {
      return semesters.find((s) => s.isCurrent)?.id ?? semesters[semesters.length - 1]?.id ?? null;
    }
    const needle = semesterName.toLowerCase();
    const match = semesters.find(
      (s) =>
        s.label.toLowerCase().includes(needle) ||
        `${s.season} ${s.year}`.toLowerCase().includes(needle),
    );
    return match?.id ?? semesters[semesters.length - 1]?.id ?? null;
  };

  const confirmAddCourseToPlan = async () => {
    if (!pendingAction || pendingAction.kind !== "addCourseToPlan") return;
    const code = pendingAction.courseCode?.trim() || pendingAction.title;
    try {
      const semesterId = await resolveSemesterId(pendingAction.semesterName);
      if (!semesterId) {
        showToast("Add a semester in Planner first.", "error");
        return;
      }
      await ipc.academicsUpsertCourse({
        semesterId,
        code,
        title: pendingAction.courseName?.trim() || code,
        credits: pendingAction.credits ?? 3,
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Added ${code} to plan`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Added **${code}** to your planner.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmAddSemester = async () => {
    if (!pendingAction || pendingAction.kind !== "addSemester") return;
    const year = pendingAction.year ?? new Date().getFullYear();
    const season = pendingAction.season ?? "Fall";
    try {
      await ipc.academicsUpsertSemester({
        year,
        season,
        label: pendingAction.semesterName ?? pendingAction.title,
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Added ${season} ${year}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Added **${season} ${year}** to your planner.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmRemoveCourseFromPlan = async () => {
    if (!pendingAction || pendingAction.kind !== "removeCourseFromPlan") return;
    const code = (pendingAction.courseCode ?? pendingAction.title).toLowerCase();
    try {
      const courses = await ipc.academicsListCourses();
      const match = courses.find((c) => c.code.toLowerCase().includes(code));
      if (!match) {
        showToast(`No course matching ${pendingAction.title}`, "error");
        return;
      }
      await ipc.academicsDeleteCourse(match.id);
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Removed ${match.code}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Removed **${match.code}** from your planner.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmUpdateTask = async () => {
    if (!pendingAction || pendingAction.kind !== "updateTask") return;
    const existing = pendingAction.existingTitle?.trim();
    if (!existing) return;
    try {
      const tasks = await ipc.calendarListTasks();
      const match = tasks.find((t) => t.title.toLowerCase().includes(existing.toLowerCase()));
      if (!match) {
        showToast(`No task matching "${existing}"`, "error");
        return;
      }
      await ipc.calendarUpsertTask({
        id: match.id,
        title: pendingAction.title,
        dueAt: pendingAction.dueAt ?? match.dueAt,
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast("Task updated", "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Updated task to **${pendingAction.title}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmUpdateApplicationStatus = async () => {
    if (!pendingAction || pendingAction.kind !== "updateApplicationStatus") return;
    const company = pendingAction.company?.trim() || pendingAction.title;
    const status = pendingAction.status ?? "applied";
    try {
      const apps = await ipc.careerListApplications();
      const match = apps.find((a) => a.company.toLowerCase().includes(company.toLowerCase()));
      if (!match) {
        showToast(`No application matching "${company}"`, "error");
        return;
      }
      await ipc.careerUpdateApplicationStatus(match.id, status);
      setPendingAction(null);
      await refreshEmpty();
      showToast(`${match.company} → ${status}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Moved **${match.company}** to **${status}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmDeleteTask = async () => {
    if (!pendingAction || pendingAction.kind !== "deleteTask") return;
    const needle = (pendingAction.existingTitle ?? pendingAction.title).toLowerCase();
    try {
      const tasks = await ipc.calendarListTasks();
      const match = tasks.find((t) => t.title.toLowerCase().includes(needle));
      if (!match) {
        showToast(`No task matching "${pendingAction.title}"`, "error");
        return;
      }
      await ipc.calendarDeleteTask(match.id);
      setPendingAction(null);
      await refreshEmpty();
      showToast("Task deleted", "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Deleted task **${match.title}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmDeleteEvent = async () => {
    if (!pendingAction || pendingAction.kind !== "deleteCalendarEvent") return;
    const needle = (pendingAction.existingTitle ?? pendingAction.title).toLowerCase();
    try {
      const events = await ipc.calendarListEvents();
      const match = events.find((e) => e.title.toLowerCase().includes(needle));
      if (!match) {
        showToast(`No event matching "${pendingAction.title}"`, "error");
        return;
      }
      await ipc.calendarDeleteEvent(match.id);
      setPendingAction(null);
      await refreshEmpty();
      showToast("Event deleted", "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Deleted event **${match.title}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmUpdateEvent = async () => {
    if (!pendingAction || pendingAction.kind !== "updateCalendarEvent") return;
    const existing = pendingAction.existingTitle?.trim();
    if (!existing) return;
    try {
      const events = await ipc.calendarListEvents();
      const match = events.find((e) => e.title.toLowerCase().includes(existing.toLowerCase()));
      if (!match) {
        showToast(`No event matching "${existing}"`, "error");
        return;
      }
      await ipc.calendarUpsertEvent({
        id: match.id,
        title: pendingAction.title,
        startAt: match.startAt,
        endAt: match.endAt,
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast("Event updated", "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Renamed event to **${pendingAction.title}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmUpdateAppSetting = async () => {
    if (!pendingAction || pendingAction.kind !== "updateAppSetting") return;
    const key = pendingAction.settingKey?.trim();
    const value = pendingAction.settingValue?.trim();
    if (!key || value === undefined) return;
    try {
      await ipc.settingsSet(key, value);
      if (key === "ui.theme") {
        document.documentElement.dataset.theme = value;
      }
      setPendingAction(null);
      showToast(`Updated ${pendingAction.title}`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Set **${pendingAction.title}** to **${value}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmSaveWebLearning = async () => {
    if (!pendingAction || pendingAction.kind !== "saveWebLearning") return;
    const body = pendingAction.summaryBody?.trim();
    if (!body) return;
    try {
      const settings = await ipc.settingsGet();
      const prev = settings.values["assistant.webMemory"]?.trim() ?? "";
      const entry = `- ${pendingAction.title}: ${body}`;
      const next = prev ? `${prev}\n${entry}` : entry;
      await ipc.settingsSet("assistant.webMemory", next);
      setWebMemory(next);
      setWebMemoryDraft(next);
      setPendingAction(null);
      showToast("Saved to web memory", "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Saved to web memory: **${pendingAction.title}**`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmUpdateProfile = async () => {
    if (!pendingAction || pendingAction.kind !== "updateProfile") return;
    try {
      const current = await ipc.profileGetIdentity();
      await ipc.profileUpsertIdentity({
        fullName: pendingAction.profileName?.trim() || current.fullName || "Student",
        email: pendingAction.profileEmail?.trim() || current.email || undefined,
        universityName: pendingAction.profileUniversity?.trim() || current.universityName || undefined,
        major: pendingAction.profileMajor?.trim() || current.major || undefined,
        graduationYear: current.graduationYear ?? undefined,
      });
      setPendingAction(null);
      await refreshEmpty();
      showToast("Profile updated", "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Updated profile: **${pendingAction.title}**.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const confirmSyncSyllabusDeadlines = async () => {
    if (!pendingAction || pendingAction.kind !== "syncSyllabusDeadlines") return;
    const raw = pendingAction.summaryBody?.trim();
    if (!raw) return;
    try {
      const drafts = JSON.parse(raw) as Array<{ title?: string; dueAt?: string | null }>;
      let created = 0;
      for (const draft of drafts.slice(0, 24)) {
        const title = draft.title?.trim();
        if (!title) continue;
        await ipc.calendarUpsertTask({
          title,
          dueAt: draft.dueAt ?? undefined,
        });
        created += 1;
      }
      setPendingAction(null);
      await refreshEmpty();
      showToast(`Created ${created} task(s)`, "success");
      setMessages((prev) => [
        ...prev,
        createMessage("assistant", `Synced **${created}** syllabus deadline task(s) to your planner.`),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const loadSample = async () => {
    try {
      await ipc.demoSeedSampleData();
      await refreshEmpty();
      showToast("Sample data loaded", "success");
      setMessages((prev) => [
        ...prev,
        createMessage(
          "assistant",
          "Sample data is in. Ask “What credits do I have?”, “What’s on my calendar?”, or “How’s my career pipeline?”",
        ),
      ]);
    } catch (e) {
      showToast(formatIpcError(e), "error");
    }
  };

  const aiStatusChips = status ? (
    <>
      <StatusChip title={status.backend} tint="var(--color-primary)" filled />
      <StatusChip title={status.model} tint="var(--color-primary)" />
      <StatusChip
        title={status.llmReady ? "LLM ready" : "LLM fallback"}
        tint={status.llmReady ? "var(--color-success)" : "var(--color-warning)"}
        filled
      />
      <StatusChip
        title={`Embeddings: ${status.embeddingsBackend}`}
        tint={status.embeddingsReady ? "var(--color-success)" : "var(--color-text-light)"}
        filled={status.embeddingsReady}
      />
      {status.onnxPathConfigured && (
        <StatusChip title="ONNX path set" tint="var(--color-primary)" />
      )}
      <StatusChip
        title={emptyWorkspace ? "Empty workspace" : "Live data"}
        tint={emptyWorkspace ? "var(--color-warning)" : "var(--color-success)"}
        filled
      />
    </>
  ) : (
    <StatusChip title="Loading runtime…" />
  );

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={view === "syllabus" ? "Syllabus AI" : "Chat"}
        subtitle={
          view === "syllabus"
            ? "PDF review — extract events, grading, and professor details"
            : "Answers grounded in your live College workspace"
        }
        actions={
          view === "chat" ? (
            <div className="flex gap-2">
              {emptyWorkspace && (
                <Button size="sm" onClick={() => void loadSample()}>
                  Load sample data
                </Button>
              )}
              <Button
                size="sm"
                variant="secondary"
                onClick={() => {
                  setMessages([
                    createMessage(
                      "assistant",
                      "Ask about credits, deadlines, or career prep. I read your live College data. If everything looks empty, load sample data from Settings first.",
                    ),
                  ]);
                  void refreshEmpty();
                }}
              >
                Clear
              </Button>
            </div>
          ) : undefined
        }
      />

      <div className="flex flex-wrap gap-1.5 px-3 pb-1">{aiStatusChips}</div>

      {view === "syllabus" && <SyllabusReviewPage />}

      {view === "chat" && (
        <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-hidden p-3 pt-1">
          <div className="grid shrink-0 gap-2.5 sm:grid-cols-2 lg:grid-cols-4">
            <MetricTile
              label="Courses"
              value={workspaceStats.courses}
              accent={workspaceStats.courses > 0 ? "var(--color-primary)" : undefined}
            />
            <MetricTile label="Open tasks" value={workspaceStats.openTasks} />
            <MetricTile label="Events" value={workspaceStats.events} />
            <MetricTile
              label="Career apps"
              value={workspaceStats.apps}
              accent={workspaceStats.apps > 0 ? "var(--color-success)" : undefined}
            />
          </div>

          {emptyWorkspace && (
            <AppCard className="shrink-0">
              <EmptyState
                title="Workspace is empty"
                body="Load sample data or add planner rows so credit, calendar, and career answers aren’t zeros."
                action={
                  <Button size="sm" onClick={() => void loadSample()}>
                    Load sample data
                  </Button>
                }
              />
            </AppCard>
          )}

          <div className="grid shrink-0 gap-2.5 lg:grid-cols-2">
            <AppCard title="Attachments">
              <p className="mb-2 text-[12px] text-[var(--color-text-light)]">
                Pin vault documents — sent with each turn and included in vault semantic search.
              </p>
              <div className="flex flex-wrap gap-1.5">
                {attachments.length === 0 ? (
                  <StatusChip title="No attachments" />
                ) : (
                  attachments.map((a) => (
                    <StatusChip key={a.id} title={a.title} tint="var(--color-primary)" filled />
                  ))
                )}
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={async () => {
                    const docs = await ipc.documentsListVault().catch(() => []);
                    const next = docs.slice(0, 3).map((d) => ({ id: d.id, title: d.title || "Untitled" }));
                    setAttachments(next);
                    showToast(
                      next.length ? `Attached ${next.length} recent vault files` : "Vault is empty",
                      next.length ? "success" : "error",
                    );
                  }}
                >
                  Attach recent vault
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setAttachments([])}>
                  Clear
                </Button>
              </div>
            </AppCard>
            <AppCard title="Web memory">
              <p className="mb-2 text-[12px] text-[var(--color-text-light)]">
                Persistent notes the assistant can reference (stored in Settings).
              </p>
              <FormField label="Memory snippet">
                <textarea
                  className={fieldControlClass}
                  rows={4}
                  value={webMemoryDraft}
                  onChange={(e) => setWebMemoryDraft(e.target.value)}
                  placeholder="Course preferences, internship targets, writing style…"
                />
              </FormField>
              <Button
                size="sm"
                className="mt-2"
                onClick={async () => {
                  await ipc.settingsSet("assistant.webMemory", webMemoryDraft);
                  setWebMemory(webMemoryDraft);
                  showToast("Web memory saved", "success");
                }}
              >
                Save memory
              </Button>
              {webMemory.trim() && (
                <p className="mt-2 text-[11px] text-[var(--color-text-light)]">
                  Active: {webMemory.slice(0, 120)}
                  {webMemory.length > 120 ? "…" : ""}
                </p>
              )}
            </AppCard>
          </div>

          <AppCard className="flex min-h-0 flex-1 flex-col overflow-hidden p-0">
            <div
              className="shrink-0 border-b border-[var(--color-chrome-stroke)] px-4 py-3"
              style={{
                background:
                  "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 8%, transparent), transparent)",
              }}
            >
              <h3
                className="text-[var(--color-text-main)]"
                style={{
                  font: "var(--type-section-title)",
                  fontSize: 16,
                  letterSpacing: "-0.02em",
                }}
              >
                Conversation
              </h3>
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <SegmentedPills
                  value={agentRole}
                  onChange={setAgentRole}
                  options={AGENT_ROLE_OPTIONS}
                />
                {busy && (
                  <StatusChip title="Thinking…" tint="var(--color-primary)" filled />
                )}
                {busy &&
                  toolTrace.map((t) => (
                    <StatusChip
                      key={t.name}
                      title={toolChipLabel(t)}
                      tint="var(--color-primary)"
                    />
                  ))}
                <StatusChip title={`${messages.length} messages`} />
              </div>
              {pendingAction?.kind === "createTask" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Create task: <strong>{pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmCreateTask()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "createEvent" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Schedule event: <strong>{pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmCreateEvent()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "createApplication" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Track job at <strong>{pendingAction.company ?? pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmCreateApplication()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "addCourseToPlan" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Add <strong>{pendingAction.courseCode ?? pendingAction.title}</strong>
                    {pendingAction.semesterName ? ` to ${pendingAction.semesterName}` : " to plan"}?
                  </span>
                  <Button size="sm" onClick={() => void confirmAddCourseToPlan()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "addSemester" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Add semester <strong>{pendingAction.semesterName ?? pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmAddSemester()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "removeCourseFromPlan" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Remove <strong>{pendingAction.courseCode ?? pendingAction.title}</strong> from plan?
                  </span>
                  <Button size="sm" onClick={() => void confirmRemoveCourseFromPlan()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "updateTask" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Rename task <strong>{pendingAction.existingTitle}</strong> →{" "}
                    <strong>{pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmUpdateTask()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "updateApplicationStatus" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Mark <strong>{pendingAction.company ?? pendingAction.title}</strong> as{" "}
                    <strong>{pendingAction.status}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmUpdateApplicationStatus()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "deleteTask" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Delete task <strong>{pendingAction.existingTitle ?? pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" variant="danger" onClick={() => void confirmDeleteTask()}>
                    Delete
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "deleteCalendarEvent" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Delete event <strong>{pendingAction.existingTitle ?? pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" variant="danger" onClick={() => void confirmDeleteEvent()}>
                    Delete
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "updateCalendarEvent" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Rename event <strong>{pendingAction.existingTitle}</strong> →{" "}
                    <strong>{pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmUpdateEvent()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "updateAppSetting" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Set <strong>{pendingAction.title}</strong> to{" "}
                    <strong>{pendingAction.settingValue}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmUpdateAppSetting()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "saveWebLearning" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Save to web memory: <strong>{pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmSaveWebLearning()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "updateProfile" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Update profile: <strong>{pendingAction.title}</strong>?
                  </span>
                  <Button size="sm" onClick={() => void confirmUpdateProfile()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
              {pendingAction?.kind === "syncSyllabusDeadlines" && (
                <div className="mt-3 flex flex-wrap items-center gap-2 rounded-[12px] border border-[var(--color-chrome-stroke)] bg-[var(--color-surface)] px-3 py-2">
                  <span className="text-[12px] text-[var(--color-text-main)]">
                    Create <strong>{pendingAction.title}</strong> from syllabi?
                  </span>
                  <Button size="sm" onClick={() => void confirmSyncSyllabusDeadlines()}>
                    Confirm
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setPendingAction(null)}>
                    Dismiss
                  </Button>
                </div>
              )}
            </div>
            <ul ref={listRef} className="min-h-0 flex-1 overflow-auto p-3">
              <div className="mx-auto flex w-full max-w-[720px] flex-col gap-3">
                {buildTranscriptItems(messages).map((item) => {
                  if (item.kind === "day") {
                    return (
                      <li
                        key={`day-${item.key}`}
                        className="flex items-center gap-3 py-1"
                        aria-label={item.label}
                      >
                        <span className="h-px flex-1 bg-[var(--color-chrome-stroke)]" />
                        <span
                          className="shrink-0 text-[11px] font-medium tracking-wide text-[var(--color-text-light)]"
                          style={{ fontVariant: "small-caps" }}
                        >
                          {item.label}
                        </span>
                        <span className="h-px flex-1 bg-[var(--color-chrome-stroke)]" />
                      </li>
                    );
                  }

                  const m = item.message;
                  const isUser = m.role === "user";
                  const isLastAssistant =
                    busy && m.role === "assistant" && item.index === messages.length - 1;
                  const showResultCard =
                    !isUser &&
                    m.source &&
                    looksLikeToolResult(m.content);

                  return (
                    <li
                      key={`${item.index}-${m.createdAt}`}
                      className={`flex ${isUser ? "justify-end" : "justify-start"}`}
                    >
                      {showResultCard ? (
                        <div className={isLastAssistant ? "animate-pulse" : undefined}>
                          <AssistantResultCard
                            content={m.content}
                            source={m.source!}
                          />
                        </div>
                      ) : (
                        <div
                          className={`max-w-[min(100%,640px)] rounded-[16px] px-3.5 py-2.5 text-[13px] leading-relaxed ${
                            isUser
                              ? "bg-[var(--color-primary-soft)] text-[var(--color-text-main)] shadow-[0_1px_2px_color-mix(in_srgb,var(--color-primary)_18%,transparent)] ring-1 ring-inset ring-[var(--color-primary)]/12"
                              : "bg-[var(--color-surface)] text-[var(--color-text-main)] shadow-[var(--shadow-elevated)] ring-1 ring-[var(--color-chrome-stroke)]"
                          } ${isLastAssistant ? "animate-pulse" : ""}`}
                        >
                          {isUser ? (
                            <p className="whitespace-pre-wrap">{m.content}</p>
                          ) : (
                            <SimpleMarkdown content={m.content} />
                          )}
                        </div>
                      )}
                    </li>
                  );
                })}
                {busy && (
                  <li className="flex flex-col justify-start gap-2">
                    {toolTrace.length > 0 && (
                      <div className="flex flex-wrap gap-1.5">
                        {toolTrace.map((t) => (
                          <StatusChip
                            key={`trace-${t.name}`}
                            title={toolChipLabel(t)}
                            tint="var(--color-primary)"
                            filled
                          />
                        ))}
                      </div>
                    )}
                    <div
                      className={`max-w-[min(100%,640px)] rounded-[16px] bg-[var(--color-surface)] px-3.5 py-2.5 text-[13px] text-[var(--color-text-main)] shadow-[var(--shadow-elevated)] ring-1 ring-[var(--color-chrome-stroke)] ${
                        streamingContent ? "" : "animate-pulse text-[var(--color-text-light)]"
                      }`}
                      aria-live="polite"
                    >
                      {streamingContent ? (
                        <SimpleMarkdown content={streamingContent} />
                      ) : (
                        <span className="inline-flex items-center gap-1.5">
                          <span className="h-1.5 w-1.5 rounded-full bg-[var(--color-primary)]/60" />
                          <span className="h-1.5 w-1.5 rounded-full bg-[var(--color-primary)]/40" />
                          <span className="h-1.5 w-1.5 rounded-full bg-[var(--color-primary)]/25" />
                        </span>
                      )}
                    </div>
                  </li>
                )}
              </div>
            </ul>
          </AppCard>

          <div className="flex shrink-0 flex-wrap gap-1.5">
            {ROLE_QUICK_PROMPTS[agentRole].map((prompt) => (
              <button
                key={prompt}
                type="button"
                disabled={busy}
                onClick={() => void sendText(prompt)}
              >
                <StatusChip title={prompt} />
              </button>
            ))}
          </div>

          <div className="flex shrink-0 gap-2">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask about credits, deadlines, applications…"
              className={fieldControlClass}
              onKeyDown={(e) => {
                if (e.key === "Enter") void sendText(input);
              }}
            />
            <Button onClick={() => void sendText(input)} disabled={busy}>
              Send
            </Button>
            {busy && (
              <Button variant="secondary" onClick={() => void cancelTurn()}>
                Stop
              </Button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
