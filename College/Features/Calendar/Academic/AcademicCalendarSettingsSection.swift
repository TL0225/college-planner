// AcademicCalendarSettingsSection.swift
// Feature: Calendar
// Purpose: Settings UI for university academic calendar scraping.

import CollegeCalendar
import SwiftUI

struct AcademicCalendarSettingsSection: View {
    @Environment(AppContainer.self) private var container

    @State private var urlDraft: String = ""
    @State private var configs: [AcademicCalendarConfig] = []
    @State private var isScraping = false
    @State private var errorText: String?
    @State private var forcedMode: AcademicCalendarForcedMode = .auto
    @State private var levelScope: AcademicCalendarLevelScope = .all
    @State private var programAudienceLabel: String = ""
    @State private var activeTermLabel: String = ""
    @State private var showLog = false
    @State private var pendingHubCandidates: [AcademicCalendarSubCalendarCandidate] = []
    @State private var pendingConfig: AcademicCalendarConfig?
    @State private var showHubPicker = false
    @State private var showPreview = false
    @State private var previewEvents: [AcademicCalendarParsedEvent] = []
    @State private var previewChanges: [AcademicCalendarSyncChange] = []
    @State private var isDiscoveringURL = false
    @State private var suggestedDiscoveryURL: String?
    @State private var showAddCollegePicker = false
    @State private var hubPickerNeutral = false

    private var calendarManager: CalendarIntegrationManager { container.calendarManager }

    var body: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_term_dates", defaultValue: "University Term Dates"),
            icon: "graduationcap",
            iconColor: .purple
        ) {
            SRow(
                label: String(
                    localized: "settings.calendar.term_dates_intro",
                    defaultValue: "Import registration deadlines, breaks, and finals by scraping your school's academic calendar webpage."
                )
            )

            rowDivider

            STextFieldRow(
                label: String(localized: "settings.calendar.term_dates_url_label", defaultValue: "School Calendar Page URL"),
                subtitle: suggestedDiscoveryURL == urlDraft && !urlDraft.isEmpty
                    ? String(localized: "settings.calendar.suggested_url", defaultValue: "Suggested URL from your registrar site")
                    : String(
                        localized: "settings.calendar.term_dates_url_sub",
                        defaultValue: "The registrar or academic calendar page on your university website"
                    ),
                placeholder: "https://...",
                text: $urlDraft,
                fieldWidth: 260
            )

            if isDiscoveringURL {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "settings.calendar.discovering", defaultValue: "Finding your school's calendar…"))
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
            }

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.term_dates_import_mode", defaultValue: "Import mode"),
                selection: $forcedMode,
                options: AcademicCalendarForcedMode.allCases,
                optionLabel: { $0.displayName }
            )

            rowDivider

            SRow(
                label: String(localized: "settings.calendar.term_dates_audience", defaultValue: "Calendar audience"),
                subtitle: String(
                    localized: "settings.calendar.term_dates_audience_sub",
                    defaultValue: "Matched from your declared program catalog (undergraduate vs graduate)"
                ),
                value: programAudienceLabel.isEmpty
                    ? String(localized: "settings.calendar.term_dates_audience_unknown", defaultValue: "Set a program in Profile")
                    : programAudienceLabel + (programAudienceDegraded ? " · " + String(localized: "settings.calendar.program_name_only", defaultValue: "Using program name only") : "")
            )

            rowDivider

            SRow(
                label: String(localized: "settings.calendar.term_dates_manual_import", defaultValue: "Manual import"),
                subtitle: String(
                    localized: "settings.calendar.term_dates_manual_import_sub",
                    defaultValue: "Re-run term date import any time using your school URL and program catalog"
                )
            )

            rowDivider

            SRow(
                label: String(localized: "settings.calendar.term_dates_active_term", defaultValue: "Active term"),
                subtitle: String(
                    localized: "settings.calendar.term_dates_active_term_sub",
                    defaultValue: "Imports only dates for the term selected in your planner"
                ),
                value: activeTermLabel.isEmpty
                    ? String(localized: "settings.calendar.term_dates_active_term_unknown", defaultValue: "Not set")
                    : activeTermLabel
            )

            rowDivider

            scrapeControls

            if AcademicCalendarStore.canAddDepartment(for: activeSchoolID) {
                rowDivider
                Button {
                    hubPickerNeutral = true
                    if let cached = AcademicCalendarFingerprintCache.hubCandidates(for: activeSchoolID) {
                        pendingHubCandidates = cached
                        showAddCollegePicker = true
                    } else {
                        Task { await discoverHubCandidatesForAdditionalImport() }
                    }
                } label: {
                    Label(
                        String(localized: "settings.calendar.add_college_calendar", defaultValue: "Add another college calendar"),
                        systemImage: "plus.circle"
                    )
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }

            if let errorText {
                Text(errorText)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
            }

            ForEach(configs) { config in
                rowDivider
                configRow(config)
            }
        }
        .sheet(isPresented: $showHubPicker) {
            AcademicCalendarHubPickerSheet(
                candidates: pendingHubCandidates,
                suggestedURL: suggestedHubURL,
                neutralMode: hubPickerNeutral,
                onSelect: { candidate in
                    showHubPicker = false
                    guard var config = pendingConfig else { return }
                    config.chosenSubCalendarURL = candidate.url
                    config.persistenceTier = .userConfirmed
                    config.departmentKey = AcademicCalendarProgramProfile.departmentKey(from: candidate.label)
                    config.departmentDisplayName = AcademicCalendarProgramProfile.departmentDisplayName(
                        from: candidate.label,
                        schoolName: config.schoolDisplayName
                    )
                    config.configID = AcademicCalendarConfig.makeConfigID(
                        schoolID: config.schoolID,
                        departmentKey: config.departmentKey
                    )
                    Task { await runScrape(config: &config, subURL: candidate.url, writeChanges: false, userConfirmed: true) }
                },
                onCancel: { showHubPicker = false }
            )
        }
        .sheet(isPresented: $showAddCollegePicker) {
            AcademicCalendarHubPickerSheet(
                candidates: pendingHubCandidates,
                suggestedURL: nil,
                neutralMode: true,
                onSelect: { candidate in
                    showAddCollegePicker = false
                    Task {
                        _ = await AcademicCalendarImportCoordinator.importAdditionalDepartment(
                            persistence: container.persistence,
                            calendarManager: calendarManager,
                            hubCandidate: candidate,
                            entryURL: urlDraft
                        )
                        reloadConfigs()
                    }
                },
                onCancel: { showAddCollegePicker = false }
            )
        }
        .sheet(isPresented: $showPreview) {
            AcademicCalendarPreviewSheet(
                events: previewEvents,
                changes: previewChanges,
                isRefreshDiff: false,
                onConfirm: { selected in
                    showPreview = false
                    guard var config = pendingConfig else { return }
                    Task { await confirmImport(config: &config, events: selected) }
                },
                onCancel: { showPreview = false }
            )
        }
        .onAppear {
            reloadConfigs()
            prefillFromManifest()
            refreshProgramAudience()
            refreshActiveTermLabel()
            AcademicCalendarIntegration.syncAllRegistrations(calendarManager: calendarManager)
            Task { await discoverSuggestedURLIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .catalogRequirementsDidUpdate)) { _ in
            refreshProgramAudience()
            if let schoolID = activeSchoolIDIfAvailable() {
                AcademicCalendarFingerprintCache.invalidate(schoolID: schoolID)
            }
        }
    }

    @State private var programAudienceDegraded = false

    private var activeSchoolID: String {
        activeSchoolIDIfAvailable() ?? ""
    }

    private func activeSchoolIDIfAvailable() -> String? {
        guard let name = container.persistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        let schools = SchoolManifestCatalog.bundled()
        let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        return manifest?.id ?? name.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private func refreshProgramAudience() {
        if let profile = AcademicCalendarProgramProfile.resolve(persistence: container.persistence) {
            levelScope = profile.levelScope
            programAudienceDegraded = profile.isDegraded
            var parts: [String] = []
            switch profile.levelScope {
            case .undergrad:
                parts.append(String(localized: "settings.calendar.audience_undergrad", defaultValue: "Undergraduate"))
            case .grad:
                parts.append(String(localized: "settings.calendar.audience_grad", defaultValue: "Graduate"))
            case .all:
                parts.append(String(localized: "settings.calendar.audience_all", defaultValue: "All"))
            }
            if let college = profile.owningCollege, !college.isEmpty {
                parts.append(college)
            } else if let department = profile.owningDepartment, !department.isEmpty {
                parts.append(department)
            }
            if let program = profile.programLabel, !program.isEmpty {
                parts.append(program)
            }
            programAudienceLabel = parts.joined(separator: " · ")
        } else {
            programAudienceLabel = ""
            programAudienceDegraded = false
        }
    }

    private func refreshActiveTermLabel() {
        if let resolved = AcademicCalendarTermScope.resolve(persistence: container.persistence, level: levelScope) {
            activeTermLabel = resolved.label
        } else {
            activeTermLabel = ""
        }
    }

    private var suggestedHubURL: String? {
        let termScope = AcademicCalendarTermScope.resolve(persistence: container.persistence, level: levelScope)
        let profile = AcademicCalendarProgramProfile.resolve(persistence: container.persistence)
        return AcademicCalendarLinkResolver.bestMatch(
            candidates: pendingHubCandidates,
            profile: profile,
            termScope: termScope
        )
    }

    @ViewBuilder
    private var scrapeControls: some View {
        HStack {
            Button {
                Task { await startScrape() }
            } label: {
                Label(
                    isScraping
                        ? String(localized: "settings.calendar.term_dates_scraping", defaultValue: "Importing…")
                        : String(localized: "settings.calendar.term_dates_scrape", defaultValue: "Import Term Dates"),
                    systemImage: "arrow.down.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScraping || urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                    forcedMode = .scrape
                }
            )

            Spacer()

            Button("Refresh All") {
                Task { await AcademicCalendarRefreshService.shared.refreshAll(reason: .manual) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func configRow(_ config: AcademicCalendarConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(config.calendarDisplayName)
                    .font(DesignSystem.Fonts.body(weight: .semibold))
                if let err = config.lastError, !err.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(err)
                }
                Spacer()
                if let last = config.lastSuccessfulAt {
                    Text(last, style: .relative)
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Re-scrape") {
                    var copy = config
                    Task { await runScrape(config: &copy, subURL: nil, writeChanges: true) }
                }
                Button("Reset Removed") {
                    AcademicCalendarStore.clearDeletedKeys(configID: config.configID)
                }
                Button("Remove", role: .destructive) {
                    AcademicCalendarIntegration.removeCalendar(configID: config.configID, calendarManager: calendarManager)
                    reloadConfigs()
                }
            }
            .buttonStyle(.borderless)

            DisclosureGroup("Scrape log", isExpanded: $showLog) {
                ForEach(AcademicCalendarStore.loadScrapeLog(configID: config.configID)) { entry in
                    Text("\(entry.timestamp.formatted()) · \(entry.path.rawValue) · +\(entry.added)/~\(entry.changed)/-\(entry.removed)")
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(.secondary)
                }
            }
            .font(DesignSystem.Fonts.caption1())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var rowDivider: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.5))
            .padding(.horizontal, 18)
    }

    private func prefillFromManifest() {
        guard urlDraft.isEmpty else { return }
        guard let name = container.persistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }
        let schools = SchoolManifestCatalog.bundled()
        if let school = schools.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            urlDraft = school.academicCalendarURL ?? ""
        }
    }

    private func reloadConfigs() {
        configs = AcademicCalendarStore.loadAllConfigs()
    }

    private func startScrape() async {
        let trimmedURL = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let schools = SchoolManifestCatalog.bundled()
        let universityName = container.persistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "My University"
        let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(universityName) == .orderedSame })
        let schoolID = manifest?.id ?? universityName.lowercased().replacingOccurrences(of: " ", with: "_")

        var config = AcademicCalendarStore.config(schoolID: schoolID, departmentKey: AcademicCalendarProgramProfile.resolve(persistence: container.persistence)?.departmentKey ?? AcademicCalendarConfig.universityWideKey)
            ?? AcademicCalendarConfig(
                schoolID: schoolID,
                name: manifest?.name ?? universityName,
                url: trimmedURL,
                chosenSubCalendarURL: nil,
                forcedMode: forcedMode == .auto ? nil : forcedMode,
                timeZoneID: AcademicCalendarTimezone.resolve(manifest: manifest),
                levelScope: levelScope,
                importedScopes: [],
                departmentDisplayName: AcademicCalendarProgramProfile.resolve(persistence: container.persistence)?.departmentDisplayName,
                schoolDisplayName: manifest?.name ?? universityName
            )
        config.url = trimmedURL
        config.forcedMode = forcedMode == .auto ? nil : forcedMode
        config.levelScope = levelScope
        config.timeZoneID = AcademicCalendarTimezone.resolve(manifest: manifest)
        config.importedScopes = buildImportedScopes()

        await runScrape(config: &config, subURL: config.chosenSubCalendarURL, writeChanges: false)
    }

    func importFromProgramCatalog(writeChanges: Bool = false) async {
        refreshProgramAudience()
        if urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prefillFromManifest()
        }
        await startScrape()
    }

    private func runScrape(config: inout AcademicCalendarConfig, subURL: String?, writeChanges: Bool, userConfirmed: Bool = false) async {
        isScraping = true
        errorText = nil
        pendingConfig = config
        let profile = AcademicCalendarProgramProfile.resolve(persistence: container.persistence)
        let output = await AcademicCalendarScrapeService.scrape(
            config: &config,
            reason: .manual,
            calendarManager: calendarManager,
            selectedSubCalendarURL: subURL,
            writeChanges: writeChanges,
            programProfile: profile,
            hubPickerNeutral: hubPickerNeutral,
            userConfirmedURL: userConfirmed
        )
        isScraping = false
        pendingConfig = config
        AcademicCalendarStore.upsertConfig(config)
        reloadConfigs()

        if output.needsHubPicker {
            pendingHubCandidates = output.hubCandidates
            hubPickerNeutral = output.hubPickerNeutral
            showHubPicker = true
            return
        }

        if output.contentUnchanged {
            errorText = String(
                localized: "settings.calendar.term_dates_no_changes",
                defaultValue: "No changes detected."
            )
            return
        }

        if let err = output.result.error ?? config.lastError, !err.isEmpty {
            errorText = err
        }

        if !writeChanges, !output.result.parsedEvents.isEmpty {
            previewEvents = output.result.parsedEvents
            previewChanges = output.result.changes
            showPreview = true
        }
    }

    private func buildImportedScopes() -> [AcademicCalendarImportedScope] {
        AcademicCalendarTermScope.importedScopes(persistence: container.persistence, level: levelScope)
    }

    private func confirmImport(config: inout AcademicCalendarConfig, events: [AcademicCalendarParsedEvent]) async {
        let scrapeID = UUID()
        let scopes = Set(events.map(\.scopeKey))
        _ = await AcademicCalendarUpsertService.reconcile(
            config: config,
            incoming: events,
            scrapeID: scrapeID,
            activeScopeKeys: scopes
        )
        AcademicCalendarIntegration.registerCalendarIfNeeded(config: config, calendarManager: calendarManager)
        AcademicCalendarStore.upsertConfig(config)
        reloadConfigs()
    }

    private func discoverSuggestedURLIfNeeded() async {
        guard urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isDiscoveringURL = true
        defer { isDiscoveringURL = false }
        let discoverer = AcademicCalendarEntryDiscoverer(fetcher: AcademicCalendarFetchPort.shared)
        let schools = SchoolManifestCatalog.bundled()
        let universityName = container.persistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(universityName) == .orderedSame })
        if let discovered = await discoverer.discover(
            manifest: manifest,
            policyMetadata: container.persistence.activeSchoolPolicyMetadata(),
            universityName: universityName
        ) {
            suggestedDiscoveryURL = discovered.url
            urlDraft = discovered.url
        }
    }

    private func discoverHubCandidatesForAdditionalImport() async {
        guard !urlDraft.isEmpty else { return }
        isScraping = true
        defer { isScraping = false }
        do {
            let fetch = try await AcademicCalendarFetchPort.shared.fetch(urlString: urlDraft, etag: nil)
            guard let base = URL(string: urlDraft) else { return }
            let classification = AcademicCalendarPageClassifier.classify(content: fetch.content, baseURL: base, forcedMode: .hub)
            pendingHubCandidates = classification.subCalendars
            if !pendingHubCandidates.isEmpty {
                AcademicCalendarFingerprintCache.storeHubCandidates(schoolID: activeSchoolID, candidates: pendingHubCandidates)
                showAddCollegePicker = true
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

