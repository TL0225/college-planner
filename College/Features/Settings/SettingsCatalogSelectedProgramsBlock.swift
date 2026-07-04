// SettingsCatalogSelectedProgramsBlock.swift
// Feature: Settings
// Purpose: Settings module — SettingsCatalogSelectedProgramsBlock.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// "Selected programs" block for the catalog sync settings.
///
/// Lets the user pick **specific** programs from the indexed catalog (any school, any degree level)
/// and run a deep scrape only for those, instead of the all-programs Full Catalog button.
///
/// Data flow:
/// 1. After Skeleton sync, every catalog program lives in `MajorEntity`.
/// 2. We pull rows for the selected schools via
///    `CatalogProgramRequirementsHydrator.selectableProgramsFromCatalog(...)`.
/// 3. The user multi-selects rows; choices persist via `CatalogSelectedProgramsStore`.
/// 4. Tapping "Scrape selected programs" hands `WorkItem`s straight to
///    `CatalogProgramRequirementsHydrator.runUserInitiatedRequirementsSync(...)`.
struct SettingsCatalogSelectedProgramsBlock: View {
    @Environment(AppContainer.self) private var container
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    /// Inline status banner state. We render this directly in the Settings sidebar so the user
    /// gets immediate feedback when they tap "Scrape selected programs" without relying on
    /// macOS system notifications (which may be disabled). Each scrape transitions through
    /// `.starting` → `.scraping` → `.success` / `.failure`.
    enum ScrapeStatus: Equatable {
        case idle
        case starting(count: Int)
        case scraping(count: Int)
        case success(programsCount: Int, categoriesCount: Int, message: String)
        case warning(message: String)
        case failure(message: String)

        var isBusy: Bool {
            switch self {
            case .starting, .scraping: return true
            default: return false
            }
        }
    }

    let universityNames: [String]
    let isOtherSyncRunning: Bool
    /// Notifies the parent when the local scrape starts (`true`) or finishes (`false`) so the
    /// parent can OR this into its `isAnySyncRunning` lock and grey out sibling controls.
    let onSyncStateChange: (Bool) -> Void

    private var collegePersistence: CollegePersistence { container.persistence }
        @State private var allPrograms: [CatalogProgramRequirementsHydrator.SelectableProgram] = []
    @State private var selectedIDs: Set<String> = CatalogSelectedProgramsStore.allSelected()
    @State private var search: String = ""
    @State private var expandedSections: Set<String> = []
    @State private var forceRefresh: Bool = false
    @State private var isHydrated: Bool = false
    @State private var status: ScrapeStatus = .idle

    private struct ProgramsRefreshTrigger: Equatable {
        var catalogDataRevision: Int
        var profileRevision: Int
        var universityNamesKey: String
    }

    private var programsRefreshTrigger: ProgramsRefreshTrigger {
        ProgramsRefreshTrigger(
            catalogDataRevision: collegePersistence.catalogDataRevision,
            profileRevision: collegePersistence.profileRevision,
            universityNamesKey: universityNames.joined(separator: "|")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(
                localized: "settings.general.catalog_selected_help",
                defaultValue: "Pick the specific programs you care about. Only those get a deep scrape of their requirement pages — much faster than the Full catalog button, and you can come back later to add more. Your picks are saved on this Mac."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if !isHydrated {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(
                        localized: "settings.general.catalog_selected_loading",
                        defaultValue: "Loading catalog programs…"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else if universityNames.isEmpty {
                Text(String(
                    localized: "settings.general.catalog_selected_no_schools",
                    defaultValue: "Pick at least one school above to choose specific programs."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if allPrograms.isEmpty {
                Text(String(
                    localized: "settings.general.catalog_selected_empty",
                    defaultValue: "No catalog programs found for the selected schools. Run the Skeleton scrape first so we know which programs exist."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                controlsRow
                searchField
                programList
            }

            Toggle(String(
                localized: "settings.general.catalog_selected_force",
                defaultValue: "Force refresh (ignore 24h cache)"
            ), isOn: $forceRefresh)
            .toggleStyle(.checkbox)
            .disabled(controlsLocked)

            SettingsLabeledAction(title: String(
                localized: "settings.general.catalog_selected_action",
                defaultValue: "Selected program scrape"
            )) {
                Button(scrapeButtonTitle) {
                    triggerScrape()
                }
                .disabled(controlsLocked || selectedSyncableCount == 0)
            }

            statusBanner
        }
        .padding(.vertical, 2)
        .opacity(isOtherSyncRunning ? 0.65 : 1)
        .task(id: programsRefreshTrigger) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await Task.yield()
            await refreshPrograms()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCatalogScrapePurgeFinished)) { _ in
            Task {
                await Task.yield()
                await refreshPrograms()
            }
        }
    }

    /// Inline status banner replaces silent reliance on system notifications. Always rendered when
    /// a scrape has been attempted so the user can see exactly what happened (or what's happening).
    @ViewBuilder
    private var statusBanner: some View {
        switch status {
        case .idle:
            EmptyView()
        case .starting(let count):
            statusRow(
                systemImage: "hourglass",
                tint: .secondary,
                text: "Preparing to scrape \(count) program\(count == 1 ? "" : "s")…",
                showsSpinner: true
            )
        case .scraping(let count):
            statusRow(
                systemImage: "arrow.triangle.2.circlepath",
                tint: .accentColor,
                text: "Scraping \(count) program\(count == 1 ? "" : "s")… this can take a minute.",
                showsSpinner: true
            )
        case .success(_, _, let message):
            statusRow(systemImage: "checkmark.circle.fill", tint: .green, text: message)
        case .warning(let message):
            statusRow(systemImage: "exclamationmark.triangle.fill", tint: .yellow, text: message)
        case .failure(let message):
            statusRow(systemImage: "xmark.octagon.fill", tint: .red, text: message)
        }
    }

    private func statusRow(systemImage: String, tint: Color, text: String, showsSpinner: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    /// Locks UI when EITHER the sibling sync blocks are running OR this block is mid-scrape OR catalog reset is running.
    private var controlsLocked: Bool {
        isOtherSyncRunning || status.isBusy || CatalogSchoolDataPurgeRunner.shared.isRunning
    }

    // MARK: - Subviews

    private var controlsRow: some View {
        HStack(spacing: 12) {
            Button(String(
                localized: "settings.general.catalog_selected_select_all",
                defaultValue: "Select all visible"
            )) {
                let visible = Set(filteredPrograms.compactMap(\.syncWorkItem).map(\.persistenceKey))
                selectedIDs.formUnion(visible)
                persistSelection()
            }
            .disabled(filteredPrograms.isEmpty || controlsLocked)

            Button(String(
                localized: "settings.general.catalog_selected_clear",
                defaultValue: "Clear selection"
            )) {
                selectedIDs.removeAll()
                persistSelection()
            }
            .disabled(selectedIDs.isEmpty || controlsLocked)

            Button(String(
                localized: "settings.general.catalog_selected_use_profile",
                defaultValue: "Use my profile picks"
            )) {
                applyProfileDefaults()
            }
            .disabled(controlsLocked)

            Spacer()

            Text(selectionCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        TextField(
            String(
                localized: "settings.general.catalog_selected_search",
                defaultValue: "Search programs"
            ),
            text: $search
        )
        .textFieldStyle(.roundedBorder)
        .disabled(controlsLocked)
    }

    private var programList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredSectionsByPicker, id: \.title) { section in
                    sectionHeader(section)
                    if expandedSections.contains(section.title) {
                        ForEach(section.programs) { option in
                            programRow(option)
                                .padding(.leading, 16)
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(DesignSystem.Spacing.sm)
        }
        .frame(maxHeight: 320)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sectionHeader(
        _ section: (title: String, programs: [CatalogProgramRequirementsHydrator.SelectableProgram])
    ) -> some View {
        let expanded = expandedSections.contains(section.title)
        let picked = sectionSelectedCount(section)
        return Button {
            toggleExpansion(section.title)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(section.title)
                    .font(.subheadline.weight(.medium))
                Text("(\(section.programs.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if picked > 0 {
                    Text(String(
                        format: String(
                            localized: "settings.general.catalog_selected_school_picked_fmt",
                            defaultValue: "%d picked"
                        ),
                        picked
                    ))
                    .font(.caption2)
                    .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func toggleExpansion(_ title: String) {
        if expandedSections.contains(title) {
            expandedSections.remove(title)
        } else {
            expandedSections.insert(title)
        }
    }

    @ViewBuilder
    private func programRow(_ option: CatalogProgramRequirementsHydrator.SelectableProgram) -> some View {
        if let workItem = option.syncWorkItem {
            Toggle(isOn: selectionBinding(for: workItem)) {
                Text(option.pickerLabel)
                    .lineLimit(3)
            }
            .toggleStyle(.checkbox)
            .disabled(controlsLocked)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.pickerLabel)
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                    Text(String(
                        localized: "settings.general.catalog_selected_no_link",
                        defaultValue: "No catalog link — run Skeleton scrape first"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Derived state

    private var filteredPrograms: [CatalogProgramRequirementsHydrator.SelectableProgram] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allPrograms }
        return allPrograms.filter {
            $0.pickerLabel.localizedCaseInsensitiveContains(query)
                || $0.sectionTitle.localizedCaseInsensitiveContains(query)
                || $0.universityName.localizedCaseInsensitiveContains(query)
                || $0.catalogLevel.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredSectionsByPicker: [(title: String, programs: [CatalogProgramRequirementsHydrator.SelectableProgram])] {
        CatalogProgramRequirementsHydrator.programSectionsByPickerSection(from: filteredPrograms)
    }

    private var allWorkItems: [CatalogProgramRequirementsHydrator.WorkItem] {
        allPrograms.compactMap(\.syncWorkItem)
    }

    private var selectedSyncableCount: Int {
        allWorkItems.filter { selectedIDs.contains($0.persistenceKey) }.count
    }

    private var selectionCountLabel: String {
        let totalSelected = selectedSyncableCount
        let totalAvailable = allWorkItems.count
        if totalSelected == 0 {
            return String(
                format: String(
                    localized: "settings.general.catalog_selected_count_fmt",
                    defaultValue: "%d available · 0 picked"
                ),
                totalAvailable
            )
        }
        return String(
            format: String(
                localized: "settings.general.catalog_selected_picked_fmt",
                defaultValue: "%d picked of %d"
            ),
            totalSelected,
            totalAvailable
        )
    }

    private var scrapeButtonTitle: String {
        if status.isBusy {
            return String(
                localized: "settings.general.catalog_selected_scrape_running",
                defaultValue: "Scraping…"
            )
        }
        let count = selectedSyncableCount
        if count == 0 {
            return String(
                localized: "settings.general.catalog_selected_scrape_idle",
                defaultValue: "Scrape selected programs"
            )
        }
        if count == 1 {
            return String(
                localized: "settings.general.catalog_selected_scrape_one",
                defaultValue: "Scrape 1 program"
            )
        }
        return String(
            format: String(
                localized: "settings.general.catalog_selected_scrape_n_fmt",
                defaultValue: "Scrape %d programs"
            ),
            count
        )
    }

    private func sectionSelectedCount(
        _ section: (title: String, programs: [CatalogProgramRequirementsHydrator.SelectableProgram])
    ) -> Int {
        section.programs.reduce(0) { acc, program in
            guard let item = program.syncWorkItem else { return acc }
            return acc + (selectedIDs.contains(item.persistenceKey) ? 1 : 0)
        }
    }

    // MARK: - Bindings

    private func selectionBinding(
        for workItem: CatalogProgramRequirementsHydrator.WorkItem
    ) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(workItem.persistenceKey) },
            set: { isOn in
                if isOn {
                    selectedIDs.insert(workItem.persistenceKey)
                } else {
                    selectedIDs.remove(workItem.persistenceKey)
                }
                persistSelection()
            }
        )
    }

    // MARK: - Actions

    private func refreshPrograms() async {
        let names = universityNames
        let programs = await CatalogProgramRequirementsHydrator.selectableProgramsFromCatalogOffMain(
            universityNames: names
        )

        let validIDs = Set(programs.compactMap(\.syncWorkItem).map(\.persistenceKey))
        let pruned = CatalogSelectedProgramsStore.prune(validIDs: validIDs)

        allPrograms = programs
        selectedIDs = pruned
        if expandedSections.isEmpty {
            expandedSections = Set(CatalogProgramRequirementsHydrator.programSectionsByPickerSection(from: programs).map(\.title))
        }
        isHydrated = true
    }

    private func persistSelection() {
        CatalogSelectedProgramsStore.replace(selectedIDs)
    }

    private func applyProfileDefaults() {
        let profilePrograms = CatalogProgramRequirementsHydrator.selectablePrograms(
            profiles: AcademicProfileReadBridge.entities(collegePersistence: collegePersistence),
            universityNames: universityNames,
            persistence: collegePersistence,
            fallbackCollege: collegePersistence.profile?.collegeName
        )
        let profileKeys = profilePrograms.compactMap(\.syncWorkItem).map(\.persistenceKey)
        let availableKeys = Set(allWorkItems.map(\.persistenceKey))
        selectedIDs.formUnion(profileKeys.filter { availableKeys.contains($0) })
        persistSelection()
    }

    private func triggerScrape() {
        guard !status.isBusy else {
            DebugLogger.shared.scraper("📚 Selected scrape: ignored click — already running")
            return
        }
        guard !isOtherSyncRunning else {
            status = .warning(message: "Another catalog sync is already running — wait for it to finish.")
            DebugLogger.shared.scraper("📚 Selected scrape: blocked by parent sync")
            return
        }
        let items = allWorkItems.filter { selectedIDs.contains($0.persistenceKey) }
        guard !items.isEmpty else {
            status = .warning(message: "Nothing to scrape — your selection has no programs with catalog links.")
            DebugLogger.shared.scraper("📚 Selected scrape: zero items after filter (selectedIDs=\(selectedIDs.count), allWorkItems=\(allWorkItems.count))")
            return
        }

        DebugLogger.shared.scraper("📚 Selected scrape: launching items=\(items.count) force=\(forceRefresh)")
        status = .starting(count: items.count)
        Task { @MainActor in
            await Task.yield()
            onSyncStateChange(true)
        }
        let force = forceRefresh
        let toScrape = items
        let persistence = collegePersistence
        let notifications = appNotifications

        Task { @MainActor in
            status = .scraping(count: toScrape.count)
            DebugLogger.shared.scraper("📚 Selected scrape: hydrator start")
            let results = await CatalogProgramRequirementsHydrator.runUserInitiatedRequirementsSync(
                items: toScrape,
                persistence: persistence,
                notifications: notifications,
                force: force
            )
            let summary = summarize(results, requested: toScrape.count)
            DebugLogger.shared.scraper(
                "📚 Selected scrape: hydrator finished saved=\(summary.savedCategories) covered=\(summary.coveredPrograms) failed=\(summary.failedPrograms) skipped=\(summary.skippedPrograms)"
            )
            status = bannerStatus(from: summary, requested: toScrape.count, force: force, errors: results.compactMap(\.errorMessage))
            await Task.yield()
            onSyncStateChange(false)
        }
    }

    private struct ScrapeSummary {
        var savedCategories: Int
        var savedCourses: Int
        var coveredPrograms: Int
        var emptyCategoryPrograms: Int
        var failedPrograms: Int
        var skippedPrograms: Int
    }

    /// Turns the hydrator's per-program result list into a banner-friendly aggregate. Avoids
    /// re-reading local store here — `RequirementsRefreshResult` already carries both the saved
    /// category count and the saved course-code count for the precise `(university, programURL)`
    /// the user just scraped (works for cross-school picks too).
    private func summarize(
        _ results: [CollegePersistence.RequirementsRefreshResult],
        requested: Int
    ) -> ScrapeSummary {
        var savedCategories = 0
        var savedCourses = 0
        var covered = 0
        var emptyCategoryPrograms = 0
        var skipped = 0
        var failed = 0
        for result in results {
            if result.errorMessage != nil {
                failed += 1
            } else if result.skippedDueToFreshCache {
                skipped += 1
            } else if result.savedRowCount > 0 {
                savedCategories += result.savedRowCount
                savedCourses += result.savedCourseCount
                if result.savedCourseCount == 0 {
                    emptyCategoryPrograms += 1
                } else {
                    covered += 1
                }
            }
        }
        if results.count < requested {
            failed += requested - results.count
        }
        return ScrapeSummary(
            savedCategories: savedCategories,
            savedCourses: savedCourses,
            coveredPrograms: covered,
            emptyCategoryPrograms: emptyCategoryPrograms,
            failedPrograms: failed,
            skippedPrograms: skipped
        )
    }

    private func bannerStatus(
        from summary: ScrapeSummary,
        requested: Int,
        force: Bool,
        errors: [String]
    ) -> ScrapeStatus {
        if summary.coveredPrograms == 0 && summary.emptyCategoryPrograms == 0 && summary.failedPrograms > 0 {
            let firstError = errors.first ?? "Scrape finished but no categories were saved. Check that Skeleton scrape ran for the program’s school and try Force refresh."
            return .failure(message: firstError)
        }
        if summary.savedCategories == 0 && summary.skippedPrograms == requested && !force {
            return .warning(message: "No changes — every selected program was already fresh in the last 24 hours. Turn on Force refresh to re-download anyway.")
        }
        if summary.savedCategories == 0 {
            return .warning(message: "Scrape ran but no requirement categories were parsed. The catalog page may be empty or the program link is stale — try Force refresh.")
        }
        // Categories landed but every program came back with 0 course codes — Modern Campus
        // parser likely missed a layout variant (common for graduate / certificate pages).
        if summary.savedCourses == 0 && summary.emptyCategoryPrograms > 0 {
            return .warning(message: "Saved \(summary.savedCategories) category header\(summary.savedCategories == 1 ? "" : "s") across \(summary.emptyCategoryPrograms) program\(summary.emptyCategoryPrograms == 1 ? "" : "s"), but the parser couldn’t pull course codes out of the catalog page. This is a parser gap for that catalog layout — Academics will stay empty until we add support for it.")
        }

        let totalLanded = summary.coveredPrograms + summary.emptyCategoryPrograms
        let progPlural = totalLanded == 1 ? "" : "s"
        let catPlural = summary.savedCategories == 1 ? "y" : "ies"
        var msg = "Saved \(summary.savedCategories) requirement categor\(catPlural) (\(summary.savedCourses) course code\(summary.savedCourses == 1 ? "" : "s")) across \(totalLanded) program\(progPlural)."
        if summary.emptyCategoryPrograms > 0 {
            msg += " \(summary.emptyCategoryPrograms) program\(summary.emptyCategoryPrograms == 1 ? "" : "s") parsed categories but no courses — Academics won’t show those until the parser is extended."
        }
        if summary.failedPrograms > 0 {
            msg += " \(summary.failedPrograms) failed."
        }
        if summary.skippedPrograms > 0 {
            msg += " \(summary.skippedPrograms) skipped (fresh)."
        }

        // Promote to a warning banner when ANY program landed with empty categories so the user
        // immediately sees the parser-gap message instead of a green checkmark.
        if summary.emptyCategoryPrograms > 0 {
            return .warning(message: msg)
        }
        return .success(
            programsCount: totalLanded,
            categoriesCount: summary.savedCategories,
            message: msg
        )
    }
}

// MARK: - WorkItem persistence key

extension CatalogProgramRequirementsHydrator.WorkItem {
    /// Stable identifier suitable for UserDefaults persistence and dictionary keys.
    var persistenceKey: String {
        let url = programURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(universityName)|\(url)|\(isMinor ? "minor" : "major")"
    }
}
