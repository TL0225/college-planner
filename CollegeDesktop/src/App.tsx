import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Home,
  GraduationCap,
  Briefcase,
  CalendarDays,
  FolderOpen,
  Settings,
  LayoutDashboard,
  ListChecks,
  BookOpen,
  Compass,
  ArrowLeftRight,
  Globe,
  Wallet,
  PiggyBank,
  PieChart,
  CalendarRange,
  Columns3,
  Sun,
  CalendarDays as CalIcon,
  Clock,
  Star,
  AlertCircle,
  FileText,
  Trophy,
  Layers,
  UserRound,
  Link2,
  Shield,
  Monitor,
  Target,
  Receipt,
  Award,
  Plus,
} from "lucide-react";
import {
  AppSidebar,
  CommandPalette,
  ModulePillBar,
  ShellSplitLayout,
  SuperAppContentSurface,
  ToastHost,
  UserMenu,
  AIPanel,
  AIFloatingButton,
  PageTransition,
  PlatformProvider,
  MotionProvider,
  ThemeProvider,
  useShellLayout,
  densityScale,
  usePlatform,
  type CommandItem,
  type ModuleId,
  type ModulePillItem,
  type SidebarItem,
} from "@/design-system";
import { ipc } from "@/lib/ipc";
import { maybeNotifyDueItems } from "@/lib/notifications";
import { NAVIGATE_EVENT, type ShellNavigateDetail } from "@/lib/shellNavigate";
import { migrateShellState } from "@/lib/shell/migration";
import { defaultPageFor } from "@/lib/shell/defaults";
import {
  PAGES_BY_MODULE_KEY,
  readPagesByModule,
  resolveModulePage,
} from "@/lib/shell/pageMemory";
import {
  ShellNavigationProvider,
  type ShellNavigationValue,
} from "@/lib/shell/ShellNavigationContext";
import { ShellBoundsProvider } from "@/lib/shell/ShellBoundsContext";
import { useWindowsIntegration } from "@/hooks/useWindowsIntegration";
import { IA_VERSION, type ShellRecent } from "@/lib/shell/types";
import { showToast } from "@/lib/toast";
import { openAssistantPopOut } from "@/modules/assistant/openAssistantPopOut";
import { humanLabel, SETTINGS_CATEGORY_LABELS } from "@/lib/copy/humanLabels";
import { isSettingsDetailPage, normalizeSettingsPage } from "@/modules/settings/types";
import { HubLauncher } from "@/modules/shell/HubLauncher";
import { FirstRunWelcome } from "@/modules/shell/FirstRunWelcome";
import { WhatsNewSheet } from "@/modules/shell/WhatsNewSheet";
import {
  WebShortcutsSidebarSection,
  type WebShortcut,
} from "@/modules/shell/WebShortcutsSidebarSection";

const HomeModule = lazy(() =>
  import("@/modules/home/HomeModule").then((m) => ({ default: m.HomeModule })),
);
const SchoolModule = lazy(() =>
  import("@/modules/school/SchoolModule").then((m) => ({ default: m.SchoolModule })),
);
const LifeModule = lazy(() =>
  import("@/modules/life/LifeModule").then((m) => ({ default: m.LifeModule })),
);
const LibraryModule = lazy(() =>
  import("@/modules/library/LibraryModule").then((m) => ({ default: m.LibraryModule })),
);
const CareerModule = lazy(() =>
  import("@/modules/career/CareerHub").then((m) => ({ default: m.CareerHub })),
);
const AssistantModule = lazy(() =>
  import("@/modules/assistant/AssistantModule").then((m) => ({ default: m.AssistantModule })),
);
const SettingsModule = lazy(() =>
  import("@/modules/settings/SettingsModule").then((m) => ({ default: m.SettingsModule })),
);
const ResumePopOutView = lazy(() =>
  import("@/modules/career/ResumePopOutView").then((m) => ({ default: m.ResumePopOutView })),
);
const AssistantPopOutView = lazy(() =>
  import("@/modules/assistant/AssistantPopOutView").then((m) => ({ default: m.AssistantPopOutView })),
);

import type { SettingsPage } from "@/modules/settings/SettingsModule";
import {
  resolveDensity,
  type DensityPreference,
} from "@/design-system/platform/useShellLayout";

const MODULE_PILLS: ModulePillItem[] = [
  { id: "home", title: "Home", icon: <Home size={13} strokeWidth={2} /> },
  { id: "school", title: "School", icon: <GraduationCap size={13} strokeWidth={2} /> },
  { id: "career", title: "Career", icon: <Briefcase size={13} strokeWidth={2} /> },
  { id: "life", title: "Life", icon: <CalendarDays size={13} strokeWidth={2} /> },
  { id: "library", title: "Library", icon: <FolderOpen size={13} strokeWidth={2} /> },
];

const LIFE_FINANCE_PAGES = new Set([
  "money",
  "accounts",
  "ledger",
  "budgets",
  "goals",
  "inventory",
  "receipts",
  "reports",
  "net-worth",
]);

function isLifeFinancePage(page: string): boolean {
  return LIFE_FINANCE_PAGES.has(page) || page.startsWith("account-");
}

function isSchoolPageValid(page: string, sidebarIds: Set<string>): boolean {
  return sidebarIds.has(page) || page.startsWith("req-");
}

function isLibraryPageValid(page: string, sidebarIds: Set<string>): boolean {
  return sidebarIds.has(page) || page.startsWith("folder-") || page.startsWith("course-") || page.startsWith("cat-");
}

/** Career pages reachable via command palette / deep links but not always in the sidebar. */
const CAREER_EXTRA_PAGES = new Set(["board", "stats", "apply", "openings"]);

function isCareerPageValid(page: string, sidebarIds: Set<string>): boolean {
  return sidebarIds.has(page) || CAREER_EXTRA_PAGES.has(page);
}

function AppInner() {
  const { modKey } = usePlatform();
  const [module, setModule] = useState<ModuleId>("home");
  const [page, setPage] = useState("today");
  const [reduceMotion, setReduceMotion] = useState(false);
  const [densityPreference, setDensityPreference] = useState<DensityPreference>("default");
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [aiOpen, setAiOpen] = useState(false);
  const [aiFabHidden, setAiFabHidden] = useState(() => {
    try {
      return localStorage.getItem("ui.aiFabDismissed") === "true";
    } catch {
      return false;
    }
  });
  const [liveCommands, setLiveCommands] = useState<CommandItem[]>([]);
  const [recents, setRecents] = useState<ShellRecent[]>([]);
  const [welcomeOpen, setWelcomeOpen] = useState(false);
  const [whatsNewOpen, setWhatsNewOpen] = useState(false);
  const [whatsNewPending, setWhatsNewPending] = useState(false);
  const [appReady, setAppReady] = useState(false);
  const [hubOpen, setHubOpen] = useState(false);
  const [hubActiveIndex, setHubActiveIndex] = useState(0);
  const [settingsSearch, setSettingsSearch] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [financeAccounts, setFinanceAccounts] = useState<
    Array<{ id: string; name: string; institution: string }>
  >([]);
  const [auditSections, setAuditSections] = useState<Array<{ id: string; sectionTitle: string }>>(
    [],
  );
  const [calendarSources, setCalendarSources] = useState<Array<{ id: string; name: string }>>([]);
  const [webShortcuts, setWebShortcuts] = useState<WebShortcut[]>([]);
  const [vaultFolders, setVaultFolders] = useState<Array<{ id: string; title: string }>>([]);
  const [plannerCourses, setPlannerCourses] = useState<Array<{ id: string; code: string; title: string }>>(
    [],
  );
  const hydrated = useRef(false);
  const lastPagesRef = useRef<Partial<Record<ModuleId, string>>>({});
  const previousHubRef = useRef<ModuleId>("home");
  const aiTriggerRef = useRef<HTMLButtonElement>(null);
  const shellRootRef = useRef<HTMLDivElement>(null);

  const shellLayout = useShellLayout();
  const effectiveDensity = resolveDensity(densityPreference, shellLayout.width);

  useEffect(() => {
    document.documentElement.dataset.density = effectiveDensity;
    document.documentElement.style.setProperty("--ui-scale", String(densityScale(effectiveDensity)));
  }, [effectiveDensity]);

  useEffect(() => {
    void ipc.settingsGet().then(async (s) => {
      setReduceMotion(s.values["ui.reduceMotion"] === "true");
      const d = s.values["ui.density"];
      if (d === "compact" || d === "comfortable" || d === "default" || d === "auto") {
        setDensityPreference(d);
      }
      const stroke = s.values["ui.windowStroke"] === "subtle" ? "subtle" : "none";
      document.documentElement.dataset.windowStroke = stroke;
      document.documentElement.dataset.theme = s.values["ui.theme"] || "system";

      const migrated = migrateShellState(s.values);
      const pagesByModule = readPagesByModule(s.values);
      pagesByModule[migrated.module] = migrated.page;
      lastPagesRef.current = pagesByModule;
      setModule(migrated.module);
      const nextPage =
        migrated.module === "settings"
          ? normalizeSettingsPage(migrated.page)
          : migrated.page;
      setPage(nextPage);
      setRecents(migrated.recents);
      if (migrated.openAi) setAiOpen(true);
      if (migrated.showWhatsNew) setWhatsNewPending(true);

      if (parseInt(s.values["shell.iaVersion"] ?? "1", 10) < IA_VERSION) {
        await ipc.settingsSet("shell.iaVersion", String(IA_VERSION));
        await ipc.settingsSet("shell.module", migrated.module);
        await ipc.settingsSet("shell.page", migrated.page);
        await ipc.settingsSet(PAGES_BY_MODULE_KEY, JSON.stringify(pagesByModule));
        if (migrated.recents.length) {
          await ipc.settingsSet("shell.recents", JSON.stringify(migrated.recents));
        }
      }

      if (s.values["shell.onboarded"] !== "true") {
        setWelcomeOpen(true);
      } else if (migrated.showWhatsNew) {
        setWhatsNewOpen(true);
      }

      try {
        const id = await ipc.profileGetIdentity().catch(() => null);
        if (id?.fullName) setDisplayName(id.fullName);
      } catch {
        /* ignore */
      }

      try {
        const rawShortcuts = s.values["web.shortcuts.v1"];
        if (rawShortcuts) {
          const parsed = JSON.parse(rawShortcuts) as WebShortcut[];
          if (Array.isArray(parsed)) setWebShortcuts(parsed);
        }
      } catch {
        /* ignore */
      }

      hydrated.current = true;
      setAppReady(true);
      void maybeNotifyDueItems();
    });

    const onSettings = (ev: Event) => {
      const detail = (ev as CustomEvent<{ key: string; value: string }>).detail;
      if (!detail) return;
      if (detail.key === "ui.reduceMotion") setReduceMotion(detail.value === "true");
      if (detail.key === "ui.density") {
        const v = detail.value;
        if (v === "compact" || v === "comfortable" || v === "default" || v === "auto") {
          setDensityPreference(v);
        }
      }
      if (detail.key === "ui.windowStroke") {
        document.documentElement.dataset.windowStroke =
          detail.value === "subtle" ? "subtle" : "none";
      }
      if (detail.key === "ui.theme") {
        document.documentElement.dataset.theme = detail.value || "system";
      }
      if (detail.key === "web.shortcuts.v1") {
        try {
          const parsed = JSON.parse(detail.value) as WebShortcut[];
          setWebShortcuts(Array.isArray(parsed) ? parsed : []);
        } catch {
          setWebShortcuts([]);
        }
      }
    };
    window.addEventListener("college:settings", onSettings);
    return () => window.removeEventListener("college:settings", onSettings);
  }, []);

  useEffect(() => {
    if (module === "life") {
      void ipc.financeListAccounts().then(setFinanceAccounts).catch(() => setFinanceAccounts([]));
      void ipc
        .calendarListSources()
        .then((s) => setCalendarSources(s.map((x) => ({ id: x.id, name: x.name }))))
        .catch(() => setCalendarSources([]));
    }
    if (module === "school") {
      void ipc
        .academicsGetRequirementAudit()
        .then((a) =>
          setAuditSections(
            a.items.slice(0, 8).map((i) => ({ id: i.id, sectionTitle: i.sectionTitle })),
          ),
        )
        .catch(() => setAuditSections([]));
    }
    if (module === "library") {
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
  }, [module]);

  const switchModule = useCallback((nextModule: ModuleId) => {
    const pageId = resolveModulePage(lastPagesRef.current, nextModule);
    setModule(nextModule);
    setPage(pageId);
  }, []);

  const switchPage = useCallback((nextPage: string) => {
    setPage(nextPage);
  }, []);

  const openSettings = useCallback(() => {
    if (module === "settings") {
      switchModule(previousHubRef.current);
      return;
    }
    previousHubRef.current = module;
    switchModule("settings");
  }, [module, switchModule]);

  const go = useCallback(
    (nextModule: ModuleId, nextPage?: string, title?: string) => {
      if (nextModule === "settings" && module !== "settings") {
        previousHubRef.current = module;
      }
      const pageId = resolveModulePage(lastPagesRef.current, nextModule, nextPage);
      setModule(nextModule);
      setPage(pageId);
      const label = title ?? nextPage ?? nextModule;
      setRecents((prev) => {
        const entry = { module: nextModule, page: pageId, title: label };
        const next = [
          entry,
          ...prev.filter((r) => !(r.module === nextModule && r.page === pageId)),
        ].slice(0, 8);
        if (hydrated.current) void ipc.settingsSet("shell.recents", JSON.stringify(next));
        return next;
      });
    },
    [module],
  );

  useEffect(() => {
    if (!aiOpen) return;
    try {
      if (localStorage.getItem("ui.aiFabDismissed") !== "true") {
        localStorage.setItem("ui.aiFabDismissed", "true");
        setAiFabHidden(true);
      }
    } catch {
      /* storage unavailable */
    }
  }, [aiOpen]);

  useEffect(() => {
    const onNavigate = (ev: Event) => {
      const detail = (ev as CustomEvent<ShellNavigateDetail>).detail;
      const rawHub = detail?.hub ?? detail?.module;
      if (!rawHub) return;
      const migrated = migrateShellState({
        "shell.module": rawHub,
        "shell.page": detail.page ?? "",
        "shell.iaVersion": String(IA_VERSION),
      });
      if (detail.openAi) setAiOpen(true);
      go(migrated.module, detail.page ? migrated.page : undefined, detail.title);
    };
    window.addEventListener(NAVIGATE_EVENT, onNavigate);
    return () => window.removeEventListener(NAVIGATE_EVENT, onNavigate);
  }, [go]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;
      if (!meta || e.altKey) return;
      const target = e.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      const typing = tag === "input" || tag === "textarea" || target?.isContentEditable;

      if (e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen((o) => !o);
        return;
      }
      if (e.key.toLowerCase() === "j") {
        e.preventDefault();
        setAiOpen((o) => !o);
        return;
      }
      if (e.shiftKey && e.key.toLowerCase() === "h") {
        e.preventDefault();
        setHubOpen((o) => !o);
        return;
      }
      if (typing) return;
      if (e.key === ",") {
        e.preventDefault();
        openSettings();
        return;
      }
      const map: Record<string, ModuleId> = {
        "1": "home",
        "2": "school",
        "3": "career",
        "4": "life",
        "5": "library",
      };
      const next = map[e.key];
      if (next) {
        e.preventDefault();
        switchModule(next);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go, switchModule, openSettings]);

  useEffect(() => {
    if (!hydrated.current) return;
    void ipc.settingsSet("shell.module", module);
  }, [module]);

  useEffect(() => {
    if (!hydrated.current) return;
    lastPagesRef.current = { ...lastPagesRef.current, [module]: page };
    void ipc.settingsSet(PAGES_BY_MODULE_KEY, JSON.stringify(lastPagesRef.current));
    void ipc.settingsSet("shell.page", page);
  }, [module, page]);

  const { sidebarItems, sectionTitle } = useMemo((): {
    sidebarItems: SidebarItem[];
    sectionTitle?: string;
  } => {
    switch (module) {
      case "home":
        return {
          sectionTitle: "Home",
          sidebarItems: [
            { id: "today", title: "Today", icon: <LayoutDashboard size={14} /> },
            { id: "week", title: "Week", icon: <CalendarRange size={14} /> },
            { id: "goals", title: "Goals", icon: <Target size={14} /> },
            { id: "recents", title: "Recents", icon: <Clock size={14} /> },
          ],
        };
      case "school":
        return {
          sectionTitle: "School",
          sidebarItems: [
            { id: "plan", title: humanLabel("plan"), icon: <GraduationCap size={14} /> },
            { id: "courses", title: humanLabel("courses"), icon: <BookOpen size={14} /> },
            { id: "degree", title: humanLabel("degree"), icon: <ListChecks size={14} /> },
            ...auditSections.map((s) => ({
              id: `req-${s.id}`,
              title: s.sectionTitle.length > 22 ? `${s.sectionTitle.slice(0, 20)}…` : s.sectionTitle,
              icon: <ListChecks size={14} />,
              indent: true,
            })),
            { id: "schools", title: humanLabel("schools"), icon: <Compass size={14} /> },
            { id: "catalog", title: humanLabel("catalog"), icon: <BookOpen size={14} /> },
            { id: "transfer", title: humanLabel("transfer"), icon: <ArrowLeftRight size={14} /> },
            { id: "lms", title: humanLabel("lms"), icon: <Globe size={14} /> },
          ],
        };
      case "career":
        return {
          sectionTitle: "Career",
          sidebarItems: [
            { id: "pipeline", title: "Applications", icon: <Briefcase size={14} /> },
            { id: "openings", title: "Openings", icon: <Target size={14} /> },
            { id: "pathing", title: humanLabel("pathing"), icon: <ListChecks size={14} /> },
            { id: "resume", title: "Resume", icon: <FileText size={14} /> },
            { id: "growth", title: "Growth", icon: <Trophy size={14} /> },
          ],
        };
      case "life":
        return {
          sectionTitle: "Life",
          sidebarItems: [
            { id: "schedule", title: humanLabel("schedule"), icon: <CalIcon size={14} />, section: "Calendar" },
            { id: "week", title: humanLabel("week"), icon: <Columns3 size={14} />, section: "Calendar" },
            { id: "day", title: humanLabel("day"), icon: <Sun size={14} />, section: "Calendar" },
            { id: "tasks", title: humanLabel("tasks"), icon: <ListChecks size={14} />, section: "Calendar" },
            ...calendarSources.slice(0, 5).map((s) => ({
              id: `source-${s.id}`,
              title: s.name.length > 18 ? `${s.name.slice(0, 16)}…` : s.name,
              icon: <CalIcon size={14} />,
              indent: true,
              section: "Calendar",
            })),
            { id: "money", title: humanLabel("money"), icon: <Wallet size={14} />, section: "Money" },
            { id: "ledger", title: humanLabel("ledger"), icon: <Receipt size={14} />, section: "Money" },
            { id: "budgets", title: humanLabel("budgets"), icon: <PiggyBank size={14} />, section: "Money" },
            { id: "reports", title: humanLabel("reports"), icon: <PieChart size={14} />, section: "Money" },
            ...financeAccounts.slice(0, 5).map((a) => ({
              id: `account-${a.id}`,
              title: a.name.length > 20 ? `${a.name.slice(0, 18)}…` : a.name,
              icon: <Wallet size={14} />,
              indent: true,
              section: "Money",
            })),
          ],
        };
      case "library":
        return {
          sectionTitle: "Library",
          sidebarItems: [
            { id: "all", title: "All files", icon: <FolderOpen size={14} /> },
            { id: "recent", title: "Recent", icon: <Clock size={14} /> },
            { id: "starred", title: "Starred", icon: <Star size={14} /> },
            { id: "needs-review", title: "Needs review", icon: <AlertCircle size={14} /> },
            { id: "portfolio", title: "Portfolio", icon: <Layers size={14} /> },
            { id: "experiences", title: "Experiences", icon: <Briefcase size={14} /> },
            { id: "achievements", title: "Achievements", icon: <Award size={14} /> },
            { id: "identity", title: "Student Identity", icon: <UserRound size={14} /> },
            { id: "advisor", title: "Advisor Prep", icon: <ListChecks size={14} /> },
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
      case "settings":
        return {
          sectionTitle: "Settings",
          sidebarItems: [
            { id: "you", title: SETTINGS_CATEGORY_LABELS.you, icon: <UserRound size={14} /> },
            { id: "appearance", title: SETTINGS_CATEGORY_LABELS.appearance, icon: <Monitor size={14} /> },
            { id: "connections", title: SETTINGS_CATEGORY_LABELS.connections, icon: <Link2 size={14} /> },
            { id: "school-work", title: SETTINGS_CATEGORY_LABELS["school-work"], icon: <GraduationCap size={14} /> },
            { id: "advanced", title: SETTINGS_CATEGORY_LABELS.advanced, icon: <Shield size={14} /> },
          ],
        };
      default:
        return { sidebarItems: [] };
    }
  }, [module, financeAccounts, auditSections, calendarSources, vaultFolders, plannerCourses]);

  const filteredSidebarItems = useMemo(() => {
    if (module !== "settings" || !settingsSearch.trim()) return sidebarItems;
    const q = settingsSearch.trim().toLowerCase();
    return sidebarItems.filter((item) => item.title.toLowerCase().includes(q));
  }, [module, sidebarItems, settingsSearch]);

  useEffect(() => {
    const sidebarIds = new Set(sidebarItems.map((i) => i.id));
    const valid =
      sidebarItems.some((i) => i.id === page) ||
      (module === "settings" && isSettingsDetailPage(page)) ||
      (module === "life" && (isLifeFinancePage(page) || page.startsWith("source-"))) ||
      (module === "library" && isLibraryPageValid(page, sidebarIds)) ||
      (module === "school" && isSchoolPageValid(page, sidebarIds)) ||
      (module === "career" && isCareerPageValid(page, sidebarIds));
    if (!valid) setPage(defaultPageFor(module));
  }, [module, sidebarItems, page]);

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
        for (const t of tasks.slice(0, 3)) {
          items.push({
            id: `task-${t.id}`,
            title: t.title,
            subtitle: t.isComplete ? "Done" : t.dueAt ? `Due ${new Date(t.dueAt).toLocaleDateString()}` : "Open",
            group: "Library",
            keywords: "todo assignment task",
            run: () => go("life", "tasks"),
          });
        }
        for (const a of apps.slice(0, 3)) {
          items.push({
            id: `app-${a.id}`,
            title: `${a.roleTitle} @ ${a.company}`,
            subtitle: a.status,
            group: "Library",
            keywords: "job career application",
            run: () => go("career", "pipeline"),
          });
        }
        for (const c of courses.slice(0, 3)) {
          items.push({
            id: `course-${c.id}`,
            title: `${c.code} — ${c.title}`,
            group: "Library",
            keywords: "course class catalog",
            run: () => go("school", "catalog"),
          });
        }
        for (const d of docs.slice(0, 3)) {
          items.push({
            id: `doc-${d.id}`,
            title: d.title,
            subtitle: d.category,
            group: "Library",
            keywords: "document file vault",
            run: () => go("library", d.category ? `cat-${d.category}` : "all"),
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
  }, [paletteOpen, go]);

  const commandItems = useMemo((): CommandItem[] => {
    const recentItems: CommandItem[] = recents.slice(0, 3).map((r, i) => ({
      id: `recent-${r.module}-${r.page}-${i}`,
      title: r.title,
      group: "Library",
      keywords: "history last recent",
      run: () => go(r.module, r.page, r.title),
    }));
    const nav: CommandItem[] = [
      { id: "nav-home", title: "Today", subtitle: "Home", icon: <Home size={14} />, group: "Navigate", run: () => go("home", "today", "Today") },
      { id: "nav-school", title: humanLabel("plan"), subtitle: "School", icon: <GraduationCap size={14} />, group: "Navigate", run: () => go("school", "plan", humanLabel("plan")) },
      { id: "nav-career", title: humanLabel("pipeline"), subtitle: "Career", icon: <Briefcase size={14} />, group: "Navigate", run: () => go("career", "pipeline", humanLabel("pipeline")) },
      {
        id: "nav-career-openings",
        title: "Job openings",
        subtitle: "Career",
        group: "Navigate",
        keywords: "jobs board sync",
        run: () => go("career", "openings", "Openings"),
      },
      {
        id: "nav-career-board",
        title: "Application board",
        subtitle: "Career",
        group: "Navigate",
        keywords: "kanban pipeline",
        run: () => go("career", "board", "Board"),
      },
      {
        id: "nav-career-stats",
        title: "Pipeline stats",
        subtitle: "Career",
        group: "Navigate",
        keywords: "metrics analytics",
        run: () => go("career", "stats", "Stats"),
      },
      {
        id: "nav-career-apply",
        title: "Apply profile",
        subtitle: "Career",
        group: "Navigate",
        keywords: "autofill identity",
        run: () => go("career", "apply", "Apply"),
      },
      { id: "nav-life", title: humanLabel("schedule"), subtitle: "Life", icon: <CalIcon size={14} />, group: "Navigate", run: () => go("life", "schedule", humanLabel("schedule")) },
      { id: "nav-library", title: humanLabel("all"), subtitle: "Library", icon: <FolderOpen size={14} />, group: "Navigate", run: () => go("library", "all", humanLabel("all")) },
      { id: "nav-settings", title: "Settings", icon: <Settings size={14} />, group: "Navigate", keywords: "preferences", run: () => openSettings() },
    ];
    const actions: CommandItem[] = [
      {
        id: "act-ai",
        title: "Ask assistant",
        group: "Actions",
        keywords: "ai chat",
        run: () => setAiOpen(true),
      },
      {
        id: "act-add-task",
        title: "Add task",
        group: "Actions",
        keywords: "new todo",
        run: () => {
          go("life", "tasks", "Tasks");
          window.setTimeout(() => {
            window.dispatchEvent(new CustomEvent("college:quick-add", { detail: { kind: "task" } }));
          }, 50);
        },
      },
      {
        id: "act-add-event",
        title: "Add event",
        group: "Actions",
        keywords: "new calendar",
        run: () => {
          go("life", "schedule", humanLabel("schedule"));
          window.setTimeout(() => {
            window.dispatchEvent(new CustomEvent("college:quick-add", { detail: { kind: "event" } }));
          }, 50);
        },
      },
      {
        id: "act-add-expense",
        title: "Log expense",
        group: "Actions",
        keywords: "finance transaction",
        run: () => go("life", "money", humanLabel("money")),
      },
      {
        id: "act-add-app",
        title: "Add application",
        group: "Actions",
        keywords: "new job career",
        run: () => {
          go("career", "pipeline", humanLabel("pipeline"));
          window.setTimeout(() => {
            window.dispatchEvent(
              new CustomEvent("college:quick-add", { detail: { kind: "application" } }),
            );
          }, 50);
        },
      },
      {
        id: "act-theme-system",
        title: "Theme: Match system OS setting",
        subtitle: "Automatically follow OS dark / light mode",
        group: "Actions",
        keywords: "dark light theme mode system os auto",
        run: () => {
          void ipc.settingsSet("ui.theme", "system");
          window.dispatchEvent(
            new CustomEvent("college:settings", { detail: { key: "ui.theme", value: "system" } }),
          );
        },
      },
      {
        id: "act-theme-dark",
        title: "Theme: Dark mode",
        subtitle: "Force dark interface",
        group: "Actions",
        keywords: "dark theme night mode black",
        run: () => {
          void ipc.settingsSet("ui.theme", "dark");
          window.dispatchEvent(
            new CustomEvent("college:settings", { detail: { key: "ui.theme", value: "dark" } }),
          );
        },
      },
      {
        id: "act-theme-light",
        title: "Theme: Light mode",
        subtitle: "Force light interface",
        group: "Actions",
        keywords: "light theme day mode white",
        run: () => {
          void ipc.settingsSet("ui.theme", "light");
          window.dispatchEvent(
            new CustomEvent("college:settings", { detail: { key: "ui.theme", value: "light" } }),
          );
        },
      },
    ];
    return [...recentItems, ...nav, ...actions, ...liveCommands];
  }, [liveCommands, recents, go, openSettings]);

  const quickAdd = (kind: "event" | "expense" | "task") => {
    if (kind === "expense") {
      go("life", "money", humanLabel("money"));
      return;
    }
    if (kind === "event") {
      go("life", "schedule", humanLabel("schedule"));
      window.setTimeout(() => {
        window.dispatchEvent(new CustomEvent("college:quick-add", { detail: { kind: "event" } }));
      }, 50);
      return;
    }
    go("life", "tasks", "Tasks");
    window.setTimeout(() => {
      window.dispatchEvent(new CustomEvent("college:quick-add", { detail: { kind: "task" } }));
    }, 50);
  };

  const sidebarSelection =
    module === "life" && page.startsWith("account-")
      ? page
      : module === "life" && page.startsWith("source-")
        ? page
        : module === "library" && (page.startsWith("course-") || page.startsWith("folder-"))
          ? page
          : module === "school" && page.startsWith("req-")
            ? page
            : page;

  const shellNavigation = useMemo(
    (): ShellNavigationValue => ({
      module,
      page,
      go,
      switchModule,
      switchPage,
      openSettings,
    }),
    [module, page, go, switchModule, switchPage, openSettings],
  );

  const content = (() => {
    if (module === "settings") return <SettingsModule page={page as SettingsPage} />;
    if (module === "home")
      return (
        <HomeModule
          page={page}
          recents={recents}
          onNavigate={go}
          onQuickAdd={quickAdd}
          onClearRecents={() => setRecents([])}
        />
      );
    if (module === "school") return <SchoolModule page={page} />;
    if (module === "life") return <LifeModule page={page} />;
    if (module === "library") return <LibraryModule page={page} />;
    if (module === "career") return <CareerModule page={page} />;
    return null;
  })();

  if (!appReady) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-3 bg-[var(--color-shell-chrome)]">
        <div className="text-section-title font-semibold tracking-tight text-[var(--color-text-main)]">
          College
        </div>
        <p className="text-meta text-[var(--color-text-light)]">Loading your workspace…</p>
      </div>
    );
  }

  return (
  <ShellNavigationProvider value={shellNavigation}>
    <ShellBoundsProvider rootRef={shellRootRef}>
    <>
    <div ref={shellRootRef} className="flex h-full w-full overflow-hidden">
      <div className="min-h-0 min-w-0 flex-1">
      <ShellSplitLayout
        sidebarCollapsed={shellLayout.sidebarCollapsed}
        header={
          <div className="flex w-full items-center gap-2">
            <ModulePillBar
              items={MODULE_PILLS}
              selection={module === "settings" ? "" : module}
              reduceMotion={reduceMotion}
              onSelect={(id) => switchModule(id as ModuleId)}
              onReselect={() => switchModule("home")}
              className="min-w-0"
            />
            <div className="ml-auto flex shrink-0 items-center gap-2">
              <button
                type="button"
                className="chrome-nav-btn mb-0.5 inline-flex h-7 shrink-0 items-center gap-1 rounded-full px-2"
                onClick={() => setPaletteOpen(true)}
                aria-label="Open search"
              >
                <span>Search</span>
                <kbd className="rounded-[5px] border border-[var(--color-chrome-stroke)] px-1 py-px text-caption">
                  {modKey}K
                </kbd>
              </button>
              <button
                type="button"
                className="chrome-nav-btn mb-0.5 inline-flex h-7 items-center gap-1 rounded-full px-2"
                onClick={() => setHubOpen(true)}
                aria-label="All hubs"
              >
                Jump to…
              </button>
            </div>
          </div>
        }
        sidebar={
          <div className="flex h-full flex-col">
            {module === "settings" && (
              <div className="shrink-0 border-b border-[var(--color-chrome-stroke)] px-3 py-2">
                <input
                  className="w-full rounded-[8px] border border-[var(--color-chrome-stroke)] bg-[var(--color-content-surface)] px-2.5 py-1.5 text-chrome outline-none focus:border-[var(--color-primary)]"
                  placeholder="Search settings…"
                  value={settingsSearch}
                  onChange={(e) => setSettingsSearch(e.target.value)}
                />
              </div>
            )}
            <div className="min-h-0 flex-1">
              <AppSidebar
                items={filteredSidebarItems}
                selection={sidebarSelection}
                sectionTitle={sectionTitle}
                reduceMotion={reduceMotion}
                collapsed={shellLayout.sidebarCollapsed}
                onSelect={switchPage}
                footer={
                  <div className="flex flex-col gap-1">
                    {module === "school" && (
                      <WebShortcutsSidebarSection
                        shortcuts={webShortcuts}
                        onManage={() => go("settings", "shortcuts", "Shortcuts")}
                      />
                    )}
                    <div className="flex flex-col gap-0.5 px-1 pb-1">
                      <button
                        type="button"
                        className="chrome-nav-btn flex w-full items-center gap-2 rounded-[8px] px-2.5 py-1.5 text-left"
                        onClick={() => quickAdd("event")}
                        aria-label="Add event"
                        title="Add event"
                      >
                        <Plus size={12} />
                        <span>Event</span>
                      </button>
                      <button
                        type="button"
                        className="chrome-nav-btn flex w-full items-center gap-2 rounded-[8px] px-2.5 py-1.5 text-left"
                        onClick={() => quickAdd("task")}
                        aria-label="Add task"
                        title="Add task"
                      >
                        <Plus size={12} />
                        <span>Task</span>
                      </button>
                      <button
                        type="button"
                        className="chrome-nav-btn flex w-full items-center gap-2 rounded-[8px] px-2.5 py-1.5 text-left"
                        onClick={() => quickAdd("expense")}
                        aria-label="Add expense"
                        title="Add expense"
                      >
                        <Plus size={12} />
                        <span>Expense</span>
                      </button>
                      <button
                        type="button"
                        className={`chrome-nav-btn flex w-full items-center gap-2 rounded-[8px] px-2.5 py-1.5 text-left ${
                          module === "settings"
                            ? "bg-[color-mix(in_srgb,var(--registrar-accent)_14%,transparent)] font-semibold text-[var(--registrar-ink)]"
                            : ""
                        }`}
                        onClick={openSettings}
                        aria-label="Settings"
                        title="Settings"
                      >
                        <Settings size={12} />
                        <span>Settings</span>
                      </button>
                    </div>
                    <UserMenu
                      displayName={displayName}
                      onProfile={() => go("library", "identity", "Identity")}
                      onSettings={openSettings}
                    />
                  </div>
                }
              />
            </div>
          </div>
        }
      >
        <SuperAppContentSurface>
          <Suspense
            fallback={
              <div className="flex h-full items-center justify-center text-body text-[var(--color-text-light)]">
                Loading…
              </div>
            }
          >
            <PageTransition pageKey={`${module}-${page}`}>{content}</PageTransition>
          </Suspense>
        </SuperAppContentSurface>
      </ShellSplitLayout>
      </div>
      <AIPanel
        open={aiOpen}
        onOpenChange={setAiOpen}
        triggerRef={aiTriggerRef}
        onPopOut={() => {
          setAiOpen(false);
          void openAssistantPopOut();
        }}
      >
        <Suspense fallback={<div className="p-4 text-body">Loading assistant…</div>}>
          <AssistantModule page="chat" />
        </Suspense>
      </AIPanel>
    </div>
      <CommandPalette
        open={paletteOpen}
        onOpenChange={setPaletteOpen}
        items={commandItems}
        reduceMotion={reduceMotion}
      />
      <AIFloatingButton
        buttonRef={aiTriggerRef}
        hidden={aiFabHidden || aiOpen}
        onClick={() => setAiOpen(true)}
      />
      <ToastHost reduceMotion={reduceMotion} />
      <FirstRunWelcome
        open={welcomeOpen}
        onDismiss={() => {
          setWelcomeOpen(false);
          if (whatsNewPending) setWhatsNewOpen(true);
        }}
        onComplete={() => {
          showToast("Welcome! Your workspace is ready.", "success");
        }}
      />
      <WhatsNewSheet
        open={whatsNewOpen}
        onDismiss={() => {
          setWhatsNewOpen(false);
          void ipc.settingsSet("shell.iaVersion", String(IA_VERSION));
        }}
      />
      <HubLauncher
        open={hubOpen}
        onOpenChange={setHubOpen}
        activeIndex={hubActiveIndex}
        onActiveIndexChange={setHubActiveIndex}
        onSelect={(id) => {
          switchModule(id);
        }}
      />
    </>
    </ShellBoundsProvider>
  </ShellNavigationProvider>
  );
}

export default function App() {
  const popout =
    typeof window !== "undefined"
      ? new URLSearchParams(window.location.search).get("popout")
      : null;
  if (popout === "resume") {
    return (
      <PlatformProvider>
        <ThemeProvider>
          <Suspense fallback={<div className="p-4 text-body">Loading…</div>}>
            <ResumePopOutView />
          </Suspense>
        </ThemeProvider>
      </PlatformProvider>
    );
  }
  if (popout === "assistant") {
    return (
      <PlatformProvider>
        <ThemeProvider>
          <MotionProvider reduceMotion={false}>
            <Suspense fallback={<div className="p-4 text-body">Loading…</div>}>
              <AssistantPopOutView />
            </Suspense>
          </MotionProvider>
        </ThemeProvider>
      </PlatformProvider>
    );
  }

  return (
    <PlatformProvider>
      <ThemeProvider>
        <AppRoot />
      </ThemeProvider>
    </PlatformProvider>
  );
}

function AppRoot() {
  const [reduceMotion, setReduceMotion] = useState(false);
  useWindowsIntegration();
  useEffect(() => {
    void ipc.settingsGet().then((s) => {
      setReduceMotion(s.values["ui.reduceMotion"] === "true");
    });
    const onSettings = (ev: Event) => {
      const detail = (ev as CustomEvent<{ key: string; value: string }>).detail;
      if (detail?.key === "ui.reduceMotion") setReduceMotion(detail.value === "true");
    };
    window.addEventListener("college:settings", onSettings);
    return () => window.removeEventListener("college:settings", onSettings);
  }, []);

  return (
    <MotionProvider reduceMotion={reduceMotion}>
      <AppInner />
    </MotionProvider>
  );
}
