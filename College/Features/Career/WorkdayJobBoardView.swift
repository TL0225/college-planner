// WorkdayJobBoardView.swift
// Feature: Career
// Purpose: Career module — WorkdayJobBoardView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct WorkdayJobBoardView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @ObservedObject private var coordinator = WorkdayJobBoardSyncCoordinator.shared
    @ObservedObject private var logoStore = WorkdayCompanyLogoStore.shared

    var onNavigateToBoard: () -> Void = {}

    private var companiesStore: WorkdayCompaniesStore { WorkdayCompaniesStore.shared }

    @State private var selectedCompanyID: UUID?
    @State private var selectedPostingPath: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    private var selectedCompany: WorkdayCompanyConfigEntry? {
        guard let selectedCompanyID else { return nil }
        return companiesStore.enabledCompanies.first { $0.id == selectedCompanyID }
    }

    var body: some View {
        Group {
            if companiesStore.enabledCount == 0 {
                emptyNoCompanies
            } else {
                openingsSplitView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .onAppear {
            selectDefaultCompanyIfNeeded()
            for company in companiesStore.enabledCompanies {
                logoStore.loadLogoIfNeeded(for: company)
            }
        }
        .onChange(of: companiesStore.enabledCompanies.map(\.id)) { _, _ in
            selectDefaultCompanyIfNeeded()
        }
        .onChange(of: selectedCompanyID) { _, _ in
            selectedPostingPath = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .workdayImportDidFinish)) { _ in
            coordinator.rebuildIdleUIState()
        }
    }

    /// `HSplitView` fills the window width (unlike `NavigationSplitView`, which caps column widths and leaves side gutters).
    private var openingsSplitView: some View {
        HSplitView {
            companySidebarColumn
                .frame(
                    minWidth: WorkdayOpeningsLayout.companySidebarWidth,
                    idealWidth: WorkdayOpeningsLayout.companySidebarWidth,
                    maxWidth: WorkdayOpeningsLayout.companySidebarMaxWidth
                )

            openingsContentColumn
                .frame(
                    minWidth: WorkdayOpeningsLayout.jobListMinWidth,
                    idealWidth: WorkdayOpeningsLayout.jobListIdealWidth,
                    maxWidth: .infinity
                )

            openingsDetailColumn
                .frame(
                    minWidth: WorkdayOpeningsLayout.detailMinWidth,
                    idealWidth: WorkdayOpeningsLayout.detailIdealWidth,
                    maxWidth: .infinity
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var openingsContentColumn: some View {
        if let company = selectedCompany {
            WorkdayCompanyJobsView(
                company: company,
                selectedPostingPath: $selectedPostingPath,
                onNavigateToBoard: onNavigateToBoard
            )
            .environmentObject(collegePersistence)
            .id(company.id)
        } else {
            selectCompanyPlaceholder
        }
    }

    @ViewBuilder
    private var openingsDetailColumn: some View {
        if let company = selectedCompany,
           let path = selectedPostingPath,
           let posting = WorkdayReadBridge.posting(
                companySlug: company.normalizedSlug,
                externalPath: path
            ) {
            WorkdayJobDetailPane(
                posting: posting,
                company: company,
                onClose: { selectedPostingPath = nil },
                onInterested: { app in
                    NotificationCenter.default.post(name: .careerOpenBoardJob, object: app.objectID)
                },
                onNavigateToBoard: onNavigateToBoard,
                embeddedInNavigationSplit: true
            )
            .environmentObject(collegePersistence)
        } else {
            selectJobPlaceholder
        }
    }

    private var selectJobPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(DesignSystem.Fonts.main(size: 32))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Text("Select a job")
                .font(.title3)
            Text("Pick an opening from the list to read the full description.")
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.surface)
    }

    private var companySidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Companies")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                Spacer(minLength: 0)
                Button {
                    Task { await coordinator.scrapeAllEnabledCompanies() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help(refreshAllCompaniesHelp)
                .disabled(coordinator.uiState.isAnyScrapeInFlight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().opacity(0.35)

            List(selection: $selectedCompanyID) {
                ForEach(companiesStore.enabledCompanies) { company in
                    WorkdayCompanySidebarRow(
                        company: company,
                        isSelected: selectedCompanyID == company.id,
                        state: coordinator.uiState.companies.first { $0.slug == company.normalizedSlug },
                        newCount: collegePersistence.newOpeningsCount(companySlug: company.normalizedSlug),
                        onScrape: { Task { await coordinator.scrapeCompany(company) } }
                    )
                    .tag(company.id)
                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedCompanyID) { _, newID in
                guard let newID,
                      let company = companiesStore.enabledCompanies.first(where: { $0.id == newID })
                else { return }
                WorkdayOpeningsState.markCompanyViewed(slug: company.normalizedSlug)
            }
        }
        .background(DesignSystem.Colors.surface.opacity(0.65))
        .overlay(alignment: .trailing) {
            Divider().opacity(0.35)
        }
    }

    private var refreshAllCompaniesHelp: String {
        let interval = WorkdayRefreshScheduler.shared.selectedIntervalSeconds
        let schedule = interval > 0
            ? "Automatic refresh: \(WorkdayRefreshIntervalOption.fromStoredSeconds(Int(interval)).displayName). "
            : "Automatic refresh is off (manual only). "
        return schedule + "Change schedule in Settings → Job Boards. Refreshes all companies now."
    }

    private var selectCompanyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(DesignSystem.Fonts.main(size: 36))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Text("Select a company")
                .font(.title3)
            Text("Choose a company in the sidebar to browse its openings.")
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyNoCompanies: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(DesignSystem.Fonts.main(size: 40))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Text("No Workday companies configured")
                .font(.title3)
            Text("Open Settings → Job Boards to add career board URLs.")
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectDefaultCompanyIfNeeded() {
        let enabled = companiesStore.enabledCompanies
        guard !enabled.isEmpty else {
            selectedCompanyID = nil
            return
        }
        if let selectedCompanyID,
           enabled.contains(where: { $0.id == selectedCompanyID }) {
            return
        }
        let first = enabled.first!
        selectedCompanyID = first.id
        WorkdayOpeningsState.markCompanyViewed(slug: first.normalizedSlug)
    }
}

// MARK: - Compact company sidebar row

private struct WorkdayCompanySidebarRow: View {
    @ObservedObject private var logoStore = WorkdayCompanyLogoStore.shared

    let company: WorkdayCompanyConfigEntry
    let isSelected: Bool
    let state: WorkdaySyncUIState.CompanyState?
    let newCount: Int
    let onScrape: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            companyLogo
            VStack(alignment: .leading, spacing: 2) {
                Text(company.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                trailingBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? DesignSystem.Colors.accent.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(companyTooltip)
        .contextMenu {
            Button("Scrape now", action: onScrape)
        }
        .onAppear {
            logoStore.loadLogoIfNeeded(for: company)
        }
    }

    @ViewBuilder
    private var companyLogo: some View {
        Group {
            if let image = logoStore.image(for: company) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "building.2")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var trailingBadge: some View {
        switch state?.status {
        case .scraping(let progress):
            if let progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            } else {
                ProgressView().controlSize(.mini)
            }
        case .ok, .error, .idle, .none:
            jobCountBadge
        }
    }

    @ViewBuilder
    private var jobCountBadge: some View {
        HStack(spacing: 6) {
            if newCount > 0 {
                Text("+\(newCount) new")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            switch state?.status {
            case .ok(let count, _):
                Text("\(count) jobs")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            case .scraping:
                Text("Syncing…")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            case .error:
                Text("Sync failed")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            case .idle, .none:
                Text("Not synced")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        }
    }

    private var companyTooltip: String {
        var lines: [String] = [company.displayName]
        switch state?.status {
        case .scraping:
            lines.append("Scraping listings…")
        case .ok(let count, let at):
            lines.append("\(count) active jobs")
            lines.append("Updated \(at.formatted(.relative(presentation: .named)))")
        case .error(let err, let at):
            lines.append(err.displayMessage)
            lines.append("Last attempt \(at.formatted(.relative(presentation: .named)))")
        case .idle, .none:
            lines.append("Not scraped yet")
        }
        let interval = WorkdayRefreshScheduler.shared.selectedIntervalSeconds
        if interval > 0 {
            let label = WorkdayRefreshIntervalOption.fromStoredSeconds(Int(interval)).displayName
            lines.append("Scheduled refresh: \(label)")
        } else {
            lines.append("Scheduled refresh: manual only")
        }
        lines.append("Right-click to scrape now.")
        return lines.joined(separator: "\n")
    }
}
