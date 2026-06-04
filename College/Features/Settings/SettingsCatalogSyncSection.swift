// SettingsCatalogSyncSection.swift
// Feature: Settings
// Purpose: Settings module — SettingsCatalogSyncSection.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Academic catalog sync (multi-school)

struct SettingsCatalogSyncSection: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject private var appNotifications: AppNotificationCenter

    @State private var availableSchools: [String] = []
    @State private var selectedSchools: Set<String> = []
    @State private var schoolSearch = ""
    @State private var isLoadingSchools = false
    @State private var activeCatalogSync: CatalogBackgroundSyncRunner.CatalogSyncDepth?
    @State private var isRequirementsSyncRunning = false
    @State private var forceRequirementsRefresh = false
    @State private var hydratableMajors: [CatalogProgramRequirementsHydrator.SelectableMajor] = []
    @State private var selectedMajorWorkItems: Set<CatalogProgramRequirementsHydrator.WorkItem> = []
    @State private var expandedSchoolSections: Set<String> = []
    @State private var didApplyDefaultSchoolSelection = false
    @State private var localCatalogFiles: [LocalCatalogInfo] = []
    @State private var showTrustedSources = false
    @State private var showClearScrapedDataConfirm = false
    @ObservedObject private var catalogPurgeRunner = CatalogSchoolDataPurgeRunner.shared
    @AppStorage("catalog.ingest.forceNext.v1") private var forceNextCatalogRescrape: Bool = false

    private var filteredSchools: [String] {
        let query = schoolSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableSchools }
        return availableSchools.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var isCatalogSyncRunning: Bool { activeCatalogSync != nil }
    private var isAnySyncRunning: Bool {
        isCatalogSyncRunning || isRequirementsSyncRunning || catalogPurgeRunner.isRunning
    }

    private var selectedSchoolNames: [String] {
        availableSchools.filter { selectedSchools.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            schoolPickerBlock

            clearScrapedCatalogDataBlock

            catalogSyncDepthBlock(
                depth: .light,
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

            SettingsCatalogSelectedProgramsBlock(
                universityNames: selectedSchoolNames,
                isOtherSyncRunning: isAnySyncRunning,
                onSyncStateChange: { running in
                    isRequirementsSyncRunning = running
                    if !running { refreshHydratableMajors() }
                }
            )

            requirementsSyncBlock

            Toggle(
                String(
                    localized: "settings.general.catalog_force_rescrape_once",
                    defaultValue: "Force next catalog re-scrape (ignore unchanged signature checks once)"
                ),
                isOn: $forceNextCatalogRescrape
            )
            .toggleStyle(.checkbox)
            .disabled(isAnySyncRunning)

            catalogSyncDepthBlock(
                depth: .full,
                sectionTitle: String(
                    localized: "settings.general.catalog_full_title",
                    defaultValue: "Full catalog"
                ),
                sectionDescription: String(
                    localized: "settings.general.catalog_full_help",
                    defaultValue: "Heavy sync — fetches degree requirements for every program. Can take a long time on large catalogs (especially with strict crawl delays). Prefer skeleton first; Profile can hydrate requirements when you pick a major."
                ),
                syncButtonLabel: syncButtonTitle(for: .full)
            )

            catalogBundleSharingBlock

            catalogDiagnosticsBlock
        }
        .task { await loadSchools() }
        .alert(
            String(
                localized: "settings.general.catalog_clear_scraped_confirm_title",
                defaultValue: "Clear scraped catalog data?"
            ),
            isPresented: $showClearScrapedDataConfirm
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
        .onAppear { refreshLocalCatalogFiles() }
        .onChange(of: selectedSchools) { _, _ in
            refreshHydratableMajors()
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            refreshHydratableMajors()
        }
        .onChange(of: collegePersistence.profile?.collegeName) { _, _ in
            refreshHydratableMajors()
        }
        .onChange(of: activeCatalogSync) { _, newValue in
            if newValue == nil {
                refreshHydratableMajors()
            }
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            refreshHydratableMajors()
        }
    }

    private var programSectionsBySchool: [(school: String, programs: [CatalogProgramRequirementsHydrator.SelectableMajor])] {
        CatalogProgramRequirementsHydrator.programSectionsBySchool(from: hydratableMajors)
    }

    private var syncableProgramCount: Int {
        hydratableMajors.filter(\.isSyncable).count
    }

    // MARK: - School picker

    private var schoolPickerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.general.catalog_schools_title", defaultValue: "Schools"))
                .font(.subheadline.weight(.medium))

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
                                Text(school)
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

    @ViewBuilder
    private func catalogSyncDepthBlock(
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        sectionTitle: String,
        sectionDescription: String,
        syncButtonLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sectionTitle)
                .font(.subheadline.weight(.medium))

            Text(sectionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsLabeledAction(title: syncActionRowTitle(for: depth)) {
                Button(syncButtonLabel) {
                    runCatalogSync(depth: depth)
                }
                .disabled(isAnySyncRunning || selectedSchools.isEmpty)
            }
        }
        .padding(.vertical, 2)
        .opacity(activeCatalogSync == depth ? 1 : (isCatalogSyncRunning ? 0.65 : 1))
    }

    // MARK: - Requirements sync (selected majors)

    private var requirementsSyncBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(
                localized: "settings.general.catalog_requirements_title",
                defaultValue: "Degree requirements"
            ))
            .font(.subheadline.weight(.medium))

            Text(String(
                localized: "settings.general.catalog_requirements_help",
                defaultValue: "Programs from your Edit Profile degrees only, grouped by school. After skeleton sync for a school, fetch requirement pages for the majors and minors on that school’s degrees. Requirements are stored per university in the app database."
            ))
            .font(.caption)
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
                .padding(8)
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
        .padding(.vertical, 2)
        .opacity(isRequirementsSyncRunning ? 1 : (isCatalogSyncRunning ? 0.65 : 1))
        .onAppear { refreshHydratableMajors() }
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

    private func refreshHydratableMajors() {
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
        if activeCatalogSync == depth {
            switch depth {
            case .light:
                return String(localized: "settings.general.syncing_skeleton", defaultValue: "Skeleton sync…")
            case .full:
                return String(localized: "settings.general.syncing_full", defaultValue: "Full sync…")
            }
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
            refreshHydratableMajors()
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
        Task {
            for school in schools {
                await CatalogBackgroundSyncRunner.runUserInitiatedCatalogSync(
                    schoolName: school,
                    collegePersistence: collegePersistence,
                    notifications: appNotifications,
                    depth: depth
                )
            }
            await MainActor.run {
                activeCatalogSync = nil
                refreshHydratableMajors()
            }
        }
    }

    private var catalogBundleSharingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Catalog bundle sharing")
                .font(.headline)
            Text("Export signed catalog bundles for other College users, or import a bundle you received (AirDrop, email, etc.).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Import Catalog Bundle…") {
                    openCatalogBundleImportPanel()
                }
                .disabled(isAnySyncRunning)

                Button("Import Local Catalog PDF…") {
                    runManualLocalPDFImport()
                }
                .disabled(isAnySyncRunning || selectedSchoolNames.count != 1)

                Button("Trusted Catalog Sources…") {
                    showTrustedSources = true
                }
            }

            if !localCatalogFiles.isEmpty {
                Text("Local catalog files")
                    .font(.subheadline.weight(.semibold))
                ForEach(localCatalogFiles, id: \.fileURL) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.schoolName)
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 8) {
                                Text(ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
                                Text(info.lastModified, style: .date)
                                if let fp = info.signerFingerprint {
                                    Text(fp)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Share") {
                            shareLocalCatalog(info)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
        .sheet(isPresented: $showTrustedSources) {
            NavigationStack {
                CatalogTrustedSourcesView()
            }
            .frame(minWidth: 520, minHeight: 400)
        }
    }

    private var clearScrapedCatalogDataBlock: some View {
        SettingsCard(title: "Reset scraped catalog", icon: "arrow.counterclockwise.circle", iconColor: .orange) {
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
                refreshHydratableMajors()
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

    @ViewBuilder
    private var catalogDiagnosticsBlock: some View {
        let profileSchool = collegePersistence.profile?.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let schoolID = collegePersistence.catalogManifestSchoolID(forUniversityName: profileSchool) ?? ""
        let pdfReport = schoolID.isEmpty ? nil : PDFScrapeReport.load(schoolID: schoolID)
        let integrity = schoolID.isEmpty ? nil : CatalogIntegrityReport.load(schoolID: schoolID)
        let archiveIndex = schoolID.isEmpty ? nil : CatalogArchiveStore.loadIndex(schoolID: schoolID)
        let storeDiagnostics = schoolID.isEmpty ? nil : CatalogStoreCoordinator.shared.diagnostics(for: schoolID)
        let ingestObs = CatalogIngestObservability.summarizeRecent()
        let reviewQueueCount = CatalogReviewQueue.load().count

        if pdfReport != nil || integrity != nil || archiveIndex != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.general.catalog_diagnostics_title", defaultValue: "Catalog diagnostics"))
                    .font(.subheadline.weight(.medium))

                if let pdfReport {
                    Text("PDF scrape — \(pdfReport.schoolName)")
                        .font(.caption.weight(.semibold))
                    Text("Pages \(pdfReport.pageCount) · Programs \(pdfReport.programsExtracted) · Courses \(pdfReport.coursesExtracted) · Requirements \(pdfReport.requirementsExtracted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let blocks = pdfReport.blockClassification {
                        Text("Blocks \(blocks.totalBlocks) · Program candidates \(blocks.programCandidates) accepted \(blocks.programAccepted) rejected \(blocks.programRejected)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !pdfReport.warnings.isEmpty {
                        Text(pdfReport.warnings.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                if let integrity {
                    Text("Integrity — academic \(integrity.academicReady ? "ready" : "partial") · archive \(integrity.archiveReady ? "ready" : "pending") · search \(integrity.vectorsReady ? "ready" : "indexing")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let archiveIndex {
                    Text("Archive index — \(archiveIndex.archivedPages)/\(archiveIndex.totalPages) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let storeDiagnostics {
                    Text("Per-school sqlite — \(storeDiagnostics.exists ? "present" : "missing") · \(ByteCountFormatter.string(fromByteCount: storeDiagnostics.sizeBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(storeDiagnostics.sqlitePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("Ingest observability — failures \(Int((ingestObs.failureRate * 100).rounded()))% · avg duration \(Int(ingestObs.avgDurationMs.rounded()))ms · avg OCR usage \(Int((ingestObs.avgOCRRate * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Parser capability \(CatalogParserCapability.version) · review queue \(reviewQueueCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !schoolID.isEmpty {
                    Button(String(localized: "settings.general.catalog_cancel_import", defaultValue: "Request catalog import cancel")) {
                        CatalogIngestCheckpoint.requestCancel(schoolID: schoolID)
                        appNotifications.post(
                            kind: .info,
                            title: "Cancel requested",
                            message: "The current catalog import will stop at the next checkpoint.",
                            isDismissible: true,
                            autoDismissAfter: 5
                        )
                    }
                    .disabled(isAnySyncRunning == false)
                }
            }
            .padding(.top, 8)
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
        NotificationCenter.default.post(
            name: .plannerImportCatalogBundleFileURL,
            object: nil,
            userInfo: ["url": url]
        )
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
                    refreshHydratableMajors()
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
