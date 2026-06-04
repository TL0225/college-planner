// CatalogProgramRequirementsHydrator.swift
// Feature: Catalog
// Purpose: Catalog module — WorkItem.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Background JIT scrape of Modern Campus program requirement pages after the user selects a major.
@MainActor
enum CatalogProgramRequirementsHydrator {
    struct WorkItem: Hashable, Sendable {
        let universityName: String
        let programURL: String
        let majorDisplay: String
        let degreeType: String
        let isMinor: Bool
    }

    struct SelectableProgram: Identifiable, Hashable {
        /// Non-nil when skeleton sync saved a program link for this row.
        let syncWorkItem: WorkItem?
        /// Plain program label shown in the picker, e.g. `Computer Science (BS)`.
        let pickerLabel: String
        /// Onboarding-style section title, e.g. `Undergraduate > Tandon School of Engineering`.
        let sectionTitle: String
        let catalogLevel: String
        let universityName: String

        /// Legacy combined label kept for search/backward compatibility.
        var degreeLabel: String { pickerLabel }

        var id: String {
            syncWorkItem?.persistenceKey ?? "\(universityName)|\(sectionTitle)|\(pickerLabel)"
        }

        var isSyncable: Bool { syncWorkItem != nil }
    }

    /// Backward-compatible alias for Settings call sites.
    typealias SelectableMajor = SelectableProgram

    /// Intermediate row used while deduplicating catalog programs (see
    /// `selectableProgramsFromCatalog`). Not exposed to call sites.
    fileprivate struct SelectableProgramCandidate {
        let typeLabel: String
        let displayName: String
        let canonical: String
        let isMinor: Bool
        let storedType: String
        let program: SelectableProgram
    }

    private static var hydrationTask: Task<Void, Never>?

    /// Every program indexed for the selected schools, grouped for Settings (Undergraduate, Graduate, …).
    ///
    /// Catalog scrapes can emit two rows for the same canonical major: one stamped with a real
    /// degree type ("Master of Science · Cyber Defense, M.S.") and a leftover generic row whose
    /// degree info wasn't resolved ("Program · Cyber Defense"). We collapse those duplicates by
    /// bucketing on `(university, canonical-name, isMinor)` and preferring the most specific row.
    static func selectableProgramsFromCatalog(
        universityNames: [String],
        persistence: CollegePersistence
    ) -> [SelectableProgram] {
        let majors = persistence.fetchCatalogProgramsForRequirementsPicker(universityNames: universityNames)
        let rows = majors.map { major in
            let firstDepartment = major.departments?.first
            return CatalogProgramPickerRowSnapshot(
                universityName: (major.university?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                name: major.name.trimmingCharacters(in: .whitespacesAndNewlines),
                degreeLevel: major.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines),
                degreeType: major.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines),
                isMinor: major.isMinor,
                programURL: major.programURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                resolvedDepartment: major.resolvedDepartment,
                resolvedCollege: major.resolvedCollege,
                departmentSchool: firstDepartment?.school,
                departmentName: firstDepartment?.name
            )
        }
        return selectablePrograms(fromPickerRows: rows)
    }

    /// Off-main catalog fetch + dedup (Phase 5 P0). Prefer over ``selectableProgramsFromCatalog`` in UI refresh paths.
    static func selectableProgramsFromCatalogOffMain(
        universityNames: [String]
    ) async -> [SelectableProgram] {
        await CatalogProgramPickerBridge.selectableProgramsOffMain(universityNames: universityNames)
    }

    /// Pure dedup/sort from sendable picker rows; safe to call from a detached task.
    nonisolated static func selectablePrograms(
        fromPickerRows rows: [CatalogProgramPickerRowSnapshot]
    ) -> [SelectableProgram] {
        var candidates: [SelectableProgramCandidate] = []
        var seen = Set<String>()

        for row in rows {
            let university = row.universityName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !university.isEmpty, !displayName.isEmpty else { continue }

            let rawLevel = row.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
            let catalogLevel = rawLevel.isEmpty
                ? DegreeConfiguration.undergraduate
                : DegreeConfiguration.canonicalLevel(rawLevel)

            let storedType = (row.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isMinor = row.isMinor

            let canonicalURL = (row.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rowID = "\(university)|\(canonicalURL)|\(displayName)|\(storedType)|\(isMinor)"
            guard seen.insert(rowID).inserted else { continue }

            let pickerLabel = CatalogProgramPickerQuery.pickerLabel(
                name: displayName,
                degreeType: storedType.isEmpty ? nil : storedType,
                isMinor: isMinor
            ) ?? displayName
            let sectionTitle = CatalogProgramPickerQuery.sectionTitle(for: row)
                ?? "\(catalogLevel) > \(university)"

            let syncWorkItem = makeWorkItem(
                programURL: canonicalURL,
                university: university,
                programDisplay: displayName,
                requirementsDegreeType: isMinor
                    ? "Minor"
                    : (storedType.isEmpty ? requirementsDegreeTypeFromDisplayName(displayName) : storedType),
                isMinor: isMinor
            )

            let program = SelectableProgram(
                syncWorkItem: syncWorkItem,
                pickerLabel: pickerLabel,
                sectionTitle: sectionTitle,
                catalogLevel: catalogLevel,
                universityName: university
            )

            candidates.append(
                SelectableProgramCandidate(
                    typeLabel: storedType.isEmpty ? "Program" : CatalogDegreeTypeFilter.tabDisplayLabel(forDegreeType: storedType),
                    displayName: displayName,
                    canonical: canonicalProgramName(displayName) + "|" + canonicalURL.lowercased(),
                    isMinor: isMinor,
                    storedType: storedType,
                    program: program
                )
            )
        }

        let collapsed = collapseDuplicateCandidates(candidates)

        return collapsed.sorted {
            if $0.sectionTitle != $1.sectionTitle {
                return $0.sectionTitle.localizedCaseInsensitiveCompare($1.sectionTitle) == .orderedAscending
            }
            return $0.pickerLabel.localizedCaseInsensitiveCompare($1.pickerLabel) == .orderedAscending
        }
    }

    /// Canonical program name used for dedup: trim, lowercase, drop the trailing `, X.Y.` suffix.
    nonisolated private static func canonicalProgramName(_ display: String) -> String {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(",") {
            let stem = trimmed
                .split(separator: ",", omittingEmptySubsequences: false)
                .dropLast()
                .joined(separator: ",")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stem.isEmpty { return stem.lowercased() }
        }
        return trimmed.lowercased()
    }

    /// Bucket candidates by `(university, canonical-name, isMinor)` and keep the most
    /// specific row per bucket (typed beats generic "Program"; with-suffix beats without).
    nonisolated private static func collapseDuplicateCandidates(
        _ candidates: [SelectableProgramCandidate]
    ) -> [SelectableProgram] {
        var order: [String] = []
        var buckets: [String: [SelectableProgramCandidate]] = [:]
        for candidate in candidates {
            let key = "\(candidate.program.universityName.lowercased())|\(candidate.canonical)|\(candidate.isMinor ? "m" : "p")"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(candidate)
        }

        return order.compactMap { key in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            let typed = group.filter { $0.typeLabel != "Program" }
            let pool = typed.isEmpty ? group : typed
            let best = pool.max { lhs, rhs in
                specificityScore(lhs) < specificityScore(rhs)
            }
            return best?.program
        }
    }

    nonisolated private static func specificityScore(_ c: SelectableProgramCandidate) -> Int {
        var score = 0
        if c.typeLabel != "Program" { score += 4 }
        if c.displayName.contains(",") { score += 2 }
        if !c.storedType.isEmpty { score += 2 }
        if c.program.syncWorkItem != nil { score += 1 }
        return score
    }

    /// Settings sections grouped like onboarding: `Undergraduate > College/Department`.
    static func programSectionsByPickerSection(
        from programs: [SelectableProgram]
    ) -> [(title: String, programs: [SelectableProgram])] {
        Dictionary(grouping: programs) { $0.sectionTitle }
            .map { title, rows in
                (
                    title: title,
                    programs: rows.sorted {
                        $0.pickerLabel.localizedCaseInsensitiveCompare($1.pickerLabel) == .orderedAscending
                    }
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Settings sections grouped by school (one disclosure per university).
    static func programSectionsBySchool(
        from programs: [SelectableProgram]
    ) -> [(school: String, programs: [SelectableProgram])] {
        Dictionary(grouping: programs) { $0.universityName }
            .map { school, rows in
                (
                    school: school,
                    programs: rows.sorted {
                        $0.degreeLabel.localizedCaseInsensitiveCompare($1.degreeLabel) == .orderedAscending
                    }
                )
            }
            .sorted { $0.school.localizedCaseInsensitiveCompare($1.school) == .orderedAscending }
    }

    nonisolated private static func requirementsDegreeTypeFromDisplayName(_ displayName: String) -> String {
        if let suffix = CatalogDegreeTypeFilter.suffixToken(fromDisplayName: displayName) {
            return suffix
        }
        return "Unknown"
    }

    /// Majors and minors on the user's academic profiles (used to pre-select rows in Settings).
    static func selectablePrograms(
        profiles: [AcademicProfile],
        universityNames: [String],
        persistence: CollegePersistence,
        fallbackCollege: String? = nil
    ) -> [SelectableProgram] {
        let allowedSchools = universityNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let legacyCollege = fallbackCollege?.trimmingCharacters(in: .whitespacesAndNewlines)

        let scoped = profiles.filter { profile in
            let college = profile.effectiveUniversityName(
                among: profiles,
                fallbackCollege: legacyCollege
            )
            guard !college.isEmpty else { return false }
            if allowedSchools.isEmpty { return true }
            return allowedSchools.contains { $0.caseInsensitiveCompare(college) == .orderedSame }
        }

        var options: [SelectableProgram] = []
        var seen = Set<String>()

        for profile in scoped {
            let university = profile.effectiveUniversityName(
                among: profiles,
                fallbackCollege: legacyCollege
            )
            let level = profile.degreeLevel?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !university.isEmpty, !level.isEmpty else { continue }

            let profileDegreeType = profile.degreeType?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let catalogLevel = DegreeConfiguration.canonicalLevel(level)

            let majors = AcademicProfileProgramLists.majors(from: profile)
            if let primary = majors.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !primary.isEmpty {
                let rowKey = "\(university)|\(catalogLevel)|major|\(primary)|\(profileDegreeType)"
                guard seen.insert(rowKey).inserted else { continue }
                let syncItem = makeWorkItem(
                    programDisplay: primary,
                    university: university,
                    degreeLevel: level,
                    pickerDegreeType: profileDegreeType.isEmpty ? nil : profileDegreeType,
                    requirementsDegreeType: profileDegreeType.isEmpty
                       ? "Unknown"
                       : CatalogDegreeTypeFilter.requirementsStorageKey(fromProfileDegreeType: profileDegreeType),
                    isMinor: false,
                    persistence: persistence
                )
                options.append(
                    SelectableProgram(
                        syncWorkItem: syncItem,
                        pickerLabel: primary,
                        sectionTitle: "\(catalogLevel) > \(university)",
                        catalogLevel: catalogLevel,
                        universityName: university
                    )
                )
            }

            let minors = AcademicProfileProgramLists.minors(from: profile)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "none" }
            for minor in minors {
                let rowKey = "\(university)|\(catalogLevel)|minor|\(minor)"
                guard seen.insert(rowKey).inserted else { continue }
                let syncItem = makeWorkItem(
                    programDisplay: minor,
                    university: university,
                    degreeLevel: level,
                    pickerDegreeType: nil,
                    requirementsDegreeType: "Minor",
                    isMinor: true,
                    persistence: persistence
                )
                options.append(
                    SelectableProgram(
                        syncWorkItem: syncItem,
                        pickerLabel: minor,
                        sectionTitle: "\(catalogLevel) > \(university)",
                        catalogLevel: catalogLevel,
                        universityName: university
                    )
                )
            }
        }

        return options.sorted {
            if $0.universityName != $1.universityName {
                return $0.universityName.localizedCaseInsensitiveCompare($1.universityName) == .orderedAscending
            }
            return $0.degreeLabel.localizedCaseInsensitiveCompare($1.degreeLabel) == .orderedAscending
        }
    }

    static func selectableMajors(
        profiles: [AcademicProfile],
        universityNames: [String],
        persistence: CollegePersistence,
        fallbackCollege: String? = nil
    ) -> [SelectableProgram] {
        selectablePrograms(
            profiles: profiles,
            universityNames: universityNames,
            persistence: persistence,
            fallbackCollege: fallbackCollege
        )
    }

    /// Builds a scrape work item for Academics audit auto-hydration (same resolution as Settings sync).
    static func makeWorkItemForAudit(
        programDisplay: String,
        university: String,
        degreeLevel: String,
        profileDegreeType: String,
        isMinor: Bool,
        persistence: CollegePersistence
    ) -> WorkItem? {
        makeWorkItem(
            programDisplay: programDisplay,
            university: university,
            degreeLevel: degreeLevel,
            pickerDegreeType: profileDegreeType.isEmpty ? nil : profileDegreeType,
            requirementsDegreeType: isMinor
                ? "Minor"
                : (profileDegreeType.isEmpty
                    ? "Unknown"
                    : CatalogDegreeTypeFilter.requirementsStorageKey(fromProfileDegreeType: profileDegreeType)),
            isMinor: isMinor,
            persistence: persistence
        )
    }

    nonisolated private static func makeWorkItem(
        programURL: String,
        university: String,
        programDisplay: String,
        requirementsDegreeType: String,
        isMinor: Bool
    ) -> WorkItem? {
        let url = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return WorkItem(
            universityName: university,
            programURL: url,
            majorDisplay: programDisplay,
            degreeType: requirementsDegreeType,
            isMinor: isMinor
        )
    }

    private static func makeWorkItem(
        from major: Major,
        university: String,
        programDisplay: String,
        requirementsDegreeType: String,
        isMinor: Bool
    ) -> WorkItem? {
        makeWorkItem(
            programURL: major.programURL ?? "",
            university: university,
            programDisplay: programDisplay,
            requirementsDegreeType: requirementsDegreeType,
            isMinor: isMinor
        )
    }

    private static func makeWorkItem(
        programDisplay: String,
        university: String,
        degreeLevel: String,
        pickerDegreeType: String?,
        requirementsDegreeType: String,
        isMinor: Bool,
        persistence: CollegePersistence
    ) -> WorkItem? {
        guard let programURL = persistence.resolveProgramURL(
            programDisplay: programDisplay,
            universityName: university,
            degreeLevel: degreeLevel,
            degreeType: pickerDegreeType,
            isMinor: isMinor
        ) else { return nil }

        return WorkItem(
            universityName: university,
            programURL: programURL,
            majorDisplay: programDisplay,
            degreeType: requirementsDegreeType,
            isMinor: isMinor
        )
    }

    /// Settings / explicit user action — scrape requirement pages for the chosen programs only.
    /// Returns the per-program results so callers can render their own in-UI summary banner
    /// (system notifications may be muted by the user).
    @discardableResult
    static func runUserInitiatedRequirementsSync(
        items: [WorkItem],
        persistence: CollegePersistence,
        notifications: AppNotificationCenter,
        force: Bool = false
    ) async -> [CollegePersistence.RequirementsRefreshResult] {
        guard !items.isEmpty else {
            notifications.post(
                kind: .error,
                title: String(
                    localized: "catalog.requirements.no_selection_title",
                    defaultValue: "No programs selected"
                ),
                message: String(
                    localized: "catalog.requirements.no_selection_body",
                    defaultValue: "Choose at least one major or minor with a catalog program link, or set programs in Edit Profile."
                ),
                isDismissible: true,
                autoDismissAfter: 6
            )
            return []
        }

        hydrationTask?.cancel()
        let toastID = notifications.post(
            kind: .progress,
            title: String(
                localized: "catalog.requirements.toast_title",
                defaultValue: "Requirements Sync"
            ),
            message: String(
                format: String(
                    localized: "catalog.requirements.starting_fmt",
                    defaultValue: "Fetching requirements for %d program(s)…"
                ),
                items.count
            ),
            progress: 0.05,
            isDismissible: true
        )

        CatalogMenuBarProgressNotifier.postInProgress(
            fraction: 0.1,
            title: String(
                localized: "catalog.requirements.menubar_starting",
                defaultValue: "Syncing degree requirements…"
            ),
            indeterminate: true
        )

        let results = await runHydration(items: items, persistence: persistence, force: force)

        persistence.bumpProfileRevision()
        NotificationCenter.default.post(
            name: .catalogRequirementsDidUpdate,
            object: nil,
            userInfo: ["programCount": items.count]
        )

        let savedCategories = results.reduce(0) { $0 + $1.savedRowCount }
        let skipped = results.filter(\.skippedDueToFreshCache).count
        let failures = results.compactMap(\.errorMessage)

        if !failures.isEmpty {
            notifications.complete(
                id: toastID,
                kind: .error,
                title: String(
                    localized: "catalog.requirements.failed_title",
                    defaultValue: "Requirements Sync Failed"
                ),
                message: failures.prefix(2).joined(separator: "\n"),
                autoDismissAfter: 10
            )
        } else if savedCategories == 0, skipped == items.count, !force {
            notifications.complete(
                id: toastID,
                kind: .warning,
                title: String(
                    localized: "catalog.requirements.skipped_title",
                    defaultValue: "Requirements Already Fresh"
                ),
                message: String(
                    localized: "catalog.requirements.skipped_body",
                    defaultValue: "No scrape was needed (synced recently). Turn on Force refresh to re-download now."
                ),
                autoDismissAfter: 8
            )
        } else if savedCategories == 0 {
            notifications.complete(
                id: toastID,
                kind: .warning,
                title: String(
                    localized: "catalog.requirements.empty_title",
                    defaultValue: "No Requirements Parsed"
                ),
                message: String(
                    localized: "catalog.requirements.empty_body",
                    defaultValue: "The catalog page returned no requirement categories. Check the program link (skeleton sync) and try Force refresh."
                ),
                autoDismissAfter: 10
            )
        } else {
            notifications.complete(
                id: toastID,
                kind: .success,
                title: String(
                    localized: "catalog.requirements.done_title",
                    defaultValue: "Requirements Sync Complete"
                ),
                message: String(
                    format: String(
                        localized: "catalog.requirements.done_saved_fmt",
                        defaultValue: "Saved %d requirement categories across %d program(s). Open Academics → requirements sidebar to review."
                    ),
                    savedCategories,
                    items.count
                ),
                autoDismissAfter: 8
            )
        }

        CatalogMenuBarProgressNotifier.postSucceeded(
            title: String(
                format: String(
                    localized: "catalog.requirements.menubar_done_fmt",
                    defaultValue: "Requirements synced for %d program(s)."
                ),
                items.count
            )
        )

        return results
    }

    /// Queue hydration for every academic profile that has a primary major, grouped by school (one concurrent lane per university).
    static func scheduleHydrationForAllProfiles(
        persistence: CollegePersistence,
        profiles: [AcademicProfile],
        force: Bool = false
    ) {
        let items = workItems(from: profiles, persistence: persistence)
        guard !items.isEmpty else { return }

        hydrationTask?.cancel()
        hydrationTask = Task {
            _ = await runHydration(items: items, persistence: persistence, force: force)
            persistence.bumpProfileRevision()
            NotificationCenter.default.post(name: .catalogRequirementsDidUpdate, object: nil)
        }
    }

    /// After the user picks a primary major on one degree, hydrate that program and refresh other schools in parallel.
    static func scheduleHydrationAfterPrimaryMajorSelection(
        persistence: CollegePersistence,
        profiles: [AcademicProfile],
        triggerProfileID: UUID?
    ) {
        scheduleHydrationForAllProfiles(persistence: persistence, profiles: profiles, force: false)
    }

    static func workItems(
        from profiles: [AcademicProfile],
        persistence: CollegePersistence
    ) -> [WorkItem] {
        selectablePrograms(
            profiles: profiles,
            universityNames: profiles.compactMap { p in
                let n = p.effectiveUniversityName(
                    among: profiles,
                    fallbackCollege: persistence.profile?.collegeName
                )
                return n.isEmpty ? nil : n
            },
            persistence: persistence,
            fallbackCollege: persistence.profile?.collegeName
        ).compactMap(\.syncWorkItem)
    }

    static func runHydration(
        items: [WorkItem],
        persistence: CollegePersistence,
        force: Bool
    ) async -> [CollegePersistence.RequirementsRefreshResult] {
        let byUniversity = Dictionary(grouping: items, by: \.universityName)
        let lanes = byUniversity.values.map { universityItems in
            Task {
                await hydrateLaneOnMainActor(
                    items: universityItems,
                    persistence: persistence,
                    force: force
                )
            }
        }
        var all: [CollegePersistence.RequirementsRefreshResult] = []
        all.reserveCapacity(items.count)
        for lane in lanes {
            all.append(contentsOf: await lane.value)
        }
        return all
    }

    @MainActor
    private static func hydrateLaneOnMainActor(
        items: [WorkItem],
        persistence: CollegePersistence,
        force: Bool
    ) async -> [CollegePersistence.RequirementsRefreshResult] {
        var results: [CollegePersistence.RequirementsRefreshResult] = []
        results.reserveCapacity(items.count)
        for item in items {
            if Task.isCancelled { return results }
            let result = await persistence.refreshProgramRequirementsForCatalogPick(
                programURL: item.programURL,
                major: item.majorDisplay,
                degreeType: item.degreeType,
                universityName: item.universityName,
                force: force
            )
            results.append(result)
        }
        return results
    }
}
