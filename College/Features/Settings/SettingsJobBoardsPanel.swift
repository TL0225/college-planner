// SettingsJobBoardsPanel.swift
// Feature: Settings
// Purpose: Settings module — SettingsJobBoardsPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct SettingsJobBoardsPanel: View {
    @ObservedObject private var coordinator = JobBoardSyncCoordinator.shared

    @AppStorage(JobBoardRefreshScheduler.refreshIntervalStorageKey)
    private var refreshIntervalSeconds: Int = JobBoardRefreshIntervalOption.twelveHours.rawValue

    @State private var isScrapingAll = false

    private var isAnyScrapeInFlight: Bool {
        isScrapingAll || coordinator.uiState.isAnyScrapeInFlight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            usaJobsCredentialsCard
            refreshCard
            companiesCard
        }
        .onAppear {
            coordinator.rebuildIdleUIState()
        }
    }

    // MARK: - USAJobs API

    private var usaJobsCredentialsCard: some View {
        SettingsUSAJobsCredentialsCard()
    }

    // MARK: - Refresh card

    private var refreshCard: some View {
        SettingsCard(
            title: String(localized: "settings.jobboards.refresh", defaultValue: "Refresh"),
            icon: "arrow.clockwise",
            iconColor: DesignSystem.Colors.info
        ) {
            SPickerRow(
                label: String(localized: "settings.jobboards.automatic_refresh", defaultValue: "Automatic refresh"),
                subtitle: String(
                    localized: "settings.jobboards.automatic_refresh.help",
                    defaultValue: "Background refresh is best-effort — macOS may defer scheduled runs to save battery."
                ),
                selection: Binding(
                    get: { refreshIntervalSeconds },
                    set: { newValue in
                        refreshIntervalSeconds = newValue
                        JobBoardRefreshScheduler.shared.reschedule()
                    }
                ),
                options: JobBoardRefreshIntervalOption.allCases.map(\.storageSeconds),
                optionLabel: { JobBoardRefreshIntervalOption.fromStoredSeconds($0).displayName }
            )

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: String(localized: "settings.jobboards.scrape_all", defaultValue: "Scrape all companies"),
                subtitle: String(
                    localized: "settings.jobboards.scrape_all.help",
                    defaultValue: "Last sync times are shown per company."
                ),
                actionLabel: isAnyScrapeInFlight
                    ? String(localized: "settings.jobboards.scraping", defaultValue: "Scraping…")
                    : String(localized: "settings.jobboards.scrape_now", defaultValue: "Scrape now"),
                isDisabled: JobBoardCompaniesStore.shared.enabledCount == 0 || isAnyScrapeInFlight
            ) {
                Task {
                    isScrapingAll = true
                    await coordinator.scrapeAllEnabledCompanies(force: true)
                    isScrapingAll = false
                }
            }
        }
    }

    // MARK: - Companies card

    private var companiesCard: some View {
        SettingsCard(
            title: String(localized: "settings.jobboards.companies", defaultValue: "Companies"),
            icon: "building.2",
            iconColor: DesignSystem.Colors.primary
        ) {
            if JobBoardCompaniesStore.shared.companies.isEmpty {
                SettingsInfoRow(
                    text: String(
                        localized: "settings.jobboards.companies.empty",
                        defaultValue: "Track companies from Career → Openings to scrape Workday, Greenhouse, Lever, and other boards."
                    )
                )
            } else {
                let companies = JobBoardCompaniesStore.shared.companies
                ForEach(Array(companies.enumerated()), id: \.element.id) { index, company in
                    if index > 0 {
                        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                    }
                    JobBoardCompanySettingsRow(company: company, coordinator: coordinator)
                }
            }
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

// MARK: - Per-company row

private struct JobBoardCompanySettingsRow: View {
    let company: JobBoardCompany
    @ObservedObject var coordinator: JobBoardSyncCoordinator

    @State private var displayName: String = ""
    @State private var careersURL: String = ""
    @State private var slug: String = ""
    @State private var enabled: Bool = true
    @State private var platform: JobBoardPlatform = .workday
    @State private var apiHint: String?
    @State private var clearedJobsMessage: String?

    private var isScraping: Bool {
        coordinator.isScraping(slug: company.normalizedSlug)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            actionsRow

            if let clearedJobsMessage {
                SettingsStatusRow(
                    message: clearedJobsMessage,
                    systemImage: "trash",
                    tint: .secondary
                )
            }

            SAdvancedDisclosure(
                title: String(localized: "settings.jobboards.edit_details", defaultValue: "Edit details")
            ) {
                STextFieldRow(
                    label: String(localized: "settings.jobboards.display_name", defaultValue: "Display name"),
                    text: $displayName,
                    onSubmit: commit
                )
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                STextFieldRow(
                    label: String(localized: "settings.jobboards.careers_url", defaultValue: "Careers URL"),
                    text: $careersURL,
                    onSubmit: commit
                )
                .onChange(of: careersURL) { _, _ in validateURL() }
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                STextFieldRow(
                    label: String(localized: "settings.jobboards.slug", defaultValue: "Slug"),
                    text: $slug,
                    onSubmit: commit
                )
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                SPickerRow(
                    label: String(localized: "settings.jobboards.platform", defaultValue: "Platform"),
                    selection: $platform,
                    options: JobBoardPlatform.allCases,
                    optionLabel: { $0.displayName }
                )
                .onChange(of: platform) { _, _ in commit() }

                if let apiHint {
                    SettingsStatusRow(
                        message: apiHint,
                        systemImage: apiHint.hasPrefix("API") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: apiHint.hasPrefix("API") ? Color.green : Color.orange
                    )
                }
            }
        }
        .onAppear(perform: syncFromCompany)
        .onChange(of: company) { _, _ in syncFromCompany() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: platform.icon)
                .foregroundStyle(enabled ? DesignSystem.Colors.primary : Color.secondary)
                .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(company.displayName)
                        .font(DesignSystem.Fonts.body(weight: .medium))
                        .foregroundStyle(.primary)
                    JobBoardPlatformBadge(platform: platform)
                }
                statusLine
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { value in
                    enabled = value
                    JobBoardCompaniesStore.shared.setEnabled(id: company.id, enabled: value)
                    coordinator.rebuildIdleUIState()
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var actionsRow: some View {
        HStack(spacing: 18) {
            Button {
                commit()
                Task { await coordinator.scrapeCompany(currentCompany(), force: true) }
            } label: {
                Text(isScraping
                    ? String(localized: "settings.jobboards.scraping", defaultValue: "Scraping…")
                    : String(localized: "settings.jobboards.refresh_now", defaultValue: "Refresh now"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.primary)
            .disabled(!enabled || isScraping)

            Button {
                clearScrapedJobs()
            } label: {
                Text(String(localized: "settings.jobboards.clear_jobs", defaultValue: "Clear scraped jobs"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.warning)

            Spacer()

            Button(role: .destructive) {
                JobBoardCompaniesStore.shared.removeCompany(id: company.id)
                coordinator.rebuildIdleUIState()
            } label: {
                Text(String(localized: "common.remove", defaultValue: "Remove"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.error)
        }
        .font(DesignSystem.Fonts.caption1(weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var statusLine: some View {
        let normalized = company.normalizedSlug
        if let state = coordinator.uiState.companies.first(where: { $0.slug == normalized }) {
            switch state.status {
            case .idle:
                Text(String(localized: "settings.jobboards.status.idle", defaultValue: "Not scraped yet"))
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
            case .scraping(let progress):
                HStack(spacing: 6) {
                    Text(String(localized: "settings.jobboards.scraping", defaultValue: "Scraping…"))
                    if let progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .monospacedDigit()
                    }
                }
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
            case .importing:
                Text(String(localized: "settings.jobboards.importing", defaultValue: "Saving listings…"))
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
            case .ok(let count, let at):
                Text(String(
                    format: String(localized: "settings.jobboards.status.ok", defaultValue: "Last scraped %1$@ · %2$d jobs"),
                    at.formatted(.relative(presentation: .named)),
                    count
                ))
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
            case .error(let err, let at):
                Text("\(err.displayMessage) · \(at.formatted(.relative(presentation: .named)))")
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func currentCompany() -> JobBoardCompany {
        var updated = company
        updated.displayName = displayName
        updated.careersURL = careersURL
        updated.slug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        updated.enabled = enabled
        updated.platform = platform
        return updated
    }

    private func syncFromCompany() {
        displayName = company.displayName
        careersURL = company.careersURL
        slug = company.slug
        enabled = company.enabled
        platform = company.platform
        validateURL()
    }

    private func validateURL() {
        if let detected = JobBoardPlatformDetector.detect(from: careersURL) {
            platform = detected
        }
        let result = JobBoardPlatformDetector.validationMessage(for: careersURL, platform: platform)
        apiHint = result.message
    }

    private func commit() {
        JobBoardCompaniesStore.shared.updateCompany(currentCompany())
        coordinator.rebuildIdleUIState()
    }

    private func clearScrapedJobs() {
        let removed = CollegePersistence.shared.clearJobBoardPostings(companySlug: company.normalizedSlug)
        coordinator.rebuildIdleUIState()
        clearedJobsMessage = String(
            format: String(localized: "settings.jobboards.cleared_jobs", defaultValue: "Cleared %d scraped jobs."),
            removed
        )
    }
}

private struct SettingsUSAJobsCredentialsCard: View {
    var body: some View {
        SettingsCard(
            title: String(localized: "settings.jobboards.usajobs", defaultValue: "USAJobs API"),
            icon: "flag.fill",
            iconColor: DesignSystem.Colors.info
        ) {
            JobBoardUSAJobsCredentialsForm(style: .settings)
        }
    }
}
