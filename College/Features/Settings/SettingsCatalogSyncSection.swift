// SettingsCatalogSyncSection.swift
// Feature: Settings
// Purpose: Settings module — SettingsCatalogSyncSection.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Academic catalog sync (multi-school)

struct SettingsCatalogSyncSection: View {
    @Environment(AppContainer.self) private var container
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
        @State private var availableSchools: [String] = []
    @State private var selectedSchools: Set<String> = []
    @State private var schoolSearch = ""
    @State private var isLoadingSchools = false
    @State private var activeCatalogSync: CatalogBackgroundSyncRunner.CatalogSyncDepth?
    @State private var catalogSyncResults: [String: CatalogSyncTerminal] = [:]
    @State private var catalogPhaseBCoursesInFlight = false
    @State private var isRequirementsSyncRunning = false
    @State private var forceRequirementsRefresh = false
    @State private var hydratableMajors: [CatalogProgramRequirementsHydrator.SelectableMajor] = []
    @State private var selectedMajorWorkItems: Set<CatalogProgramRequirementsHydrator.WorkItem> = []
    @State private var expandedSchoolSections: Set<String> = []
    @State private var didApplyDefaultSchoolSelection = false
    @State private var localCatalogFiles: [LocalCatalogInfo] = []
    @State private var showClearScrapedDataConfirm = false
    @ObservedObject private var catalogPurgeRunner = CatalogSchoolDataPurgeRunner.shared
    @AppStorage("catalog.ingest.forceNext.v1") private var forceNextCatalogRescrape: Bool = false

    private struct HydratableMajorsRefreshTrigger: Equatable {
        var catalogDataRevision: Int
        var profileRevision: Int
        var profileCollegeName: String
        var selectedSchools: Set<String>
        var activeCatalogSync: CatalogBackgroundSyncRunner.CatalogSyncDepth?
        var availableSchoolsCount: Int
    }

    private var hydratableMajorsRefreshTrigger: HydratableMajorsRefreshTrigger {
        HydratableMajorsRefreshTrigger(
            catalogDataRevision: collegePersistence.catalogDataRevision,
            profileRevision: collegePersistence.profileRevision,
            profileCollegeName: collegePersistence.profile?.collegeName ?? "",
            selectedSchools: selectedSchools,
            activeCatalogSync: activeCatalogSync,
            availableSchoolsCount: availableSchools.count
        )
    }

    private var filteredSchools: [String] {
        let query = schoolSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableSchools }
        return availableSchools.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var isCatalogSyncRunning: Bool {
        activeCatalogSync != nil || catalogPhaseBCoursesInFlight
    }
    private var isAnySyncRunning: Bool {
        isCatalogSyncRunning || isRequirementsSyncRunning || catalogPurgeRunner.isRunning
    }

    private var selectedSchoolNames: [String] {
        availableSchools.filter { selectedSchools.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(
                title: String(localized: "settings.general.catalog_schools_title", defaultValue: "Schools"),
                icon: "building.columns",
                iconColor: DesignSystem.Colors.primary,
                contentPadding: DesignSystem.Spacing.md
            ) {
                schoolPickerContent
            }

            catalogSyncDepthCard(
                depth: .light,
                icon: "rectangle.stack",
                sectionTitle: String(
                    localized: "settings.general.catalog_skeleton_title",
                    defaultValue: "Skeleton catalog"
                ),
                sectionDescription: String(
                    localized: "settings.general.catalog_skeleton_help",
                    defaultValue: "Fast program index only — majors, minors, and program links. Same depth as Edit Profile auto-sync. Does not download every degree requirement page."
                ),
                syncButtonLabel: syncButtonTitle(for: .light)
            )

            SettingsCard(
                title: String(
                    localized: "settings.general.catalog_selected_title",
                    defaultValue: "Selected programs only"
                ),
                icon: "checklist",
                iconColor: DesignSystem.Colors.info,
                contentPadding: DesignSystem.Spacing.md
            ) {
                SettingsCatalogSelectedProgramsBlock(
                    universityNames: selectedSchoolNames,
                    isOtherSyncRunning: isAnySyncRunning,
                    onSyncStateChange: { running in
                        Task { @MainActor in
                            await Task.yield()
                            isRequirementsSyncRunning = running
                        }
                    }
                )
            }

            requirementsSyncCard

            SettingsCard(
                title: String(
                    localized: "settings.general.catalog_full_title",
                    defaultValue: "Full catalog"
                ),
                icon: "books.vertical",
                iconColor: DesignSystem.Colors.warning,
                contentPadding: DesignSystem.Spacing.md
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(
                        localized: "settings.general.catalog_full_help",
                        defaultValue: "Heavy sync — fetches degree requirements for every program. Can take a long time on large catalogs (especially with strict crawl delays). Prefer skeleton first; Profile can hydrate requirements when you pick a major."
                    ))
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Toggle(
                        String(
                            localized: "settings.general.catalog_force_rescrape_once",
                            defaultValue: "Force next catalog re-scrape (ignore unchanged signature checks once)"
                        ),
                        isOn: $forceNextCatalogRescrape
                    )
                    .toggleStyle(.checkbox)
                    .disabled(isAnySyncRunning)

                    catalogSyncDepthActions(
                        depth: .full,
                        syncButtonLabel: syncButtonTitle(for: .full)
                    )
                }
            }

            catalogBundleSharingBlock

            clearScrapedCatalogDataBlock

            #if DEBUG
            SAdvancedDisclosure(
                title: String(
                    localized: "settings.general.catalog_diagnostics_title",
                    defaultValue: "Catalog diagnostics"
                )
            ) {
                CatalogDataDiagnosticsView(
                    schoolID: CatalogDataDiagnosticsView.resolvedSchoolID(from: collegePersistence),
                    isAnySyncRunning: isAnySyncRunning
                )
            }
            #endif
        }
        .task { await loadSchools() }
        .onReceive(NotificationCenter.default.publisher(for: .catalogSyncProgressDidUpdate)) { note in
            guard let activityID = note.userInfo?["activityID"] as? String,
                  activityID == BackgroundActivityCenter.catalogCoursesID,
                  let phase = note.userInfo?["phase"] as? String else { return }
            if phase == CatalogSyncProgress.Phase.succeeded.rawValue
                || phase == CatalogSyncProgress.Phase.failed.rawValue
                || phase == CatalogSyncProgress.Phase.skipped.rawValue {
                catalogPhaseBCoursesInFlight = false
                activeCatalogSync = nil
            }
        }
        .task(id: hydratableMajorsRefreshTrigger) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await Task.yield()
            applyHydratableMajorsRefresh()
        }
        .confirmationDialog(
            String(
                localized: "settings.general.catalog_clear_scraped_confirm_title",
                defaultValue: "Clear scraped catalog data?"
            ),
            isPresented: $showClearScrapedDataConfirm,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "settings.general.catalog_clear_scraped_confirm_action", defaultValue: "Clear"),
                role: .destructive
            ) {
                clearScrapedCatalogDataForSelectedSchools()
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "settings.general.catalog_clear_scraped_confirm_message",
                    defaultValue: "Deletes program index, degree requirements, course catalog rows, on-disk caches, ingest signatures, and your “selected program” scrape picks for the chosen school(s). Your profile and transcript are not affected. Run Skeleton sync afterward."
                )
            )
        }
        .task {
            await Task.yield()
            refreshLocalCatalogFiles()
        }
    }

    private var programSectionsBySchool: [(school: String, programs: [CatalogProgramRequirementsHydrator.SelectableMajor])] {
        CatalogProgramRequirementsHydrator.programSectionsBySchool(from: hydratableMajors)
    }

    private var syncableProgramCount: Int {
        hydratableMajors.filter(\.isSyncable).count
    }

    // MARK: - School picker

    private var schoolPickerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                String(localized: "settings.general.catalog_search", defaultValue: "Search schools"),
                text: $schoolSearch
            )
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button(String(localized: "settings.general.catalog_select_all", defaultValue: "Select all")) {
                    selectedSchools.formUnion(filteredSchools)
                }
                .disabled(filteredSchools.isEmpty || isAnySyncRunning)

                Button(String(localized: "settings.general.catalog_clear", defaultValue: "Clear")) {
                    for school in filteredSchools {
                        selectedSchools.remove(school)
                    }
                }
                .disabled(filteredSchools.isEmpty || isAnySyncRunning)

                Spacer()

                Text(selectionCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if isLoadingSchools {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "settings.general.catalog_loading", defaultValue: "Loading schools…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                } else if availableSchools.isEmpty {
                    Text(String(localized: "settings.general.catalog_empty", defaultValue: "No catalog-backed schools are available yet. Check your network connection and try again."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    List {
                        ForEach(filteredSchools, id: \.self) { school in
                            Toggle(isOn: schoolSelectionBinding(school)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(school)
                                    Text(schoolCatalogStatusLabel(for: school))
                                        .font(DesignSystem.Fonts.caption1())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(isAnySyncRunning)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                }
            }
        }
    }

    private func schoolCatalogStatusLabel(for school: String) -> String {
        let programs = collegePersistence.catalogProgramCount(for: school)
        let courses = collegePersistence.existingCatalogCourseCount(for: school)
        if programs == 0, courses == 0 {
            return String(
                localized: "settings.general.catalog_school_not_synced",
                defaultValue: "Not synced"
            )
        }
        return String(
            format: String(
                localized: "settings.general.catalog_school_status_fmt",
                defaultValue: "%d programs · %d courses"
            ),
            programs,
            courses
        )
    }

    @ViewBuilder
    private func catalogSyncDepthCard(
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        icon: String,
        sectionTitle: String,
        sectionDescription: String,
        syncButtonLabel: String
    ) -> some View {
        SettingsCard(
            title: sectionTitle,
            icon: icon,
            iconColor: DesignSystem.Colors.primary,
            contentPadding: DesignSystem.Spacing.md
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(sectionDescription)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                catalogSyncDepthActions(depth: depth, syncButtonLabel: syncButtonLabel)
            }
            .opacity(activeCatalogSync == depth ? 1 : (isCatalogSyncRunning ? 0.65 : 1))
        }
    }

    @ViewBuilder
    private func catalogSyncDepthActions(
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        syncButtonLabel: String
    ) -> some View {
        SettingsLabeledAction(title: syncActionRowTitle(for: depth)) {
            Button(syncButtonLabel) {
                runCatalogSync(depth: depth)
            }
            .disabled(isAnySyncRunning || selectedSchools.isEmpty)
        }
    }

    // MARK: - Requirements sync (selected majors)

    private var requirementsSyncCard: some View {
        SettingsCard(
            title: String(
                localized: "settings.general.catalog_requirements_title",
                defaultValue: "Degree requirements"
            ),
            icon: "doc.text",
            iconColor: DesignSystem.Colors.info,
            contentPadding: DesignSystem.Spacing.md
        ) {
            requirementsSyncContent
        }
    }

    private var requirementsSyncContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(
                localized: "settings.general.catalog_requirements_help",
                defaultValue: "Programs from your Edit Profile degrees only, grouped by school. After skeleton sync for a school, fetch requirement pages for the majors and minors on that school’s degrees. Requirements are stored per university in the app database."
            ))
            .font(DesignSystem.Fonts.caption1())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if hydratableMajors.isEmpty {
                Text(String(
                    localized: "settings.general.catalog_requirements_no_majors",
                    defaultValue: "No programs on your degrees yet. In Edit Profile, set college, degree level, degree type, and primary major (and minors if any) for each degree tab."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    Button(String(
                        localized: "settings.general.catalog_requirements_select_all",
                        defaultValue: "Select all programs"
                    )) {
                        selectedMajorWorkItems = Set(hydratableMajors.compactMap(\.syncWorkItem))
                    }
                    .disabled(isAnySyncRunning || syncableProgramCount == 0)

                    Button(String(
                        localized: "settings.general.catalog_requirements_clear",
                        defaultValue: "Clear programs"
                    )) {
                        selectedMajorWorkItems.removeAll()
                    }
                    .disabled(isAnySyncRunning)

                    Button(String(
                        localized: "settings.general.catalog_requirements_expand_all",
                        defaultValue: "Expand all"
                    )) {
                        expandedSchoolSections = Set(programSectionsBySchool.map(\.school))
                    }
                    .disabled(programSectionsBySchool.isEmpty)

                    Spacer()

                    Text(catalogProgramCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(programSectionsBySchool, id: \.school) { section in
                        DisclosureGroup(
                            isExpanded: schoolSectionExpansionBinding(section.school),
                            content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(section.programs) { option in
                                        programRow(option)
                                    }
                                }
                                .padding(.leading, 4)
                                .padding(.bottom, 4)
                            },
                            label: {
                                Text(schoolSectionHeaderTitle(school: section.school, count: section.programs.count))
                                    .font(.subheadline.weight(.medium))
                            }
                        )
                    }
                }
                .padding(DesignSystem.Spacing.sm)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Toggle(String(
                localized: "settings.general.catalog_requirements_force",
                defaultValue: "Force refresh (ignore 24h cache)"
            ), isOn: $forceRequirementsRefresh)
            .toggleStyle(.checkbox)
            .disabled(isAnySyncRunning)

            SettingsLabeledAction(title: String(
                localized: "settings.general.catalog_requirements_action",
                defaultValue: "Requirements scrape"
            )) {
                Button(requirementsSyncButtonTitle) {
                    runRequirementsSync()
                }
                .disabled(isAnySyncRunning || selectedMajorWorkItems.isEmpty)
            }
        }
        .opacity(isRequirementsSyncRunning ? 1 : (isCatalogSyncRunning ? 0.65 : 1))
    }

    private var catalogProgramCountLabel: String {
        let selected = selectedMajorWorkItems.count
        let total = hydratableMajors.count
        let syncable = syncableProgramCount
        let schoolCount = programSectionsBySchool.count
        if selected == 0 {
            return String(
                format: String(
                    localized: "settings.general.catalog_requirements_profile_fmt",
                    defaultValue: "%d programs · %d school(s) (%d with catalog links)"
                ),
                total,
                schoolCount,
                syncable
            )
        }
        return String(
            format: String(
                localized: "settings.general.catalog_requirements_selected_profile_fmt",
                defaultValue: "%d selected · %d programs · %d school(s)"
            ),
            selected,
            total,
            schoolCount
        )
    }

    @ViewBuilder
    private func programRow(_ option: CatalogProgramRequirementsHydrator.SelectableMajor) -> some View {
        if let workItem = option.syncWorkItem {
            Toggle(isOn: majorSelectionBinding(workItem)) {
                Text(option.degreeLabel)
                    .lineLimit(3)
            }
            .toggleStyle(.checkbox)
            .disabled(isAnySyncRunning)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.degreeLabel)
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                    Text(String(
                        localized: "settings.general.catalog_requirements_no_link",
                        defaultValue: "No catalog link — run skeleton sync"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func schoolSectionHeaderTitle(school: String, count: Int) -> String {
        String(
            format: String(
                localized: "settings.general.catalog_requirements_school_section_fmt",
                defaultValue: "%@ (%d)"
            ),
            school,
            count
        )
    }

    private func schoolSectionExpansionBinding(_ school: String) -> Binding<Bool> {
        Binding(
            get: { expandedSchoolSections.contains(school) },
            set: { isExpanded in
                if isExpanded {
                    expandedSchoolSections.insert(school)
                } else {
                    expandedSchoolSections.remove(school)
                }
            }
        )
    }

    private var requirementsSyncButtonTitle: String {
        if isRequirementsSyncRunning {
            return String(
                localized: "settings.general.catalog_requirements_syncing",
                defaultValue: "Syncing requirements…"
            )
        }
        let count = selectedMajorWorkItems.count
        if count <= 1 {
            return String(
                localized: "settings.general.catalog_requirements_sync",
                defaultValue: "Sync requirements"
            )
        }
        return String(
            format: String(
                localized: "settings.general.catalog_requirements_sync_fmt",
                defaultValue: "Sync requirements (%d)"
            ),
            count
        )
    }

    private func majorSelectionBinding(
        _ item: CatalogProgramRequirementsHydrator.WorkItem
    ) -> Binding<Bool> {
        Binding(
            get: { selectedMajorWorkItems.contains(item) },
            set: { isOn in
                if isOn {
                    selectedMajorWorkItems.insert(item)
                } else {
                    selectedMajorWorkItems.remove(item)
                }
            }
        )
    }

    private func applyHydratableMajorsRefresh() {
        hydratableMajors = CatalogProgramRequirementsHydrator.selectablePrograms(
            profiles: AcademicProfileReadBridge.entities(collegePersistence: collegePersistence),
            universityNames: [],
            persistence: collegePersistence,
            fallbackCollege: collegePersistence.profile?.collegeName
        )

        let syncable = Set(hydratableMajors.compactMap(\.syncWorkItem))
        selectedMajorWorkItems = selectedMajorWorkItems.intersection(syncable)
        if selectedMajorWorkItems.isEmpty, !syncable.isEmpty {
            selectedMajorWorkItems = syncable
        }

        let sections = programSectionsBySchool
        if expandedSchoolSections.isEmpty, !sections.isEmpty {
            expandedSchoolSections = Set(sections.map(\.school))
        } else {
            expandedSchoolSections = expandedSchoolSections.intersection(Set(sections.map(\.school)))
        }
    }

    private func syncActionRowTitle(for depth: CatalogBackgroundSyncRunner.CatalogSyncDepth) -> String {
        switch depth {
        case .light:
            return String(localized: "settings.general.catalog_skeleton_action", defaultValue: "Skeleton scrape")
        case .full:
            return String(localized: "settings.general.catalog_full_action", defaultValue: "Full scrape")
        }
    }

    // MARK: - Labels

    private var selectionCountLabel: String {
        let count = selectedSchools.count
        if count == 1 {
            return String(localized: "settings.general.catalog_one_selected", defaultValue: "1 school selected")
        }
        return String(
            format: String(
                localized: "settings.general.catalog_n_selected_fmt",
                defaultValue: "%d schools selected"
            ),
            count
        )
    }

    private func syncButtonTitle(for depth: CatalogBackgroundSyncRunner.CatalogSyncDepth) -> String {
        if catalogPhaseBCoursesInFlight, activeCatalogSync == depth || activeCatalogSync == nil {
            return String(
                localized: "settings.general.syncing_courses_background",
                defaultValue: "Courses importing…"
            )
        }

        if activeCatalogSync == depth {
            switch depth {
            case .light:
                return String(localized: "settings.general.syncing_skeleton", defaultValue: "Skeleton sync…")
            case .full:
                return String(localized: "settings.general.syncing_full", defaultValue: "Full sync…")
            }
        }

        let failedSchools = selectedSchoolNames.filter { school in
            if case .failed = catalogSyncResults[school] { return true }
            return false
        }
        if !failedSchools.isEmpty {
            return String(
                localized: "settings.general.sync_failed_retry",
                defaultValue: "Sync failed — Retry"
            )
        }

        let count = selectedSchools.count
        switch depth {
        case .light:
            if count <= 1 {
                return String(localized: "settings.general.sync_skeleton", defaultValue: "Run skeleton sync")
            }
            return String(
                format: String(
                    localized: "settings.general.sync_skeleton_batch_fmt",
                    defaultValue: "Skeleton sync (%d)"
                ),
                count
            )
        case .full:
            if count <= 1 {
                return String(localized: "settings.general.sync_full", defaultValue: "Run full sync")
            }
            return String(
                format: String(
                    localized: "settings.general.sync_full_batch_fmt",
                    defaultValue: "Full sync (%d)"
                ),
                count
            )
        }
    }

    // MARK: - Selection & sync

    private func schoolSelectionBinding(_ school: String) -> Binding<Bool> {
        Binding(
            get: { selectedSchools.contains(school) },
            set: { isOn in
                if isOn {
                    selectedSchools.insert(school)
                } else {
                    selectedSchools.remove(school)
                }
            }
        )
    }

    private func loadSchools() async {
        await MainActor.run { isLoadingSchools = true }
        let githubService = GitHubDataService()
        var manifests = githubService.loadResolvedSchoolsList()
        if let fetched = try? await githubService.refreshResolvedSchoolsList() {
            manifests = fetched
        }

        let profileCollege = collegePersistence.profile?.collegeName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let names = SchoolManifestSelection.universityPickerNames(
            manifests: manifests,
            importedCatalogNames: collegePersistence.fetchCatalogUniversityNames(),
            preserving: profileCollege
        )

        await MainActor.run {
            availableSchools = names
            isLoadingSchools = false
            if !didApplyDefaultSchoolSelection {
                applyDefaultSelection(profileCollege: profileCollege)
                didApplyDefaultSchoolSelection = true
            } else {
                selectedSchools = selectedSchools.filter { names.contains($0) }
            }
        }
    }

    private func applyDefaultSelection(profileCollege: String?) {
        var defaults = Set<String>()
        if let profileCollege, !profileCollege.isEmpty,
           let match = availableSchools.first(where: { $0.caseInsensitiveCompare(profileCollege) == .orderedSame }) {
            defaults.insert(match)
        }
        for imported in collegePersistence.fetchCatalogUniversityNames() {
            if let match = availableSchools.first(where: { $0.caseInsensitiveCompare(imported) == .orderedSame }) {
                defaults.insert(match)
            }
        }
        if !defaults.isEmpty {
            selectedSchools = defaults
        }
    }

    private func runCatalogSync(depth: CatalogBackgroundSyncRunner.CatalogSyncDepth) {
        guard !isAnySyncRunning else { return }
        let schools = selectedSchoolNames
        guard !schools.isEmpty else { return }

        activeCatalogSync = depth
        catalogSyncResults = [:]
        catalogPhaseBCoursesInFlight = false
        Task {
            var anyScheduledPassB = false
            var results: [String: CatalogSyncTerminal] = [:]
            for school in schools {
                let result = await CatalogBackgroundSyncRunner.runUserInitiatedCatalogSync(
                    schoolName: school,
                    collegePersistence: collegePersistence,
                    notifications: appNotifications,
                    depth: depth
                )
                if let terminal = result.terminal {
                    results[school] = terminal
                }
                if result.scheduledBackgroundCourseImport {
                    anyScheduledPassB = true
                }
            }
            await MainActor.run {
                catalogSyncResults = results
                if anyScheduledPassB {
                    catalogPhaseBCoursesInFlight = true
                    activeCatalogSync = depth
                } else {
                    activeCatalogSync = nil
                }
            }
        }
    }

    private var catalogBundleSharingBlock: some View {
        SettingsCard(
            title: String(
                localized: "settings.general.catalog_bundle_title",
                defaultValue: "Catalog bundle sharing"
            ),
            icon: "square.and.arrow.up.on.square",
            iconColor: DesignSystem.Colors.primary,
            contentPadding: DesignSystem.Spacing.md
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(
                    localized: "settings.general.catalog_bundle_help",
                    defaultValue: "Export signed catalog bundles for other College users, or import a bundle you received (AirDrop, email, etc.)."
                ))
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(String(
                        localized: "settings.general.catalog_bundle_import",
                        defaultValue: "Import Catalog Bundle…"
                    )) {
                        openCatalogBundleImportPanel()
                    }
                    .disabled(isAnySyncRunning)

                    Button(String(
                        localized: "settings.general.catalog_bundle_import_pdf",
                        defaultValue: "Import Local Catalog PDF…"
                    )) {
                        runManualLocalPDFImport()
                    }
                    .disabled(isAnySyncRunning || selectedSchoolNames.count != 1)
                }

                if !localCatalogFiles.isEmpty {
                    Text(String(
                        localized: "settings.general.catalog_bundle_local_files",
                        defaultValue: "Local catalog files"
                    ))
                    .font(DesignSystem.Fonts.body(weight: .semibold))
                    ForEach(localCatalogFiles, id: \.fileURL) { info in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.schoolName)
                                    .font(DesignSystem.Fonts.body(weight: .medium))
                                HStack(spacing: 8) {
                                    Text(ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
                                    Text(info.lastModified, style: .date)
                                    if let fp = info.signerFingerprint {
                                        Text(fp)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                }
                                .font(DesignSystem.Fonts.caption1())
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(String(localized: "common.share", defaultValue: "Share")) {
                                shareLocalCatalog(info)
                            }
                        }
                    }
                }
            }
        }
    }

    private var clearScrapedCatalogDataBlock: some View {
        SettingsCard(
            title: "Reset scraped catalog",
            icon: "arrow.counterclockwise.circle",
            iconColor: .orange,
            contentPadding: DesignSystem.Spacing.md
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(
                    localized: "settings.general.catalog_clear_scraped_help",
                    defaultValue: "Deletes program index, requirements, caches, and selected-program scrape picks for the school(s) checked above. Your profile and transcript are kept. Use before re-running Skeleton sync after parser fixes."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if catalogPurgeRunner.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(catalogPurgeRunner.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let fraction = catalogPurgeRunner.progressFraction {
                        ProgressView(value: min(1, max(0, fraction)))
                    }
                } else if let summary = catalogPurgeRunner.lastSummary, summary.remainingRows == 0, summary.failures.isEmpty {
                    Label {
                        Text(String(
                            localized: "settings.general.catalog_clear_scraped_verified",
                            defaultValue: "Catalog scrape data cleared"
                        ))
                        .font(.caption)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .labelStyle(.titleAndIcon)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button(clearScrapedDataButtonTitle) {
                        showClearScrapedDataConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isAnySyncRunning || selectedSchools.isEmpty)
                }
            }
        }
    }

    private var clearScrapedDataButtonTitle: String {
        if catalogPurgeRunner.isRunning {
            return catalogPurgeRunner.statusLine
        }
        let count = selectedSchools.count
        if count <= 1 {
            return String(
                localized: "settings.general.catalog_clear_scraped_button",
                defaultValue: "Clear scraped catalog data"
            )
        }
        return String(
            format: String(
                localized: "settings.general.catalog_clear_scraped_button_fmt",
                defaultValue: "Clear scraped catalog data (%d)"
            ),
            count
        )
    }

    private func clearScrapedCatalogDataForSelectedSchools() {
        guard !catalogPurgeRunner.isRunning, !isAnySyncRunning else { return }
        let schools = selectedSchoolNames
        guard !schools.isEmpty else { return }

        Task {
            await BackgroundServiceOnDemand.run(id: "catalog_school_purge") {
            let manifests = GitHubDataService().loadResolvedSchoolsList()
            var targets: [CatalogSchoolDataPurgeRunner.Target] = []
            var failures: [String] = []

            for schoolName in schools {
                guard let manifest = CatalogBackgroundSyncRunner.matchSchoolManifest(named: schoolName, in: manifests) else {
                    failures.append("\(schoolName): no manifest")
                    continue
                }
                targets.append(
                    CatalogSchoolDataPurgeRunner.Target(
                        schoolID: manifest.id,
                        universityName: manifest.name,
                        catalogURL: manifest.catalogURL,
                        programURLNeedle: CatalogSchoolDataPurge.programURLNeedle(
                            forSchoolID: manifest.id,
                            catalogURL: manifest.catalogURL
                        )
                    )
                )
            }

            let summary = await catalogPurgeRunner.run(targets: targets, persistence: collegePersistence)

            await MainActor.run {
                forceNextCatalogRescrape = true

                if summary.deletedRows > 0 || summary.remainingRows == 0 {
                    let message = targets.map(\.universityName).joined(separator: ", ")
                    appNotifications.post(
                        kind: summary.failures.isEmpty && summary.remainingRows == 0 ? .success : .info,
                        title: catalogPurgeRunner.statusLine,
                        message: "\(message): \(summary.deletedRows) rows removed",
                        isDismissible: true,
                        autoDismissAfter: 8
                    )
                }
                if !failures.isEmpty || !summary.failures.isEmpty {
                    appNotifications.post(
                        kind: .error,
                        title: String(
                            localized: "settings.general.catalog_clear_scraped_failed_title",
                            defaultValue: "Some schools could not be cleared"
                        ),
                        message: (failures + summary.failures).joined(separator: " · "),
                        isDismissible: true,
                        autoDismissAfter: 10
                    )
                }
            }
            }
        }
    }

    private func refreshLocalCatalogFiles() {
        localCatalogFiles = CatalogFileStore.listLocalCatalogs()
    }

    private func openCatalogBundleImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Catalog Bundle"
        panel.allowedContentTypes = [
            UTType(filenameExtension: CatalogBundle.fileExtension) ?? .json,
            UTType(filenameExtension: "sqlite") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppTypedNavigationRouter.importCatalogBundle(at: url)
    }

    private func shareLocalCatalog(_ info: LocalCatalogInfo) {
        do {
            let url = try CatalogFileStore.shareableCopy(for: info.schoolName)
            let picker = NSSharingServicePicker(items: [url])
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            }
        } catch {
            appNotifications.post(
                kind: .error,
                title: "Share Failed",
                message: error.localizedDescription,
                isDismissible: true,
                autoDismissAfter: 6
            )
        }
    }

    private func runManualLocalPDFImport() {
        guard selectedSchoolNames.count == 1, let schoolName = selectedSchoolNames.first else {
            appNotifications.post(
                kind: .error,
                title: "Select one school",
                message: "Choose exactly one school before importing a local catalog PDF.",
                isDismissible: true,
                autoDismissAfter: 5
            )
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import Local Catalog PDF"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let localURL = panel.url else { return }

        Task {
            await MainActor.run {
                activeCatalogSync = .full
            }
            defer {
                Task { @MainActor in
                    activeCatalogSync = nil
                }
            }

            let schools = GitHubDataService().loadResolvedSchoolsList()
            guard let manifest = CatalogBackgroundSyncRunner.matchSchoolManifest(named: schoolName, in: schools) else {
                _ = await MainActor.run {
                    appNotifications.post(
                        kind: .error,
                        title: "School Not Found",
                        message: "Could not resolve manifest for \(schoolName).",
                        isDismissible: true,
                        autoDismissAfter: 6
                    )
                }
                return
            }

            let localManifest = SchoolManifest(
                id: manifest.id,
                name: manifest.name,
                shortName: manifest.shortName,
                unitID: manifest.unitID,
                opeID: manifest.opeID,
                profileURL: manifest.profileURL,
                catalogURL: localURL.absoluteString,
                academicCalendarURL: manifest.academicCalendarURL,
                timeZoneID: manifest.timeZoneID,
                countryCode: manifest.countryCode,
                stateCode: manifest.stateCode,
                officialWebsiteURL: manifest.officialWebsiteURL,
                financialAidURL: manifest.financialAidURL,
                registrarURL: manifest.registrarURL,
                stateAidAgencyURL: manifest.stateAidAgencyURL,
                catalogFormat: "pdf",
                lastUpdated: manifest.lastUpdated,
                coursesCount: manifest.coursesCount,
                verified: manifest.verified
            )

            let toastID = appNotifications.post(
                kind: .progress,
                title: "Catalog PDF Import",
                message: "Importing local PDF for \(schoolName)…",
                progress: 0.05,
                isDismissible: true
            )

            do {
                _ = try await PDFCatalogIngestAdapter.runPDFCatalogSync(
                    manifest: localManifest,
                    toastID: toastID,
                    collegePersistence: collegePersistence,
                    notifications: appNotifications,
                    githubService: GitHubDataService(),
                    depth: .full,
                    hooks: nil
                )
                await MainActor.run {
                    appNotifications.complete(
                        id: toastID,
                        kind: .success,
                        title: "Local PDF Imported",
                        message: "Imported local catalog PDF for \(schoolName).",
                        autoDismissAfter: 5
                    )
                }
            } catch {
                await MainActor.run {
                    appNotifications.dismiss(id: toastID)
                    appNotifications.post(
                        kind: .error,
                        title: "Local PDF Import Failed",
                        message: error.localizedDescription,
                        isDismissible: true,
                        autoDismissAfter: 8
                    )
                }
            }
        }
    }

    private func runRequirementsSync() {
        runRequirementsSyncForItems(Array(selectedMajorWorkItems), force: forceRequirementsRefresh)
    }

    /// Shared sync runner used by both the profile-scoped requirements block and the
    /// "Selected programs only" block. Both surfaces produce `WorkItem`s the same way.
    private func runRequirementsSyncForItems(
        _ items: [CatalogProgramRequirementsHydrator.WorkItem],
        force: Bool
    ) {
        guard !isAnySyncRunning else { return }
        guard !items.isEmpty else { return }

        isRequirementsSyncRunning = true
        Task {
            await CatalogProgramRequirementsHydrator.runUserInitiatedRequirementsSync(
                items: items,
                persistence: collegePersistence,
                notifications: appNotifications,
                force: force
            )
            await MainActor.run { isRequirementsSyncRunning = false }
        }
    }
}
