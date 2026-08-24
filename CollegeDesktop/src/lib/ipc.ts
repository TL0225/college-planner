import { invoke as tauriInvoke } from "@tauri-apps/api/core";

/** Turn Tauri/IPC throwables into a readable string (avoids "[object Object]"). */
export function formatIpcError(err: unknown): string {
  if (err == null) return "Unknown error";
  if (typeof err === "string") return err;
  if (err instanceof Error) return err.message || err.name || "Error";
  if (typeof err === "object") {
    const o = err as Record<string, unknown>;
    if (typeof o.message === "string" && o.message.trim()) return o.message;
    if (typeof o.error === "string" && o.error.trim()) return o.error;
    if (typeof o.error === "object" && o.error) {
      const nested = formatIpcError(o.error);
      if (nested !== "[object Object]") return nested;
    }
    try {
      return JSON.stringify(err);
    } catch {
      return "Unexpected error";
    }
  }
  return String(err);
}

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  try {
    return await tauriInvoke<T>(cmd, args);
  } catch (err) {
    throw new Error(formatIpcError(err));
  }
}

export type PlatformInfo = {
  os: string;
  arch: string;
  family: string;
  appVersion: string;
};

export type StoragePaths = {
  root: string;
  collegeDb: string;
  financeDb: string;
  vaultDir: string;
  modelsDir: string;
  cacheDir: string;
  backupsDir: string;
};

export type AuditSummary = {
  plannedCredits: number;
  completedCredits: number;
  semesterCount: number;
  courseCount: number;
};

export type PipelineMetrics = {
  interested: number;
  applied: number;
  interviewing: number;
  offer: number;
  rejected: number;
  accepted: number;
  total: number;
};

export type ResumeProfile = {
  id: string;
  vaultDocId: string;
  targetRole: string;
  targetCompany: string;
  notes: string;
  updatedAt: string;
};

export type ResumeMetrics = {
  vaultResumeCount: number;
  profilesWithNotesCount: number;
  lastMatchScore?: number | null;
};

export type FinanceDashboardSummary = {
  netWorth: number;
  accountBalanceTotal: number;
  holdingsValue: number;
  accountCount: number;
  transactionCount: number;
  budgetCount: number;
};

export type FinanceHolding = {
  id: string;
  assetType: string;
  symbol: string;
  name: string;
  quantity: number;
  pricePerUnit: number;
  marketValue: number;
};

export type CareerApplyAutofillResult = {
  platform: string;
  fields: Array<{
    payloadKey: string;
    intended: string;
    filled?: string | null;
    verified: boolean;
    status: string;
    atsLabel: string;
  }>;
  writeAttemptCount: number;
  filledCount: number;
};

export type AiRuntimeStatus = {
  backend: string;
  embeddingsBackend: string;
  embeddingsReady: boolean;
  llmReady: boolean;
  model: string;
  endpointConfigured: boolean;
  onnxPathConfigured: boolean;
  modelDir: string;
  device: string;
  endpointUrl: string;
  ollamaEndpoint: boolean;
  pingOk: boolean | null;
  pingMessage: string;
};

export type AiPingResult = {
  ok: boolean;
  message: string;
  model?: string | null;
};

export type ProfileIdentity = {
  id?: string | null;
  fullName: string;
  email: string;
  universityName: string;
  major: string;
  graduationYear?: number | null;
};

export type Semester = {
  id: string;
  year: number;
  season: string;
  label: string;
  isCurrent: boolean;
};

export type PlannerCourse = {
  id: string;
  semesterId: string;
  code: string;
  title: string;
  credits: number;
  status: string;
  grade?: string | null;
};

export type GpaSummary = {
  gpa?: number | null;
  gradedCredits: number;
  gradedCourses: number;
};

export type ProgramSummary = {
  id: string;
  name: string;
  degreeType: string;
  universityName: string;
  programUrl: string;
  sectionCount: number;
  isActive: boolean;
};

export type ProgramDetail = {
  id: string;
  name: string;
  degreeType: string;
  universityName: string;
  programUrl: string;
  isActive: boolean;
  requirements: Array<{
    id: string;
    sectionTitle: string;
    creditsRequired?: number | null;
    ruleCodes: string[];
    sortOrder: number;
  }>;
};

export type SubscribeFeedResult = {
  path: string;
  eventCount: number;
  writtenAt: string;
};

export const ipc = {
  getPlatformInfo: () => invoke<PlatformInfo>("get_platform_info"),
  getStoragePaths: () => invoke<StoragePaths>("get_storage_paths"),
  platformTypstAvailable: () => invoke<boolean>("platform_typst_available"),
  platformFetchWeather: (lat: number, lon: number) =>
    invoke<{ temperatureF: number; summary: string; windMph?: number | null; source: string }>(
      "platform_fetch_weather",
      { lat, lon },
    ),
  platformImportSwiftWorkspace: (input?: {
    swiftCollegeDb?: string;
    swiftFinanceDb?: string;
    domains?: string[];
  }) =>
    invoke<{
      swiftDbPath: string;
      sourceSchema: string;
      profileRows: number;
      experienceRows: number;
      achievementRows: number;
      semesterRows: number;
      courseRows: number;
      taskRows: number;
      calendarRows: number;
      applicationRows: number;
      postingRows: number;
      settingsRows: number;
      vaultRows: number;
      vaultFilesCopied: number;
      financeRows: number;
      totalRows: number;
      skippedReason?: string | null;
    }>("platform_import_swift_workspace", { input: input ?? {} }),
  platformSyncPublishedCalendarFeed: () =>
    invoke<{ imported: number; skipped: number; lastSyncedAt: string }>(
      "platform_sync_published_calendar_feed",
    ),
  academicsGetAuditSummary: () => invoke<AuditSummary>("academics_get_audit_summary"),
  academicsGetGpaSummary: () => invoke<GpaSummary>("academics_get_gpa_summary"),
  academicsGetRequirementAudit: () =>
    invoke<{
      items: Array<{
        id: string;
        sectionTitle: string;
        creditsRequired?: number | null;
        creditsEarned: number;
        status: string;
        matchedCodes: string[];
        missingCodes: string[];
      }>;
      satisfiedCount: number;
      totalCount: number;
      progressRatio: number;
    }>("academics_get_requirement_audit"),
  academicsListSemesters: () => invoke<Semester[]>("academics_list_semesters"),
  academicsListCourses: (semesterId?: string) =>
    invoke<PlannerCourse[]>("academics_list_courses", { semesterId: semesterId ?? null }),
  academicsUpsertSemester: (input: {
    year: number;
    season: string;
    label?: string;
    isCurrent?: boolean;
  }) => invoke<string>("academics_upsert_semester", { input }),
  academicsUpsertCourse: (input: {
    semesterId: string;
    code: string;
    title: string;
    credits?: number;
    status?: string;
  }) => invoke<string>("academics_upsert_course", { input }),
  academicsUpdateCourseStatus: (id: string, status: string) =>
    invoke<void>("academics_update_course_status", { id, status }),
  academicsUpdateCourseGrade: (id: string, grade?: string | null) =>
    invoke<void>("academics_update_course_grade", { id, grade: grade ?? null }),
  academicsDeleteCourse: (id: string) => invoke<void>("academics_delete_course", { id }),
  academicsDeleteSemester: (id: string) => invoke<void>("academics_delete_semester", { id }),
  academicsAddRequirementCourse: (input: {
    semesterId: string;
    code: string;
    title?: string;
    credits?: number;
  }) => invoke<boolean>("academics_add_requirement_course", { input }),
  academicsAssignFulfillment: (input: { categoryId: string; courseCode: string }) =>
    invoke<boolean>("academics_assign_fulfillment", {
      input: { categoryId: input.categoryId, courseCode: input.courseCode },
    }),
  academicsListPrograms: () => invoke<ProgramSummary[]>("academics_list_programs"),
  academicsGetProgramDetail: (programId: string) =>
    invoke<ProgramDetail>("academics_get_program_detail", { programId }),
  academicsSetActiveProgram: (programId: string) =>
    invoke<void>("academics_set_active_program", { input: { programId } }),
  academicsListGradingCategories: (courseId?: string) =>
    invoke<
      Array<{ id: string; courseId: string; name: string; weight: number; sortOrder: number }>
    >("academics_list_grading_categories", { courseId: courseId ?? null }),
  academicsEvaluatePrerequisites: (courseCode: string) =>
    invoke<{ satisfied: boolean; missingCodes: string[]; notes: string }>(
      "academics_evaluate_prerequisites",
      { courseCode },
    ),
  calendarListEvents: () =>
    invoke<
      Array<{
        id: string;
        title: string;
        startAt: string;
        endAt?: string;
        allDay: boolean;
        location: string;
        notes?: string;
        provider: string;
        color: string;
        recurrence: string;
        sourceId?: string | null;
      }>
    >("calendar_list_events"),
  calendarListSources: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        color: string;
        icsUrl: string;
        lastSyncedAt?: string | null;
        isEnabled: boolean;
        sortOrder: number;
      }>
    >("calendar_list_sources"),
  calendarUpsertSource: (input: {
    id?: string;
    name: string;
    color?: string;
    icsUrl?: string;
    isEnabled?: boolean;
  }) => invoke<string>("calendar_upsert_source", { input }),
  calendarDeleteSource: (id: string) => invoke<void>("calendar_delete_source", { id }),
  calendarSyncIcsUrl: (sourceId: string) =>
    invoke<{ imported: number; skipped: number; lastSyncedAt: string }>(
      "calendar_sync_ics_url",
      { sourceId },
    ),
  calendarListTasks: () =>
    invoke<Array<{ id: string; title: string; dueAt?: string; isComplete: boolean }>>(
      "calendar_list_tasks",
    ),
  calendarUpsertEvent: (input: {
    id?: string;
    title: string;
    startAt: string;
    endAt?: string;
    location?: string;
    allDay?: boolean;
    color?: string;
    recurrence?: string;
    courseId?: string;
    semesterId?: string;
    notes?: string;
  }) => invoke<string>("calendar_upsert_event", { input }),
  calendarUpsertTask: (input: { id?: string; title: string; dueAt?: string }) =>
    invoke<string>("calendar_upsert_task", { input }),
  calendarToggleTaskComplete: (id: string) =>
    invoke<void>("calendar_toggle_task_complete", { id }),
  calendarDeleteEvent: (id: string) => invoke<void>("calendar_delete_event", { id }),
  calendarDeleteTask: (id: string) => invoke<void>("calendar_delete_task", { id }),
  calendarImportIcs: (icsText: string) =>
    invoke<{ imported: number; skipped: number }>("calendar_import_ics", {
      input: { icsText },
    }),
  calendarImportIcsPath: (path: string) =>
    invoke<{ imported: number; skipped: number }>("calendar_import_ics_path", { path }),
  calendarExportIcs: () => invoke<string>("calendar_export_ics"),
  calendarExportIcsPath: (path: string) =>
    invoke<{ eventCount: number; path: string }>("calendar_export_ics_path", { path }),
  calendarPublishSubscribeFeed: () =>
    invoke<SubscribeFeedResult>("calendar_publish_subscribe_feed"),
  calendarOpenAppleCalendarFeed: () =>
    invoke<SubscribeFeedResult>("calendar_open_apple_calendar_feed"),
  calendarGeocodeLocation: (query: string) =>
    invoke<{ lat: number; lon: number; displayName: string }>("calendar_geocode_location", {
      query,
    }),
  calendarOauthBegin: (provider: "google" | "outlook") =>
    invoke<{ authUrl: string; state: string; redirectUri: string }>("calendar_oauth_begin", {
      provider,
    }),
  calendarOauthComplete: (oauthState: string) =>
    invoke<{
      id: string;
      provider: string;
      accountEmail: string;
      sourceId?: string | null;
      scopes: string;
      expiresAt?: string | null;
      lastSyncedAt?: string | null;
    }>("calendar_oauth_complete", { oauthState }),
  calendarOauthStatus: () =>
    invoke<{
      accounts: Array<{
        id: string;
        provider: string;
        accountEmail: string;
        sourceId?: string | null;
        scopes: string;
        expiresAt?: string | null;
        lastSyncedAt?: string | null;
      }>;
      googleConfigured: boolean;
      outlookConfigured: boolean;
    }>("calendar_oauth_status"),
  calendarOauthSync: (input?: { provider?: string; accountId?: string }) =>
    invoke<{ imported: number; skipped: number; lastSyncedAt: string }>("calendar_oauth_sync", {
      provider: input?.provider ?? null,
      accountId: input?.accountId ?? null,
    }),
  calendarOauthSyncAll: () =>
    invoke<{
      accounts: number;
      imported: number;
      skipped: number;
      errors: string[];
    }>("calendar_oauth_sync_all"),
  calendarOauthDisconnect: (accountId: string) =>
    invoke<void>("calendar_oauth_disconnect", { accountId }),
  calendarOauthPushLocal: (input?: { accountId?: string; provider?: string }) =>
    invoke<{ pushed: number; skipped: number; errors: string[] }>(
      "calendar_oauth_push_local",
      { accountId: input?.accountId ?? null, provider: input?.provider ?? null },
    ),
  careerListApplications: () =>
    invoke<
      Array<{
        id: string;
        company: string;
        roleTitle: string;
        status: string;
        location: string;
        url: string;
        appliedAt?: string;
      }>
    >("career_list_applications"),
  careerPipelineMetrics: () => invoke<PipelineMetrics>("career_pipeline_metrics"),
  careerUpsertApplication: (input: {
    id?: string;
    company: string;
    roleTitle: string;
    status?: string;
    location?: string;
    url?: string;
  }) => invoke<string>("career_upsert_application", { input }),
  careerUpdateApplicationStatus: (id: string, status: string) =>
    invoke<void>("career_update_application_status", { id, status }),
  careerMoveApplication: (id: string, status: string, sortOrder?: number) =>
    invoke<void>("career_move_application", { id, status, sortOrder }),
  careerApplyComplete: (id: string) => invoke<void>("career_apply_complete", { id }),
  careerApplyBuildPayload: () =>
    invoke<{
      personal: {
        firstName: string;
        lastName: string;
        fullName: string;
        email: string;
        phone: string;
        linkedInUrl: string;
      };
      applicationProfile: {
        workAuthorization: {
          usAuthorized?: boolean | null;
          requiresSponsorshipNow?: boolean | null;
          requiresSponsorshipFuture?: boolean | null;
        };
      };
      platform: string;
    }>("career_apply_build_payload"),
  careerApplyInstallBridge: (applicationId: string) =>
    invoke<void>("career_apply_install_bridge", { applicationId }),
  careerApplyRunAutofill: (applicationId: string, url?: string) =>
    invoke<CareerApplyAutofillResult>("career_apply_run_autofill", {
      input: { applicationId, url: url ?? null },
    }),
  careerListPathEntries: () =>
    invoke<
      Array<{
        id: string;
        organization: string;
        roleTitle: string;
        startDate?: string | null;
        endDate?: string | null;
        summary: string;
        sortOrder: number;
        resumeDocumentId?: string | null;
      }>
    >("career_list_path_entries"),
  careerUpsertPathEntry: (input: {
    id?: string;
    organization: string;
    roleTitle: string;
    startDate?: string;
    endDate?: string;
    summary?: string;
  }) => invoke<string>("career_upsert_path_entry", { input }),
  careerDeletePathEntry: (id: string) => invoke<void>("career_delete_path_entry", { id }),
  careerListPathMilestones: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        title: string;
        status: string;
        dueAt?: string | null;
        notes: string;
        lane: string;
        sortOrder: number;
      }>
    >("career_list_path_milestones", { pathEntryId }),
  careerUpsertPathMilestone: (input: {
    id?: string;
    pathEntryId: string;
    title: string;
    status?: string;
    dueAt?: string;
    notes?: string;
    lane?: string;
  }) => invoke<string>("career_upsert_path_milestone", { input }),
  careerDeletePathMilestone: (id: string) =>
    invoke<void>("career_delete_path_milestone", { id }),
  careerListPathJournalEntries: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        occurredAt: string;
        title: string;
        body: string;
        mood: string;
        sortOrder: number;
      }>
    >("career_list_path_journal_entries", { pathEntryId }),
  careerUpsertPathJournalEntry: (input: {
    id?: string;
    pathEntryId: string;
    occurredAt: string;
    title?: string;
    body?: string;
    mood?: string;
  }) => invoke<string>("career_upsert_path_journal_entry", { input }),
  careerDeletePathJournalEntry: (id: string) =>
    invoke<void>("career_delete_path_journal_entry", { id }),
  careerListPathPromotions: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        title: string;
        effectiveAt?: string | null;
        notes: string;
        sortOrder: number;
      }>
    >("career_list_path_promotions", { pathEntryId }),
  careerUpsertPathPromotion: (input: {
    id?: string;
    pathEntryId: string;
    title: string;
    effectiveAt?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_path_promotion", { input }),
  careerDeletePathPromotion: (id: string) =>
    invoke<void>("career_delete_path_promotion", { id }),
  careerListPathPeople: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        name: string;
        roleTitle: string;
        relationship: string;
        notes: string;
        sortOrder: number;
      }>
    >("career_list_path_people", { pathEntryId }),
  careerUpsertPathPerson: (input: {
    id?: string;
    pathEntryId: string;
    name: string;
    roleTitle?: string;
    relationship?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_path_person", { input }),
  careerDeletePathPerson: (id: string) =>
    invoke<void>("career_delete_path_person", { id }),
  careerGetPathDecisionJournal: (pathEntryId: string) =>
    invoke<{
      pathEntryId: string;
      whyAccepted: string;
      alternatives: string;
      expectedBenefits: string;
      concerns: string;
      successCriteria: string;
      whyLeft: string;
      lessons: string;
      wouldDoDifferently: string;
      updatedAt?: string | null;
    }>("career_get_path_decision_journal", { pathEntryId }),
  careerUpsertPathDecisionJournal: (input: {
    pathEntryId: string;
    whyAccepted?: string;
    alternatives?: string;
    expectedBenefits?: string;
    concerns?: string;
    successCriteria?: string;
    whyLeft?: string;
    lessons?: string;
    wouldDoDifferently?: string;
  }) => invoke<void>("career_upsert_path_decision_journal", { input }),
  careerListPathBenefits: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        title: string;
        isActive: boolean;
        notes: string;
        sortOrder: number;
      }>
    >("career_list_path_benefits", { pathEntryId }),
  careerUpsertPathBenefit: (input: {
    id?: string;
    pathEntryId: string;
    title: string;
    isActive?: boolean;
    notes?: string;
  }) => invoke<string>("career_upsert_path_benefit", { input }),
  careerDeletePathBenefit: (id: string) =>
    invoke<void>("career_delete_path_benefit", { id }),
  careerListPathCompensation: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        kind: string;
        title: string;
        amount?: number | null;
        currency: string;
        cadence: string;
        notes: string;
        sortOrder: number;
      }>
    >("career_list_path_compensation", { pathEntryId }),
  careerUpsertPathCompensation: (input: {
    id?: string;
    pathEntryId: string;
    kind?: string;
    title: string;
    amount?: number;
    currency?: string;
    cadence?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_path_compensation", { input }),
  careerDeletePathCompensation: (id: string) =>
    invoke<void>("career_delete_path_compensation", { id }),
  careerGetPathEmploymentTerms: (pathEntryId: string) =>
    invoke<{
      pathEntryId: string;
      employmentType: string;
      workLocation: string;
      scheduleNotes: string;
      noticePeriod: string;
      otherTerms: string;
      updatedAt?: string | null;
    }>("career_get_path_employment_terms", { pathEntryId }),
  careerUpsertPathEmploymentTerms: (input: {
    pathEntryId: string;
    employmentType?: string;
    workLocation?: string;
    scheduleNotes?: string;
    noticePeriod?: string;
    otherTerms?: string;
  }) => invoke<void>("career_upsert_path_employment_terms", { input }),
  careerListSkills: () =>
    invoke<
      Array<{ id: string; name: string; evidenceCount: number; sortOrder: number }>
    >("career_list_skills"),
  careerUpsertSkill: (input: { id?: string; name: string }) =>
    invoke<string>("career_upsert_skill", { input }),
  careerDeleteSkill: (id: string) => invoke<void>("career_delete_skill", { id }),
  careerAddSkillEvidence: (input: {
    skillId: string;
    pathEntryId?: string;
    note?: string;
  }) => invoke<string>("career_add_skill_evidence", { input }),
  careerPathAchievementPipeline: (pathEntryId: string) =>
    invoke<{
      openRoadmapItems: number;
      doneMilestones: number;
      bragWins: number;
      activeBenefits: number;
      promotions: number;
      people: number;
      compensationItems: number;
    }>("career_path_achievement_pipeline", { pathEntryId }),
  careerListPathDocuments: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        pathEntryId: string;
        vaultDocId: string;
        note: string;
        title: string;
        category: string;
        hasFile: boolean;
      }>
    >("career_list_path_documents", { pathEntryId }),
  careerLinkPathDocument: (input: {
    pathEntryId: string;
    vaultDocId: string;
    note?: string;
  }) => invoke<string>("career_link_path_document", { input }),
  careerUnlinkPathDocument: (id: string) =>
    invoke<void>("career_unlink_path_document", { id }),
  careerGetRoleExpectation: (pathEntryId: string) =>
    invoke<{
      pathEntryId: string;
      summary: string;
      boxes: Array<{ id: string; title: string; body: string; sortOrder?: number }>;
      updatedAt?: string | null;
    }>("career_get_role_expectation", { pathEntryId }),
  careerSaveRoleExpectation: (input: {
    pathEntryId: string;
    summary?: string;
    boxes?: Array<{ id: string; title: string; body: string; sortOrder?: number }>;
  }) => invoke<void>("career_save_role_expectation", { input }),
  careerListPathRelationships: (pathEntryId: string) =>
    invoke<
      Array<{
        id: string;
        fromEntryId: string;
        toEntryId: string;
        kind: string;
        notes: string;
        createdAt: string;
        linkedEntryId: string;
        linkedOrganization: string;
        linkedRoleTitle: string;
        direction: string;
      }>
    >("career_list_path_relationships", { pathEntryId }),
  careerUpsertPathRelationship: (input: {
    id?: string;
    fromEntryId: string;
    toEntryId: string;
    kind?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_path_relationship", { input }),
  careerDeletePathRelationship: (id: string) =>
    invoke<void>("career_delete_path_relationship", { id }),
  careerSetPathResume: (pathEntryId: string, resumeDocumentId?: string | null) =>
    invoke<void>("career_set_path_resume", { pathEntryId, resumeDocumentId }),
  careerMergePathEntries: (fromId: string, toId: string) =>
    invoke<void>("career_merge_path_entries", { fromId, toId }),
  careerListPathGoals: (entryId?: string) =>
    invoke<
      Array<{
        id: string;
        entryId: string;
        title: string;
        category: string;
        cadence: string;
        targetDate?: string | null;
        notes: string;
        sortOrder: number;
      }>
    >("career_list_path_goals", { entryId: entryId ?? null }),
  careerUpsertPathGoal: (input: {
    id?: string;
    entryId: string;
    title: string;
    category?: string;
    cadence?: string;
    targetDate?: string;
    notes?: string;
    sortOrder?: number;
  }) => invoke<string>("career_upsert_path_goal", { input }),
  careerDeletePathGoal: (id: string) => invoke<void>("career_delete_path_goal", { id }),
  careerGetPathScenario: (entryId: string) =>
    invoke<{
      entryId: string;
      current: { title: string; notes: string };
      alternate: { title: string; notes: string };
    } | null>("career_get_path_scenario", { entryId }),
  careerSavePathScenario: (input: {
    entryId: string;
    current: { title: string; notes: string };
    alternate: { title: string; notes: string };
  }) => invoke<void>("career_save_path_scenario", { input }),
  careerGetPathDisclosure: (entryId: string) =>
    invoke<{ entryId: string; comp: boolean; benefits: boolean; equity: boolean } | null>(
      "career_get_path_disclosure",
      { entryId },
    ),
  careerSavePathDisclosure: (input: {
    entryId: string;
    comp: boolean;
    benefits: boolean;
    equity: boolean;
  }) => invoke<void>("career_save_path_disclosure", { input }),
  careerMigratePathingSettings: () => invoke<number>("career_migrate_pathing_settings"),
  careerListEvents: (applicationId?: string) =>
    invoke<
      Array<{
        id: string;
        applicationId?: string | null;
        title: string;
        occursAt: string;
        kind: string;
        notes: string;
      }>
    >("career_list_events", { applicationId }),
  careerUpsertEvent: (input: {
    id?: string;
    applicationId: string;
    title: string;
    occursAt: string;
    kind?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_event", { input }),
  careerDeleteEvent: (id: string) => invoke<void>("career_delete_event", { id }),
  careerDeleteApplication: (id: string) => invoke<void>("career_delete_application", { id }),
  careerResumeKeywordMatch: (input: { resumeText: string; jobText: string }) =>
    invoke<{ score: number; matched: string[]; missing: string[] }>(
      "career_resume_keyword_match",
      { input },
    ),
  careerListResumeProfiles: () => invoke<ResumeProfile[]>("career_list_resume_profiles"),
  careerUpsertResumeProfile: (input: {
    vaultDocId: string;
    targetRole?: string;
    targetCompany?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_resume_profile", { input }),
  careerResumeMetrics: () => invoke<ResumeMetrics>("career_resume_metrics"),
  careerListJobPostings: () =>
    invoke<
      Array<{
        id: string;
        company: string;
        title: string;
        location: string;
        url: string;
        postedAt?: string | null;
        trackedApplicationId?: string | null;
      }>
    >("career_list_job_postings"),
  careerUpsertJobPosting: (input: {
    company: string;
    title: string;
    location?: string;
    url?: string;
    postedAt?: string;
  }) => invoke<string>("career_upsert_job_posting", { input }),
  careerDeleteJobPosting: (id: string) => invoke<void>("career_delete_job_posting", { id }),
  careerTrackJobPosting: (id: string) => invoke<string>("career_track_job_posting", { id }),
  careerImportJobFromUrl: (url: string) =>
    invoke<string>("career_import_job_from_url", { url }),
  careerSyncJobBoards: (input?: { sources?: string[] }) =>
    invoke<{
      imported: number;
      updated: number;
      skipped: number;
      fetched: number;
      sources: Array<{
        source: string;
        label: string;
        imported: number;
        updated: number;
        skipped: number;
        fetched: number;
        error?: string | null;
      }>;
    }>("career_sync_job_boards", { input: input ?? null }),
  careerListJobBoardCompanies: () =>
    invoke<
      Array<{
        id: string;
        displayName: string;
        careersUrl: string;
        platform: string;
        enabled: boolean;
        sortOrder: number;
        lastSyncedAt?: string | null;
      }>
    >("career_list_job_board_companies"),
  careerUpsertJobBoardCompany: (input: {
    id?: string;
    displayName: string;
    careersUrl: string;
    enabled?: boolean;
  }) => invoke<string>("career_upsert_job_board_company", { input }),
  careerDeleteJobBoardCompany: (id: string) =>
    invoke<void>("career_delete_job_board_company", { id }),
  careerSyncJobBoardCompanies: (input?: { companyIds?: string[] }) =>
    invoke<{
      imported: number;
      updated: number;
      skipped: number;
      fetched: number;
      sources: Array<{
        source: string;
        label: string;
        imported: number;
        updated: number;
        skipped: number;
        fetched: number;
        error?: string | null;
      }>;
    }>("career_sync_job_board_companies", { input: input ?? null }),
  careerListSmartBoards: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        companyIds: string[];
        filter: {
          smartQuery?: string;
          keywords?: string[];
          requiredSkills?: string[];
          jobTypeKeywords?: string[];
          scheduleKeywords?: string[];
          locationKeywords?: string[];
          minMatchScore?: number | null;
          daysPostedFilter?: string;
          hideOnBoard?: boolean;
          showClosed?: boolean;
          closingSoonOnly?: boolean;
          remoteOnly?: boolean;
        };
        sortOrder: number;
        createdAt: string;
        updatedAt: string;
      }>
    >("career_list_smart_boards"),
  careerUpsertSmartBoard: (input: {
    id?: string;
    name: string;
    companyIds: string[];
    filter?: {
      smartQuery?: string;
      keywords?: string[];
      requiredSkills?: string[];
      jobTypeKeywords?: string[];
      scheduleKeywords?: string[];
      locationKeywords?: string[];
      minMatchScore?: number | null;
      daysPostedFilter?: string;
      hideOnBoard?: boolean;
      showClosed?: boolean;
      closingSoonOnly?: boolean;
      remoteOnly?: boolean;
    };
    sortOrder?: number;
  }) => invoke<string>("career_upsert_smart_board", { input }),
  careerDeleteSmartBoard: (id: string) => invoke<void>("career_delete_smart_board", { id }),
  careerQuerySmartBoardPostings: (input: { smartBoardId: string }) =>
    invoke<
      Array<{
        id: string;
        company: string;
        title: string;
        location: string;
        url: string;
        postedAt?: string | null;
        trackedApplicationId?: string | null;
      }>
    >("career_query_smart_board_postings", { input }),
  careerListBragEntries: () =>
    invoke<
      Array<{
        id: string;
        title: string;
        occurredAt?: string | null;
        summary: string;
        evidenceNote: string;
        sortOrder: number;
      }>
    >("career_list_brag_entries"),
  careerUpsertBragEntry: (input: {
    id?: string;
    title: string;
    occurredAt?: string;
    summary?: string;
    evidenceNote?: string;
  }) => invoke<string>("career_upsert_brag_entry", { input }),
  careerDeleteBragEntry: (id: string) => invoke<void>("career_delete_brag_entry", { id }),
  careerListNetworkContacts: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        organization: string;
        roleTitle: string;
        email: string;
        lastContactAt?: string | null;
        notes: string;
        sortOrder: number;
      }>
    >("career_list_network_contacts"),
  careerUpsertNetworkContact: (input: {
    id?: string;
    name: string;
    organization?: string;
    roleTitle?: string;
    email?: string;
    lastContactAt?: string;
    notes?: string;
  }) => invoke<string>("career_upsert_network_contact", { input }),
  careerDeleteNetworkContact: (id: string) =>
    invoke<void>("career_delete_network_contact", { id }),
  careerListInterviewPrep: () =>
    invoke<
      Array<{
        id: string;
        applicationId?: string | null;
        company: string;
        roleTitle: string;
        scheduledAt?: string | null;
        status: string;
        notes: string;
        questions: string;
        sortOrder: number;
      }>
    >("career_list_interview_prep"),
  careerUpsertInterviewPrep: (input: {
    id?: string;
    applicationId?: string;
    company: string;
    roleTitle: string;
    scheduledAt?: string;
    status?: string;
    notes?: string;
    questions?: string;
  }) => invoke<string>("career_upsert_interview_prep", { input }),
  careerDeleteInterviewPrep: (id: string) =>
    invoke<void>("career_delete_interview_prep", { id }),
  careerCompileTypstPdf: (source: string, pdfPath: string) =>
    invoke<void>("career_compile_typst_pdf", { source, pdfPath }),
  catalogListUniversities: () =>
    invoke<
      Array<{ id: string; name: string; shortName: string; domain: string; isActive: boolean }>
    >("catalog_list_universities"),
  catalogListDepartments: (universityId: string) =>
    invoke<
      Array<{
        id: string;
        universityId: string;
        name: string;
        code: string;
        courseCount: number;
      }>
    >("catalog_list_departments", { universityId }),
  catalogListDepartmentCourses: (departmentId: string) =>
    invoke<
      Array<{
        id: string;
        code: string;
        title: string;
        credits?: number;
        description: string;
      }>
    >("catalog_list_department_courses", { departmentId }),
  catalogSearchCourses: (query: string) =>
    invoke<
      Array<{
        id: string;
        code: string;
        title: string;
        credits?: number;
        description: string;
      }>
    >("catalog_search_courses", { query }),
  catalogIngestUrl: (input: { url: string; universityId?: string }) =>
    invoke<{
      imported: number;
      skipped: number;
      universityId: string;
      sourceTitle: string;
    }>("catalog_ingest_url", { input }),
  catalogGetSyncDiagnostics: () =>
    invoke<{
      universities: Array<{
        id: string;
        name: string;
        catalogBaseUrl: string;
        courseCount: number;
        lastSyncedAt?: string | null;
        lastImported: number;
        lastSkipped: number;
        lastSignature?: string | null;
        lastError?: string | null;
        unchanged: boolean;
      }>;
    }>("catalog_get_sync_diagnostics"),
  catalogSyncUniversity: (input: { universityId: string; force?: boolean }) =>
    invoke<{
      universityId: string;
      imported: number;
      skipped: number;
      unchanged: boolean;
      sourceTitle: string;
      syncedAt: string;
    }>("catalog_sync_university", { input }),
  catalogEmbeddingStats: () =>
    invoke<{ indexedCount: number; courseCount: number; modelTag: string }>(
      "catalog_embedding_stats",
    ),
  catalogReindexEmbeddings: (limit?: number) =>
    invoke<{ indexed: number; skipped: number; modelTag: string }>(
      "catalog_reindex_embeddings",
      { limit: limit ?? null },
    ),
  catalogSemanticSearch: (query: string, limit?: number) =>
    invoke<
      Array<{
        id: string;
        code: string;
        title: string;
        description: string;
        score: number;
      }>
    >("catalog_semantic_search", { query, limit: limit ?? null }),
  documentsListVault: () =>
    invoke<
      Array<{
        id: string;
        title: string;
        category: string;
        mimeType: string;
        fileSize: number;
        updatedAt: string;
        relativePath: string;
        hasFile: boolean;
        isStarred: boolean;
        parentFolderId: string | null;
        isFolder: boolean;
      }>
    >("documents_list_vault"),
  documentsUpsertVaultDoc: (input: {
    title: string;
    category?: string;
    mimeType?: string;
    parentFolderId?: string | null;
  }) => invoke<string>("documents_upsert_vault_doc", { input }),
  documentsImportFile: (input: {
    sourcePath: string;
    category?: string;
    title?: string;
    parentFolderId?: string | null;
  }) => invoke<string>("documents_import_file", { input }),
  documentsCreateFolder: (name: string, parentFolderId?: string | null) =>
    invoke<string>("documents_create_folder", { name, parentFolderId }),
  documentsMoveVaultItem: (id: string, parentFolderId?: string | null) =>
    invoke<void>("documents_move_vault_item", { id, parentFolderId }),
  documentsRenameVaultItem: (id: string, title: string) =>
    invoke<void>("documents_rename_vault_item", { id, title }),
  documentsQuickLook: (id: string) =>
    invoke<{ opened: boolean; path: string | null }>("documents_quick_look", { id }),
  documentsQuickLookPreview: (id: string) =>
    invoke<{
      mimeType: string;
      base64Preview?: string | null;
      tempPath?: string | null;
      isEncrypted: boolean;
    }>("documents_quick_look_preview", { id }),
  documentsResolvePath: (id: string) => invoke<string | null>("documents_resolve_path", { id }),
  documentsDeleteVaultDoc: (id: string, cascade?: boolean) =>
    invoke<void>("documents_delete_vault_doc", { id, cascade: cascade ?? null }),
  documentsDeleteFolderCascade: (id: string) =>
    invoke<void>("documents_delete_folder_cascade", { id }),
  documentsUpdateVaultDoc: (input: {
    id: string;
    title?: string;
    category?: string;
    isStarred?: boolean;
  }) =>
    invoke<void>("documents_update_vault_doc", { input }),
  documentsListWatchedFolders: () =>
    invoke<Array<{ id: string; path: string; addedAt: string }>>(
      "documents_list_watched_folders",
    ),
  documentsUpsertWatchedFolder: (input: { id?: string; path: string }) =>
    invoke<string>("documents_upsert_watched_folder", { input }),
  documentsDeleteWatchedFolder: (id: string) =>
    invoke<void>("documents_delete_watched_folder", { id }),
  documentsWatchdogStatus: () =>
    invoke<{
      isWatching: boolean;
      watchedCount: number;
      lastDetectedPath: string | null;
      lastDetectedAt: string | null;
    }>("documents_watchdog_status"),
  backgroundWeeklyDigestPreview: () =>
    invoke<{
      title: string;
      body: string;
      openTasks: number;
      upcomingEvents: number;
      staleVaultCount: number;
    }>("background_weekly_digest_preview"),
  financeDashboardSummary: () => invoke<FinanceDashboardSummary>("finance_dashboard_summary"),
  financeListAccounts: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        institution: string;
        accountType: string;
        balance: number;
        currency: string;
      }>
    >("finance_list_accounts"),
  financeListTransactions: (accountId?: string, limit?: number) =>
    invoke<
      Array<{
        id: string;
        accountId: string;
        accountName: string;
        postedAt: string;
        amount: number;
        payee: string;
        category: string;
        memo: string;
      }>
    >("finance_list_transactions", {
      accountId: accountId ?? null,
      limit: limit ?? null,
    }),
  financeListBudgets: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        category: string;
        amount: number;
        period: string;
      }>
    >("finance_list_budgets"),
  financeListGoals: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        targetAmount: number;
        currentAmount: number;
        deadline?: string | null;
        notes: string;
        sortOrder: number;
      }>
    >("finance_list_goals"),
  financeListInventoryItems: () =>
    invoke<
      Array<{
        id: string;
        name: string;
        category: string;
        purchaseDate?: string | null;
        value: number;
        notes: string;
        sortOrder: number;
      }>
    >("finance_list_inventory_items"),
  financeListReceipts: () =>
    invoke<
      Array<{
        id: string;
        title: string;
        merchant: string;
        amount: number;
        purchasedAt?: string | null;
        category: string;
        notes: string;
        vaultDocId?: string | null;
        sortOrder: number;
      }>
    >("finance_list_receipts"),
  financeListHoldings: () => invoke<FinanceHolding[]>("finance_list_holdings"),
  financeListCategories: () =>
    invoke<Array<{ id: string; name: string; kind: string; sortOrder: number }>>(
      "finance_list_categories",
    ),
  financeListDue: () =>
    invoke<
      Array<{ id: string; person: string; amount: number; dueAt: string; isPaid: boolean; notes: string }>
    >("finance_list_due"),
  financeListRecurring: () =>
    invoke<
      Array<{
        id: string;
        accountId?: string | null;
        accountName: string;
        title: string;
        amount: number;
        cadence: string;
        nextDue?: string | null;
        category: string;
      }>
    >("finance_list_recurring"),
  financeUpsertRecurring: (input: {
    id?: string;
    accountId?: string | null;
    title: string;
    amount: number;
    cadence?: string;
    nextDue?: string | null;
    category?: string;
  }) =>
    invoke<string>("finance_upsert_recurring", {
      input: {
        id: input.id ?? null,
        accountId: input.accountId ?? null,
        title: input.title,
        amount: input.amount,
        cadence: input.cadence ?? null,
        nextDue: input.nextDue ?? null,
        category: input.category ?? null,
      },
    }),
  financeRunRecurringDue: () =>
    invoke<{ created: number; skipped: number }>("finance_run_recurring_due"),
  financeMarkDuePaid: (id: string) => invoke<void>("finance_mark_due_paid", { id }),
  financeUpsertHolding: (input: {
    id?: string;
    assetType: string;
    symbol: string;
    name?: string;
    quantity: number;
    pricePerUnit: number;
  }) => invoke<string>("finance_upsert_holding", { input }),
  financeDeleteHolding: (id: string) => invoke<void>("finance_delete_holding", { id }),
  financeUpsertAccount: (input: {
    id?: string;
    name: string;
    institution?: string;
    accountType?: string;
    balance?: number;
  }) => invoke<string>("finance_upsert_account", { input }),
  financeUpsertTransaction: (input: {
    accountId: string;
    amount: number;
    payee: string;
    category?: string;
    memo?: string;
    postedAt?: string;
  }) => invoke<string>("finance_upsert_transaction", { input }),
  financeUpsertBudget: (input: {
    name: string;
    category?: string;
    amount: number;
    period?: string;
  }) => invoke<string>("finance_upsert_budget", { input }),
  financeUpsertGoal: (input: {
    id?: string;
    name: string;
    targetAmount: number;
    currentAmount?: number;
    deadline?: string | null;
    notes?: string;
    sortOrder?: number;
  }) => invoke<string>("finance_upsert_goal", { input }),
  financeUpsertInventoryItem: (input: {
    id?: string;
    name: string;
    category?: string;
    purchaseDate?: string | null;
    value?: number;
    notes?: string;
    sortOrder?: number;
  }) => invoke<string>("finance_upsert_inventory_item", { input }),
  financeUpsertReceipt: (input: {
    id?: string;
    title: string;
    merchant?: string;
    amount?: number;
    purchasedAt?: string | null;
    category?: string;
    notes?: string;
    vaultDocId?: string | null;
    sortOrder?: number;
  }) => invoke<string>("finance_upsert_receipt", { input }),
  financeImportTransactionsCsv: (input: { accountId: string; csvText: string }) =>
    invoke<number>("finance_import_transactions_csv", { input }),
  financeImportTransactionsCsvPath: (accountId: string, path: string) =>
    invoke<number>("finance_import_transactions_csv_path", { accountId, path }),
  financeDeleteTransaction: (id: string) => invoke<void>("finance_delete_transaction", { id }),
  financeDeleteAccount: (id: string) => invoke<void>("finance_delete_account", { id }),
  financeDeleteBudget: (id: string) => invoke<void>("finance_delete_budget", { id }),
  financeDeleteGoal: (id: string) => invoke<void>("finance_delete_goal", { id }),
  financeDeleteInventoryItem: (id: string) =>
    invoke<void>("finance_delete_inventory_item", { id }),
  financeDeleteReceipt: (id: string) => invoke<void>("finance_delete_receipt", { id }),
  financeExportTransactionsCsv: (accountId?: string) =>
    invoke<string>("finance_export_transactions_csv", { accountId: accountId ?? null }),
  financeExportTransactionsCsvPath: (path: string, accountId?: string) =>
    invoke<{ path: string; rowCount: number }>("finance_export_transactions_csv_path", {
      path,
      accountId: accountId ?? null,
    }),
  financeSyncCoinbase: () =>
    invoke<{ accountsUpdated: number; holdingsUpdated: number; error?: string | null }>(
      "finance_sync_coinbase",
    ),
  profileGetIdentity: () => invoke<ProfileIdentity>("profile_get_identity"),
  profileListExperiences: () =>
    invoke<
      Array<{
        id: string;
        title: string;
        organization: string;
        startDate?: string;
        endDate?: string;
        summary: string;
      }>
    >("profile_list_experiences"),
  profileUpsertIdentity: (input: {
    fullName: string;
    email?: string;
    universityName?: string;
    major?: string;
    graduationYear?: number;
  }) => invoke<string>("profile_upsert_identity", { input }),
  profileUpsertExperience: (input: {
    title: string;
    organization: string;
    summary?: string;
    startDate?: string;
    endDate?: string;
  }) => invoke<string>("profile_upsert_experience", { input }),
  profileListAchievements: () =>
    invoke<Array<{ id: string; title: string; issuer: string; notes: string }>>(
      "profile_list_achievements",
    ),
  profileUpsertAchievement: (input: { title: string; issuer?: string; notes?: string }) =>
    invoke<string>("profile_upsert_achievement", {
      title: input.title,
      issuer: input.issuer ?? null,
      notes: input.notes ?? null,
    }),
  profileDeleteExperience: (id: string) => invoke<void>("profile_delete_experience", { id }),
  profileDeleteAchievement: (id: string) => invoke<void>("profile_delete_achievement", { id }),
  syllabusExtractAssignments: (text: string) =>
    invoke<{
      assignments: Array<{ title: string; dueHint?: string | null; line: string }>;
      courseHint?: string | null;
      rawLineCount: number;
    }>("syllabus_extract_assignments", { input: { text } }),
  syllabusAnalyzeText: (text: string) =>
    invoke<import("@/modules/assistant/syllabus/types").SyllabusAnalyzeResult>(
      "syllabus_analyze_text",
      { input: { text } },
    ),
  syllabusAnalyzePdfPath: (path: string) =>
    invoke<import("@/modules/assistant/syllabus/types").SyllabusAnalyzeResult>(
      "syllabus_analyze_pdf_path",
      { input: { path } },
    ),
  syllabusResolvePdfPath: (input: { vaultDocId?: string | null; path?: string | null }) =>
    invoke<string | null>("syllabus_resolve_pdf_path", { input }),
  settingsGet: () => invoke<{ values: Record<string, string> }>("settings_get"),
  settingsSet: (key: string, value: string) => invoke<void>("settings_set", { key, value }),
  securityIsLocked: () => invoke<boolean>("security_is_locked"),
  securityLock: () =>
    invoke<{ locked: boolean; biometricAvailable: boolean; platform: string }>("security_lock"),
  securityUnlock: (reason: string) =>
    invoke<{ locked: boolean; biometricAvailable: boolean; platform: string }>("security_unlock", {
      reason,
    }),
  securityBiometricAvailable: () => invoke<boolean>("security_biometric_available"),
  aiRuntimeStatus: () => invoke<AiRuntimeStatus>("ai_runtime_status"),
  aiPing: () => invoke<AiPingResult>("ai_ping"),
  aiEmbedTexts: (texts: string[]) => invoke<number[][]>("ai_embed_texts", { texts }),
  aiChatCompletion: (messages: Array<{ role: string; content: string }>, maxTokens?: number) =>
    invoke<{ content: string; backend: string }>("ai_chat_completion", {
      request: { messages, maxTokens },
    }),
  assistantTurn: (input: {
    messages: Array<{ role: string; content: string }>;
    agentRole?: string;
    attachmentIds?: string[];
    webMemory?: string;
  }) =>
    invoke<{
      content: string;
      toolTrace: Array<{ name: string; summary: string }>;
      sources: Array<{ title: string; detail: string }>;
      pendingAction?: {
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
      } | null;
    }>("assistant_turn", { request: input }),
  assistantCancelTurn: () => invoke<boolean>("assistant_cancel_turn"),
  assistantListTools: () =>
    invoke<
      Array<{
        name: string;
        description: string;
        category: string;
        keywords: string[];
        roleAffinity?: string | null;
      }>
    >("assistant_list_tools"),
  aiSemanticSearchCatalog: (query: string, limit?: number) =>
    invoke<
      Array<{
        id: string;
        code: string;
        title: string;
        description: string;
        score: number;
      }>
    >("ai_semantic_search_catalog", { query, limit: limit ?? null }),
  aiSemanticSearchVault: (query: string, limit?: number) =>
    invoke<
      Array<{
        id: string;
        code: string;
        title: string;
        description: string;
        score: number;
      }>
    >("ai_semantic_search_vault", { query, limit: limit ?? null }),
  backupCreate: () =>
    invoke<{ name: string; path: string; sizeBytes: number; modifiedAt: string }>("backup_create"),
  backupList: () =>
    invoke<Array<{ name: string; path: string; sizeBytes: number; modifiedAt: string }>>(
      "backup_list",
    ),
  backupRestore: (path: string) =>
    invoke<{ pendingPath: string; safetyBackup?: string | null; needsRestart: boolean }>(
      "backup_restore",
      { path },
    ),
  scraperFetchHtmlPreview: (url: string) =>
    invoke<{ url: string; title: string; textExcerpt: string; status: number }>(
      "scraper_fetch_html_preview",
      { url },
    ),
  demoSeedSampleData: () => invoke<void>("demo_seed_sample_data"),
  lmsListPortals: () =>
    invoke<Array<{ id: string; name: string; url: string; notes: string; sortOrder: number }>>(
      "lms_list_portals",
    ),
  lmsUpsertPortal: (input: { id?: string; name: string; url: string; notes?: string }) =>
    invoke<string>("lms_upsert_portal", { input }),
  lmsDeletePortal: (id: string) => invoke<void>("lms_delete_portal", { id }),
  lmsImportItems: (
    items: Array<{
      kind: string;
      title: string;
      dueAt?: string;
      courseCode?: string;
      notes?: string;
      lmsItemId?: string;
      portalId?: string;
    }>,
  ) =>
    invoke<{ tasksCreated: number; eventsCreated: number; skipped: number }>("lms_import_items", {
      items,
    }),
  lmsExtractPortalPage: (portalId: string) =>
    invoke<string>("lms_extract_portal_page", { portalId }),
  lmsPortalNavigate: (portalId: string, action: "back" | "forward" | "reload") =>
    invoke<void>("lms_portal_navigate", { portalId, action }),
  lmsPortalFind: (portalId: string, query: string, forward?: boolean) =>
    invoke<{ found: boolean; matchCount: number }>("lms_portal_find", {
      portalId,
      query,
      forward: forward ?? true,
    }),
  lmsPortalCredentialsGet: (portalId: string) =>
    invoke<{ username: string; hasPassword: boolean }>("lms_portal_credentials_get", {
      portalId,
    }),
  lmsPortalCredentialsSet: (input: {
    portalId: string;
    username: string;
    password: string;
  }) => invoke<void>("lms_portal_credentials_set", { input }),
  lmsPortalCredentialsClear: (portalId: string) =>
    invoke<void>("lms_portal_credentials_clear", { portalId }),
  lmsPortalInstallBridge: (portalId: string) =>
    invoke<void>("lms_portal_install_bridge", { portalId }),
  lmsPortalAutofillLogin: (portalId: string) =>
    invoke<{ filledUsername: boolean; filledPassword: boolean }>("lms_portal_autofill_login", {
      portalId,
    }),
  discoveryListInstitutions: (query?: string, limit?: number) =>
    invoke<
      Array<{
        id: string;
        name: string;
        unitId?: string | null;
        state: string;
        city: string;
        website: string;
        isSaved: boolean;
        admitRate?: number | null;
      }>
    >("discovery_list_institutions", {
      query: query ?? null,
      limit: limit ?? null,
    }),
  discoveryGetProfile: (institutionId: string) =>
    invoke<{
      institution: {
        id: string;
        name: string;
        unitId?: string | null;
        state: string;
        city: string;
        website: string;
        isSaved: boolean;
      };
      cds?: {
        unitId: string;
        academicYear: number;
        sourceUrl: string;
        applicants?: number | null;
        admits?: number | null;
        enrolled?: number | null;
        admitRate?: number | null;
        yield?: number | null;
        factorImportance: Record<string, string>;
        testPolicyNote?: string | null;
        satEbrw25?: number | null;
        satEbrw75?: number | null;
        satMath25?: number | null;
        satMath75?: number | null;
        actComposite25?: number | null;
        actComposite75?: number | null;
        percentSubmittingSat?: number | null;
        percentSubmittingAct?: number | null;
        hsGpaAverage?: number | null;
        hsGpaDistribution: Record<string, number>;
        earlyDecisionApplicants?: number | null;
        earlyDecisionAdmits?: number | null;
      } | null;
    }>("discovery_get_profile", { institutionId }),
  discoveryGetCds: (unitId: string) =>
    invoke<{
      unitId: string;
      academicYear: number;
      sourceUrl: string;
      applicants?: number | null;
      admits?: number | null;
      enrolled?: number | null;
      admitRate?: number | null;
      yield?: number | null;
      factorImportance: Record<string, string>;
      testPolicyNote?: string | null;
      satEbrw25?: number | null;
      satEbrw75?: number | null;
      satMath25?: number | null;
      satMath75?: number | null;
      actComposite25?: number | null;
      actComposite75?: number | null;
      percentSubmittingSat?: number | null;
      percentSubmittingAct?: number | null;
      hsGpaAverage?: number | null;
      hsGpaDistribution: Record<string, number>;
      earlyDecisionApplicants?: number | null;
      earlyDecisionAdmits?: number | null;
    } | null>("discovery_get_cds", { unitId }),
  discoveryUpsertInstitution: (input: {
    name: string;
    city?: string;
    stateCode?: string;
    website?: string;
  }) =>
    invoke<string>("discovery_upsert_institution", {
      name: input.name,
      city: input.city ?? null,
      stateCode: input.stateCode ?? null,
      website: input.website ?? null,
    }),
  discoveryUpdateInstitution: (input: { id: string; isSaved?: boolean }) =>
    invoke<void>("discovery_update_institution", {
      input: {
        id: input.id,
        isSaved: input.isSaved ?? null,
      },
    }),
  discoveryDeleteInstitution: (id: string) => invoke<void>("discovery_delete_institution", { id }),
  discoverySyncFederalData: () =>
    invoke<{ synced: number; skipped: number; errors: string[] }>("discovery_sync_federal_data"),
  transferListEquivalencies: () =>
    invoke<
      Array<{
        id: string;
        sourceSchool: string;
        sourceCode: string;
        targetCode: string;
        credits?: number | null;
        notes: string;
        proofDocumentId?: string | null;
      }>
    >("transfer_list_equivalencies"),
  transferUpsertEquivalency: (input: {
    sourceSchool: string;
    sourceCode: string;
    targetCode: string;
    credits?: number;
    notes?: string;
  }) => invoke<string>("transfer_upsert_equivalency", { input }),
  transferImportEquivalencies: (
    rows: Array<{
      sourceSchool: string;
      sourceCode: string;
      targetCode: string;
      credits?: number;
      notes?: string;
    }>,
  ) =>
    invoke<{ imported: number; skipped: number }>("transfer_import_equivalencies", { rows }),
  transferDeleteEquivalency: (id: string) => invoke<void>("transfer_delete_equivalency", { id }),
  transferLinkProofDocument: (equivalencyId: string, vaultDocumentId: string | null) =>
    invoke<void>("transfer_link_proof_document", { equivalencyId, vaultDocumentId }),
  transferImportCommunityJson: (jsonText: string) =>
    invoke<{ imported: number; skipped: number }>("transfer_import_community_json", { jsonText }),
  transferImportAssist: (input: {
    sourceSchoolId: string;
    targetSchoolId: string;
    mode?: "fixture" | "live";
  }) =>
    invoke<{ imported: number; skipped: number }>("transfer_import_assist", { input }),
  calendarListFocusBlocks: () =>
    invoke<Array<{ id: string; title: string; durationMinutes: number; sortOrder: number }>>(
      "calendar_list_focus_blocks",
    ),
  calendarUpsertFocusBlock: (input: {
    id?: string;
    title: string;
    durationMinutes?: number;
    sortOrder?: number;
  }) => invoke<string>("calendar_upsert_focus_block", { input }),
  calendarDeleteFocusBlock: (id: string) => invoke<void>("calendar_delete_focus_block", { id }),
};
