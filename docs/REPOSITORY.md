# Repository guide

> Every path tracked in git is listed here with its purpose.
> Regenerate: `python3 scripts/generate-repository-index.py --write`

For module-level architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Root files

| File | Purpose |
|------|---------|
| `.gitignore` | Git ignore rules for build artifacts, secrets, and local editor state. |
| `.gitleaks.toml` | Secret scanning configuration for CI and local gitleaks runs. |
| `Config.xcconfig` | Xcode build configuration; includes Secrets.xcconfig for local keys. |
| `Inspection` | SwiftLint/static analysis configuration or inspection profile. |
| `LICENSE` | MIT license for project source code. |
| `README.md` | Product landing page and link hub for the repository. |
| `Secrets.xcconfig.example` | Template for local-only API keys and OAuth client IDs. |
| `toolbar-health-report.json` | Generated toolbar architecture health report artifact. |

## College

Main macOS app target — SwiftUI views, persistence, and feature modules.

### `College/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `College/College.entitlements` | App or extension bundle configuration. |
| `College/Info.plist` | App or extension bundle configuration. |
| `College/Localizable.xcstrings` | Localized string catalog. |

### `College/App/`

Launch shell, navigation, onboarding, menu bar, and app coordinators.

| File | Purpose |
|------|---------|
| `College/App/ActivePageFocusedValue.swift` | App module — ActivePageFocusedValueKey. |
| `College/App/AppActivityCoordinator.swift` | App module — AppActivityCoordinator. |
| `College/App/AppCompatibility.swift` | App module — PlannerMenuCommands. |
| `College/App/AppContainer.swift` | Window-scoped composition root (ADR 005). |
| `College/App/AppHeaderView.swift` | Swift source — AppHeaderView. |
| `College/App/AppModels.swift` | App module — Course. |
| `College/App/AppleSiliconRequiredView.swift` | App module — AppleSiliconRequiredView. |
| `College/App/AskCollegeCoordinator.swift` | App module — AskCollegeCoordinator. |
| `College/App/AutosaveNames.swift` | App module — AutosaveNames. |
| `College/App/BackgroundTaskCompliance.swift` | App module — Report. |
| `College/App/CalendarMenuBarSummary.swift` | App module — CalendarMenuBarSummary. |
| `College/App/CatalogMenuBarProgressController.swift` | App module — CatalogMenuBarProgressController. |
| `College/App/CatalogMenuBarProgressNotifier.swift` | App module — CatalogMenuBarProgressNotifier. |
| `College/App/CollegeApp.swift` | App module — CollegeApp. |
| `College/App/CollegeAppDelegate.swift` | App module — CollegeAppDelegate. |
| `College/App/CollegeKeyboardShortcuts.swift` | App module — CollegeKeyboardShortcuts. |
| `College/App/CollegeMenuBarRoot.swift` | App module — CollegeMenuBarSectionHeader. |
| `College/App/CollegeMenuBarStatusModel.swift` | App module — ProgressPayload. |
| `College/App/CollegeTestRuntime.swift` | App module — CollegeTestRuntime. |
| `College/App/ContentView.swift` | App module — ContentView. |
| `College/App/LMSPortalConfiguration.swift` | App module — LMSProvider. |
| `College/App/LaunchBootstrapCache.swift` | App module — LaunchBootstrapCache. |
| `College/App/LaunchDependencyManifest.json` | Test fixture or documentation artifact. |
| `College/App/LaunchPreloadCoordinator.swift` | App module — FeaturePreloadDescriptor. |
| `College/App/LaunchPreloadView.swift` | App module — LaunchPreloadView. |
| `College/App/LaunchShellPagePersistence.swift` | App module — LaunchShellPagePersistence. |
| `College/App/LaunchStartupBudget.swift` | App module — Lane. |
| `College/App/MainContentSignals.swift` | App module — MainContentReadyPreferenceKey. |
| `College/App/MainWindowToolbar.swift` | Sole activePage router for main window toolbar (ADR 001 → ADR 003 registry). |
| `College/App/ModalCoordinator.swift` | App module — CourseEditSelection. |
| `College/App/NavigationSplitChromeCoordinator.swift` | App module — NavigationSplitChromeCoordinator. |
| `College/App/OnboardingPreferenceBridge.swift` | App module — OnboardingPreferenceBridge. |
| `College/App/OnboardingRootView.swift` | App module — OnboardingAcademicDraft. |
| `College/App/PlannerMenuNotifications.swift` | App module — MacPreferencesWindow. |
| `College/App/SessionTerminationTracker.swift` | App module — SessionTerminationTracker. |
| `College/App/SidebarView.swift` | App module — SidebarView. |
| `College/App/SplitViewAutosaveNameBridge.swift` | App module — SplitViewAutosaveNameBridge. |
| `College/App/StartupPhase.swift` | App module — StartupPhase. |
| `College/App/UITestLaunchFlags.swift` | App module — UITestLaunchFlags. |
| `College/App/UITestPersistenceSeeder.swift` | App module — UITestPersistenceSeeder. |
| `College/App/WebShortcutStore.swift` | App module — WebShortcut. |

### `College/App/Toolbar/`

Window-scoped toolbar providers and dispatch for each app page.

| File | Purpose |
|------|---------|
| `College/App/Toolbar/AcademicsToolbarContent.swift` | Swift source — AcademicsToolbarContent. |
| `College/App/Toolbar/AppPageToolbarMetadata.swift` | Static registry for architecture tests — every AppPage maps to toolbar content. |
| `College/App/Toolbar/AppToolbarStore.swift` | Cross-tab toolbar state only (ADR 001). Never page-specific display fields. |
| `College/App/Toolbar/AppToolbarViews.swift` | Shared SwiftUI toolbar chrome views (no AppKit). |
| `College/App/Toolbar/CalendarToolbarContent.swift` | Swift source — CalendarToolbarContent. |
| `College/App/Toolbar/CareerToolbarContent.swift` | Swift source — CareerToolbarContent. |
| `College/App/Toolbar/CrossTabToolbarState.swift` | Type-level boundary for cross-tab toolbar store (ADR 001). |
| `College/App/Toolbar/ToolbarAction.swift` | Versioned toolbar action API surface with per-feature ownership. |
| `College/App/Toolbar/ToolbarDispatcher.swift` | Window-scoped scoped toolbar action dispatch (ADR 002). |
| `College/App/Toolbar/ToolbarProviderRegistry.swift` | ADR 003 — page → toolbar provider registry (delegates from MainWindowToolbar). |
| `College/App/Toolbar/ToolbarProviding.swift` | ADR 003 — per-feature toolbar provider protocol and routing context. |
| `College/App/Toolbar/ToolbarTelemetry.swift` | Pluggable telemetry sink for toolbar dispatch layer. |
| `College/App/Toolbar/WebPortalSceneState.swift` | Swift source — WebPortalSceneState. |
| `College/App/Toolbar/WebToolbarContent.swift` | Swift source — WebToolbarContent. |

### `College/Core/`

Cross-cutting infrastructure shared across features.

| File | Purpose |
|------|---------|
| `College/Core/MLXGlobalErrorHandler.swift` | Core module — MLXGlobalErrorHandler. |
| `College/Core/MemoryPressureHandler.swift` | Core module — MemoryPressureHandler. |
| `College/Core/PerformanceDiagnostics.swift` | Core module — PerformanceDiagnostics. |
| `College/Core/PerformanceSignposts.swift` | Core module — PerformanceSignposts. |
| `College/Core/SheetDismissOnOutsideClick.swift` | Core module — SheetWindowReader. |

### `College/Core/Data/`

SwiftData schema, persistence, repositories, and storage.

| File | Purpose |
|------|---------|
| `College/Core/Data/AppBackupManager.swift` | Core/Data persistence — — AppBackupManager. |

### `College/Core/Data/Persistence/`

CollegePersistence extensions and academic computation.

| File | Purpose |
|------|---------|
| `College/Core/Data/Persistence/AcademicProgressTypes.swift` | Core/Data persistence — — CreditsProgressSummary. |
| `College/Core/Data/Persistence/CollegePersistence+AcademicComputation.swift` | Core/Data persistence — — CompletionInfo. |
| `College/Core/Data/Persistence/CollegePersistence+AcademicIdentity.swift` | Core/Data persistence — — CollegePersistence+AcademicIdentity. |
| `College/Core/Data/Persistence/CollegePersistence+AcademicProgress.swift` | Core/Data persistence — — CollegePersistence+AcademicProgress. |
| `College/Core/Data/Persistence/CollegePersistence+Calendar.swift` | Core/Data persistence — — CollegePersistence+Calendar. |
| `College/Core/Data/Persistence/CollegePersistence+CallSiteShims.swift` | Core/Data persistence — — ScrapeCoverageReport. |
| `College/Core/Data/Persistence/CollegePersistence+Career.swift` | Core/Data persistence — — CollegePersistence+Career. |
| `College/Core/Data/Persistence/CollegePersistence+Catalog.swift` | Core/Data persistence — — CatalogCapability. |
| `College/Core/Data/Persistence/CollegePersistence+ChangeTokens.swift` | Core/Data persistence — — CollegePersistence+ChangeTokens. |
| `College/Core/Data/Persistence/CollegePersistence+LegacyShims.swift` | Core/Data persistence — — CollegePersistence+LegacyShims. |
| `College/Core/Data/Persistence/CollegePersistence+PlannerWrites.swift` | Core/Data persistence — — CollegePersistence+PlannerWrites. |
| `College/Core/Data/Persistence/CollegePersistence+ProfileShell.swift` | Core/Data persistence — — CollegePersistence+ProfileShell. |
| `College/Core/Data/Persistence/CollegePersistence+ProgramRequirementsScrape.swift` | Core/Data persistence — — CollegePersistence+ProgramRequirementsScrape. |
| `College/Core/Data/Persistence/CollegePersistence+Vault.swift` | Core/Data persistence — — CollegePersistence+Vault. |
| `College/Core/Data/Persistence/CollegePersistence.swift` | Core/Data persistence — — CatalogImportPolicy. |

### `College/Core/Data/Repositories/`

Feature-facing repository CRUD and query adapters.

| File | Purpose |
|------|---------|
| `College/Core/Data/Repositories/CalendarRepository+EventWrites.swift` | Core/Data persistence — — CalendarRepository+EventWrites. |
| `College/Core/Data/Repositories/CalendarRepository+TaskWrites.swift` | Core/Data persistence — — CalendarRepository+TaskWrites. |
| `College/Core/Data/Repositories/CalendarRepository+Writes.swift` | Core/Data persistence — — CalendarRepository+Writes. |
| `College/Core/Data/Repositories/CalendarRepository.swift` | Core/Data persistence — — CalendarRepository. |
| `College/Core/Data/Repositories/CareerRepository+ApplicationWrites.swift` | Core/Data persistence — — CareerRepository+ApplicationWrites. |
| `College/Core/Data/Repositories/CareerRepository+JobBoardImport.swift` | Import scraped listings into SwiftData job-board postings. |
| `College/Core/Data/Repositories/CareerRepository+JobBoardPostings.swift` | Fetch and delete mirrored job-board postings in SwiftData. |
| `College/Core/Data/Repositories/CareerRepository+JobBoardTracker.swift` | Promote postings to the career tracker and apply scraped detail payloads. |
| `College/Core/Data/Repositories/CareerRepository+Resume.swift` | Core/Data persistence — — CareerResumeLibraryStats. |
| `College/Core/Data/Repositories/CareerRepository.swift` | Core/Data persistence — — CareerRepository. |
| `College/Core/Data/Repositories/CatalogRepository+CourseLookup.swift` | Core/Data persistence — — CatalogRepository+CourseLookup. |
| `College/Core/Data/Repositories/CatalogRepository+Import.swift` | Core/Data persistence — — CourseImportInput. |
| `College/Core/Data/Repositories/CatalogRepository+ProgramResolution.swift` | Core/Data persistence — — RequirementsRefreshResult. |
| `College/Core/Data/Repositories/CatalogRepository+Reads.swift` | Core/Data persistence — — CatalogRepository+Reads. |
| `College/Core/Data/Repositories/CatalogRepository+RequirementReads.swift` | Core/Data persistence — — CatalogRepository+RequirementReads. |
| `College/Core/Data/Repositories/CatalogRepository+RequirementScrape.swift` | Core/Data persistence — — CatalogRepository+RequirementScrape. |
| `College/Core/Data/Repositories/CatalogRepository+ScrapePresence.swift` | Core/Data persistence — — CatalogScrapeDataPresence. |
| `College/Core/Data/Repositories/CatalogRepository+ScrapePurge.swift` | Core/Data persistence — — CatalogScrapePurgeCounts. |
| `College/Core/Data/Repositories/CatalogRepository+Writes.swift` | Core/Data persistence — — DepartmentUpsertInput. |
| `College/Core/Data/Repositories/CatalogRepository.swift` | Core/Data persistence — — CatalogRepository. |
| `College/Core/Data/Repositories/ProfileRepository+ExperienceAchievementWrites.swift` | Core/Data persistence — — ProfileRepository+ExperienceAchievementWrites. |
| `College/Core/Data/Repositories/ProfileRepository+FocusBlocks.swift` | Core/Data persistence — — ProfileRepository+FocusBlocks. |
| `College/Core/Data/Repositories/ProfileRepository+GraduationPlan.swift` | Core/Data persistence — — ProfileRepository+GraduationPlan. |
| `College/Core/Data/Repositories/ProfileRepository+NativeWrites.swift` | Core/Data persistence — — ProfileRepository+NativeWrites. |
| `College/Core/Data/Repositories/ProfileRepository+PlannerSemesterWrites.swift` | Core/Data persistence — — ProfileRepository+PlannerSemesterWrites. |
| `College/Core/Data/Repositories/ProfileRepository+ProfileShellWrites.swift` | Core/Data persistence — — ProfileRepository+ProfileShellWrites. |
| `College/Core/Data/Repositories/ProfileRepository+Writes.swift` | Core/Data persistence — — ProfileRepositoryWriteError. |
| `College/Core/Data/Repositories/ProfileRepository.swift` | Core/Data persistence — — ProfileRepository. |
| `College/Core/Data/Repositories/VaultRepository+FileIO.swift` | Core/Data persistence — — VaultDocumentCategory. |
| `College/Core/Data/Repositories/VaultRepository+MetadataWrites.swift` | Core/Data persistence — — VaultRepository+MetadataWrites. |
| `College/Core/Data/Repositories/VaultRepository+Writes.swift` | Core/Data persistence — — VaultRepository+Writes. |
| `College/Core/Data/Repositories/VaultRepository.swift` | Core/Data persistence — — VaultRepository. |

### `College/Core/Data/Storage/`

Model container factory, migrations, and store maintenance.

| File | Purpose |
|------|---------|
| `College/Core/Data/Storage/AppDataStore+UnitTesting.swift` | Core/Data persistence — — AppDataStore+UnitTesting. |
| `College/Core/Data/Storage/AppDataStore.swift` | Core/Data persistence — — AppDataStore. |
| `College/Core/Data/Storage/AppDataStoreBootstrap.swift` | Core/Data persistence — — AppDataStoreBootstrap. |
| `College/Core/Data/Storage/AppDataStoreBridge.swift` | Core/Data persistence — — AppDataStoreBridge. |
| `College/Core/Data/Storage/AppDataStoreLaunchWarmup.swift` | Core/Data persistence — — AppDataStoreLaunchWarmup. |
| `College/Core/Data/Storage/CalendarSyncIngestService.swift` | Core/Data persistence — — AppleEventSnapshot. |
| `College/Core/Data/Storage/CollegeModelContainerFactory.swift` | Core/Data persistence — — CollegeModelContainerFactory. |
| `College/Core/Data/Storage/CollegeSchemaMigrationPlan.swift` | Core/Data persistence — — CollegeSchemaMigrationPlan. |
| `College/Core/Data/Storage/CollegeSchemaV1.swift` | Core/Data persistence — — FocusBlockRecord. |
| `College/Core/Data/Storage/CollegeSchemaV1_2.swift` | Historical schema 1.2 stamp (catalog provenance release). |
| `College/Core/Data/Storage/JobBoardStoreMirror.swift` | Swift source — JobBoardStoreMirror. |
| `College/Core/Data/Storage/ModelEntityCompatibility.swift` | Core/Data persistence — — ModelEntityCompatibility. |
| `College/Core/Data/Storage/ModelMergeCoalescer.swift` | Core/Data persistence — — ModelMergeCoalescer. |
| `College/Core/Data/Storage/ModelStoreMaintenance.swift` | Core/Data persistence — — ModelStoreMaintenance. |
| `College/Core/Data/Storage/PlannerStoreAccessors.swift` | Core/Data persistence — — PlannerStoreAccessors. |
| `College/Core/Data/Storage/ProfilePlannerQueryHost.swift` | Core/Data persistence — — ProfilePlannerQueryHost. |
| `College/Core/Data/Storage/ProfilePlannerReadBridge.swift` | Core/Data persistence — — ProfilePlannerReadBridge. |
| `College/Core/Data/Storage/ProfilePlannerStoreMirror.swift` | Swift source — ProfilePlannerStoreMirror. |
| `College/Core/Data/Storage/ProfilePlannerSyncBridge.swift` | Core/Data persistence — — ProfilePlannerSyncBridge. |
| `College/Core/Data/Storage/ProfileRepository+CareerSync.swift` | Core/Data persistence — — ProfileRepository+CareerSync. |
| `College/Core/Data/Storage/ProfileRepository+PlannerSync.swift` | Core/Data persistence — — ProfileRepository+PlannerSync. |
| `College/Core/Data/Storage/ProfileRepository+VaultSync.swift` | Core/Data persistence — — ProfileRepository+VaultSync. |
| `College/Core/Data/Storage/VaultStoreMirror.swift` | Swift source — VaultStoreMirror. |

### `College/Core/DesignSystem/`

Shared UI tokens, headers, and toolbar metrics.

| File | Purpose |
|------|---------|
| `College/Core/DesignSystem/AppNavBar.swift` | Swift source — AppNavBar. |
| `College/Core/DesignSystem/AppPageHeader.swift` | Core module — AppPageHeader. |
| `College/Core/DesignSystem/AutoGrowingTextEditor.swift` | Core module — AutoGrowingTextEditor. |
| `College/Core/DesignSystem/DashboardHints.swift` | Core module — DashboardEmptyHint. |
| `College/Core/DesignSystem/DesignSystem+Tokens.swift` | Swift source — DesignSystem+Tokens. |
| `College/Core/DesignSystem/DesignSystem.swift` | Swift source — DesignSystem. |
| `College/Core/DesignSystem/LiquidGlassSidebarRow.swift` | Swift source — LiquidGlassSidebarRow. |
| `College/Core/DesignSystem/ToolbarMetrics.swift` | Core module — ToolbarMetrics. |
| `College/Core/DesignSystem/UnifiedActionHeader.swift` | Core module — UnifiedActionHeader. |

### `College/Core/Location/`

Location permission and picker utilities.

| File | Purpose |
|------|---------|
| `College/Core/Location/LocationETAService.swift` | Core module — LocationETAService. |
| `College/Core/Location/LocationPermissionService.swift` | Core module — LocationPermissionService. |
| `College/Core/Location/LocationPickerSheet.swift` | Core module — LocationPickerSheet. |
| `College/Core/Location/LocationRecentsStore.swift` | Core module — LocationRecentsStore. |
| `College/Core/Location/LocationSuggestionsDropdown.swift` | Core module — LocationSuggestionsDropdown. |
| `College/Core/Location/MapLocationSearchService.swift` | Core module — ResolvedLocation. |
| `College/Core/Location/TravelTimeStore.swift` | Core module — TravelTimeSettings. |

### `College/Core/Notifications/`

Academic notification scheduling.

| File | Purpose |
|------|---------|
| `College/Core/Notifications/AcademicNotificationScheduler.swift` | Core module — SemesterSnapshot. |
| `College/Core/Notifications/AppNotificationCenter.swift` | Core module — AppNotification. |
| `College/Core/Notifications/AppNotificationHost.swift` | Core module — AppNotificationHost. |
| `College/Core/Notifications/NotificationNames.swift` | Core module — NotificationNames. |

### `College/Core/Platform/`

Platform helpers, commands, focus blocks, and undo/toast.

| File | Purpose |
|------|---------|
| `College/Core/Platform/AppleSiliconPlatform.swift` | Core module — Report. |
| `College/Core/Platform/BuildCompatibility.swift` | Core module — BuildCompatibility. |

### `College/Core/Platform/Availability/`

Free/busy availability link helpers.

| File | Purpose |
|------|---------|
| `College/Core/Platform/Availability/AvailabilityLinkService.swift` | Core module — Link. |

### `College/Core/Platform/Commands/`

App-wide command palette and menu commands.

| File | Purpose |
|------|---------|
| `College/Core/Platform/Commands/AppCommandPalette.swift` | Core module — AppCommandPalette. |
| `College/Core/Platform/Commands/NaturalLanguageEventParser.swift` | Core module — ParsedCalendarIntent. |

### `College/Core/Platform/Focus/`

Focus block scheduling integration.

| File | Purpose |
|------|---------|
| `College/Core/Platform/Focus/AppFocusBlockStore.swift` | Core module — FocusBlock. |

### `College/Core/Platform/Integrations/`

Cloud and third-party integration ports.

| File | Purpose |
|------|---------|
| `College/Core/Platform/Integrations/IntegrationStatusBadge.swift` | Core module — IntegrationStatusBadge. |

### `College/Core/Platform/Intelligence/`

Shared intelligence/embedding helpers.

| File | Purpose |
|------|---------|
| `College/Core/Platform/Intelligence/PlannerMemoryQuery.swift` | Core module — Hit. |
| `College/Core/Platform/Intelligence/PlannerNarrativeService.swift` | Core module — DaySummary. |

### `College/Core/Platform/Undo/`

Undo coordinator and toast host.

| File | Purpose |
|------|---------|
| `College/Core/Platform/Undo/AppToastHost.swift` | Core module — AppToast. |
| `College/Core/Platform/Undo/AppUndoCoordinator.swift` | Core module — AppUndoCoordinator. |

### `College/Core/Security/`

App lock, privacy overview, backup, and data wipe.

| File | Purpose |
|------|---------|
| `College/Core/Security/DataWipeManager.swift` | Core module — DataWipeManager. |
| `College/Core/Security/PrivacyOverviewView.swift` | Core module — PrivacyOverviewView. |
| `College/Core/Security/SecretStore.swift` | Core module — SecretStore. |
| `College/Core/Security/SecurityManager.swift` | Core module — SecurityManager. |
| `College/Core/Security/UnlockView.swift` | Core module — UnlockView. |

### `College/Core/Services/`

Shared services (vault, catalog sync, email, PDF, etc.).

| File | Purpose |
|------|---------|
| `College/Core/Services/CatalogBackgroundSyncRunner.swift` | Core module — Hooks. |
| `College/Core/Services/CatalogBreadthHydrationService.swift` | Core module — CatalogBreadthHydrationService. |
| `College/Core/Services/CatalogScrapeAuditCSVSupport.swift` | Core module — CatalogScrapeAuditCSVSupport. |
| `College/Core/Services/CatalogSessionWarmup.swift` | Core module — CatalogSessionWarmup. |
| `College/Core/Services/CloudIntegrationService.swift` | Core module — AuthorizedRoot. |
| `College/Core/Services/DocumentClassifierService.swift` | Core module — ClassificationResult. |
| `College/Core/Services/FSWatchdogService.swift` | Core module — FSWatchdogService. |
| `College/Core/Services/GoogleAuthService.swift` | Core module — EffectiveConfig. |
| `College/Core/Services/PDFAnnotationView.swift` | Core module — PDFAnnotationView. |
| `College/Core/Services/StaleFileMonitor.swift` | Core module — StaleFileMonitor. |
| `College/Core/Services/VaultDocumentAccess.swift` | Core module — VaultDocumentAccess. |
| `College/Core/Services/VaultDocumentMetadataAccess.swift` | Core module — VaultDocumentMetadataAccess. |
| `College/Core/Services/VaultDocumentService.swift` | Core module — IndexItem. |
| `College/Core/Services/VaultDuplicateDetector.swift` | Core module — DuplicateGroup. |
| `College/Core/Services/VaultFileOrganizer.swift` | Core module — for. |
| `College/Core/Services/VaultImportSerialQueue.swift` | Core module — VaultImportSerialQueue. |
| `College/Core/Services/VaultLocationManager.swift` | Core module — VaultLocationManager. |
| `College/Core/Services/VaultReadBridge.swift` | Core module — VaultReadBridge. |
| `College/Core/Services/VaultScreenshotTriage.swift` | Core module — VaultScreenshotTriage. |
| `College/Core/Services/VaultSemesterArchive.swift` | Core module — ArchiveError. |
| `College/Core/Services/VaultShareBundleService.swift` | Core module — VaultBundleItem. |
| `College/Core/Services/VaultStorageAnalytics.swift` | Core module — CourseStorageStat. |
| `College/Core/Services/VaultSummaryService.swift` | Core module — VaultSummaryService. |
| `College/Core/Services/VaultUploadSheet.swift` | Core module — VaultUploadMetadata. |
| `College/Core/Services/VaultWeeklyDigest.swift` | Core module — VaultWeeklyDigest. |

### `College/Core/Utilities/`

Shared helper utilities.

| File | Purpose |
|------|---------|
| `College/Core/Utilities/UserDefaultsWindowAutosaveCleanup.swift` | Core module — UserDefaultsWindowAutosaveCleanup. |
| `College/Core/Utilities/VectorMath.swift` | Core module — VectorMath. |

### `College/Core/WebShortcuts/`

Embedded web shortcut coordinator and favicon store.

| File | Purpose |
|------|---------|
| `College/Core/WebShortcuts/ShortcutWebCoordinator.swift` | Core module — ShortcutWebCoordinator. |
| `College/Core/WebShortcuts/ShortcutWebHostView.swift` | Core module — ShortcutWebHostView. |

### `College/Debug/`

Diagnostics center, crash reports, and DEBUG-only tooling.

| File | Purpose |
|------|---------|
| `College/Debug/AppLogger.swift` | Debug module — Entry. |
| `College/Debug/AppLogsView.swift` | Debug module — AppLogsView. |
| `College/Debug/CrashReportStore.swift` | Debug module — CrashReport. |
| `College/Debug/CrashSignalHandler.swift` | Debug module — CrashSignalHandler. |
| `College/Debug/DebugLogModifiers.swift` | Debug module — DebugLogModifiers. |
| `College/Debug/DebugLogger.swift` | Debug module — DebugLogger. |
| `College/Debug/ErrorReportView.swift` | Debug module — ErrorReportView. |
| `College/Debug/GoogleDebugLog.swift` | Debug module — GoogleDebugLog. |
| `College/Debug/LaunchPerformanceAcceptance.swift` | Debug module — LaunchPerformanceAcceptance. |
| `College/Debug/PerformanceMonitor.swift` | Debug module — PerformanceMonitor. |
| `College/Debug/RuntimeTelemetryMonitor.swift` | Debug module — RuntimeTelemetryMonitor. |
| `College/Debug/UncaughtExceptionLogger.swift` | Debug module — UncaughtExceptionLogger. |
| `College/Debug/UnlockDebugLog.swift` | Debug module — Mark. |

### `College/Features/Academics/`

Semester planner UI, degree audit panel, GPA/credit views, and graduation timeline.

| File | Purpose |
|------|---------|
| `College/Features/Academics/AcademicMetricsStore.swift` | Academics module — AcademicMetricsSnapshot. |
| `College/Features/Academics/AcademicProfile+ProgramLists.swift` | Academics module — AcademicProfileProgramLists. |
| `College/Features/Academics/AcademicProfileEntity+Extensions.swift` | Academics module — AcademicProfileStatus. |
| `College/Features/Academics/AcademicProgramHelpers.swift` | Academics module — RequirementFingerprint. |
| `College/Features/Academics/AcademicsBottomSummaryStrip.swift` | Academics module — ProgramCreditStatusStripRow. |
| `College/Features/Academics/AcademicsLeftStatsSidebar.swift` | Academics module — AcademicsLeftStatsSidebar. |
| `College/Features/Academics/AcademicsPlannerCreditsBridge.swift` | Academics module — AcademicsPlannerCreditBuckets. |
| `College/Features/Academics/AcademicsPlannerReadBridge.swift` | Academics module — AcademicsPlannerReadBridge. |
| `College/Features/Academics/AcademicsPlannerSemesterSummary.swift` | Academics module — AcademicsPlannerSemesterSummary. |
| `College/Features/Academics/AcademicsSemesterQueryHost.swift` | Academics module — AcademicsSemesterQueryHost. |
| `College/Features/Academics/AcademicsStatusPalette.swift` | Academics module — AcademicsStatusPalette. |
| `College/Features/Academics/AcademicsView.swift` | Academics module — AcademicsEntranceModifier. |
| `College/Features/Academics/AuditCatalogBatchLookupQuery.swift` | Academics module — AuditCatalogBatchLookupQuery. |
| `College/Features/Academics/AuditCatalogLookupBridge.swift` | Academics module — AuditCatalogCourseSnapshot. |
| `College/Features/Academics/AuditSnapshotStore+LoadAudit.swift` | Academics module — SelectDetail. |
| `College/Features/Academics/AuditSnapshotStore.swift` | Academics module — AcademicsCreditBuckets. |
| `College/Features/Academics/GPACalculation.swift` | Academics module — GPACalculationResult. |
| `College/Features/Academics/GraduationTimelineConfigSheet.swift` | Academics module — GraduationTimelineConfigSheet. |
| `College/Features/Academics/GraduationTimelinePolicyBridge.swift` | Swift source — GraduationTimelinePolicyBridge. |
| `College/Features/Academics/GraduationTimelinePrereqValidator.swift` | Academics module — Warning. |
| `College/Features/Academics/RequirementBreakdownBuilder.swift` | Academics module — BreakdownCategory. |
| `College/Features/Academics/RequirementBreakdownCredits.swift` | Academics module — RequirementBreakdownCredits. |
| `College/Features/Academics/RequirementFulfillmentStore.swift` | Academics module — RequirementFulfillmentAssignmentSource. |
| `College/Features/Academics/RequirementProgressEngine.swift` | Academics module — RequirementCourseSnapshot. |
| `College/Features/Academics/SpecializationRequirementFilter.swift` | Academics module — CatBucket. |

### `College/Features/Assistant/`

On-device AI assistant, tool routing, and conversation UI.

| File | Purpose |
|------|---------|
| `College/Features/Assistant/AIAssistantAcademicTools.swift` | Assistant module — GetStudentProfileTool. |
| `College/Features/Assistant/AIAssistantCareerTools.swift` | Assistant module — JobApplicationSummaryPayload. |
| `College/Features/Assistant/AIAssistantDocumentTools.swift` | Assistant module — DocumentSearchHitPayload. |
| `College/Features/Assistant/AIAssistantFinancialTools.swift` | Assistant module — GetAidDeadlinesTool. |
| `College/Features/Assistant/AIAssistantLocationTools.swift` | Assistant module — ResolvedEventLocationPayload. |
| `College/Features/Assistant/AIAssistantNavigationTools.swift` | Assistant module — NavigateToPageTool. |
| `College/Features/Assistant/AIAssistantPlanMutationTools.swift` | Assistant module — PlanMutationPayload. |
| `College/Features/Assistant/AIAssistantProfileTools.swift` | Assistant module — ProfileToolPayload. |
| `College/Features/Assistant/AIAssistantService.swift` | Assistant module — GenerationOutcome. |
| `College/Features/Assistant/AIAssistantSettingsTools.swift` | Assistant module — GetAppSettingTool. |
| `College/Features/Assistant/AIAssistantSystemTools.swift` | Assistant module — CreateTaskTool. |
| `College/Features/Assistant/AIAssistantToolRouter.swift` | Assistant module — AssistantPlannerSnapshot. |
| `College/Features/Assistant/AIAssistantTools.swift` | Assistant module — AssistantToolDescriptor. |
| `College/Features/Assistant/AIAssistantView.swift` | Assistant module — AssistantMessage. |
| `College/Features/Assistant/AIAssistantViewModel.swift` | Assistant module — AIAssistantViewModel. |
| `College/Features/Assistant/AssistantArithmeticExpression.swift` | Assistant module — AssistantArithmeticExpressionError. |
| `College/Features/Assistant/AssistantAttachmentIngestor.swift` | Assistant module — Result. |
| `College/Features/Assistant/AssistantChatChrome.swift` | Assistant module — AssistantReplyFormattedText. |
| `College/Features/Assistant/AssistantConfirmationStyle.swift` | Assistant module — AssistantConfirmationStyle. |
| `College/Features/Assistant/AssistantContextAssembler.swift` | Assistant module — Layer. |
| `College/Features/Assistant/AssistantContextBridge.swift` | Assistant module — AssistantContextBridge. |
| `College/Features/Assistant/AssistantContextBudget.swift` | Assistant module — AssistantContextBudget. |
| `College/Features/Assistant/AssistantConversationMemory.swift` | Assistant module — Row. |
| `College/Features/Assistant/AssistantFinancialAidPolicy.swift` | Assistant module — UniversityPolicyJurisdiction. |
| `College/Features/Assistant/AssistantGemmaStreamFilter.swift` | Assistant module — AssistantGemmaStreamFilter. |
| `College/Features/Assistant/AssistantIntentEmbeddingClassifier.swift` | Assistant module — AssistantIntentPrototype. |
| `College/Features/Assistant/AssistantIntentSemantics.swift` | Assistant module — SemanticRouteSuggestion. |
| `College/Features/Assistant/AssistantLogRedactor.swift` | Assistant module — AssistantLogRedactor. |
| `College/Features/Assistant/AssistantMinimalProfileContext.swift` | Assistant module — AssistantMinimalProfileContext. |
| `College/Features/Assistant/AssistantPlanJSONParser.swift` | Assistant module — AssistantJSONRobustnessSettings. |
| `College/Features/Assistant/AssistantPlannerIndexingConsent.swift` | Assistant module — AssistantPlannerIndexingConsentSheet. |
| `College/Features/Assistant/AssistantPlannerIndexingSettings.swift` | Assistant module — AssistantPlannerIndexingSettings. |
| `College/Features/Assistant/AssistantPolicyEvidence.swift` | Assistant module — AssistantPolicyJurisdiction. |
| `College/Features/Assistant/AssistantPolicyRAG.swift` | Assistant module — AssistantPolicyContext. |
| `College/Features/Assistant/AssistantProfessionalHandbookRegistry.swift` | Assistant module — Entry. |
| `College/Features/Assistant/AssistantReplyModels.swift` | Assistant module — AssistantReplySource. |
| `College/Features/Assistant/AssistantSettingsKey.swift` | Assistant module — AssistantSettingsKey. |
| `College/Features/Assistant/AssistantStudentGuidePanel.swift` | Assistant module — AssistantStudentGuidePanel. |
| `College/Features/Assistant/AssistantToolSources.swift` | Assistant module — AssistantToolSources. |
| `College/Features/Assistant/AssistantUndoSupport.swift` | Assistant module — AssistantUndoSupport. |
| `College/Features/Assistant/AssistantWebFetchPolicy.swift` | Assistant module — AssistantWebFetchPolicy. |
| `College/Features/Assistant/AssistantWebMemoryEmbedding.swift` | Assistant module — AssistantWebMemoryEmbedding. |
| `College/Features/Assistant/AssistantWebMemoryLibraryView.swift` | Assistant module — AssistantWebMemoryLibraryView. |
| `College/Features/Assistant/AssistantWebMemoryStore.swift` | Assistant module — EntryPreference. |
| `College/Features/Assistant/AssistantWebPageExtractor.swift` | Assistant module — AssistantWebPageExtractor. |
| `College/Features/Assistant/AssistantWebSearchRateLimiter.swift` | Assistant module — AssistantWebSearchRateLimiter. |
| `College/Features/Assistant/AssistantWebSearchSettings.swift` | Assistant module — AssistantWebSearchSettings. |
| `College/Features/Assistant/GitHubDataService.swift` | Assistant module — GitHubDataService. |
| `College/Features/Assistant/IntelligenceDebugView.swift` | Assistant module — IntelligenceDebugView. |
| `College/Features/Assistant/IntelligenceService.swift` | Assistant module — ParsingStats. |
| `College/Features/Assistant/IntentClassifier.mlmodel` | Repository file. |
| `College/Features/Assistant/PlannerChunkProjection.swift` | Assistant module — IndexedChunk. |
| `College/Features/Assistant/PlannerVectorIndexer.swift` | Assistant module — PlannerVectorIndexer. |
| `College/Features/Assistant/PlannerVectorIndexingLifecycle.swift` | Assistant module — PlannerVectorIndexingLifecycle. |
| `College/Features/Assistant/PlannerVectorSearchConfig.swift` | Assistant module — SearchParams. |
| `College/Features/Assistant/PlannerVectorStore.swift` | Assistant module — Row. |
| `College/Features/Assistant/ProductionIntentClassifier.swift` | Assistant module — AssistantIntentNLModelSettings. |
| `College/Features/Assistant/SearXNGClient.swift` | Assistant module — SearXNGClient. |
| `College/Features/Assistant/ToolCallStreamParser.swift` | Assistant module — ToolCallStreamParseResult. |
| `College/Features/Assistant/VaultDocumentTextIndexer.swift` | Assistant module — IndexWork. |

### `College/Features/Assistant/AssistantInference/`

Local LLM inference sessions and prompt builders.

| File | Purpose |
|------|---------|
| `College/Features/Assistant/AssistantInference/AssistantInferenceAvailability.swift` | Assistant module — AssistantInferenceAvailability. |
| `College/Features/Assistant/AssistantInference/AssistantInferenceBackend.swift` | Assistant module — AssistantInferenceBackend. |
| `College/Features/Assistant/AssistantInference/AssistantInferenceSession.swift` | Assistant module — AssistantPlanningRequest. |
| `College/Features/Assistant/AssistantInference/AssistantInferenceSessionFactory.swift` | Assistant module — AssistantInferenceSessionFactory. |
| `College/Features/Assistant/AssistantInference/AssistantInferenceSettings.swift` | Assistant module — AssistantInferenceSettings. |
| `College/Features/Assistant/AssistantInference/AssistantPlanningPromptBuilder.swift` | Assistant module — AssistantPromptThreadSegments. |
| `College/Features/Assistant/AssistantInference/FMRegistryToolAdapter.swift` | Assistant module — FMRegistryToolAdapter. |
| `College/Features/Assistant/AssistantInference/FoundationModelsAssistantSession.swift` | Assistant module — FoundationModelsAssistantSession. |
| `College/Features/Assistant/AssistantInference/JsonWorkerAssistantSession.swift` | Assistant module — JsonWorkerAssistantSession. |
| `College/Features/Assistant/AssistantInference/StubAssistantInferenceSession.swift` | Assistant module — StubAssistantInferenceSession. |

### `College/Features/Assistant/Resources/`

Assistant bundled resources and model assets.

| File | Purpose |
|------|---------|
| `College/Features/Assistant/Resources/IntentTrainingData.csv` | Test fixture or documentation artifact. |

### `College/Features/Calendar/`

Calendar grid UI, editor overlays, and academic calendar helpers.

| File | Purpose |
|------|---------|
| `College/Features/Calendar/AddCalendarItemOverlay.swift` | Calendar module — AddCalendarItemOverlay. |
| `College/Features/Calendar/AddTaskOverlay.swift` | Calendar module — AddTaskOverlay. |
| `College/Features/Calendar/CalendarCourseLinker.swift` | Calendar module — CalendarCourseLinker. |
| `College/Features/Calendar/CalendarEventEditorPopover.swift` | Calendar module — CalendarEventEditorPopover. |
| `College/Features/Calendar/CalendarEventEditorSheet.swift` | Calendar module — CalendarEventEditorSheet. |
| `College/Features/Calendar/CalendarEventSearchBridge.swift` | Calendar module — CalendarEventSearchHit. |
| `College/Features/Calendar/CalendarFeaturePreloadRegistration.swift` | Swift source — CalendarFeaturePreloadRegistration. |
| `College/Features/Calendar/CalendarFetchQuery.swift` | SwiftData fetch helpers for cache rebuild (Layer 2 bridge; stays in app target). |
| `College/Features/Calendar/CalendarGridEditorHost.swift` | Calendar module — CalendarGridEditorHostModifier. |
| `College/Features/Calendar/CalendarIntegrationPorts+App.swift` | Swift source — CalendarIntegrationPorts+App. |
| `College/Features/Calendar/CalendarModalHost.swift` | Calendar module — CalendarModalHost. |
| `College/Features/Calendar/CalendarOverlayPort+App.swift` | Swift source — CalendarOverlayPort+App. |
| `College/Features/Calendar/CalendarPersistenceBridges.swift` | App-target adapters between SwiftData models and CollegeCalendar package types. |
| `College/Features/Calendar/CalendarPersistencePort+App.swift` | Wire SwiftData persistence into CollegeCalendar package ports (ADR 004). |
| `College/Features/Calendar/CalendarQueryHost.swift` | Calendar module — CalendarQueryHost. |
| `College/Features/Calendar/CalendarReadBridge.swift` | Calendar module — CalendarReadBridge. |
| `College/Features/Calendar/CalendarReadPort+App.swift` | Swift source — CalendarReadPort+App. |
| `College/Features/Calendar/CalendarSearchQuery.swift` | Calendar module — CalendarSearchQuery. |
| `College/Features/Calendar/CalendarShellPorts+App.swift` | Swift source — CalendarShellPorts+App. |
| `College/Features/Calendar/GoogleCalendarAuthPort+App.swift` | Swift source — GoogleCalendarAuthPort+App. |
| `College/Features/Calendar/NewEventModal.swift` | Swift source — NewEventModal. |

### `College/Features/Calendar/Editor/`

Scrollable calendar item editor decomposition.

| File | Purpose |
|------|---------|
| `College/Features/Calendar/Editor/CalendarEventEditorView.swift` | Calendar module — CalendarEventEditorView. |

### `College/Features/Calendar/ICS/`

ICS subscription parsing helpers.

| File | Purpose |
|------|---------|
| `College/Features/Calendar/ICS/ICSSubscriptionRefreshService.swift` | Calendar module — ICSSubscriptionRefreshService. |
| `College/Features/Calendar/ICS/ICSSubscriptionUpsertService.swift` | Calendar module — ICSSubscriptionUpsertService. |

### `College/Features/Calendar/Views/`

Calendar subviews and layout components.

| File | Purpose |
|------|---------|
| `College/Features/Calendar/Views/CalendarGhostEventOverlay.swift` | Calendar module — CalendarGhostEvent. |

### `College/Features/Career/Applications/`

Application tracker models and kanban/list views.

| File | Purpose |
|------|---------|
| `College/Features/Career/Applications/AddRoleSheet.swift` | Career module — AddRoleSheet. |
| `College/Features/Career/Applications/CareerApplicationContextMenu.swift` | Career module — CareerApplicationContextMenu. |
| `College/Features/Career/Applications/CareerApplicationFormSheet.swift` | Add/edit job application form sheet. |
| `College/Features/Career/Applications/CareerApplicationPresentation.swift` | Career module — CareerApplicationPresentation. |
| `College/Features/Career/Applications/CareerApplicationsListView.swift` | Career module — CareerApplicationsListView. |
| `College/Features/Career/Applications/JobDescriptionFormattedView.swift` | Career module — JobDescriptionFormattedView. |
| `College/Features/Career/Applications/JobInspectorSidebar.swift` | Career module — JobInspectorFlowLayout. |

### `College/Features/Career/Applications/Views/`

Application tracker view components.

| File | Purpose |
|------|---------|
| `College/Features/Career/Applications/Views/ApplicationTrackerView.swift` | Kanban/list view for tracking job applications through the pipeline. |

### `College/Features/Career/Design/`

Career design tokens and shared styling.

| File | Purpose |
|------|---------|
| `College/Features/Career/Design/CareerKanbanTheme.swift` | Career module — PillStyle. |
| `College/Features/Career/Design/CareerListTableTheme.swift` | Career module — StageBadgeStyle. |
| `College/Features/Career/Design/CareerQuickAddTextField.swift` | Career module — CareerQuickAddTextField. |
| `College/Features/Career/Design/CareerTrailingInspectorLayout.swift` | Career module — CareerTrailingInspectorLayout. |

### `College/Features/Career/Interview/`

Interview prep stories and practice flows.

| File | Purpose |
|------|---------|
| `College/Features/Career/Interview/InterviewPrepView.swift` | Career module — InterviewPrepView. |

### `College/Features/Career/Job Board/`

Job board UI and posting presentation.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board/JobBoardBranding.swift` | Career module — JobBoardCompanyLogoStore. |
| `College/Features/Career/Job Board/JobBoardCompaniesStore.swift` | Career module — JobBoardCompaniesStore. |
| `College/Features/Career/Job Board/JobBoardMenuBarView.swift` | Career module — JobBoardMenuBarView. |
| `College/Features/Career/Job Board/JobBoardModels.swift` | Career module — JobBoardCompany. |
| `College/Features/Career/Job Board/JobBoardNotificationService.swift` | Career module — JobBoardNotificationService. |
| `College/Features/Career/Job Board/JobBoardOpeningsState.swift` | Career module — JobBoardOpeningsState. |
| `College/Features/Career/Job Board/JobBoardPosting+Display.swift` | Career module — JobBoardPosting+Display. |
| `College/Features/Career/Job Board/JobBoardPostingParsing+Store.swift` | Career module — JobTypeFilterOption. |
| `College/Features/Career/Job Board/JobBoardPostingParsing.swift` | Career module — LocationFilterOption. |
| `College/Features/Career/Job Board/JobBoardReadBridge.swift` | Career module — JobBoardReadBridge. |
| `College/Features/Career/Job Board/JobBoardRefreshScheduler.swift` | Career module — JobBoardRefreshScheduler. |
| `College/Features/Career/Job Board/JobBoardSyncCoordinator.swift` | Career module — JobBoardSyncCoordinator. |
| `College/Features/Career/Job Board/JobBoardToolbarFilters.swift` | Career module — JobBoardFilterMenuLabel. |

### `College/Features/Career/Job Board Scrapers/`

External job board scraper implementations.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/JobBoardPlatformDetector.swift` | Detect job-board platform from careers URL. |
| `College/Features/Career/Job Board Scrapers/JobBoardScraper.swift` | Shared job-board scraper protocol, DTOs, registry, and HTTP helpers. |

### `College/Features/Career/Job Board Scrapers/Greenhouse/`

Greenhouse ATS scraper.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/Greenhouse/GreenhouseScraper.swift` | Greenhouse job board scraper and API models. |

### `College/Features/Career/Job Board Scrapers/ICIMS/`

iCIMS ATS scraper.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/ICIMS/ICIMSScraper.swift` | ICIMS / Jibe job board scraper and API models. |

### `College/Features/Career/Job Board Scrapers/Lever/`

Lever ATS scraper.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/Lever/LeverScraper.swift` | Lever job board scraper and API models. |

### `College/Features/Career/Job Board Scrapers/Oracle/`

Oracle HCM scraper.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/Oracle/OracleHCMScraper.swift` | Oracle HCM job board scraper and API models. |

### `College/Features/Career/Job Board Scrapers/Talemetry/`

Talemetry ATS scraper.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/Talemetry/TalemetryScraper.swift` | Talemetry / Jobvite job board scraper. |

### `College/Features/Career/Job Board Scrapers/Workday/`

Workday ATS scraper.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board Scrapers/Workday/WorkdayScraper.swift` | Workday job board scraper, API models, and HTTP client. |

### `College/Features/Career/Job Board/Views/`

Job board view components.

| File | Purpose |
|------|---------|
| `College/Features/Career/Job Board/Views/JobBoardCompanyJobsView.swift` | Career module — JobBoardCompanyJobsView. |
| `College/Features/Career/Job Board/Views/JobBoardJobDetailPane.swift` | Career module — JobBoardJobDetailPane. |
| `College/Features/Career/Job Board/Views/JobOpeningsView.swift` | Browse scraped external job postings by company. |

### `College/Features/Career/Networking/`

Networking tracker UI and detail panes.

| File | Purpose |
|------|---------|
| `College/Features/Career/Networking/LogInteractionSheet.swift` | Career module — LogInteractionSheet. |
| `College/Features/Career/Networking/NetworkingAddContactSheet.swift` | Career module — NetworkingAddContactSheet. |
| `College/Features/Career/Networking/NetworkingDetailPane.swift` | Career module — ContactAvatarView. |
| `College/Features/Career/Networking/NetworkingFollowUpStore.swift` | Career module — NetworkingFollowUpStore. |
| `College/Features/Career/Networking/NetworkingTrackerView.swift` | Networking contacts tracker in the Career workspace. |
| `College/Features/Career/Networking/RecruiterContactEntity+CareerNetworking.swift` | Career module — RecruiterContactEntity+CareerNetworking. |

### `College/Features/Career/Resumes/`

Resume library, builder sheets, and autofill review.

| File | Purpose |
|------|---------|
| `College/Features/Career/Resumes/CareerResumeLibrary.swift` | Career module — CareerResumeMetadataV1. |
| `College/Features/Career/Resumes/ResumeManagerView.swift` | Resume library manager in the Career workspace. |

### `College/Features/Career/Services/`

Resume parsing, ATS scoring, and career enrichment services.

| File | Purpose |
|------|---------|
| `College/Features/Career/Services/CareerAIService.swift` | Career module — ParseResponse. |
| `College/Features/Career/Services/CareerFollowUpScheduler.swift` | Career module — CareerFollowUpScheduler. |
| `College/Features/Career/Services/CareerIngestCoordinator.swift` | Career module — CareerIngestCoordinator. |
| `College/Features/Career/Services/CareerReadBridge.swift` | Career module — CareerApplicationStatsRow. |
| `College/Features/Career/Services/CareerSpotlightIndexer.swift` | Career module — CareerSpotlightIndexer. |

### `College/Features/Career/Stats/`

Career funnel KPI views.

| File | Purpose |
|------|---------|
| `College/Features/Career/Stats/CareerFunnelHeaderView.swift` | Career module — CareerFunnelHeaderView. |
| `College/Features/Career/Stats/CareerKPIStatCard.swift` | Career module — CareerKPIStatCard. |
| `College/Features/Career/Stats/CareerStatsView.swift` | Career module — CareerStatsView. |

### `College/Features/Career/Workspace/`

Career workspace layout and sub-view routing.

| File | Purpose |
|------|---------|
| `College/Features/Career/Workspace/CareerBoardLayout.swift` | Swift source — CareerBoardLayout. |
| `College/Features/Career/Workspace/CareerFeaturePreloadRegistration.swift` | Swift source — CareerFeaturePreloadRegistration. |
| `College/Features/Career/Workspace/CareerQueryHost.swift` | Career module — CareerQueryHost. |
| `College/Features/Career/Workspace/CareerSceneMaintenanceCoordinator.swift` | Career module — CareerSceneMaintenanceCoordinator. |
| `College/Features/Career/Workspace/CareerWorkspaceView.swift` | Career workspace shell and subview routing. |

### `College/Features/Catalog/`

School catalog scrape, ingest, search, and vector index.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/CatalogAvailability.swift` | Catalog module — CatalogAvailability. |
| `College/Features/Catalog/CatalogBundle.swift` | Catalog module — CatalogBundleEnvelope. |
| `College/Features/Catalog/CatalogBundleExporter.swift` | Catalog module — CatalogBundleExporter. |
| `College/Features/Catalog/CatalogBundleImportSheet.swift` | Catalog module — CatalogBundleImportPreview. |
| `College/Features/Catalog/CatalogBundleImporter.swift` | Catalog module — CatalogBundleImporter. |
| `College/Features/Catalog/CatalogBundleSecurity.swift` | Catalog module — CatalogBundleSecurityError. |
| `College/Features/Catalog/CatalogBundleTrustStore.swift` | Catalog module — CatalogBundleTrustStore. |
| `College/Features/Catalog/CatalogCourseCodeHelpers.swift` | Catalog module — CatalogCourseCodeHelpers. |
| `College/Features/Catalog/CatalogCourseSearchBridge.swift` | Catalog module — CatalogCourseSearchHit. |
| `College/Features/Catalog/CatalogDegreeTypeFilter.swift` | Catalog module — CatalogDegreeTypeFilter. |
| `College/Features/Catalog/CatalogFetchPoliteness.swift` | Catalog module — CatalogFetchPoliteness. |
| `College/Features/Catalog/CatalogFileStore.swift` | Catalog module — CatalogFileStore. |
| `College/Features/Catalog/CatalogHostRequestScheduler.swift` | Catalog module — CatalogHostRequestScheduler. |
| `College/Features/Catalog/CatalogModels.swift` | Catalog module — SchoolManifest. |
| `College/Features/Catalog/CatalogOriginRobotsThrottle.swift` | Catalog module — CachedPolicy. |
| `College/Features/Catalog/CatalogPolicyScopeClassifier.swift` | Catalog module — CatalogPolicyScope. |
| `College/Features/Catalog/CatalogPrerequisiteValidator.swift` | Catalog module — ValidationResult. |
| `College/Features/Catalog/CatalogProgramMatching.swift` | Catalog module — CatalogProgramMatching. |
| `College/Features/Catalog/CatalogProgramPickerBridge.swift` | Catalog module — CatalogProgramPickerRowSnapshot. |
| `College/Features/Catalog/CatalogProgramReadBridge.swift` | Catalog module — CatalogProgramReadBridge. |
| `College/Features/Catalog/CatalogProgramRequirementsHydrator.swift` | Catalog module — WorkItem. |
| `College/Features/Catalog/CatalogProgramWriteBridge.swift` | Catalog module — CatalogProgramWriteBridge. |
| `College/Features/Catalog/CatalogRenderedHTMLFetcher.swift` | Catalog module — CatalogRenderedHTMLFetcher. |
| `College/Features/Catalog/CatalogScrapeStateBridge.swift` | Catalog module — CatalogScrapeStateBridge. |
| `College/Features/Catalog/CatalogSelectedProgramsStore.swift` | Catalog module — CatalogSelectedProgramsStore. |
| `College/Features/Catalog/CatalogSigningKeyManager.swift` | Catalog module — CatalogSigningKeyManager. |
| `College/Features/Catalog/CourseLeafCatalogSegmentDiscoverer.swift` | Catalog module — OnboardingCatalog. |
| `College/Features/Catalog/CourseLeafCourselistHTMLParser.swift` | Catalog module — CourseLeafCourselistHTMLParser. |
| `College/Features/Catalog/CourseLeafEngine.swift` | Catalog module — CrawlOutput. |
| `College/Features/Catalog/CourseLeafProgramRequirementsValidator.swift` | Catalog module — Result. |
| `College/Features/Catalog/CourseLeafProgramURLParser.swift` | Catalog module — CourseLeafProgramURLParser. |
| `College/Features/Catalog/CourseLeafRequirementsParser.swift` | Catalog module — RequirementFragments. |
| `College/Features/Catalog/CourseLeafXMLClient.swift` | Catalog module — CourseLeafXMLClient. |
| `College/Features/Catalog/DegreeTokenRegistry.swift` | Catalog module — Entry. |
| `College/Features/Catalog/DegreeTypeNormalizer.swift` | Catalog module — CanonicalDegreeType. |
| `College/Features/Catalog/ModernCampusAPI.swift` | Catalog module — ModernCampusAPI. |
| `College/Features/Catalog/ModernCampusCatalogLabels.swift` | Catalog module — ModernCampusCatalogLabels. |
| `College/Features/Catalog/ModernCampusEngine+Hydration.swift` | Swift source — ModernCampusEngine+Hydration. |
| `College/Features/Catalog/ModernCampusEngine.swift` | Catalog module — ScrapedProgram. |
| `College/Features/Catalog/ModernCampusPolicyIngestion.swift` | Catalog module — PolicyChunkRow. |
| `College/Features/Catalog/ProgramCatalogRequirementSheet.swift` | Catalog module — ProgramCatalogRequirementSheet. |
| `College/Features/Catalog/RequirementRowNormalizer.swift` | Catalog module — DisplayHierarchy. |
| `College/Features/Catalog/SchoolManifestCatalog.swift` | Catalog module — SchoolManifestCatalog. |
| `College/Features/Catalog/StringNormalization.swift` | Catalog module — StringNormalization. |
| `College/Features/Catalog/UniversalCatalogScraper.swift` | Catalog module — HierarchyItem. |
| `College/Features/Catalog/WebScraperService.swift` | Catalog module — BasicCourse. |
| `College/Features/Catalog/schools.json` | Test fixture or documentation artifact. |

### `College/Features/Catalog/CatalogEmbed/`

MLX sentence embedding bundle and vector search.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/CatalogEmbed/README.md` | Documentation. |

### `College/Features/Catalog/CatalogParsing/`

Shared catalog HTML/XML parsing utilities.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/CatalogParsing/PrerequisitePromptBuilder.swift` | Catalog module — PrerequisitePromptBuilder. |

### `College/Features/Catalog/CourseLeaf/`

CourseLeaf-specific catalog discovery and parsing.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/CourseLeaf/CatalogCourseLeafDOMAnalyzer.swift` | CourseLeaf index.xml / CDATA HTML → CatalogDocumentIR node tree + DOM features. |
| `College/Features/Catalog/CourseLeaf/CourseLeafEntityExtractor.swift` | Shared CourseLeaf course-block extraction (NYU / Fordham / CMU / legacy). |
| `College/Features/Catalog/CourseLeaf/CourseLeafIRPipeline.swift` | CourseLeaf ingest — DOM analyze → classify → profile extract → programs. |
| `College/Features/Catalog/CourseLeaf/CourseLeafLayoutClassifier.swift` | Deterministic CourseLeaf layout profile scoring from DOM feature vectors. |
| `College/Features/Catalog/CourseLeaf/CourseLeafLayoutProfiles.swift` | CourseLeaf layout profiles — entity extraction from CatalogDocumentIR. |
| `College/Features/Catalog/CourseLeaf/CourseLeafProfileConfig.swift` | Layout-profile extraction config (path hints, code/credit patterns) for CourseLeaf IR. |
| `College/Features/Catalog/CourseLeaf/CourseLeafRequirementSectionConfig.swift` | School-specific CourseLeaf requirement section naming (IR + requirements parser). |
| `College/Features/Catalog/CourseLeaf/CourseLeafSitemapCache.swift` | Deduplicate CourseLeaf sitemap.xml fetches within a single ingest run. |

### `College/Features/Catalog/Discovery/`

Catalog platform discovery and graph building.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/Discovery/CourseLeafCatalogDiscoverer.swift` | Catalog module — build immutable CatalogGraph from CourseLeaf sitemap URLs. |
| `College/Features/Catalog/Discovery/ModernCampusCatalogDiscoverer.swift` | Discovery-only CatalogGraph builder for Modern Campus / Acalog hosts. |

### `College/Features/Catalog/Ingest/`

Catalog download, scrape transactions, and import pipeline.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/Ingest/CatalogArchiveStore.swift` | Catalog module — Section. |
| `College/Features/Catalog/Ingest/CatalogArticulationReferenceStore.swift` | Optional articulation / Transferology rows keyed by course code per school. |
| `College/Features/Catalog/Ingest/CatalogCanonicalIR.swift` | Catalog module — CatalogCanonicalIR. |
| `College/Features/Catalog/Ingest/CatalogCanonicalIRStore.swift` | Catalog module — CatalogCanonicalIRStore. |
| `College/Features/Catalog/Ingest/CatalogCapabilityUI.swift` | Catalog module — CatalogCapabilityUI. |
| `College/Features/Catalog/Ingest/CatalogDocumentIR.swift` | Catalog module — immutable semantic document tree for catalog ingest. |
| `College/Features/Catalog/Ingest/CatalogDocumentIRStore.swift` | Application Support JSON cache of CatalogDocumentIR per school + catalog version. |
| `College/Features/Catalog/Ingest/CatalogEngineCapabilities.swift` | Catalog module — CatalogEngineCapabilities. |
| `College/Features/Catalog/Ingest/CatalogEntityExtractionResult.swift` | Catalog module — immutable entity rows produced from DocumentIR. |
| `College/Features/Catalog/Ingest/CatalogEntityIdentity.swift` | Catalog module — stable entity IDs across catalog versions. |
| `College/Features/Catalog/Ingest/CatalogEntityIdentityStore.swift` | Application Support JSON cache of catalog entity identities per school + version. |
| `College/Features/Catalog/Ingest/CatalogEntityLLMValidationStore.swift` | Persist async entity LLM validation results keyed by review snapshot ID. |
| `College/Features/Catalog/Ingest/CatalogEntityLLMValidator.swift` | Optional LLM validation for a single low-confidence catalog entity node (dev/review). |
| `College/Features/Catalog/Ingest/CatalogExternalReferenceBuilder.swift` | Populate ExternalReference on courses from engine-native IDs (Tier 3). |
| `College/Features/Catalog/Ingest/CatalogExtractionConfidence.swift` | Catalog module — CatalogExtractionConfidence. |
| `College/Features/Catalog/Ingest/CatalogExtractorMetrics.swift` | Per-run ingest metrics and historical baselines for sanity checks. |
| `College/Features/Catalog/Ingest/CatalogGoldenFixtureStore.swift` | Catalog module — Snapshot. |
| `College/Features/Catalog/Ingest/CatalogGraph.swift` | Catalog module — immutable discovery graph of bulletin page URLs. |
| `College/Features/Catalog/Ingest/CatalogImportTransforms.swift` | Catalog module — CatalogImportTransforms. |
| `College/Features/Catalog/Ingest/CatalogIngestCheckpoint.swift` | Catalog module — CatalogIntegrityReport. |
| `College/Features/Catalog/Ingest/CatalogIngestGate.swift` | Orchestrates sanity + invariants + recovery before catalog persist. |
| `College/Features/Catalog/Ingest/CatalogIngestObservability.swift` | Catalog module — CatalogIngestMetricSample. |
| `College/Features/Catalog/Ingest/CatalogIngestParityDiff.swift` | Dev helper — compare legacy crawl vs IR entity sets for offline fixtures. |
| `College/Features/Catalog/Ingest/CatalogIngestPersistenceHelpers.swift` | Shared identity resolution + provenance encoding for catalog ingest adapters. |
| `College/Features/Catalog/Ingest/CatalogIngestReconciler.swift` | Catalog module — CatalogIngestReconciler. |
| `College/Features/Catalog/Ingest/CatalogIngestRecoveryPolicy.swift` | Catalog module — scoped pass/partial/fail ingest recovery decisions. |
| `College/Features/Catalog/Ingest/CatalogIngestSnapshot.swift` | Catalog module — CatalogIngestSnapshot. |
| `College/Features/Catalog/Ingest/CatalogIngestTelemetry.swift` | Catalog module — CatalogIngestTelemetrySession. |
| `College/Features/Catalog/Ingest/CatalogLayoutCorpus.swift` | Organic layout corpus — grow from successful ingests (Tier 3, low cost). |
| `College/Features/Catalog/Ingest/CatalogLayoutFingerprint.swift` | Stable layout signature per catalog version for drift detection (Tier 2). |
| `College/Features/Catalog/Ingest/CatalogLayoutLLMClassifier.swift` | LLM fallback for ambiguous layout profile classification (Tier 2, last resort). |
| `College/Features/Catalog/Ingest/CatalogLayoutProfileGovernance.swift` | Layout profile registry rules — min schools per profile, per-school overrides. |
| `College/Features/Catalog/Ingest/CatalogLayoutProfileRegistry.swift` | Loads bundled layout profile metadata and school overrides for CourseLeafProfileConfig. |
| `College/Features/Catalog/Ingest/CatalogManifestCapabilities.swift` | Per-school capability metadata (transfer, articulation) beyond engine defaults. |
| `College/Features/Catalog/Ingest/CatalogParserCapability.swift` | Catalog module — CatalogParserCapability. |
| `College/Features/Catalog/Ingest/CatalogPlatformFlags.swift` | UserDefaults feature flags for catalog platform rollout. |
| `College/Features/Catalog/Ingest/CatalogPlatformProbe.swift` | Warn when manifest catalog_format disagrees with URL/HTML sniff (Tier 2). |
| `College/Features/Catalog/Ingest/CatalogProfileRegistry.json` | Test fixture or documentation artifact. |
| `College/Features/Catalog/Ingest/CatalogProvenance.swift` | Catalog module — traceability for extracted catalog entities. |
| `College/Features/Catalog/Ingest/CatalogRelationship.swift` | Catalog module — graph edges between stable catalog entities. |
| `College/Features/Catalog/Ingest/CatalogRelationshipStore.swift` | JSON persistence for catalog graph edges (prerequisites, etc.) per school. |
| `College/Features/Catalog/Ingest/CatalogReviewSeverity.swift` | Catalog module — review queue severity (critical blocks ingest). |
| `College/Features/Catalog/Ingest/CatalogReviewSnapshot.swift` | Review queue context snapshots (URL, excerpt, metrics) for operator triage. |
| `College/Features/Catalog/Ingest/CatalogSanityConstraints.swift` | Cheap post-extraction sanity checks against historical baselines. |
| `College/Features/Catalog/Ingest/CatalogSchoolImportService.swift` | Catalog module — ImportPolicy. |
| `College/Features/Catalog/Ingest/CatalogStructuralDiffEngine.swift` | Rename-aware structural diff via catalogStableID / display keys (Tier 2). |
| `College/Features/Catalog/Ingest/CatalogStructuralInvariantValidator.swift` | Pre-persist structural constraints for catalog ingest (highest ROI gate). |
| `College/Features/Catalog/Ingest/CatalogSyncProgress.swift` | Catalog module — CatalogSyncProgress. |
| `College/Features/Catalog/Ingest/CatalogVersion.swift` | Catalog module — catalog edition identity (school + bulletin slice). |
| `College/Features/Catalog/Ingest/PDFScrapeReport.swift` | Catalog module — PDFScrapeReport. |
| `College/Features/Catalog/Ingest/RequirementNodeIR.swift` | Catalog module — Node. |

### `College/Features/Catalog/ModernCampus/`

Modern Campus catalog engine and IR adapters.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/ModernCampus/CatalogModernCampusHTMLAnalyzer.swift` | Modern Campus HTML → CatalogDocumentIR (sidebar + content headers). |
| `College/Features/Catalog/ModernCampus/ModernCampusCatalogIngestAdapter.swift` | Modern Campus Document IR crawl — graph pages → programs/courses. |
| `College/Features/Catalog/ModernCampus/ModernCampusIRCourseExtractor.swift` | Extract CatalogCourse stubs from Modern Campus Document IR link nodes. |
| `College/Features/Catalog/ModernCampus/ModernCampusIRPipeline.swift` | Modern Campus ingest — HTML analyze → classify → profile extract (stub). |
| `College/Features/Catalog/ModernCampus/ModernCampusLayoutProfiles.swift` | Modern Campus layout profiles — feature-based IR entity extraction. |
| `College/Features/Catalog/ModernCampus/UniversalCatalogScraperIRConsumer.swift` | Build CatalogDocumentIR from CatalogGraph + UniversalCatalogScraper hierarchy pages. |

### `College/Features/Catalog/PDF/`

PDF catalog extraction and normalization.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/PDF/CatalogPDFBlockClassifier.swift` | Catalog module — CatalogPDFBlockClassifier. |
| `College/Features/Catalog/PDF/CatalogPDFCourseExtractor.swift` | Catalog module — CatalogPDFCourseExtractor. |
| `College/Features/Catalog/PDF/CatalogPDFDocumentModel.swift` | Catalog module — CatalogPDFDocumentSection. |
| `College/Features/Catalog/PDF/CatalogPDFEngine.swift` | Catalog module — CatalogPDFEngine. |
| `College/Features/Catalog/PDF/CatalogPDFError.swift` | Catalog module — CatalogPDFError. |
| `College/Features/Catalog/PDF/CatalogPDFIngestPersistence.swift` | Persist PDF Document IR, entity identities, and provenance-backed program rows. |
| `College/Features/Catalog/PDF/CatalogPDFLayoutReconstructor.swift` | Catalog module — CatalogPDFLayoutReconstructor. |
| `College/Features/Catalog/PDF/CatalogPDFNormalizer.swift` | Catalog module — CatalogPDFNormalizer. |
| `College/Features/Catalog/PDF/CatalogPDFPipeline.swift` | Catalog module — Options. |
| `College/Features/Catalog/PDF/CatalogPDFPolicyExtractor.swift` | Catalog module — CatalogPDFPolicyExtractor. |
| `College/Features/Catalog/PDF/CatalogPDFProfile.swift` | Catalog module — CatalogPDFHeadingRules. |
| `College/Features/Catalog/PDF/CatalogPDFProgramExtractor.swift` | Catalog module — CatalogPDFProgramExtractor. |
| `College/Features/Catalog/PDF/CatalogPDFProgramRejectLexicon.swift` | Catalog module — CatalogPDFProgramRejectLexicon. |
| `College/Features/Catalog/PDF/CatalogPDFRequirementExtractor.swift` | Parse degree-requirement course tables from catalog PDF program sections. |
| `College/Features/Catalog/PDF/CatalogPDFSectionClassifier.swift` | Catalog module — Input. |
| `College/Features/Catalog/PDF/CatalogPDFTextExtractor.swift` | Catalog module — CatalogPDFTextExtractor. |
| `College/Features/Catalog/PDF/CatalogPDFToDocumentIRAdapter.swift` | Map classified PDF blocks → shared CatalogDocumentIR (Tier 2). |
| `College/Features/Catalog/PDF/PDFPageTextCleaner.swift` | Catalog module — PDFPageTextCleaner. |

### `College/Features/Catalog/PDF/Profiles/`

Per-school PDF layout profiles.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/PDF/Profiles/brooklyn.json` | Test fixture or documentation artifact. |
| `College/Features/Catalog/PDF/Profiles/cmu.json` | Test fixture or documentation artifact. |
| `College/Features/Catalog/PDF/Profiles/fordham.json` | Test fixture or documentation artifact. |

### `College/Features/Catalog/Store/`

Catalog store snapshots and security bridges.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/Store/CatalogSchoolDataPurge.swift` | Catalog module — Report. |
| `College/Features/Catalog/Store/CatalogSchoolDataPurgeRunner.swift` | Catalog module — Target. |
| `College/Features/Catalog/Store/CatalogSchoolRemoval.swift` | Catalog module — CatalogSchoolRemoval. |
| `College/Features/Catalog/Store/CatalogSchoolScrapePurgeNotifier.swift` | Catalog module — CatalogSchoolScrapePurgeNotifier. |
| `College/Features/Catalog/Store/CatalogStoreCoordinator.swift` | Catalog module — SchoolStoreRecord. |
| `College/Features/Catalog/Store/CatalogStorePortableBridge.swift` | Catalog module — CatalogStorePortableBridge. |
| `College/Features/Catalog/Store/CatalogStoreSecurity.swift` | Catalog module — CatalogStoreEnvelope. |
| `College/Features/Catalog/Store/CatalogStoreSnapshotBridge.swift` | Catalog module — CatalogStoreSnapshotBridge. |

### `College/Features/Catalog/Vector/`

Catalog vector store lifecycle and embedding spikes.

| File | Purpose |
|------|---------|
| `College/Features/Catalog/Vector/CatalogChunkProjection+Store.swift` | Catalog module — CatalogChunkProjection+Store. |
| `College/Features/Catalog/Vector/CatalogChunkProjection.swift` | Catalog module — IndexedChunk. |
| `College/Features/Catalog/Vector/CatalogEmbedMemoryLifecycle.swift` | Catalog module — CatalogEmbedMemoryLifecycle. |
| `College/Features/Catalog/Vector/CatalogEmbeddingRuntime.swift` | Catalog module — CatalogEmbeddingRuntime. |
| `College/Features/Catalog/Vector/CatalogLexicalEmbedding.swift` | Catalog module — CatalogLexicalEmbedding. |
| `College/Features/Catalog/Vector/CatalogMLXEmbedService.swift` | Catalog module — CatalogMLEmbedError. |
| `College/Features/Catalog/Vector/CatalogModernBERTPhase0Spike.swift` | Catalog module — CatalogModernBERTPhase0Spike. |
| `College/Features/Catalog/Vector/CatalogVectorIndexer.swift` | Catalog module — CatalogVectorIndexError. |
| `College/Features/Catalog/Vector/CatalogVectorIndexingLifecycle.swift` | Catalog module — CatalogVectorIndexingLifecycle. |
| `College/Features/Catalog/Vector/CatalogVectorStore.swift` | Catalog module — Row. |
| `College/Features/Catalog/Vector/MLXTaskQueue.swift` | Catalog module — MLXTaskQueueError. |
| `College/Features/Catalog/Vector/VecturaServiceBoundary.swift` | Catalog module — VecturaMLXKitIsolationNotes. |

### `College/Features/Courses/`

Course detail sheets and catalog search UI.

| File | Purpose |
|------|---------|
| `College/Features/Courses/AddCourseView.swift` | Courses module — AddCourseView. |
| `College/Features/Courses/AddSemesterView.swift` | Courses module — AddSemesterView. |
| `College/Features/Courses/CourseCatalogEntity+Display.swift` | Courses module — CourseCatalogEntity+Display. |
| `College/Features/Courses/CourseCatalogManagerView.swift` | Courses module — CourseCatalogManagerView. |
| `College/Features/Courses/CourseCatalogService.swift` | Courses module — CourseCatalogService. |
| `College/Features/Courses/CourseDashboardReadBridge.swift` | Courses module — Payload. |
| `College/Features/Courses/CourseDashboardView.swift` | Courses module — CourseDashboardView. |
| `College/Features/Courses/CourseSearchView.swift` | Courses module — CourseSearchView. |
| `College/Features/Courses/EditCourseDetailsView.swift` | Courses module — EditCourseDetailsView. |
| `College/Features/Courses/GPACalculatorPopoverView.swift` | Courses module — GPACalculatorPopoverView. |
| `College/Features/Courses/GenEdAddCourseModal.swift` | Courses module — GenEdAddCourseModal. |

### `College/Features/Degree/`

Degree validation, configuration, and major/minor detail views.

| File | Purpose |
|------|---------|
| `College/Features/Degree/DegreeConfiguration.swift` | Degree module — DegreeLevel. |
| `College/Features/Degree/DegreeView.swift` | Swift source — DegreeView. |
| `College/Features/Degree/GraduationValidator.swift` | Degree module — GraduationValidationResult. |
| `College/Features/Degree/MajorMinorDetailsView.swift` | Degree module — MajorMinorDetailsView. |
| `College/Features/Degree/PrerequisiteValidator.swift` | Degree module — PrerequisiteValidationResult. |

### `College/Features/Documents/`

Document Vault UI, grid/list layouts, and file actions.

| File | Purpose |
|------|---------|
| `College/Features/Documents/DocumentsVaultQueryHost.swift` | Documents module — DocumentsVaultQueryHost. |
| `College/Features/Documents/DocumentsView.swift` | Documents module — DocumentsEntranceModifier. |

### `College/Features/LMS/`

Embedded LMS portal, import flows, and credential storage.

| File | Purpose |
|------|---------|
| `College/Features/LMS/LMSDownloadManager.swift` | LMS module — LMSDownloadManager. |
| `College/Features/LMS/LMSImportSheet.swift` | LMS module — LMSImportSheet. |
| `College/Features/LMS/LMSJSBridge.js` | Repository file. |
| `College/Features/LMS/LMSKeychainService.swift` | LMS module — LMSKeychainService. |
| `College/Features/LMS/LMSView.swift` | LMS module — LMSView. |
| `College/Features/LMS/LMSWebCoordinator.swift` | LMS module — LMSImportItem. |

### `College/Features/Overview/`

Dashboard hub, widgets, needs-attention strip, and quick actions.

| File | Purpose |
|------|---------|
| `College/Features/Overview/MultiDegreeOverviewCards.swift` | Overview module — AllDegreesProgressCard. |
| `College/Features/Overview/OverviewDeepCatalogPrompt.swift` | Swift source — OverviewDeepCatalogPrompt. |
| `College/Features/Overview/OverviewQueryHost.swift` | Overview module — OverviewQueryHost. |
| `College/Features/Overview/OverviewReadBridge.swift` | Overview module — OverviewTaskSummary. |
| `College/Features/Overview/OverviewView.swift` | Overview module — ShimmerEffect. |
| `College/Features/Overview/WeatherService.swift` | Overview module — WeatherData. |

### `College/Features/Overview/WidgetKit/`

Dashboard hub, widgets, needs-attention strip, and quick actions. (continued)

| File | Purpose |
|------|---------|
| `College/Features/Overview/WidgetKit/EqualizerBarsView.swift` | Overview module — EqualizerBarsView. |
| `College/Features/Overview/WidgetKit/OverviewCard.swift` | Overview module — OverviewCard. |
| `College/Features/Overview/WidgetKit/WidgetConfiguration.swift` | Swift source — WidgetConfiguration. |
| `College/Features/Overview/WidgetKit/WidgetDescriptor.swift` | Overview module — in. |
| `College/Features/Overview/WidgetKit/WidgetPickerView.swift` | Swift source — WidgetPickerView. |
| `College/Features/Overview/WidgetKit/WidgetRegistry.swift` | Overview module — WidgetRegistry. |

### `College/Features/Overview/Widgets/`

Dashboard hub, widgets, needs-attention strip, and quick actions. (continued)

| File | Purpose |
|------|---------|
| `College/Features/Overview/Widgets/AcademicCalendarWidget.swift` | Overview module — AcademicCalendarWidget. |
| `College/Features/Overview/Widgets/AcademicsWidget.swift` | Overview module — AcademicsWidget. |
| `College/Features/Overview/Widgets/CareerConversionWidget.swift` | Swift source — CareerConversionWidget. |
| `College/Features/Overview/Widgets/CareerFollowUpsWidget.swift` | Overview module — CareerFollowUpsWidget. |
| `College/Features/Overview/Widgets/CareerPipelineWidget.swift` | Overview module — CareerPipelineWidget. |
| `College/Features/Overview/Widgets/DeadlinesWidget.swift` | Overview module — DeadlinesWidget. |
| `College/Features/Overview/Widgets/DocumentsWidget.swift` | Overview module — DocumentsWidget. |
| `College/Features/Overview/Widgets/EventsWidget.swift` | Overview module — EventsWidget. |
| `College/Features/Overview/Widgets/MultiDegreeProgressWidget.swift` | Swift source — MultiDegreeProgressWidget. |
| `College/Features/Overview/Widgets/ScheduleWidget.swift` | Overview module — ScheduleWidget. |
| `College/Features/Overview/Widgets/TasksWidget.swift` | Overview module — TasksWidget. |
| `College/Features/Overview/Widgets/WeatherWidget.swift` | Swift source — WeatherWidget. |

### `College/Features/Profile/`

Identity, experience, achievements, and portfolio UI.

| File | Purpose |
|------|---------|
| `College/Features/Profile/AcademicDegreeTabBar.swift` | Profile module — AcademicDegreeTabBar. |
| `College/Features/Profile/AcademicIdentityView.swift` | Swift source — AcademicIdentityView. |
| `College/Features/Profile/AcademicProfileEditFields.swift` | Profile module — AcademicProfileEditFields. |
| `College/Features/Profile/AcademicProfileReadBridge.swift` | Profile module — AcademicProfileReadBridge. |
| `College/Features/Profile/AchievementsView.swift` | Profile module — AchievementsView. |
| `College/Features/Profile/AdvisorMeetingPrepView.swift` | Profile module — AdvisorMeetingPrepView. |
| `College/Features/Profile/DeclaredProgramDegreeMetadata.swift` | Profile module — Inference. |
| `College/Features/Profile/ExperienceView.swift` | Profile module — ExperienceView. |
| `College/Features/Profile/PortfolioProject.swift` | Profile module — PortfolioProject. |
| `College/Features/Profile/Profile+Display.swift` | Profile module — Profile+Display. |
| `College/Features/Profile/ProfileCompatibility.swift` | Profile module — ProfileEditMajorSection. |
| `College/Features/Profile/ProfileEditOptions.swift` | Profile module — ProfileEditOptions. |
| `College/Features/Profile/ProfileEditSheet.swift` | Profile module — ProfileEditSheet. |
| `College/Features/Profile/ProfileReadBridge.swift` | Profile module — ProfileShellSnapshot. |
| `College/Features/Profile/ProfileView.swift` | Profile module — CardSurfaceModifier. |
| `College/Features/Profile/ProgramListControls.swift` | Profile module — ProgramListControls. |
| `College/Features/Profile/ProgramListSerialization.swift` | Profile module — ProgramListSerialization. |

### `College/Features/Settings/`

Preferences, catalog sync settings, and diagnostics cards.

| File | Purpose |
|------|---------|
| `College/Features/Settings/AppUpdateCheckService.swift` | Settings module — AppUpdateInfo. |
| `College/Features/Settings/CatalogTrustedSourcesView.swift` | Settings module — CatalogTrustedSourcesView. |
| `College/Features/Settings/MacStandaloneSettingsRoot.swift` | Settings module — MacStandaloneSettingsRoot. |
| `College/Features/Settings/SettingsAssistantPanel.swift` | Settings module — SettingsAssistantPanel. |
| `College/Features/Settings/SettingsCareerPanel.swift` | Settings module — SettingsCareerPanel. |
| `College/Features/Settings/SettingsCatalogReviewDiagnosticsView.swift` | Tier 2 catalog review queue, layout drift, and structural diff detail. |
| `College/Features/Settings/SettingsCatalogSelectedProgramsBlock.swift` | Settings module — SettingsCatalogSelectedProgramsBlock. |
| `College/Features/Settings/SettingsCatalogSyncSection.swift` | Settings module — SettingsCatalogSyncSection. |
| `College/Features/Settings/SettingsChromeViews.swift` | Native sidebar profile row for Settings. |
| `College/Features/Settings/SettingsJobBoardsPanel.swift` | Settings module — SettingsJobBoardsPanel. |
| `College/Features/Settings/SettingsMetrics.swift` | Settings module — SettingsMetrics. |
| `College/Features/Settings/SettingsNavSection.swift` | Settings module — SettingsNavSection. |
| `College/Features/Settings/SettingsNavigation.swift` | Settings module — SettingsNavigateToSectionKey. |
| `College/Features/Settings/SettingsPanels_Academics.swift` | Settings module — SettingsAcademicsPanel. |
| `College/Features/Settings/SettingsPanels_App.swift` | Settings module — SettingsAppPanel. |
| `College/Features/Settings/SettingsPanels_Appearance.swift` | Settings module — SettingsAppearancePanel. |
| `College/Features/Settings/SettingsPanels_Calendar.swift` | Settings module — SettingsCalendarPanel. |
| `College/Features/Settings/SettingsPanels_General.swift` | Swift source — SettingsPanels_General. |
| `College/Features/Settings/SettingsPanels_Profile.swift` | Settings module — SettingsProfilePanel. |
| `College/Features/Settings/SettingsPanels_Services.swift` | Settings module — ConnectedServiceRow. |
| `College/Features/Settings/SettingsPerformanceDiagnosticsCard.swift` | Settings module — SettingsPerformanceDiagnosticsCard. |
| `College/Features/Settings/SettingsSearchIndex.swift` | Settings module — Hit. |
| `College/Features/Settings/SettingsSessionController.swift` | Settings module — section state, history, and lightweight window chrome. |
| `College/Features/Settings/SettingsSidebarSplitLock.swift` | Swift source — SettingsSidebarSplitLock. |
| `College/Features/Settings/SettingsView.swift` | Settings module — SettingsView. |
| `College/Features/Settings/SettingsWebShortcutsPanel.swift` | Settings module — SettingsWebShortcutsPanel. |
| `College/Features/Settings/WatchdogSettingsPanel.swift` | Settings module — WatchdogSettingsPanel. |

### `College/Features/SyllabusAI/`

Syllabus PDF analysis, event extraction, and review flows.

| File | Purpose |
|------|---------|
| `College/Features/SyllabusAI/AIStorageViewModel.swift` | SyllabusAI module — AIStorageViewModel. |
| `College/Features/SyllabusAI/JSONSanitizer.swift` | SyllabusAI module — JSONSanitizer. |
| `College/Features/SyllabusAI/LLMMemoryLifecycle.swift` | SyllabusAI module — LLMMemoryLifecycle. |
| `College/Features/SyllabusAI/LLMOnDemandPrewarm.swift` | SyllabusAI module — LLMOnDemandPrewarm. |
| `College/Features/SyllabusAI/LLMSamplingProfile.swift` | SyllabusAI module — LLMSamplingProfile. |
| `College/Features/SyllabusAI/LocalLLMRunner.swift` | SyllabusAI module — LocalLLMRunnerError. |
| `College/Features/SyllabusAI/LocalLLMStubResponder.swift` | SyllabusAI module — LocalLLMStubResponder. |
| `College/Features/SyllabusAI/MLXTokenizerBridge.swift` | SyllabusAI module — Adapted. |
| `College/Features/SyllabusAI/ModelBootstrapService.swift` | SyllabusAI module — ModelBootstrapService. |
| `College/Features/SyllabusAI/ModelManager.swift` | SyllabusAI module — ModelSpec. |
| `College/Features/SyllabusAI/ModelMigrationService.swift` | SyllabusAI module — ModelMigrationService. |
| `College/Features/SyllabusAI/SyllabusAnalysisViewModel.swift` | SyllabusAI module — DraftSyllabusEvent. |
| `College/Features/SyllabusAI/SyllabusHeuristicExtractor.swift` | SyllabusAI module — Extraction. |
| `College/Features/SyllabusAI/SyllabusModels.swift` | SyllabusAI module — SyllabusData. |
| `College/Features/SyllabusAI/SyllabusPDFIngestService.swift` | SyllabusAI module — SyllabusIngestResult. |
| `College/Features/SyllabusAI/SyllabusPromptBuilder.swift` | SyllabusAI module — SyllabusPromptBuilder. |
| `College/Features/SyllabusAI/SyllabusReviewView.swift` | SyllabusAI module — SyllabusReviewView. |
| `College/Features/SyllabusAI/SyllabusScheduleInference.swift` | SyllabusAI module — Extraction. |

### `College/Rust/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `College/Rust/CollegeCoreSwift.swift` | Rust module — CollegeCore. |

## CollegeShareExtension


### `CollegeShareExtension/`

macOS Share Extension for saving files into the Document Vault.

| File | Purpose |
|------|---------|
| `CollegeShareExtension/CollegeShareExtension.entitlements` | App or extension bundle configuration. |
| `CollegeShareExtension/Info.plist` | App or extension bundle configuration. |
| `CollegeShareExtension/ShareViewController.swift` | Swift source — ShareViewController. |

## CollegeTests


### `CollegeTests/`

Unit and integration tests mirroring production feature layout.

| File | Purpose |
|------|---------|
| `CollegeTests/Info.plist` | App or extension bundle configuration. |

### `CollegeTests/App/`

App shell and toolbar architecture tests.

| File | Purpose |
|------|---------|
| `CollegeTests/App/GlassToolbarAccessibilityTests.swift` | Accessibility contract for window toolbar controls. |
| `CollegeTests/App/ToolbarArchitectureTests.swift` | Architecture enforcement for toolbar refactor (ADR 001–007). |
| `CollegeTests/App/ToolbarVisualTests.swift` | Liquid Glass toolbar visual regression snapshots. |

### `CollegeTests/Core/`

Cross-cutting Core regression tests.

| File | Purpose |
|------|---------|
| `CollegeTests/Core/CollegeCoreSwiftRegressionTests.swift` | Shared module — CollegeCoreSwiftRegressionTests. |
| `CollegeTests/Core/PackageImportBoundaryTests.swift` | Unit tests for PackageImportBoundary. |
| `CollegeTests/Core/UserDefaultsWindowAutosaveCleanupTests.swift` | Shared module — UserDefaultsWindowAutosaveCleanupTests. |

### `CollegeTests/Features/Academics/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Academics/AcademicsAuditSnapshotStoreTests.swift` | Academics module — AcademicsAuditSnapshotStoreTests. |
| `CollegeTests/Features/Academics/AcademicsPlannerCreditsBridgeTests.swift` | Academics module — AcademicsPlannerCreditsBridgeTests. |
| `CollegeTests/Features/Academics/RequirementBreakdownCreditsTests.swift` | Academics module — RequirementBreakdownCreditsTests. |
| `CollegeTests/Features/Academics/RequirementDisplayHierarchyTests.swift` | Academics module — RequirementDisplayHierarchyTests. |
| `CollegeTests/Features/Academics/RequirementFulfillmentStoreTests.swift` | Academics module — RequirementFulfillmentStoreTests. |
| `CollegeTests/Features/Academics/RequirementProgressEngineTests.swift` | Academics module — RequirementProgressEngineTests. |
| `CollegeTests/Features/Academics/RequirementProgressParityTests.swift` | Academics module — RequirementProgressParityTests. |

### `CollegeTests/Features/Assistant/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Assistant/AIAssistantPhase8ToolsTests.swift` | Assistant module — AIAssistantPhase8ToolsTests. |
| `CollegeTests/Features/Assistant/AssistantInferenceAvailabilityTests.swift` | Assistant module — AssistantInferenceAvailabilityTests. |
| `CollegeTests/Features/Assistant/AssistantInferenceSessionTests.swift` | Assistant module — AssistantInferenceSessionTests. |
| `CollegeTests/Features/Assistant/AssistantIntentEmbeddingTests.swift` | Assistant module — AssistantIntentEmbeddingTests. |
| `CollegeTests/Features/Assistant/AssistantIntentNLModelRoutingTests.swift` | Assistant module — AssistantIntentNLModelRoutingTests. |
| `CollegeTests/Features/Assistant/AssistantPlanJSONParserTests.swift` | Assistant module — AssistantPlanJSONParserTests. |
| `CollegeTests/Features/Assistant/AssistantProfessionalHandbookRegistryTests.swift` | Assistant module — AssistantProfessionalHandbookRegistryTests. |
| `CollegeTests/Features/Assistant/AssistantSecurityTests.swift` | Assistant module — AssistantSecurityTests. |
| `CollegeTests/Features/Assistant/AssistantSettingsKeyTests.swift` | Assistant module — AssistantSettingsKeyTests. |
| `CollegeTests/Features/Assistant/FMRegistryToolAdapterTests.swift` | Assistant module — FMRegistryToolAdapterTests. |
| `CollegeTests/Features/Assistant/LocalLLMRunnerMemoryTests.swift` | Shared module — LocalLLMRunnerMemoryTests. |
| `CollegeTests/Features/Assistant/PlannerChunkProjectionCalendarTests.swift` | Assistant module — PlannerChunkProjectionCalendarTests. |
| `CollegeTests/Features/Assistant/PlannerVectorStoreTests.swift` | Assistant module — PlannerVectorStoreTests. |
| `CollegeTests/Features/Assistant/QwenJsonWorkerGoldenTests.swift` | Shared module — QwenJsonWorkerGoldenTests. |

### `CollegeTests/Features/Calendar/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Calendar/CalendarPlannerBridgeTests.swift` | Calendar module — CalendarPlannerBridgeTests. |
| `CollegeTests/Features/Calendar/CalendarReadBridgeTests.swift` | Calendar module — CalendarReadBridgeTests. |
| `CollegeTests/Features/Calendar/CalendarSearchStoreTests.swift` | Calendar module — CalendarSearchStoreTests. |
| `CollegeTests/Features/Calendar/CalendarWriteRepositoryTests.swift` | Calendar module — CalendarWriteRepositoryTests. |

### `CollegeTests/Features/Career/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Career/CareerReadBridgeTests.swift` | Career module — CareerReadBridgeTests. |
| `CollegeTests/Features/Career/CareerRepositoryStoreTests.swift` | Career module — CareerRepositoryStoreTests. |
| `CollegeTests/Features/Career/CareerSyncBridgeTests.swift` | Career module — CareerSyncBridgeTests. |
| `CollegeTests/Features/Career/JobBoardReadBridgeTests.swift` | Career module — JobBoardReadBridgeTests. |
| `CollegeTests/Features/Career/WorkdayScraperLiveTests.swift` | Optional live-network Workday scrape validation (offline by default in CI). |
| `CollegeTests/Features/Career/WorkdayScraperTests.swift` | Workday URL derivation, decoder, and scraper helper regressions. |

### `CollegeTests/Features/Catalog/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Catalog/CatalogBackgroundSyncStoreTests.swift` | Catalog module — CatalogBackgroundSyncStoreTests. |
| `CollegeTests/Features/Catalog/CatalogChunkProjectionStoreTests.swift` | Catalog module — CatalogChunkProjectionStoreTests. |
| `CollegeTests/Features/Catalog/CatalogCourseSearchBridgeTests.swift` | Catalog module — CatalogCourseSearchBridgeTests. |
| `CollegeTests/Features/Catalog/CatalogCourseSearchTests.swift` | Catalog module — CatalogCourseSearchTests. |
| `CollegeTests/Features/Catalog/CatalogDocumentIRGoldenTests.swift` | Offline DOM analyzer golden — section paths, profile ID, node counts. |
| `CollegeTests/Features/Catalog/CatalogDocumentIRStoreTests.swift` | Round-trip persistence for CatalogDocumentIR JSON cache. |
| `CollegeTests/Features/Catalog/CatalogEntityIdentityTests.swift` | Catalog entity identity matcher — stable ID reuse across syncs. |
| `CollegeTests/Features/Catalog/CatalogEntityLLMValidatorTests.swift` | Auto-validation gating (no model invocation). |
| `CollegeTests/Features/Catalog/CatalogExternalReferenceBuilderTests.swift` | ExternalReference population from engine-native course IDs. |
| `CollegeTests/Features/Catalog/CatalogGraphDiscoveryTests.swift` | Catalog graph discovery — URL classification and graph shape (no network). |
| `CollegeTests/Features/Catalog/CatalogIngestFreshnessTests.swift` | Catalog module — CatalogIngestFreshnessTests. |
| `CollegeTests/Features/Catalog/CatalogIngestGateModernCampusTests.swift` | Modern Campus ingest gate — invariants, recovery, layout profile metrics. |
| `CollegeTests/Features/Catalog/CatalogIngestGateTests.swift` | Catalog platform PR0 gate — invariants, sanity, recovery, review severity. |
| `CollegeTests/Features/Catalog/CatalogIngestParityDiffTests.swift` | Offline legacy vs IR entity-set parity for frozen CourseLeaf fixtures. |
| `CollegeTests/Features/Catalog/CatalogInvariantSanityFixtureTests.swift` | Ingest gate critical vs warning behavior on fixture-scale metrics. |
| `CollegeTests/Features/Catalog/CatalogLayoutDriftTests.swift` | Layout fingerprint drift detection (non-blocking warnings). |
| `CollegeTests/Features/Catalog/CatalogLayoutLLMClassifierTests.swift` | Ambiguity gating for layout LLM fallback (no model invocation). |
| `CollegeTests/Features/Catalog/CatalogLayoutProfileGovernanceTests.swift` | Layout profile governance and school override resolution. |
| `CollegeTests/Features/Catalog/CatalogManifestCapabilitiesTests.swift` | Per-school capability metadata beyond engine defaults. |
| `CollegeTests/Features/Catalog/CatalogModelsStoreTests.swift` | Catalog module — CatalogModelsStoreTests. |
| `CollegeTests/Features/Catalog/CatalogPDFToDocumentIRAdapterTests.swift` | PDF classified blocks → CatalogDocumentIR mapping. |
| `CollegeTests/Features/Catalog/CatalogPartitionEntitySmokeTests.swift` | Catalog module — CatalogPartitionEntitySmokeTests. |
| `CollegeTests/Features/Catalog/CatalogPolicyIngestionTests.swift` | Catalog module — CatalogPolicyIngestionTests. |
| `CollegeTests/Features/Catalog/CatalogProgramRequirementsHydratorTests.swift` | Catalog module — CatalogProgramRequirementsHydratorTests. |
| `CollegeTests/Features/Catalog/CatalogSchoolDataPurgeTests.swift` | Catalog module — CatalogSchoolDataPurgeTests. |
| `CollegeTests/Features/Catalog/CatalogScrapePurgePredicateTests.swift` | Catalog module — CatalogScrapePurgePredicateTests. |
| `CollegeTests/Features/Catalog/CatalogStoreSecurityTests.swift` | Catalog module — CatalogStoreSecurityTests. |
| `CollegeTests/Features/Catalog/CatalogStructuralDiffEngineTests.swift` | Structural diff via stable entity identities. |
| `CollegeTests/Features/Catalog/CatalogVectorIngestionTests.swift` | Catalog module — CatalogVectorIngestionTests. |
| `CollegeTests/Features/Catalog/CatalogVectorStoreScopeTests.swift` | Catalog module — CatalogVectorStoreScopeTests. |
| `CollegeTests/Features/Catalog/CatalogWAFDetectionTests.swift` | Catalog module — CatalogWAFDetectionTests. |
| `CollegeTests/Features/Catalog/CourseLeafCatalogCatoidMatchingTests.swift` | Shared module — CourseLeafCatalogCatoidMatchingTests. |
| `CollegeTests/Features/Catalog/CourseLeafCatalogSegmentDiscovererTests.swift` | Shared module — CourseLeafCatalogSegmentDiscovererTests. |
| `CollegeTests/Features/Catalog/CourseLeafCourselistParserSemanticsTests.swift` | Shared module — CourseLeafCourselistParserSemanticsTests. |
| `CollegeTests/Features/Catalog/CourseLeafCrawlRequirementsIntegrationTests.swift` | Shared module — CourseLeafCrawlRequirementsIntegrationTests. |
| `CollegeTests/Features/Catalog/CourseLeafGoldenFixtureTests.swift` | Shared module — Manifest. |
| `CollegeTests/Features/Catalog/CourseLeafHonorsTrackStorageTests.swift` | Shared module — CourseLeafHonorsTrackStorageTests. |
| `CollegeTests/Features/Catalog/CourseLeafLayoutClassifierTests.swift` | Deterministic layout profile classification from DOM feature vectors. |
| `CollegeTests/Features/Catalog/CourseLeafLiveContractTests.swift` | Shared module — SchoolLiveContract. |
| `CollegeTests/Features/Catalog/CourseLeafLiveSiteSmokeTests.swift` | Shared module — CourseLeafLiveSiteSmokeTests. |
| `CollegeTests/Features/Catalog/CourseLeafNYUCSBABreakdownRegressionTests.swift` | Shared module — CourseLeafNYUCSBABreakdownRegressionTests. |
| `CollegeTests/Features/Catalog/CourseLeafNYUCSBADiagnosticDumpTests.swift` | Shared module — CourseLeafNYUCSBADiagnosticDumpTests. |
| `CollegeTests/Features/Catalog/CourseLeafNYUSternBusinessBreakdownRegressionTests.swift` | Shared module — CourseLeafNYUSternBusinessBreakdownRegressionTests. |
| `CollegeTests/Features/Catalog/CourseLeafNYUTandonCybersecurityMinorRegressionTests.swift` | Shared module — CourseLeafNYUTandonCybersecurityMinorRegressionTests. |
| `CollegeTests/Features/Catalog/CourseLeafProgramCoverageTests.swift` | Shared module — CourseLeafProgramCoverageTests. |
| `CollegeTests/Features/Catalog/CourseLeafProgramIndexingTests.swift` | Shared module — CourseLeafProgramIndexingTests. |
| `CollegeTests/Features/Catalog/CourseLeafProgramURLParserTests.swift` | Shared module — CourseLeafProgramURLParserTests. |
| `CollegeTests/Features/Catalog/CourseLeafRequirementsBreakdownGoldenTests.swift` | Shared module — CourseLeafRequirementsBreakdownGoldenTests. |
| `CollegeTests/Features/Catalog/CourseLeafRequirementsGoldenTests.swift` | Shared module — GoldenManifest. |
| `CollegeTests/Features/Catalog/CourseLeafRequirementsSchoolWideTests.swift` | Shared module — CourseLeafRequirementsSchoolWideTests. |
| `CollegeTests/Features/Catalog/CourseLeafRequirementsSectionTests.swift` | Shared module — CourseLeafRequirementsSectionTests. |
| `CollegeTests/Features/Catalog/CourseLeafRequirementsXMLTests.swift` | Shared module — CourseLeafRequirementsXMLTests. |
| `CollegeTests/Features/Catalog/CourseLeafRoutingTests.swift` | Shared module — CourseLeafRoutingTests. |
| `CollegeTests/Features/Catalog/CourseLeafSitemapCacheTests.swift` | CourseLeaf sitemap cache deduplicates network fetches per base URL. |
| `CollegeTests/Features/Catalog/DSUProgramRequirementsParserTests.swift` | Shared module — DSUProgramRequirementsParserTests. |
| `CollegeTests/Features/Catalog/DakotaStateUniversityCatalogScraperTests.swift` | Shared module — DakotaStateUniversityCatalogScraperTests. |
| `CollegeTests/Features/Catalog/ModernCampusCatalogDiscovererTests.swift` | Modern Campus graph discovery — URL classification and offline graph shape. |
| `CollegeTests/Features/Catalog/ModernCampusCatalogIngestAdapterTests.swift` | MC IR course merge + fallback thresholds. |
| `CollegeTests/Features/Catalog/ModernCampusIRCourseExtractorTests.swift` | MC Document IR → course stub extraction. |
| `CollegeTests/Features/Catalog/ModernCampusIRPipelineTests.swift` | Offline Modern Campus IR pipeline — layout profile + program extraction. |
| `CollegeTests/Features/Catalog/NYUCourseLeafRequirementsParserTests.swift` | Shared module — NYUCourseLeafRequirementsParserTests. |
| `CollegeTests/Features/Catalog/PDFCatalogIngestFixtureTests.swift` | Shared module — SchoolExpectations. |
| `CollegeTests/Features/Catalog/ProgramCatalogParserTests.swift` | Shared module — ProgramCatalogParserTests. |
| `CollegeTests/Features/Catalog/UniversalCatalogScraperIRConsumerTests.swift` | Document IR merge/build helpers for UniversalCatalogScraper graph consumer. |

### `CollegeTests/Features/Degree/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Degree/DegreeTypeInferenceTests.swift` | Degree module — DegreeTypeInferenceTests. |

### `CollegeTests/Features/Documents/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Documents/VaultReadBridgeTests.swift` | Documents module — VaultReadBridgeTests. |
| `CollegeTests/Features/Documents/VaultSyncTests.swift` | Documents module — VaultSyncTests. |

### `CollegeTests/Features/Profile/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Profile/MinorProgramResolutionTests.swift` | Profile module — MinorProgramResolutionTests. |
| `CollegeTests/Features/Profile/OverviewReadBridgeTests.swift` | Profile module — OverviewReadBridgeTests. |
| `CollegeTests/Features/Profile/ProfileCalendarSyncBridgeTests.swift` | Profile module — ProfileCalendarSyncBridgeTests. |
| `CollegeTests/Features/Profile/ProfileDomainRepositoriesStoreTests.swift` | Profile module — ProfileDomainRepositoriesStoreTests. |
| `CollegeTests/Features/Profile/ProfilePartitionEntitySmokeTests.swift` | Profile module — ProfilePartitionEntitySmokeTests. |
| `CollegeTests/Features/Profile/ProfilePlannerModelsStoreTests.swift` | Profile module — ProfilePlannerModelsStoreTests. |
| `CollegeTests/Features/Profile/ProfilePlannerReadBridgeTests.swift` | Profile module — ProfilePlannerReadBridgeTests. |
| `CollegeTests/Features/Profile/ProfilePlannerSyncBridgeTests.swift` | Profile module — ProfilePlannerSyncBridgeTests. |
| `CollegeTests/Features/Profile/ProfileReadBridgeTests.swift` | Profile module — ProfileReadBridgeTests. |
| `CollegeTests/Features/Profile/ProfileWriteRepositoryTests.swift` | Profile module — ProfileWriteRepositoryTests. |

### `CollegeTests/Features/Settings/`

Feature-scoped unit tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Features/Settings/AppUpdateCheckServiceTests.swift` | Shared module — AppUpdateCheckServiceTests. |

### `CollegeTests/Fixtures/`

Catalog scrape fixtures (CourseLeaf XML, HTML, golden JSON).

| File | Purpose |
|------|---------|
| `CollegeTests/Fixtures/DSUCyberDefenseMS3975.html` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/majors_page.html` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/program_page.html` | Test fixture or documentation artifact. |

### `CollegeTests/Fixtures/CourseLeaf/`

Catalog scrape fixtures (CourseLeaf XML, HTML, golden JSON). (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Fixtures/CourseLeaf/CourseLeafRequirementsGolden.json` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/cmu_courses_index.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/cmu_undergrad_cs_major.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/fordham_aa_major.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/fordham_aast_courses.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/fordham_accounting_minor.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/golden_manifest.json` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_abu_dhabi_cs_bs_major.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_cs_ba_major.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_cs_minor.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_csci_ua_courses.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_stern_business_bs_major.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_tandon_cs_bs_major.xml` | Test fixture or documentation artifact. |
| `CollegeTests/Fixtures/CourseLeaf/nyu_tandon_cybersecurity_minor.xml` | Test fixture or documentation artifact. |

### `CollegeTests/Fixtures/ModernCampus/`

Catalog scrape fixtures (CourseLeaf XML, HTML, golden JSON). (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/Fixtures/ModernCampus/program_listing_snippet.html` | Test fixture or documentation artifact. |

### `CollegeTests/Performance/`

Launch and performance baseline acceptance tests.

| File | Purpose |
|------|---------|
| `CollegeTests/Performance/LaunchPerformanceAcceptanceTests.swift` | Shared module — LaunchPerformanceAcceptanceTests. |
| `CollegeTests/Performance/PerformanceBaselineAcceptanceTests.swift` | Shared module — PerformanceBaselineAcceptanceTests. |

### `CollegeTests/Persistence/`

Schema migration, backup, and persistence harness tests.

| File | Purpose |
|------|---------|
| `CollegeTests/Persistence/AppBackupRestoreStoreTests.swift` | Shared module — AppBackupRestoreStoreTests. |
| `CollegeTests/Persistence/DataWipeStoreTests.swift` | Shared module — DataWipeStoreTests. |
| `CollegeTests/Persistence/LaunchSingleCatalogMmapTests.swift` | Shared module — LaunchSingleCatalogMmapTests. |
| `CollegeTests/Persistence/PersistenceFixtureFactory.swift` | Shared module — SeedIDs. |
| `CollegeTests/Persistence/PersistenceTestCase.swift` | Shared module — PersistenceTestCase. |
| `CollegeTests/Persistence/PersistenceTestHarness.swift` | Shared module — Containers. |
| `CollegeTests/Persistence/SchemaMigrationPlanTests.swift` | Shared module — SchemaMigrationPlanTests. |

### `CollegeTests/Support/`

Shared test helpers and snapshot harnesses.

| File | Purpose |
|------|---------|
| `CollegeTests/Support/CollegeTests+LiveNetwork.swift` | Shared module — CollegeTestsSupport. |
| `CollegeTests/Support/TestFixturePaths.swift` | Shared — TestFixturePaths. |
| `CollegeTests/Support/ToolbarSnapshotHarness.swift` | PNG snapshot compare/record for ToolbarVisualTests. |

### `CollegeTests/__Snapshots__/ToolbarVisual/`

Visual regression snapshots for toolbar tests. (continued)

| File | Purpose |
|------|---------|
| `CollegeTests/__Snapshots__/ToolbarVisual/calendar-dark-regular.png` | Test fixture or documentation artifact. |
| `CollegeTests/__Snapshots__/ToolbarVisual/calendar-light-regular.png` | Test fixture or documentation artifact. |

## CollegeUITests


### `CollegeUITests/`

UI tests for Assistant scenarios and Settings flows.

| File | Purpose |
|------|---------|
| `CollegeUITests/AssistantScenarioCatalog.swift` | Swift source — AssistantScenarioCatalog. |
| `CollegeUITests/AssistantUITests.swift` | Unit tests for AssistantUI. |
| `CollegeUITests/CollegeUITestCase.swift` | Swift source — CollegeUITestCase. |
| `CollegeUITests/SettingsUITests.swift` | Unit tests for SettingsUI. |

## Packages

Extracted Swift packages shared across the app and tests.

### `Packages/CollegeAcademics/`

Shared academics types, GPA formatting, and graduation timeline engine.

| File | Purpose |
|------|---------|
| `Packages/CollegeAcademics/Package.swift` | Swift source — Package. |

### `Packages/CollegeAcademics/Sources/CollegeAcademics/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeAcademics/Sources/CollegeAcademics/AuditRequirementSelectionStore.swift` | Academics module — AuditRequirementSelectionStore. |
| `Packages/CollegeAcademics/Sources/CollegeAcademics/CollegeAcademicsBoundary.swift` | Swift source — CollegeAcademicsBoundary. |
| `Packages/CollegeAcademics/Sources/CollegeAcademics/GPAFormatting.swift` | Academics module — GPAFormatting. |
| `Packages/CollegeAcademics/Sources/CollegeAcademics/GraduationTimelineEngine.swift` | Academics module — TermState. |

### `Packages/CollegeAcademics/Sources/CollegeAcademics/UI/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeAcademics/Sources/CollegeAcademics/UI/AcademicsSceneState.swift` | Swift source — AcademicsSceneState. |

### `Packages/CollegeAcademics/Tests/CollegeAcademicsTests/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeAcademics/Tests/CollegeAcademicsTests/CollegeAcademicsBoundaryTests.swift` | Unit tests for CollegeAcademicsBoundary. |

### `Packages/CollegeCalendar/`

Calendar UI package with Google/Apple/Outlook sync adapters.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Package.swift` | Swift source — Package. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CalendarCacheEngine.swift` | Calendar module — CalendarCalEvent. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CalendarFormatters.swift` | Swift source — CalendarFormatters. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CalendarTenantKind.swift` | Swift source — CalendarTenantKind. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CalendarTimelineAggregator.swift` | Swift source — CalendarTimelineAggregator. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CalendarTimelineEpics.swift` | Swift source — CalendarTimelineEpics. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CalendarVisibilityFilter.swift` | Swift source — CalendarVisibilityFilter. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/CollegeCalendarBoundary.swift` | Swift source — CollegeCalendarBoundary. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Editor/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Editor/CalendarEventEditorForm.swift` | Calendar module — CalendarEventEditorForm. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Editor/CalendarEventGuestsCodec.swift` | Calendar module — GuestRecord. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Editor/CalendarGridPopoverMetrics.swift` | Calendar module — CalendarGridPopoverMetrics. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Editor/CalendarGuestContactPickerHost.swift` | Calendar module — Delegate. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/ICS/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/ICS/ICSCalendarParser.swift` | Swift source — ICSCalendarParser. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/AppleCalendarIntegration.swift` | Calendar module — AppleCalendarIntegration. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarIntegrationBridge.swift` | Swift source — CalendarIntegrationBridge. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarIntegrationManager+Export.swift` | Swift source — CalendarIntegrationManager+Export. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarIntegrationManager+StoreSync.swift` | Swift source — CalendarIntegrationManager+StoreSync. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarIntegrationManager+SyncProviderAPI.swift` | Calendar module — CalendarIntegrationManager+SyncProviderAPI. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarIntegrationManager.swift` | Calendar module — ConnectedCalendar. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarIntegrationPorts.swift` | Swift source — CalendarIntegrationPorts. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarLinkConfig.swift` | Calendar module — CalendarLinkConfig. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarSyncCoordinator.swift` | Routes calendar sync/export to per-provider actor implementations. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/CalendarSyncMapDiskPersistence.swift` | Calendar module — CalendarSyncMapDiskPersistence. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Integration/GoogleCalendarAuthPort.swift` | Swift source — GoogleCalendarAuthPort. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Persistence/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Persistence/CalendarPersistencePort.swift` | Swift source — CalendarPersistencePort. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Persistence/CalendarReadPort.swift` | Swift source — CalendarReadPort. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Persistence/CalendarStoredEvent.swift` | Swift source — CalendarStoredEvent. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Recurrence/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Recurrence/CalendarRecurrenceExpander.swift` | Swift source — CalendarRecurrenceExpander. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/AppleCalendarProvider.swift` | Calendar module — CalendarSyncProviderError. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/CalendarSyncMapRegistry.swift` | Calendar module — CalendarSyncMapRegistry. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/CalendarSyncProvider.swift` | Protocol-oriented calendar sync surface. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/GoogleCalendarProvider.swift` | Calendar module — GoogleCalendarProvider. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/OutlookCalendarProvider.swift` | Calendar module — OutlookCalendarProvider. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Sync/iCloudCalendarProvider.swift` | Calendar module — iCloudCalendarProvider. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/AddCalendarItemOverlaySizing.swift` | Swift source — AddCalendarItemOverlaySizing. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarColor+Hex.swift` | Swift source — CalendarColor+Hex. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarEditorAnchor.swift` | Swift source — CalendarEditorAnchor. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarEditorNotifications.swift` | Calendar module — CalendarEditorNotifications. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarEditorPresentation.swift` | Calendar module — CalendarEditorPresentationKey. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarEnvironment.swift` | Swift source — CalendarEnvironment. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarEventDisplayColorResolver.swift` | Calendar module — CalendarEventDisplayColorResolver. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarLinkingSheet.swift` | Calendar module — CalendarLinkingSheet. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarOverlayPort.swift` | Swift source — CalendarOverlayPort. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarPlannerTaskSummary.swift` | Presentation model for planner task rows in Calendar sidebar. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarReminderScheduler.swift` | Calendar module — CalendarReminderInfo. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarSceneState.swift` | Swift source — CalendarSceneState. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarShellPorts.swift` | Swift source — CalendarShellPorts. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarTimeZonePreference.swift` | Calendar module — Option. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarToolbarSearchMatch.swift` | Swift source — CalendarToolbarSearchMatch. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarView.swift` | Calendar module — CalendarView. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/DesignSystem.swift` | Swift source — DesignSystem. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/EventColorOverrides.swift` | Calendar module — EventColorOverrides. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/PrivacyMaskModifier.swift` | Calendar module — PrivacyMirrorEnabledKey. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Views/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Views/CalendarDayHeader.swift` | Calendar module — CalendarTimeZoneCornerLabel. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Views/CalendarEventChipStyle.swift` | Calendar module — CalendarStoredEventChipLabel. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Views/CalendarTimedEventChipContent.swift` | Calendar module — CalendarTimedEventChipContent. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Views/CalendarTodaySummaryView.swift` | Calendar module — CalendarTodaySummaryView. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Views/CalendarWeekPlannerView.swift` | Calendar module — CalendarWeekPlannerView. |

### `Packages/CollegeCalendar/Sources/CollegeCalendar/Write/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Write/CalendarEditorSession.swift` | Manages draft calendar events for live grid preview while the editor is open. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Write/CalendarEventWritePipeline+Overlay.swift` | Overlay write helpers for calendar event editor surfaces. |
| `Packages/CollegeCalendar/Sources/CollegeCalendar/Write/CalendarEventWritePipeline.swift` | Single chokepoint for calendar event creates/updates/deletes from any feature surface. |

### `Packages/CollegeCalendar/Tests/CollegeCalendarTests/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCalendar/Tests/CollegeCalendarTests/CalendarCacheEngineTests.swift` | Unit tests for CalendarCacheEngine. |
| `Packages/CollegeCalendar/Tests/CollegeCalendarTests/CollegeCalendarBoundaryTests.swift` | Unit tests for CollegeCalendarBoundary. |

### `Packages/CollegeCareer/`

Shared career navigation types and job posting enrichment.

| File | Purpose |
|------|---------|
| `Packages/CollegeCareer/Package.swift` | Swift source — Package. |

### `Packages/CollegeCareer/Sources/CollegeCareer/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCareer/Sources/CollegeCareer/CareerModels.swift` | Career module — CareerOfferCompensationPackage. |
| `Packages/CollegeCareer/Sources/CollegeCareer/CareerNavigation.swift` | Swift source — CareerNavigation. |
| `Packages/CollegeCareer/Sources/CollegeCareer/CollegeCareerBoundary.swift` | Swift source — CollegeCareerBoundary. |
| `Packages/CollegeCareer/Sources/CollegeCareer/JobPostingEnrichment.swift` | Career module — JobPostingEnrichment. |

### `Packages/CollegeCareer/Sources/CollegeCareer/UI/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCareer/Sources/CollegeCareer/UI/CareerSceneState.swift` | Swift source — CareerSceneState. |

### `Packages/CollegeCareer/Tests/CollegeCareerTests/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegeCareer/Tests/CollegeCareerTests/CollegeCareerBoundaryTests.swift` | Unit tests for CollegeCareerBoundary. |

### `Packages/CollegePlatformBoundary/`

Feature module registry and import boundary enforcement.

| File | Purpose |
|------|---------|
| `Packages/CollegePlatformBoundary/Package.swift` | Swift source — Package. |

### `Packages/CollegePlatformBoundary/Sources/CollegePlatformBoundary/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `Packages/CollegePlatformBoundary/Sources/CollegePlatformBoundary/FeatureModuleRegistry.swift` | Swift source — FeatureModuleRegistry. |

## VecturaService


### `VecturaService/`

Isolated MLX sentence embedding service (768-d) for catalog vector search.

| File | Purpose |
|------|---------|
| `VecturaService/Package.swift` | Swift source — Package. |

### `VecturaService/Sources/VecturaService/`

Project files for this directory.

| File | Purpose |
|------|---------|
| `VecturaService/Sources/VecturaService/IsolatedSentenceEmbedding768.swift` | Swift source — IsolatedSentenceEmbedding768. |
| `VecturaService/Sources/VecturaService/VecturaIntegrationNotes.swift` | Swift source — VecturaIntegrationNotes. |
| `VecturaService/Sources/VecturaService/VecturaMLXSentenceAdapter.swift` | Swift source — VecturaMLXSentenceAdapter. |

## scripts


### `scripts/`

Build gates, catalog parity tools, test runners, and repo maintenance scripts.

| File | Purpose |
|------|---------|
| `scripts/add-swift-file-headers.py` | Adds standard file header comments to Swift sources. |
| `scripts/catalog_ingest_parity_diff.swift` | Diffs catalog ingest outputs for parity regression. |
| `scripts/check-feature-imports.sh` | Verifies feature modules do not import across boundaries. |
| `scripts/check-neutral-persistence-labels.sh` | Enforces technology-neutral persistence naming. |
| `scripts/check-no-coredata.sh` | Guards against Core Data usage in SwiftData codebase. |
| `scripts/check-no-gemma4.sh` | Guards against disallowed Gemma 4 model references. |
| `scripts/check-no-vision-llm.sh` | Guards against Vision LLM dependencies. |
| `scripts/check-platform-boundary.sh` | Validates CollegePlatformBoundary import rules. |
| `scripts/compare_catalog_exports.py` | Compares catalog export bundles for structural diffs. |
| `scripts/fix_container_aliases.py` | Migration helper for AppContainer DI alias cleanup. |
| `scripts/generate-repository-index.py` | Generates and validates docs/REPOSITORY.md from git ls-files. |
| `scripts/migrate_app_container_di.py` | Migration script for AppContainer dependency injection. |
| `scripts/record_toolbar_snapshots.sh` | Records toolbar visual regression snapshots. |
| `scripts/refresh-performance-manifest.py` | Regenerates performance file manifest from codebase. |
| `scripts/refresh-performance-manifest.sh` | Shell wrapper for performance manifest refresh. |
| `scripts/reorg-college-tests.py` | Mechanical test file reorg helper. |
| `scripts/run-college-unit-tests.sh` | Runs College unit test shard locally or in CI. |
| `scripts/run-performance-gates.sh` | Runs launch and performance acceptance gates. |
| `scripts/run_catalog_tests.sh` | Runs catalog-specific test suite. |
| `scripts/run_toolbar_tests.sh` | Runs toolbar architecture and visual tests. |
| `scripts/slim-xcode-project-for-github.py` | Strips local-only references from Xcode project for git. |
| `scripts/test_compare_catalog_exports.py` | Unit tests for catalog export comparison script. |
| `scripts/test_dsu_catalog_scraper.py` | Tests Dakota State University catalog scraper fixtures. |
| `scripts/toolbar-health-check.sh` | Checks toolbar provider health and writes report JSON. |
| `scripts/train_intent_text_classifier.swift` | Trains Assistant intent text classifier model. |
| `scripts/validate_courseleaf_requirements.sh` | Validates CourseLeaf requirement parser output. |

## .github

GitHub Actions CI configuration.

### `.github/workflows/`

GitHub Actions CI workflows for PR gates, catalog tests, and release hardening.

| File | Purpose |
|------|---------|
| `.github/workflows/catalog-tests.yml` | Runs catalog ingest and parser test suite on PRs. |
| `.github/workflows/feature-boundaries.yml` | Enforces feature module import boundaries. |
| `.github/workflows/release-hardening.yml` | Release build hardening and sign-off gates. |
| `.github/workflows/secret-scan.yml` | Scans commits for leaked secrets via gitleaks. |
| `.github/workflows/toolbar-architecture.yml` | Validates toolbar provider registry architecture. |
| `.github/workflows/toolbar-health-check.yml` | Runs toolbar health check script and reports drift. |

## docs


### `docs/`

Architecture docs, ADRs, sign-off checklists, and performance baselines.

| File | Purpose |
|------|---------|
| `docs/ARCHITECTURE.md` | Module layout, data flow, and feature-first tree map. |
| `docs/DEVELOPMENT.md` | Clone, build, test tiers, and contributor setup guide. |
| `docs/OUTLOOK_SETUP.md` | Documentation. |
| `docs/embedding-evaluation.md` | Documentation. |
| `docs/liquid-glass-toolbar.md` | Documentation. |
| `docs/performance-architecture-signoff.md` | Documentation. |
| `docs/performance-baseline.md` | Documentation. |
| `docs/performance-file-manifest.md` | Documentation. |
| `docs/phase6-signoff-checklist.md` | Documentation. |
| `docs/post-migration-ui-checklist.md` | Documentation. |
| `docs/reorg-orphans.md` | Documentation. |
| `docs/rust-embed-phase9.md` | Documentation. |
| `docs/toolbar-development.md` | Documentation. |
| `docs/toolbar-ship-gate-signoff.md` | Documentation. |

### `docs/adr/`

Architecture Decision Records for major design choices.

| File | Purpose |
|------|---------|
| `docs/adr/001-toolbar-architecture.md` | Documentation. |
| `docs/adr/002-window-scoped-toolbar.md` | Documentation. |
| `docs/adr/003-toolbar-provider-registry.md` | Documentation. |
| `docs/adr/004-feature-module-boundaries.md` | Documentation. |
| `docs/adr/004-migration-plan.md` | Documentation. |
| `docs/adr/005-app-container-di.md` | Documentation. |
| `docs/adr/006-toolbar-deprecation-policy.md` | Documentation. |
| `docs/adr/007-liquid-glass-toolbar-design-system.md` | Documentation. |

### `docs/archive/`

Superseded migration notes and audit artifacts.

| File | Purpose |
|------|---------|
| `docs/archive/APP_PATH_MAP.md` | Documentation. |
| `docs/archive/CFPreferencesFixPlan.md` | Documentation. |
| `docs/archive/PDFImplementation.md` | Documentation. |
| `docs/archive/SWIFT_63_MIGRATION_BASELINE.md` | Documentation. |
| `docs/archive/SWIFT_AUDIT_IMPLEMENTATION_ROADMAP.md` | Documentation. |
| `docs/archive/SWIFT_AUDIT_RUBRIC.md` | Documentation. |
| `docs/archive/SWIFT_BATCH_AUDIT_COMPLETION.md` | Documentation. |
| `docs/archive/SWIFT_BATCH_FINDINGS_INTEGRATED.md` | Documentation. |
| `docs/archive/SWIFT_FULL_AUDIT_REPORT.md` | Documentation. |
| `docs/archive/SWIFT_LEGACY_GUARDRAILS.md` | Documentation. |
| `docs/archive/SWIFT_MASTER_RISK_REGISTER.md` | Documentation. |
| `docs/archive/SWIFT_PERFORMANCE_BOTTLENECK_REGISTER.md` | Documentation. |
| `docs/archive/SWIFT_REMEDIATION_PROGRESS.md` | Documentation. |
| `docs/archive/SWIFT_REMEDIATION_SEQUENCE.md` | Documentation. |

### `docs/archive/SwiftAuditBatches/`

Superseded migration notes and audit artifacts. (continued)

| File | Purpose |
|------|---------|
| `docs/archive/SwiftAuditBatches/batch_01_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_02_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_03_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_04_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_05_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_06_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_07_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_08_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_09_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_10_manifest.md` | Documentation. |
| `docs/archive/SwiftAuditBatches/batch_11_manifest.md` | Documentation. |

### `docs/archive/migration/`

Superseded migration notes and audit artifacts. (continued)

| File | Purpose |
|------|---------|
| `docs/archive/migration/README.md` | Documentation. |
| `docs/archive/migration/swiftdata-migration-7f-checklist.md` | Documentation. |
| `docs/archive/migration/swiftdata-migration-test-matrix.md` | Documentation. |
| `docs/archive/migration/swiftdata-only-fresh-cutover.md` | Documentation. |

### `docs/assets/readme/`

Screenshot and icon assets referenced by the GitHub README.

| File | Purpose |
|------|---------|
| `docs/assets/readme/README.md` | Documents expected screenshot assets for the GitHub README. |
| `docs/assets/readme/app-icon.png` | GitHub README hero icon (512×512 graduation cap). |
| `docs/assets/readme/feature-academics.png` | GitHub README screenshot — Academics planner and audit. |
| `docs/assets/readme/feature-calendar.png` | GitHub README screenshot — Calendar month view. |
| `docs/assets/readme/feature-career.png` | GitHub README screenshot — Career application board. |
| `docs/assets/readme/feature-documents.png` | GitHub README screenshot — Documents Repository. |
| `docs/assets/readme/feature-profile.png` | GitHub README screenshot — Profile page. |
| `docs/assets/readme/feature-settings.png` | GitHub README screenshot — Settings and privacy. |
| `docs/assets/readme/feature-sidebar.png` | GitHub README screenshot — sidebar navigation. |
| `docs/assets/readme/feature-transfer.png` | GitHub README screenshot — Transfer Database. |
| `docs/assets/readme/hero-overview.png` | GitHub README screenshot — Overview dashboard. |

---

## Local-only / not tracked (reference)

| Path | Notes |
|------|-------|
| `College.xcodeproj` | Xcode project (tracked for CI; may be absent in sparse checkouts). |
| `rust-typst/` | Optional Rust/Typst resume PDF bridge (local build artifacts in target/ are gitignored). |
| `Secrets.xcconfig` | Local-only secrets file — never commit. |
| `.build/` | Swift Package Manager build output. |
| `DerivedData/` | Xcode derived data. |
