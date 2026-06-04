// SettingsWorkdayPanel.swift
// Feature: Settings
// Purpose: Settings module — SettingsJobBoardsPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct SettingsJobBoardsPanel: View {
    @ObservedObject private var coordinator = WorkdayJobBoardSyncCoordinator.shared

    @AppStorage(WorkdayRefreshScheduler.refreshIntervalStorageKey)
    private var refreshIntervalSeconds: Int = WorkdayRefreshIntervalOption.twelveHours.rawValue

    @State private var newDisplayName = ""
    @State private var newCareersURL = ""
    @State private var newSlug = ""
    @State private var selectedPlatform: JobBoardPlatform = .workday
    @State private var urlValidationMessage: String?
    @State private var urlValidationOK = false
    @State private var isScrapingAll = false
    @State private var isProbingPlatform = false
    @State private var platformProbeTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Automatic refresh", selection: $refreshIntervalSeconds) {
                    ForEach(WorkdayRefreshIntervalOption.allCases) { option in
                        Text(option.displayName).tag(option.storageSeconds)
                    }
                }
                .onChange(of: refreshIntervalSeconds) { _, _ in
                    WorkdayRefreshScheduler.shared.reschedule()
                }

                Text("Background refresh is best-effort — macOS may defer scheduled runs to save battery. Last sync times are shown per company.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        isScrapingAll = true
                        await coordinator.scrapeAllEnabledCompanies()
                        isScrapingAll = false
                    }
                } label: {
                    if isScrapingAll || coordinator.uiState.isAnyScrapeInFlight {
                        Label("Scraping…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Scrape all now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(WorkdayCompaniesStore.shared.enabledCount == 0 || coordinator.uiState.isAnyScrapeInFlight)
            }

            Section("Companies") {
                if WorkdayCompaniesStore.shared.companies.isEmpty {
                    Text("Add career board URLs (Workday, Greenhouse, Lever, Oracle, iCIMS, Talemetry) to scrape openings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(WorkdayCompaniesStore.shared.companies) { company in
                        WorkdayCompanySettingsRow(company: company, coordinator: coordinator)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            WorkdayCompaniesStore.shared.removeCompany(id: WorkdayCompaniesStore.shared.companies[index].id)
                        }
                        coordinator.rebuildIdleUIState()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    workdayLabeledField("Company name", text: $newDisplayName)
                    workdayLabeledField("Careers URL", text: $newCareersURL)
                        .onChange(of: newCareersURL) { _, _ in validateNewURL() }
                    workdayLabeledField("Slug (optional)", text: $newSlug, font: .caption)

                    HStack(spacing: 8) {
                        Text("Platform")
                            .font(.caption)
                        Picker("Platform", selection: $selectedPlatform) {
                            ForEach(JobBoardPlatform.allCases) { platform in
                                Label(platform.displayName, systemImage: platform.icon).tag(platform)
                            }
                        }
                        .labelsHidden()
                        if isProbingPlatform {
                            ProgressView().controlSize(.small)
                        } else {
                            JobBoardPlatformBadge(platform: selectedPlatform)
                        }
                    }

                    if selectedPlatform.usesHTMLScraping {
                        Text("No public API — College scrapes HTML; completeness may vary by site.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let msg = urlValidationMessage {
                        Label(msg, systemImage: urlValidationOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(urlValidationOK ? .green : .orange)
                    }

                    Button("Add company") {
                        WorkdayCompaniesStore.shared.addCompany(
                            displayName: newDisplayName,
                            careersURL: newCareersURL,
                            slug: newSlug.isEmpty ? nil : newSlug,
                            platform: selectedPlatform
                        )
                        newDisplayName = ""
                        newCareersURL = ""
                        newSlug = ""
                        urlValidationMessage = nil
                        coordinator.rebuildIdleUIState()
                    }
                    .disabled(newCareersURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !urlValidationOK)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            coordinator.rebuildIdleUIState()
        }
    }

    private func validateNewURL() {
        let url = newCareersURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            urlValidationMessage = nil
            urlValidationOK = false
            return
        }
        if let detected = JobBoardPlatformDetector.detect(from: url) {
            selectedPlatform = detected
        }
        let result = JobBoardPlatformDetector.validationMessage(for: url, platform: selectedPlatform)
        urlValidationMessage = result.message
        urlValidationOK = result.ok

        if JobBoardPlatformDetector.detect(from: url) == nil {
            platformProbeTask?.cancel()
            isProbingPlatform = true
            platformProbeTask = Task {
                if let probed = await JobBoardPlatformDetector.probe(urlString: url) {
                    guard !Task.isCancelled else { return }
                    selectedPlatform = probed
                    let r = JobBoardPlatformDetector.validationMessage(for: url, platform: probed)
                    urlValidationMessage = r.message
                    urlValidationOK = r.ok
                }
                guard !Task.isCancelled else { return }
                isProbingPlatform = false
            }
        } else {
            platformProbeTask?.cancel()
            platformProbeTask = nil
            isProbingPlatform = false
        }
    }
}

struct JobBoardPlatformBadge: View {
    let platform: JobBoardPlatform

    var body: some View {
        Label(platform.displayName, systemImage: platform.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

typealias SettingsWorkdayPanel = SettingsJobBoardsPanel

private struct WorkdayCompanySettingsRow: View {
    let company: WorkdayCompanyConfigEntry
    @ObservedObject var coordinator: WorkdayJobBoardSyncCoordinator

    @State private var displayName: String = ""
    @State private var careersURL: String = ""
    @State private var slug: String = ""
    @State private var enabled: Bool = true
    @State private var platform: JobBoardPlatform = .workday
    @State private var apiHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(company.displayName)
                    .font(.headline)
                JobBoardPlatformBadge(platform: platform)
            }
            Toggle("Enabled", isOn: $enabled)
                .onChange(of: enabled) { _, value in
                    WorkdayCompaniesStore.shared.setEnabled(id: company.id, enabled: value)
                    coordinator.rebuildIdleUIState()
                }

            workdayLabeledField("Display name", text: $displayName, onSubmit: commit)
            workdayLabeledField("Careers URL", text: $careersURL, onSubmit: commit)
                .onChange(of: careersURL) { _, _ in validateURL() }
            workdayLabeledField("Slug", text: $slug, onSubmit: commit)

            if let apiHint {
                Text(apiHint)
                    .font(.caption2)
                    .foregroundStyle(apiHint.hasPrefix("API") ? Color.green : Color.orange)
            }

            statusLine

            Picker("Platform", selection: $platform) {
                ForEach(JobBoardPlatform.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            Button("Scrape now") {
                var updated = company
                updated.displayName = displayName
                updated.careersURL = careersURL
                updated.slug = slug
                updated.enabled = enabled
                updated.platform = platform
                WorkdayCompaniesStore.shared.updateCompany(updated)
                Task { await coordinator.scrapeCompany(updated) }
            }
            .disabled(!enabled)
        }
        .onAppear {
            displayName = company.displayName
            careersURL = company.careersURL
            slug = company.slug
            enabled = company.enabled
            platform = company.platform
            validateURL()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let slug = company.normalizedSlug
        if let state = coordinator.uiState.companies.first(where: { $0.slug == slug }) {
            switch state.status {
            case .idle:
                Text("Not scraped yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .scraping(let progress):
                HStack {
                    Label("Scraping…", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if let progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            case .ok(let count, let at):
                Text("Last scraped \(at.formatted(.relative(presentation: .named))) · \(count) jobs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .error(let err, let at):
                Text("\(err.displayMessage) · \(at.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func validateURL() {
        if let detected = JobBoardPlatformDetector.detect(from: careersURL) {
            platform = detected
        }
        let result = JobBoardPlatformDetector.validationMessage(for: careersURL, platform: platform)
        apiHint = result.message
    }

    private func commit() {
        var updated = company
        updated.displayName = displayName
        updated.careersURL = careersURL
        updated.slug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        updated.enabled = enabled
        updated.platform = platform
        WorkdayCompaniesStore.shared.updateCompany(updated)
        coordinator.rebuildIdleUIState()
    }
}

// MARK: - Visible text fields (grouped Form hides default borders on macOS)

@ViewBuilder
private func workdayLabeledField(
    _ label: String,
    text: Binding<String>,
    font: Font = .body,
    onSubmit: (() -> Void)? = nil
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(font)
            .foregroundStyle(.primary)
        Group {
            if let onSubmit {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(font)
                    .onSubmit(onSubmit)
            } else {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(font)
            }
        }
    }
}
