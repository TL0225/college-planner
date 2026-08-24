import { useEffect, useMemo, useRef, useState } from "react";
import {
  GraduationCap,
  Wallet,
  CalendarDays,
  Briefcase,
  FolderOpen,
  Sparkles,
  UserRound,
  Settings,
  BookOpen,
  ListChecks,
  LayoutDashboard,
  CalendarRange,
  Receipt,
  Compass,
  Columns3,
  ArrowLeftRight,
  PiggyBank,
  Target,
  TrendingUp,
  Package,
  PieChart,
  ReceiptText,
  Sun,
  FileText,
  Trophy,
  ScrollText,
  Globe,
  Link2,
  Award,
  Users,
  MessageSquare,
  Clock,
  Star,
  AlertCircle,
  Shield,
  Monitor,
  Layers,
  ClipboardList,
} from "lucide-react";
import {
  AppSidebar,
  CommandPalette,
  ModulePillBar,
  ShellSplitLayout,
  SuperAppContentSurface,
  ToastHost,
  type CommandItem,
  type ModuleId,
  type ModulePillItem,
  type SidebarItem,
} from "@/design-system";
import { ipc, formatIpcError } from "@/lib/ipc";
import { maybeNotifyDueItems } from "@/lib/notifications";
import type { ShellNavigateDetail } from "@/lib/shellNavigate";
import { showToast } from "@/lib/toast";
import { AcademicsModule } from "@/modules/academics/AcademicsModule";
import { CatalogModule } from "@/modules/catalog/CatalogModule";
import { CalendarModule } from "@/modules/calendar/CalendarModule";
import { CareerModule } from "@/modules/career/CareerModule";
import { DocumentsModule } from "@/modules/documents/DocumentsModule";
import { DiscoveryModule } from "@/modules/discovery/DiscoveryModule";
import { TransferModule } from "@/modules/transfer/TransferModule";
import { FinanceModule } from "@/modules/finance/FinanceModule";
import { LmsModule } from "@/modules/lms/LmsModule";
import { AssistantModule } from "@/modules/assistant/AssistantModule";
import { ProfileModule } from "@/modules/profile/ProfileModule";
import { SettingsModule, type SettingsPage } from "@/modules/settings/SettingsModule";
import { HubLauncher } from "@/modules/shell/HubLauncher";
import { FirstRunWelcome } from "@/modules/shell/FirstRunWelcome";
import {
  WebShortcutsSidebarSection,
  type WebShortcut,
} from "@/modules/shell/WebShortcutsSidebarSection";
import { ResumePopOutView } from "@/modules/career/ResumePopOutView";

const MODULE_PILLS: ModulePillItem[] = [
  { id: "college", title: "College", icon: <GraduationCap size={13} strokeWidth={2} /> },
  { id: "finance", title: "Finance", icon: <Wallet size={13} strokeWidth={2} /> },
  { id: "calendar", title: "Calendar", icon: <CalendarDays size={13} strokeWidth={2} /> },
  { id: "career", title: "Career", icon: <Briefcase size={13} strokeWidth={2} /> },
  { id: "documents", title: "Documents", icon: <FolderOpen size={13} strokeWidth={2} /> },
  { id: "assistant", title: "Assistant", icon: <Sparkles size={13} strokeWidth={2} /> },
  { id: "profile", title: "Profile", icon: <UserRound size={13} strokeWidth={2} /> },
];

const MODULE_IDS = new Set<string>([
  "college",
  "finance",
  "calendar",
  "career",
  "documents",
  "assistant",
  "profile",
  "settings",
]);

function isFinancePageValid(page: string): boolean {
  return page === "accounts" || page.startsWith("account-");
}

function isDocumentsPageValid(page: string, sidebarIds: Set<string>): boolean {
  return sidebarIds.has(page) || page.startsWith("course-") || page.startsWith("folder-");
}

function isCollegePageValid(page: string, sidebarIds: Set<string>): boolean {
  return sidebarIds.has(page) || page.startsWith("req-");
}

function defaultPageFor(module: ModuleId): string {
  switch (module) {
    case "finance":
      return "dashboard";
    case "calendar":
      return "month";
    case "career":
      return "applications";
    case "documents":
      return "all";
    case "assistant":
      return "chat";
    case "profile":
      return "identity";
    case "settings":
      return "app";
    default:
      return "academics";
  }
}

export default function App() {
  const popout =
    typeof window !== "undefined"
      ? new URLSearchParams(window.location.search).get("popout")
      : null;
  if (popout === "resume") {
    return <ResumePopOutView />;
  }

  const [module, setModule] = useState<ModuleId>("college");
  const [page, setPage] = useState("academics");
  const [reduceMotion, setReduceMotion] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [liveCommands, setLiveCommands] = useState<CommandItem[]>([]);
  const [recents, setRecents] = useState<Array<{ module: ModuleId; page: string; title: string }>>(
    [],
  );
  const [welcomeOpen, setWelcomeOpen] = useState(false);
  const [hubOpen, setHubOpen] = useState(false);
  const [settingsSearch, setSettingsSearch] = useState("");
  const [financeAccounts, setFinanceAccounts] = useState<
    Array<{ id: string; name: string; institution: string }>
  >([]);
  const [plannerCourses, setPlannerCourses] = useState<Array<{ id: string; code: string; title: string }>>(
    [],
  );
  const [auditSections, setAuditSections] = useState<Array<{ id: string; sectionTitle: string }>>(
    [],
  );
  const [calendarSources, setCalendarSources] = useState<Array<{ id: string; name: string }>>([]);
  const [webShortcuts, setWebShortcuts] = useState<WebShortcut[]>([]);
  const [vaultFolders, setVaultFolders] = useState<Array<{ id: string; title: string }>>([]);
  const hydrated = useRef(false);
  const skipNextModuleReset = useRef(false);

  useEffect(() => {
    void ipc.settingsGet().then((s) => {
      setReduceMotion(s.values["ui.reduceMotion"] === "true");
      const theme = s.values["ui.theme"] || "system";
      document.documentElement.dataset.theme = theme;
      const savedModule = s.values["shell.module"];
      const savedPage = s.values["shell.page"];
      if (savedModule && MODULE_IDS.has(savedModule)) {
        skipNextModuleReset.current = true;
        setModule(savedModule as ModuleId);
        if (savedPage) {
          const pageId =
            savedModule === "settings" && savedPage === "general" ? "app" : savedPage;
          setPage(pageId);
        }
      }
      try {
        const raw = s.values["shell.recents"];
        if (raw) {
          const parsed = JSON.parse(raw) as Array<{
            module: ModuleId;
            page: string;
            title: string;
          }>;
          if (Array.isArray(parsed)) setRecents(parsed.slice(0, 8));
        }
      } catch {
        /* ignore bad recents JSON */
      }
      if (s.values["shell.onboarded"] !== "true") {
        setWelcomeOpen(true);
      }
      try {
        const rawShortcuts = s.values["web.shortcuts.v1"];
        if (rawShortcuts) {
          const parsed = JSON.parse(rawShortcuts) as WebShortcut[];
          if (Array.isArray(parsed)) setWebShortcuts(parsed);
        }
      } catch {
        /* ignore bad shortcuts JSON */
      }
      hydrated.current = true;
      void maybeNotifyDueItems();
    });
    const onSettings = (ev: Event) => {
      const detail = (ev as CustomEvent<{ key: string; value: string }>).detail;
      if (!detail) return;
      if (detail.key === "ui.reduceMotion") {
        setReduceMotion(detail.value === "true");
      }
      if (detail.key === "ui.theme") {
        document.documentElement.dataset.theme = detail.value || "system";
      }
      if (detail.key === "web.shortcuts.v1") {
        try {
          const parsed = JSON.parse(detail.value) as WebShortcut[];
          if (Array.isArray(parsed)) setWebShortcuts(parsed);
        } catch {
          setWebShortcuts([]);
        }
      }
    };
    window.addEventListener("college:settings", onSettings);
    return () => window.removeEventListener("college:settings", onSettings);
  }, []);

  useEffect(() => {
    if (module === "finance") {
      void ipc.financeListAccounts().then(setFinanceAccounts).catch(() => setFinanceAccounts([]));
    }
    if (module === "documents") {
      void ipc
        .academicsListCourses()
        .then((c) =>
          setPlannerCourses(
            c.slice(0, 10).map((x) => ({ id: x.id, code: x.code, title: x.title })),
          ),
        )
        .catch(() => setPlannerCourses([]));
      void ipc
        .documentsListVault()
        .then((docs) =>
          setVaultFolders(
            docs
              .filter((d) => d.isFolder)
              .slice(0, 12)
              .map((d) => ({ id: d.id, title: d.title || "Folder" })),
          ),
        )
        .catch(() => setVaultFolders([]));
    }
    if (module === "college") {
      void ipc
        .academicsGetRequirementAudit()
        .then((a) =>
          setAuditSections(
            a.items.slice(0, 8).map((i) => ({ id: i.id, sectionTitle: i.sectionTitle })),
          ),
        )
        .catch(() => setAuditSections([]));
    }
    if (module === "calendar") {
      void ipc
        .calendarListSources()
        .then((s) => setCalendarSources(s.map((x) => ({ id: x.id, name: x.name }))))
        .catch(() => setCalendarSources([]));
    }
  }, [module]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;
      if (!meta || e.altKey) return;
      const target = e.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      const typing = tag === "input" || tag === "textarea" || target?.isContentEditable;

      if (e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen((open) => !open);
        return;
      }
      if (e.shiftKey && e.key.toLowerCase() === "h") {
        e.preventDefault();
        setHubOpen((open) => !open);
        return;
      }

      if (typing) return;

      if (e.key === ",") {
        e.preventDefault();
        skipNextModuleReset.current = true;
        setModule("settings");
        setPage("app");
        return;
      }
      const map: Record<string, ModuleId> = {
        "1": "college",
        "2": "finance",
        "3": "calendar",
        "4": "career",
        "5": "documents",
        "6": "assistant",
        "7": "profile",
      };
      const next = map[e.key];
      if (next) {
        e.preventDefault();
        setModule(next);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (!hydrated.current) return;
    void ipc.settingsSet("shell.module", module);
  }, [module]);

  useEffect(() => {
    if (!hydrated.current) return;
    void ipc.settingsSet("shell.page", page);
  }, [page]);

  const { sidebarItems, sectionTitle } = useMemo((): {
    sidebarItems: SidebarItem[];
    sectionTitle?: string;
  } => {
    switch (module) {
      case "college":
        return {
          sectionTitle: "College",
          sidebarItems: [
            { id: "academics", title: "Overview", icon: <LayoutDashboard size={14} /> },
            { id: "planner", title: "Planner", icon: <GraduationCap size={14} /> },
            { id: "catalog", title: "Catalog", icon: <BookOpen size={14} /> },
            { id: "degree", title: "Requirements", icon: <ListChecks size={14} /> },
            ...auditSections.map((s) => ({
              id: `req-${s.id}`,
              title: s.sectionTitle.length > 22 ? `${s.sectionTitle.slice(0, 20)}…` : s.sectionTitle,
              icon: <ListChecks size={14} />,
              indent: true,
            })),
            { id: "transfer", title: "Transfer", icon: <ArrowLeftRight size={14} /> },
            { id: "discovery", title: "Discovery", icon: <Compass size={14} /> },
            { id: "lms", title: "LMS", icon: <Globe size={14} /> },
          ],
        };
      case "finance":
        return {
          sectionTitle: "Finance",
          sidebarItems: [
            { id: "dashboard", title: "Dashboard", icon: <Wallet size={14} /> },
            { id: "accounts", title: "Accounts", icon: <Wallet size={14} /> },
            ...financeAccounts.map((a) => ({
              id: `account-${a.id}`,
              title: a.name.length > 20 ? `${a.name.slice(0, 18)}…` : a.name,
              icon: <Wallet size={14} />,
              indent: true,
            })),
            { id: "ledger", title: "Ledger", icon: <Receipt size={14} /> },
            { id: "budgets", title: "Budgets", icon: <PiggyBank size={14} /> },
            { id: "goals", title: "Goals", icon: <Target size={14} /> },
            { id: "inventory", title: "Inventory", icon: <Package size={14} /> },
            { id: "receipts", title: "Receipts", icon: <ReceiptText size={14} /> },
            { id: "reports", title: "Reports", icon: <PieChart size={14} /> },
            { id: "net-worth", title: "Net worth", icon: <TrendingUp size={14} /> },
          ],
        };
      case "calendar":
        return {
          sectionTitle: "Calendar",
          sidebarItems: [
            { id: "month", title: "Month", icon: <CalendarRange size={14} /> },
            { id: "week", title: "Week", icon: <Columns3 size={14} /> },
            { id: "day", title: "Day", icon: <Sun size={14} /> },
            { id: "agenda", title: "Agenda", icon: <CalendarDays size={14} /> },
            { id: "tasks", title: "Tasks", icon: <ListChecks size={14} /> },
            ...calendarSources.map((s) => ({
              id: `source-${s.id}`,
              title: s.name.length > 18 ? `${s.name.slice(0, 16)}…` : s.name,
              icon: <CalendarDays size={14} />,
              indent: true,
            })),
          ],
        };
      case "career":
        return {
          sectionTitle: "Career",
          sidebarItems: [
            { id: "applications", title: "Applications", icon: <Briefcase size={14} /> },
            { id: "board", title: "Board", icon: <LayoutDashboard size={14} /> },
            { id: "stats", title: "Stats", icon: <PieChart size={14} /> },
            { id: "apply", title: "Apply", icon: <ClipboardList size={14} /> },
            { id: "pathing", title: "Pathing", icon: <ListChecks size={14} /> },
            { id: "brag", title: "Brag Book", icon: <Award size={14} /> },
            { id: "networking", title: "Networking", icon: <Users size={14} /> },
            { id: "interview", title: "Interview", icon: <MessageSquare size={14} /> },
            { id: "resumes", title: "Resumes", icon: <FileText size={14} /> },
            { id: "openings", title: "Openings", icon: <Briefcase size={14} /> },
          ],
        };
      case "documents":
        return {
          sectionTitle: "Documents",
          sidebarItems: [
            { id: "all", title: "All files", icon: <FolderOpen size={14} /> },
            { id: "recent", title: "Recent", icon: <Clock size={14} /> },
            { id: "starred", title: "Starred", icon: <Star size={14} /> },
            { id: "needs-review", title: "Needs review", icon: <AlertCircle size={14} /> },
            { id: "cat-general", title: "General", icon: <FileText size={14} /> },
            { id: "cat-syllabus", title: "Syllabus", icon: <ScrollText size={14} /> },
            { id: "cat-transcript", title: "Transcript", icon: <FileText size={14} /> },
            { id: "cat-resume", title: "Resume", icon: <FileText size={14} /> },
            { id: "cat-receipt", title: "Receipt", icon: <Receipt size={14} /> },
            ...vaultFolders.map((f) => ({
              id: `folder-${f.id}`,
              title: f.title.length > 18 ? `${f.title.slice(0, 16)}…` : f.title,
              icon: <FolderOpen size={14} />,
              indent: true,
            })),
            ...plannerCourses.map((c) => ({
              id: `course-${c.id}`,
              title: c.code,
              icon: <BookOpen size={14} />,
              indent: true,
            })),
          ],
        };
      case "assistant":
        return {
          sectionTitle: "Assistant",
          sidebarItems: [
            { id: "chat", title: "Chat", icon: <Sparkles size={14} /> },
            { id: "syllabus", title: "Syllabus AI", icon: <ScrollText size={14} /> },
          ],
        };
      case "profile":
        return {
          sectionTitle: "Profile",
          sidebarItems: [
            { id: "identity", title: "Identity", icon: <UserRound size={14} /> },
            { id: "experiences", title: "Experiences", icon: <Briefcase size={14} /> },
            { id: "achievements", title: "Achievements", icon: <Trophy size={14} /> },
            { id: "portfolio", title: "Portfolio", icon: <Layers size={14} /> },
            { id: "advisor", title: "Advisor prep", icon: <ClipboardList size={14} /> },
          ],
        };
      case "settings":
        return {
          sectionTitle: "Settings",
          sidebarItems: [
            { id: "profile", title: "Profile", icon: <UserRound size={14} /> },
            { id: "academics", title: "Academics", icon: <GraduationCap size={14} /> },
            { id: "calendar", title: "Calendar", icon: <CalendarDays size={14} /> },
            { id: "assistant", title: "Assistant", icon: <Sparkles size={14} /> },
            { id: "documents", title: "Documents", icon: <FolderOpen size={14} /> },
            { id: "finance", title: "Finance", icon: <Wallet size={14} /> },
            { id: "discovery", title: "Discovery", icon: <Globe size={14} /> },
            { id: "career", title: "Career", icon: <Briefcase size={14} /> },
            { id: "lms", title: "LMS", icon: <Globe size={14} /> },
            { id: "shortcuts", title: "Shortcuts", icon: <Link2 size={14} /> },
            { id: "app", title: "App", icon: <Monitor size={14} /> },
            { id: "privacy", title: "Privacy", icon: <Shield size={14} /> },
          ],
        };
      default:
        return { sidebarItems: [] };
    }
  }, [module, financeAccounts, plannerCourses, auditSections, calendarSources, vaultFolders]);

  const filteredSidebarItems = useMemo(() => {
    if (module !== "settings" || !settingsSearch.trim()) return sidebarItems;
    const q = settingsSearch.trim().toLowerCase();
    return sidebarItems.filter((item) => item.title.toLowerCase().includes(q));
  }, [module, sidebarItems, settingsSearch]);

  useEffect(() => {
    if (skipNextModuleReset.current) {
      skipNextModuleReset.current = false;
      return;
    }
    setPage(defaultPageFor(module));
  }, [module]);

  useEffect(() => {
    const sidebarIds = new Set(sidebarItems.map((i) => i.id));
    const valid =
      sidebarItems.some((i) => i.id === page) ||
      (module === "finance" && isFinancePageValid(page)) ||
      (module === "documents" && isDocumentsPageValid(page, sidebarIds)) ||
      (module === "college" && isCollegePageValid(page, sidebarIds)) ||
      (module === "calendar" && page.startsWith("source-"));
    if (!valid) setPage(defaultPageFor(module));
  }, [module, sidebarItems, page]);

  const go = (nextModule: ModuleId, nextPage?: string, title?: string) => {
    const pageId = nextPage ?? defaultPageFor(nextModule);
    skipNextModuleReset.current = Boolean(nextPage);
    setModule(nextModule);
    if (nextPage) setPage(nextPage);
    const label = title ?? nextPage ?? nextModule;
    setRecents((prev) => {
      const entry = { module: nextModule, page: pageId, title: label };
      const next = [entry, ...prev.filter((r) => !(r.module === nextModule && r.page === pageId))].slice(
        0,
        8,
      );
      void ipc.settingsSet("shell.recents", JSON.stringify(next));
      return next;
    });
  };

  useEffect(() => {
    const onNavigate = (ev: Event) => {
      const detail = (ev as CustomEvent<ShellNavigateDetail>).detail;
      if (!detail?.module || !MODULE_IDS.has(detail.module)) return;
      go(detail.module as ModuleId, detail.page);
    };
    window.addEventListener("college:navigate", onNavigate);
    return () => window.removeEventListener("college:navigate", onNavigate);
  }, []);

  useEffect(() => {
    if (!paletteOpen) return;
    let cancelled = false;
    void (async () => {
      try {
        const [tasks, apps, courses, docs] = await Promise.all([
          ipc.calendarListTasks().catch(() => []),
          ipc.careerListApplications().catch(() => []),
          ipc.catalogSearchCourses("").catch(() => []),
          ipc.documentsListVault().catch(() => []),
        ]);
        if (cancelled) return;
        const items: CommandItem[] = [];
        for (const t of tasks.slice(0, 12)) {
          items.push({
            id: `task-${t.id}`,
            title: t.title,
            subtitle: t.isComplete ? "Done" : t.dueAt ? `Due ${new Date(t.dueAt).toLocaleDateString()}` : "Open",
            group: "Tasks",
            keywords: "todo assignment",
            run: () => go("calendar", "tasks"),
          });
        }
        for (const a of apps.slice(0, 12)) {
          items.push({
            id: `app-${a.id}`,
            title: `${a.roleTitle} @ ${a.company}`,
            subtitle: a.status,
            group: "Applications",
            keywords: "job career",
            run: () => go("career", "applications"),
          });
        }
        for (const c of courses.slice(0, 12)) {
          items.push({
            id: `course-${c.id}`,
            title: `${c.code} — ${c.title}`,
            group: "Catalog",
            keywords: "course class",
            run: () => go("college", "catalog"),
          });
        }
        for (const d of docs.slice(0, 12)) {
          items.push({
            id: `doc-${d.id}`,
            title: d.title,
            subtitle: d.category,
            group: "Vault",
            keywords: "document file",
            run: () => go("documents", d.category ? `cat-${d.category}` : "all"),
          });
        }
        setLiveCommands(items);
      } catch {
        if (!cancelled) setLiveCommands([]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [paletteOpen]);

  const commandItems = useMemo((): CommandItem[] => {
    const recentItems: CommandItem[] = recents.map((r, i) => ({
      id: `recent-${r.module}-${r.page}-${i}`,
      title: r.title,
      subtitle: `${r.module} / ${r.page}`,
      group: "Recent",
      keywords: "history last",
      run: () => go(r.module, r.page, r.title),
    }));
    const nav: CommandItem[] = [
      { id: "nav-college", title: "College", subtitle: "Overview", group: "Modules", keywords: "academics hub", run: () => go("college", "academics", "College Overview") },
      { id: "nav-planner", title: "Planner", group: "College", keywords: "semester courses grades", run: () => go("college", "planner", "Planner") },
      { id: "nav-catalog", title: "Catalog", group: "College", run: () => go("college", "catalog", "Catalog") },
      { id: "nav-degree", title: "Requirements", group: "College", keywords: "audit degree", run: () => go("college", "degree", "Requirements") },
      { id: "nav-transfer", title: "Transfer", group: "College", run: () => go("college", "transfer", "Transfer") },
      { id: "nav-discovery", title: "Discovery", group: "College", run: () => go("college", "discovery", "Discovery") },
      { id: "nav-lms", title: "LMS", group: "College", keywords: "canvas blackboard portal", run: () => go("college", "lms", "LMS") },
      { id: "nav-finance", title: "Finance", subtitle: "Dashboard", group: "Modules", run: () => go("finance", "dashboard", "Finance") },
      { id: "nav-accounts", title: "Accounts", group: "Finance", run: () => go("finance", "accounts", "Accounts") },
      { id: "nav-ledger", title: "Ledger", group: "Finance", keywords: "transactions", run: () => go("finance", "ledger", "Ledger") },
      { id: "nav-budgets", title: "Budgets", group: "Finance", run: () => go("finance", "budgets", "Budgets") },
      { id: "nav-goals", title: "Goals", group: "Finance", keywords: "savings target", run: () => go("finance", "goals", "Goals") },
      { id: "nav-inventory", title: "Inventory", group: "Finance", keywords: "assets items valuables", run: () => go("finance", "inventory", "Inventory") },
      { id: "nav-receipts", title: "Receipts", group: "Finance", keywords: "purchases merchant", run: () => go("finance", "receipts", "Receipts") },
      { id: "nav-reports", title: "Reports", group: "Finance", keywords: "spending analytics budget", run: () => go("finance", "reports", "Reports") },
      { id: "nav-net-worth", title: "Net worth", group: "Finance", keywords: "assets liabilities balance", run: () => go("finance", "net-worth", "Net worth") },
      { id: "nav-calendar", title: "Calendar", subtitle: "Month", group: "Modules", run: () => go("calendar", "month", "Calendar") },
      { id: "nav-week", title: "Week view", group: "Calendar", run: () => go("calendar", "week", "Week") },
      { id: "nav-day", title: "Day view", group: "Calendar", run: () => go("calendar", "day", "Day") },
      { id: "nav-agenda", title: "Agenda", group: "Calendar", run: () => go("calendar", "agenda", "Agenda") },
      { id: "nav-tasks", title: "Tasks", group: "Calendar", run: () => go("calendar", "tasks", "Tasks") },
      { id: "nav-career", title: "Career", subtitle: "Applications", group: "Modules", run: () => go("career", "applications", "Applications") },
      { id: "nav-board", title: "Board", group: "Career", run: () => go("career", "board", "Board") },
      { id: "nav-pathing", title: "Pathing", group: "Career", run: () => go("career", "pathing", "Pathing") },
      { id: "nav-brag", title: "Brag Book", group: "Career", keywords: "achievements wins accomplishments", run: () => go("career", "brag", "Brag Book") },
      { id: "nav-networking", title: "Networking", group: "Career", keywords: "contacts connections", run: () => go("career", "networking", "Networking") },
      { id: "nav-interview", title: "Interview", group: "Career", keywords: "prep questions", run: () => go("career", "interview", "Interview") },
      { id: "nav-resumes", title: "Resumes", group: "Career", run: () => go("career", "resumes", "Resumes") },
      { id: "nav-openings", title: "Openings", group: "Career", keywords: "jobs workday", run: () => go("career", "openings", "Openings") },
      { id: "nav-documents", title: "Documents", subtitle: "All files", group: "Modules", run: () => go("documents", "all", "All files") },
      { id: "nav-assistant", title: "Assistant", subtitle: "Chat", group: "Modules", keywords: "ai", run: () => go("assistant", "chat", "Assistant") },
      { id: "nav-syllabus", title: "Syllabus AI", group: "Assistant", run: () => go("assistant", "syllabus", "Syllabus AI") },
      { id: "nav-profile", title: "Profile", group: "Modules", run: () => go("profile", "identity", "Profile") },
      { id: "nav-experiences", title: "Experiences", group: "Profile", keywords: "jobs roles activities", run: () => go("profile", "experiences", "Experiences") },
      { id: "nav-achievements", title: "Achievements", group: "Profile", run: () => go("profile", "achievements", "Achievements") },
      { id: "nav-settings", title: "Settings", subtitle: "App", group: "Modules", keywords: "preferences theme backup", run: () => go("settings", "app", "Settings") },
      { id: "nav-settings-profile", title: "Settings — Profile", group: "Settings", keywords: "identity preferences", run: () => go("settings", "profile", "Settings Profile") },
      { id: "nav-settings-academics", title: "Settings — Academics", group: "Settings", keywords: "sample data scraper catalog", run: () => go("settings", "academics", "Settings Academics") },
      { id: "nav-settings-calendar", title: "Settings — Calendar", group: "Settings", keywords: "oauth google outlook", run: () => go("settings", "calendar", "Settings Calendar") },
      { id: "nav-settings-assistant", title: "Settings — Assistant", group: "Settings", keywords: "ai llm ollama model", run: () => go("settings", "assistant", "Settings Assistant") },
      { id: "nav-settings-documents", title: "Settings — Documents", group: "Settings", keywords: "storage paths vault", run: () => go("settings", "documents", "Settings Documents") },
      { id: "nav-settings-finance", title: "Settings — Finance", group: "Settings", keywords: "coinbase integrations", run: () => go("settings", "finance", "Settings Finance") },
      { id: "nav-settings-app", title: "Settings — App", group: "Settings", keywords: "theme motion notifications updater", run: () => go("settings", "app", "Settings App") },
      { id: "nav-settings-privacy", title: "Settings — Privacy", group: "Settings", keywords: "security lock backup restore", run: () => go("settings", "privacy", "Settings Privacy") },
    ];
    const actions: CommandItem[] = [
      {
        id: "act-add-task",
        title: "Add task",
        group: "Actions",
        keywords: "new todo",
        run: () => {
          go("calendar", "tasks", "Tasks");
          window.setTimeout(() => {
            window.dispatchEvent(
              new CustomEvent("college:quick-add", { detail: { kind: "task" } }),
            );
          }, 50);
        },
      },
      {
        id: "act-add-event",
        title: "Add event",
        group: "Actions",
        keywords: "new calendar",
        run: () => {
          go("calendar", "month", "Calendar");
          window.setTimeout(() => {
            window.dispatchEvent(
              new CustomEvent("college:quick-add", { detail: { kind: "event" } }),
            );
          }, 50);
        },
      },
      {
        id: "act-add-app",
        title: "Add application",
        group: "Actions",
        keywords: "new job career",
        run: () => {
          go("career", "applications", "Applications");
          window.setTimeout(() => {
            window.dispatchEvent(
              new CustomEvent("college:quick-add", { detail: { kind: "application" } }),
            );
          }, 50);
        },
      },
      {
        id: "act-seed",
        title: "Load sample data",
        group: "Actions",
        keywords: "demo seed",
        run: () => {
          void ipc
            .demoSeedSampleData()
            .then(() => showToast("Sample data loaded", "success"))
            .catch((e) => showToast(formatIpcError(e), "error"));
        },
      },
      {
        id: "act-backup",
        title: "Create backup",
        group: "Actions",
        run: () => {
          void ipc
            .backupCreate()
            .then((entry) => showToast(`Backup saved: ${entry.name}`, "success"))
            .catch((e) => showToast(formatIpcError(e), "error"));
        },
      },
    ];
    return [...recentItems, ...nav, ...actions, ...liveCommands];
  }, [liveCommands, recents]);

  const content = (() => {
    if (module === "settings") return <SettingsModule page={page as SettingsPage} />;
    if (module === "finance") return <FinanceModule page={page} />;
    if (module === "calendar") return <CalendarModule page={page} />;
    if (module === "career") return <CareerModule page={page} />;
    if (module === "documents") return <DocumentsModule page={page} />;
    if (module === "assistant") return <AssistantModule page={page} />;
    if (module === "profile") return <ProfileModule page={page} />;
    if (module === "college") {
      if (page === "catalog") return <CatalogModule />;
      if (page === "discovery") return <DiscoveryModule />;
      if (page === "transfer") return <TransferModule />;
      if (page === "lms") return <LmsModule />;
      if (page.startsWith("req-")) {
        return <AcademicsModule page="degree" highlightSectionId={page.slice(4)} />;
      }
      return <AcademicsModule page={page} />;
    }
    return <AcademicsModule page={page} />;
  })();

  return (
    <>
      <ShellSplitLayout
        header={
          <div className="flex w-full items-center gap-2">
            <ModulePillBar
              items={MODULE_PILLS}
              selection={module === "settings" ? "college" : module}
              reduceMotion={reduceMotion}
              onSelect={(id) => setModule(id as ModuleId)}
              onReselect={() => setModule("college")}
              className="min-w-0 flex-1"
            />
            <button
              type="button"
              className="mb-0.5 hidden h-7 shrink-0 items-center gap-1 rounded-full px-2 text-[11px] text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)] sm:inline-flex"
              onClick={() => setPaletteOpen(true)}
              aria-label="Open command palette"
            >
              <span>Search</span>
              <kbd className="rounded-[5px] border border-[var(--color-chrome-stroke)] px-1 py-px text-[10px]">
                ⌘K
              </kbd>
            </button>
            <button
              type="button"
              className={`mb-0.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full ${
                module === "settings"
                  ? "bg-[var(--color-shell-selection)] shadow-[var(--shadow-pill)]"
                  : "hover:bg-[var(--color-row-hover)]"
              }`}
              onClick={() => go("settings", "app", "Settings")}
              aria-label="Settings"
            >
              <Settings size={14} strokeWidth={2} className="text-[var(--color-text-light)]" />
            </button>
          </div>
        }
        sidebar={
          <div className="flex h-full flex-col">
            {module === "settings" && (
              <div
                className="shrink-0 border-b border-[var(--color-chrome-stroke)]"
                style={{
                  padding: `6px ${12}px 8px`,
                }}
              >
                <input
                  className="w-full rounded-[8px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-2.5 py-1.5 text-[12px] text-[var(--color-text-main)] outline-none focus:border-[var(--color-primary)]"
                  placeholder="Search settings…"
                  value={settingsSearch}
                  onChange={(e) => setSettingsSearch(e.target.value)}
                />
              </div>
            )}
            <div className="min-h-0 flex-1">
              <AppSidebar
                items={filteredSidebarItems}
            selection={
              module === "finance" && page.startsWith("account-")
                ? page
                : module === "calendar" && page.startsWith("source-")
                  ? page
                    : module === "documents" && page.startsWith("course-")
                      ? page
                      : module === "documents" && page.startsWith("folder-")
                        ? page
                        : module === "college" && page.startsWith("req-")
                      ? page
                      : page
            }
            sectionTitle={sectionTitle}
            reduceMotion={reduceMotion}
            onSelect={setPage}
            footer={
              <div className="flex flex-col gap-1">
                {module === "college" && (
                  <WebShortcutsSidebarSection
                    shortcuts={webShortcuts}
                    onManage={() => go("settings", "shortcuts", "Shortcuts")}
                  />
                )}
                <button
                  type="button"
                  className="inline-flex h-8 w-8 items-center justify-center rounded-[8px] text-[var(--color-text-light)] hover:bg-[var(--color-row-hover)]"
                  onClick={() => setModule("profile")}
                  aria-label="Profile"
                >
                  <UserRound size={15} />
                </button>
              </div>
            }
          />
            </div>
          </div>
        }
      >
        <SuperAppContentSurface>{content}</SuperAppContentSurface>
      </ShellSplitLayout>
      <CommandPalette
        open={paletteOpen}
        onOpenChange={setPaletteOpen}
        items={commandItems}
        reduceMotion={reduceMotion}
      />
      <ToastHost reduceMotion={reduceMotion} />
      <FirstRunWelcome
        open={welcomeOpen}
        onDismiss={() => {
          setWelcomeOpen(false);
          void ipc.settingsSet("shell.onboarded", "true");
        }}
        onLoadSample={() => {
          void ipc
            .demoSeedSampleData()
            .then(() => showToast("Sample data loaded", "success"))
            .catch((e) => showToast(formatIpcError(e), "error"));
        }}
      />
      <HubLauncher
        open={hubOpen}
        onOpenChange={setHubOpen}
        onSelect={(id) => {
          skipNextModuleReset.current = true;
          setModule(id);
          setPage(defaultPageFor(id));
        }}
      />
    </>
  );
}
