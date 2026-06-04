// AcademicProfileEditFields.swift
// Feature: Profile
// Purpose: Profile module — AcademicProfileEditFields.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import SwiftData

/// Per-degree editor: institution, program, details, contact, and advisor — scoped to one `AcademicProfile`.
struct AcademicProfileEditFields: View {
    @Bindable var academicProfile: AcademicProfile

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    private var menuBarCatalogStatus: CollegeMenuBarStatusModel { CollegeMenuBarStatusModel.shared }

    private let githubService = GitHubDataService()

    @State private var catalogScrapeTask: Task<Void, Never>?
    @State private var selectedUniversity = ""
    @State private var degreeLevel = ""
    @State private var availableDegreeLevels: [String] = []
    @State private var degreeType = ""
    @State private var status = AcademicProfileStatus.active.rawValue
    @State private var selectedMajors: [String] = [""]
    @State private var selectedMinors: [String] = []
    @State private var advisorName = ""
    @State private var universityEmail = ""
    @State private var personalPhone = ""
    @State private var permanentAddress = ""
    @State private var studentId = ""
    @State private var startedAt = Date()
    @State private var completedAt = Date()
    @State private var hasStartedAt = false
    @State private var hasCompletedAt = false

    @State private var catalogUniversities: [String] = []
    @State private var availableDegreeTypes: [String] = []
    @State private var availableMajors: [String] = []
    @State private var availableMajorSections: [ProfileEditMajorSection] = []
    @State private var availableMinors: [String] = []
    @State private var degreeTypeNeedsAttention = false

    private let maxProgramSelections = 8

    private var showsMinorPrograms: Bool {
        DegreeConfiguration.isUndergraduate(degreeLevel)
    }

    private var catalogProgramIndexingMessage: String? {
        guard case .inProgress = menuBarCatalogStatus.catalog else { return nil }
        let university = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return nil }
        return String(
            localized: "catalog.capability.program_picker_indexing",
            defaultValue: "Program list is still indexing — watch the menu bar for progress."
        )
    }

    var body: some View {
        Group {
            academicProfileSection
            degreeSection
            programSection
            detailsSection
            contactSection
            advisorSection
        }
        .onAppear {
            loadFromEntity()
            refreshUniversityOptionsFromManifest()
        }
        .onChange(of: academicProfile.id) { _, _ in
            loadFromEntity()
        }
        .onChange(of: menuBarCatalogStatus.catalog) { _, _ in
            refreshDegreeLevelOptions()
            refreshDegreeTypes()
            refreshProgramOptions()
        }
        .onDisappear {
            catalogScrapeTask?.cancel()
            persistToEntity()
        }
    }

    // MARK: - Sections

    private var academicProfileSection: some View {
        Section {
            if catalogUniversities.isEmpty {
                TextField(
                    String(localized: "profile.edit.field.university"),
                    text: $selectedUniversity,
                    prompt: Text(String(localized: "profile.edit.placeholder.not_specified"))
                )
                .onChange(of: selectedUniversity) { _, _ in
                    applyUniversityChange(resetPrograms: true)
                }
            } else {
                Picker(String(localized: "profile.edit.field.university"), selection: $selectedUniversity) {
                    Text(String(localized: "profile.edit.picker.select")).tag("")
                    ForEach(catalogUniversities, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: selectedUniversity) { _, _ in
                    applyUniversityChange(resetPrograms: true)
                }
            }
        } header: {
            Text(String(localized: "academic.profile.section.institution"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "academic.profile.section.institution.footer"))
                catalogImportStatusFooter
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var catalogImportStatusFooter: some View {
        let university = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        let programCount = university.isEmpty ? 0 : collegePersistence.catalogProgramCount(for: university)

        switch menuBarCatalogStatus.catalog {
        case .idle:
            if programCount == 0, !university.isEmpty {
                Label(
                    String(
                        localized: "academic.profile.catalog_programs_missing",
                        defaultValue: "No programs imported yet. Change school or run catalog sync from Settings."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        case .inProgress:
            Label(menuBarCatalogStatus.statusLine, systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .succeeded(let summary):
            if programCount == 0 {
                Label(
                    String(
                        localized: "academic.profile.catalog_policies_only",
                        defaultValue: "Catalog policies synced, but no programs were imported. Try Settings → Sync catalog now."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            } else {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var degreeSection: some View {
        Section {
            if selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                readOnlyLabeledContent(
                    String(localized: "profile.edit.field.degree_level"),
                    value: nil,
                    emptyPlaceholder: String(localized: "academic.profile.select_school_first")
                )
            } else if availableDegreeLevels.isEmpty {
                readOnlyLabeledContent(
                    String(localized: "profile.edit.field.degree_level"),
                    value: nil,
                    emptyPlaceholder: String(localized: "academic.profile.select_degree_level_catalog")
                )
            } else {
                Picker(String(localized: "profile.edit.field.degree_level"), selection: $degreeLevel) {
                    Text(String(localized: "profile.edit.picker.select")).tag("")
                    ForEach(availableDegreeLevels, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .onChange(of: degreeLevel) { _, _ in
                    applyDegreeLevelChange()
                }
            }

            if selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                readOnlyLabeledContent(
                    String(localized: "profile.edit.field.degree_type"),
                    value: nil,
                    emptyPlaceholder: String(localized: "academic.profile.select_school_first")
                )
            } else if degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                readOnlyLabeledContent(
                    String(localized: "profile.edit.field.degree_type"),
                    value: nil,
                    emptyPlaceholder: String(localized: "academic.profile.select_degree_level_first")
                )
            } else if availableDegreeTypes.isEmpty {
                TextField(
                    String(localized: "profile.edit.field.degree_type"),
                    text: $degreeType,
                    prompt: Text(String(localized: "profile.edit.placeholder.not_specified"))
                )
            } else {
                if degreeTypeNeedsAttention {
                    Text(String(
                        localized: "academic.profile.degree_type.select_hint",
                        defaultValue: "Select a degree type for your declared program(s)."
                    ))
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                Picker(String(localized: "profile.edit.field.degree_type"), selection: $degreeType) {
                    Text(String(localized: "profile.edit.picker.select")).tag("")
                    ForEach(availableDegreeTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .onChange(of: degreeType) { _, _ in
                    degreeTypeNeedsAttention = false
                    refreshProgramOptions()
                }
            }
        } header: {
            Text(String(localized: "academic.profile.section.degree"))
        }
    }

    private var programSection: some View {
        Section {
            readOnlyLabeledContent(
                String(localized: "profile.edit.field.department"),
                value: resolvedDepartmentDisplay
            )

            if selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                readOnlyLabeledContent(
                    String(localized: "profile.edit.field.major"),
                    value: nil,
                    emptyPlaceholder: String(localized: "academic.profile.select_school_first")
                )
            } else if degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                readOnlyLabeledContent(
                    String(localized: "profile.edit.field.major"),
                    value: nil,
                    emptyPlaceholder: String(localized: "academic.profile.select_degree_level_first")
                )
            } else {
                ForEach(selectedMajors.indices, id: \.self) { index in
                    majorPickerRow(at: index)
                }

                ProgramListControls(
                    canAdd: selectedMajors.count < maxProgramSelections,
                    canRemove: selectedMajors.count > 1,
                    addLabel: selectedMajors.count == 1
                        ? String(localized: "profile.edit.program.add_major", defaultValue: "Add major")
                        : nil,
                    onAdd: { selectedMajors.append("") },
                    onRemove: { if selectedMajors.count > 1 { selectedMajors.removeLast() } }
                )

                if availableMajors.isEmpty && availableMajorSections.isEmpty {
                    if let reason = catalogProgramIndexingMessage {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(
                            localized: "academic.profile.no_majors_hint",
                            defaultValue: "No majors in the catalog for this level yet. Clear degree type, change level, or sync the catalog from Settings."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if showsMinorPrograms {
                    if selectedMinors.isEmpty {
                        ProgramListControls(
                            canAdd: true,
                            canRemove: false,
                            addLabel: String(localized: "profile.edit.program.add_minor"),
                            onAdd: { selectedMinors.append("") },
                            onRemove: {}
                        )
                    } else {
                        ForEach(selectedMinors.indices, id: \.self) { index in
                            minorPickerRow(at: index)
                        }
                        ProgramListControls(
                            canAdd: selectedMinors.count < maxProgramSelections,
                            canRemove: true,
                            onAdd: { selectedMinors.append("") },
                            onRemove: { if !selectedMinors.isEmpty { selectedMinors.removeLast() } }
                        )
                    }
                }
            }

            readOnlyLabeledContent(
                String(localized: "profile.edit.field.class_standing"),
                value: academicProfile.classStanding
            )
            readOnlyLabeledContent(
                String(localized: "profile.edit.field.expected_graduation"),
                value: academicProfile.expectedGraduation,
                emptyPlaceholder: String(localized: "profile.edit.placeholder.select_date")
            )
        } header: {
            Text(String(localized: "profile.edit.section.academic"))
        }
    }

    private var detailsSection: some View {
        Section {
            Picker(String(localized: "academic.profile.field.status"), selection: $status) {
                ForEach(AcademicProfileStatus.allCases) { item in
                    Text(item.localizedTitle).tag(item.rawValue)
                }
            }

            Toggle(String(localized: "academic.profile.field.started"), isOn: $hasStartedAt)
            if hasStartedAt {
                DatePicker(
                    String(localized: "academic.profile.field.started_date"),
                    selection: $startedAt,
                    displayedComponents: .date
                )
            }

            if status != AcademicProfileStatus.active.rawValue {
                Toggle(String(localized: "academic.profile.field.completed"), isOn: $hasCompletedAt)
                if hasCompletedAt {
                    DatePicker(
                        String(localized: "academic.profile.field.completed_date"),
                        selection: $completedAt,
                        displayedComponents: .date
                    )
                }
            }
        } header: {
            Text(String(localized: "academic.profile.section.details"))
        }
    }

    private var contactSection: some View {
        Section {
            TextField(
                String(localized: "profile.edit.field.university_email"),
                text: $universityEmail,
                prompt: Text(String(localized: "profile.edit.placeholder.not_specified"))
            )
            .textContentType(.emailAddress)

            TextField(
                String(localized: "profile.edit.field.phone"),
                text: $personalPhone,
                prompt: Text(String(localized: "profile.edit.placeholder.not_specified"))
            )
            .textContentType(.telephoneNumber)

            TextField(
                String(localized: "profile.edit.field.address"),
                text: $permanentAddress,
                prompt: Text(String(localized: "profile.edit.placeholder.not_specified")),
                axis: .vertical
            )
            .lineLimit(2...4)
        } header: {
            Text(String(localized: "profile.edit.section.contact"))
        }
    }

    private var advisorSection: some View {
        Section {
            TextField(
                String(localized: "profile.edit.field.advisor"),
                text: $advisorName,
                prompt: Text(String(localized: "profile.edit.placeholder.not_specified"))
            )
            TextField(
                String(localized: "profile.edit.field.student_id"),
                text: $studentId,
                prompt: Text(String(localized: "profile.edit.placeholder.not_specified"))
            )
        } header: {
            Text(String(localized: "profile.edit.section.advisor"))
        }
    }

    // MARK: - Persistence

    func persistToEntity() {
        let trimmedUniversity = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        academicProfile.collegeName = trimmedUniversity.isEmpty ? nil : trimmedUniversity
        let trimmedLevel = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        academicProfile.degreeLevel = trimmedLevel.isEmpty ? nil : DegreeConfiguration.canonicalLevel(trimmedLevel)
        academicProfile.status = status
        academicProfile.advisorName = advisorName.nilIfEmptyEdit
        academicProfile.universityEmail = universityEmail.nilIfEmptyEdit
        academicProfile.personalPhone = personalPhone.nilIfEmptyEdit
        academicProfile.permanentAddress = permanentAddress.nilIfEmptyEdit
        academicProfile.studentId = studentId.nilIfEmptyEdit
        academicProfile.startedAt = hasStartedAt ? startedAt : nil
        academicProfile.completedAt = hasCompletedAt ? completedAt : nil
        academicProfile.isActive = status == AcademicProfileStatus.active.rawValue

        let validMajors = normalizedProgramList(from: selectedMajors)
        let validMinors = DegreeConfiguration.isUndergraduate(degreeLevel)
            ? normalizedProgramList(from: selectedMinors)
            : []
        AcademicProfileProgramLists.syncToProfile(majors: validMajors, minors: validMinors, profile: academicProfile)

        let pickerType = degreeType.nilIfEmptyEdit ?? ""
        if !pickerType.isEmpty {
            let inferred = DeclaredProgramDegreeMetadata.infer(fromProgramDisplays: validMajors)
            if inferred == nil,
               let canonical = DegreeTypeNormalizer.normalize(pickerType) {
                academicProfile.degreeType = canonical.fullLabel
                academicProfile.degreeLevel = canonical.degreeLevel
            } else if inferred == nil {
                academicProfile.degreeType = pickerType
            }
        }

        academicProfile.department = resolvedDepartmentForPrimaryMajor()
        degreeTypeNeedsAttention = (academicProfile.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !validMajors.isEmpty

        if let plan = academicProfile.plan {
            plan.type = academicProfile.degreeType ?? plan.type
            plan.major = validMajors.first
            plan.minor = validMinors.first
        }

        collegePersistence.save()
    }

    private func loadFromEntity() {
        reloadUniversityPickerNames(manifestSchools: githubService.loadResolvedSchoolsList())
        selectedUniversity = academicProfile.collegeName ?? ""

        degreeLevel = academicProfile.degreeLevel ?? ""
        degreeType = academicProfile.degreeType ?? ""
        degreeTypeNeedsAttention = degreeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedMajors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.isEmpty
        status = academicProfile.status
        advisorName = academicProfile.advisorName ?? ""
        universityEmail = academicProfile.universityEmail ?? ""
        personalPhone = academicProfile.personalPhone ?? ""
        permanentAddress = academicProfile.permanentAddress ?? ""
        studentId = academicProfile.studentId ?? ""
        hasStartedAt = academicProfile.startedAt != nil
        startedAt = academicProfile.startedAt ?? Date()
        hasCompletedAt = academicProfile.completedAt != nil
        completedAt = academicProfile.completedAt ?? Date()

        let majorList = AcademicProfileProgramLists.majors(from: academicProfile)
        selectedMajors = majorList.isEmpty ? [""] : majorList
        selectedMinors = AcademicProfileProgramLists.minors(from: academicProfile)
        if !DegreeConfiguration.isUndergraduate(degreeLevel) {
            selectedMinors = []
        }

        refreshDegreeLevelOptions()
        refreshDegreeTypes()
        refreshProgramOptions()
        syncDepartmentFromPrimaryMajor()
        scheduleProgramRequirementsHydrationIfNeeded()
    }

    private func reloadUniversityPickerNames(manifestSchools: [SchoolManifest]) {
        catalogUniversities = SchoolManifestSelection.universityPickerNames(
            manifests: manifestSchools,
            importedCatalogNames: collegePersistence.fetchCatalogUniversityNames(),
            preserving: academicProfile.collegeName
        )
    }

    private func refreshUniversityOptionsFromManifest() {
        reloadUniversityPickerNames(manifestSchools: githubService.loadResolvedSchoolsList())

        Task {
            do {
                let schools = try await githubService.refreshResolvedSchoolsList()
                await MainActor.run {
                    reloadUniversityPickerNames(manifestSchools: schools)
                }
            } catch {
                // Keep bundled + cached names when offline.
            }
        }
    }

    private func applyUniversityChange(resetPrograms: Bool) {
        academicProfile.collegeName = selectedUniversity.nilIfEmptyEdit
        if resetPrograms {
            selectedMajors = [""]
            selectedMinors = []
            degreeLevel = ""
            degreeType = ""
        }
        refreshDegreeLevelOptions()
        copyDegreeFieldsFromSiblingWithSameUniversityIfNeeded()
        refreshDegreeTypes()
        refreshProgramOptions()
        scheduleCatalogSkeletonScrapeIfNeeded()
    }

    /// When two degrees share the same institution, reuse the sibling's level/type (never cross-school).
    private func copyDegreeFieldsFromSiblingWithSameUniversityIfNeeded() {
        let university = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return }
        guard degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for sibling in AcademicProfileReadBridge.entities(collegePersistence: collegePersistence)
        where sibling.objectID != academicProfile.objectID {
            let siblingUniversity = sibling.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !siblingUniversity.isEmpty,
                  siblingUniversity.caseInsensitiveCompare(university) == .orderedSame
            else { continue }

            if let siblingLevel = sibling.degreeLevel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !siblingLevel.isEmpty {
                degreeLevel = siblingLevel
                degreeType = sibling.degreeType ?? ""
            }
            break
        }
    }

    private func refreshDegreeLevelOptions() {
        let university = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else {
            availableDegreeLevels = []
            return
        }

        guard CatalogAvailability.hasUniversityCatalog(name: university) else {
            availableDegreeLevels = []
            return
        }

        let fromPrograms = collegePersistence.fetchCatalogDegreeLevels(for: university)
        if !fromPrograms.isEmpty {
            availableDegreeLevels = fromPrograms
            return
        }

        let fromDepartments = DegreeConfiguration.allLevels.filter { level in
            !collegePersistence.fetchDepartments(for: university, degreeLevel: level).isEmpty
        }
        if !fromDepartments.isEmpty {
            availableDegreeLevels = fromDepartments
            return
        }

        if let current = academicProfile.degreeLevel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty {
            availableDegreeLevels = [DegreeConfiguration.canonicalLevel(current)]
        } else {
            availableDegreeLevels = DegreeConfiguration.allLevels
        }
    }

    /// Program-index scrape (same skeleton path as onboarding / UB) for scraper-backed manifest schools.
    private func scheduleCatalogSkeletonScrapeIfNeeded() {
        catalogScrapeTask?.cancel()

        let trimmed = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        catalogScrapeTask = Task {
            let manifest: SchoolManifest
            do {
                manifest = try await CatalogBackgroundSyncRunner.resolveSchoolManifest(
                    named: trimmed,
                    githubService: githubService
                )
            } catch {
                await MainActor.run {
                    CatalogMenuBarProgressNotifier.postFailed(message: error.localizedDescription)
                }
                return
            }
            guard SchoolManifestSelection.isScraperBacked(manifest) else { return }

            let canonical = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { return }

            if canonical.caseInsensitiveCompare(trimmed) != .orderedSame {
                await MainActor.run {
                    selectedUniversity = canonical
                    academicProfile.collegeName = canonical
                }
            }

            let hasPrograms = collegePersistence.catalogProgramCount(for: canonical) > 0
            if hasPrograms, !collegePersistence.fetchCatalogDegreeLevels(for: canonical).isEmpty {
                await MainActor.run {
                    refreshDegreeLevelOptions()
                    refreshDegreeTypes()
                    refreshProgramOptions()
                }
                return
            }

            await CatalogBackgroundSyncRunner.runUserInitiatedCatalogSync(
                schoolName: canonical,
                collegePersistence: collegePersistence,
                notifications: appNotifications,
                depth: .light
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                let refreshed = githubService.loadResolvedSchoolsList()
                reloadUniversityPickerNames(manifestSchools: refreshed)
                refreshDegreeLevelOptions()
                refreshDegreeTypes()
                refreshProgramOptions()
            }
        }
    }

    private func applyDegreeLevelChange() {
        let trimmedLevel = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLevel.isEmpty {
            degreeType = ""
            availableDegreeTypes = []
            selectedMinors = []
            refreshProgramOptions()
            return
        }
        if !showsMinorPrograms {
            selectedMinors = []
        }
        refreshDegreeTypes()
        if !degreeType.isEmpty, !availableDegreeTypes.contains(degreeType) {
            degreeType = preferredDegreeTypeSelection(from: availableDegreeTypes)
        }
        refreshProgramOptions()
    }

    private func refreshDegreeTypes() {
        let trimmedLevel = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLevel.isEmpty else {
            availableDegreeTypes = []
            return
        }
        availableDegreeTypes = collegePersistence.resolvedDegreeTypeOptions(
            for: selectedUniversity,
            degreeLevel: trimmedLevel,
            currentSelection: degreeType
        )
        if !degreeType.isEmpty, !availableDegreeTypes.contains(degreeType) {
            degreeType = preferredDegreeTypeSelection(from: availableDegreeTypes)
        }
    }

    private func preferredDegreeTypeSelection(from options: [String]) -> String {
        options.first(where: { !ProfileEditProgramMenuData.isNonMajorDegreeType($0) }) ?? options.first ?? ""
    }

    private func refreshProgramOptions() {
        let university = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        let level = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty, !level.isEmpty else {
            availableMajors = []
            availableMajorSections = []
            availableMinors = []
            return
        }
        let choices = ProfileEditProgramMenuData.programChoices(
            collegePersistence: collegePersistence,
            universityName: university,
            degreeLevelForQueries: level,
            degreeTypeForQueries: degreeType.nilIfEmptyEdit
        )
        availableMajors = choices.majors
        availableMajorSections = choices.majorSections
        availableMinors = choices.minors
    }

    @ViewBuilder
    private func readOnlyLabeledContent(
        _ label: String,
        value: String?,
        emptyPlaceholder: String = String(localized: "profile.edit.placeholder.not_specified")
    ) -> some View {
        LabeledContent(label) {
            Text(readOnlyDisplayText(value, emptyPlaceholder: emptyPlaceholder))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func majorPickerRow(at index: Int) -> some View {
        let label = index == 0
            ? String(localized: "profile.edit.field.major")
            : String(localized: "profile.edit.field.additional_major")

        if availableMajors.isEmpty && availableMajorSections.isEmpty {
            TextField(
                label,
                text: majorBinding(at: index),
                prompt: Text(String(localized: "profile.edit.placeholder.select_major"))
            )
        } else {
            Picker(label, selection: majorBinding(at: index)) {
                Text(String(localized: "profile.edit.placeholder.select_major")).tag("")
                if !availableMajorSections.isEmpty {
                    ForEach(Array(availableMajorSections.enumerated()), id: \.element.id) { sectionIndex, section in
                        Section(section.title) {
                            ForEach(
                                ProfileEditProgramMenuData.majorsForPickerSection(
                                    section: section,
                                    sectionIndex: sectionIndex,
                                    allSections: availableMajorSections,
                                    current: selectedMajors[index]
                                ),
                                id: \.self
                            ) { major in
                                Text(major).tag(major)
                            }
                        }
                    }
                } else {
                    ForEach(
                        ProfileEditProgramMenuData.optionsPreservingCurrentSelection(
                            base: availableMajors,
                            current: selectedMajors[index]
                        ),
                        id: \.self
                    ) { major in
                        Text(major).tag(major)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func minorPickerRow(at index: Int) -> some View {
        let label = index == 0
            ? String(localized: "profile.edit.field.minor")
            : String(localized: "profile.edit.field.additional_minor")

        if availableMinors.isEmpty {
            TextField(
                label,
                text: minorBinding(at: index),
                prompt: Text(String(localized: "profile.edit.placeholder.select_minor"))
            )
        } else {
            Picker(label, selection: minorBinding(at: index)) {
                Text(String(localized: "profile.edit.placeholder.select_minor")).tag("")
                ForEach(
                    ProfileEditProgramMenuData.optionsPreservingCurrentSelection(
                        base: availableMinors,
                        current: selectedMinors[index]
                    ),
                    id: \.self
                ) { minor in
                    Text(minor).tag(minor)
                }
            }
        }
    }

    private var resolvedDepartmentDisplay: String? {
        resolvedDepartmentForPrimaryMajor() ?? academicProfile.department
    }

    private func resolvedDepartmentForPrimaryMajor() -> String? {
        let primary = selectedMajors.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !primary.isEmpty else { return nil }

        if let fromSection = ProfileEditProgramMenuData.departmentBucket(
            forMajor: primary,
            sections: availableMajorSections
        ) {
            return fromSection
        }

        let university = selectedUniversity.trimmingCharacters(in: .whitespacesAndNewlines)
        let level = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty, !level.isEmpty else { return nil }
        return collegePersistence.resolvedCatalogDepartment(
            forMajorDisplay: primary,
            universityName: university,
            degreeLevel: level,
            degreeType: degreeType.nilIfEmptyEdit
        )
    }

    private func syncDepartmentFromPrimaryMajor() {
        academicProfile.department = resolvedDepartmentForPrimaryMajor()
    }

    private func majorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { selectedMajors[index] },
            set: { newValue in
                selectedMajors[index] = newValue
                if index == 0 {
                    syncDepartmentFromPrimaryMajor()
                    scheduleProgramRequirementsHydrationIfNeeded()
                }
            }
        )
    }

    private func scheduleProgramRequirementsHydrationIfNeeded() {
        let primary = selectedMajors.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !primary.isEmpty else { return }

        CatalogProgramRequirementsHydrator.scheduleHydrationAfterPrimaryMajorSelection(
            persistence: collegePersistence,
            profiles: AcademicProfileReadBridge.entities(collegePersistence: collegePersistence),
            triggerProfileID: academicProfile.id
        )
    }

    private func minorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { selectedMinors[index] },
            set: { selectedMinors[index] = $0 }
        )
    }

    private func readOnlyDisplayText(_ value: String?, emptyPlaceholder: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? emptyPlaceholder : trimmed
    }

    private func normalizedProgramList(from raw: [String]) -> [String] {
        var out: [String] = []
        for value in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if out.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) { continue }
            out.append(trimmed)
        }
        return out
    }
}

private extension String {
    var nilIfEmptyEdit: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
