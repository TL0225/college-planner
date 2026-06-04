// CollegeMenuBarRoot.swift
// Feature: App
// Purpose: App module — CollegeMenuBarSectionHeader.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - Metrics & chrome

enum CollegeMenuBarMetrics {
    static let panelWidth: CGFloat = 300
    static let padding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 6
}

private struct CollegeMenuBarSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - Menu bar icon

struct CollegeMenuBarLabel: View {
    var status: CollegeMenuBarStatusModel

    private var isBusy: Bool {
        status.isCatalogImporting || status.isCatalogPurgeRunning
    }

    var body: some View {
        Image(systemName: isBusy ? "arrow.triangle.2.circlepath" : "graduationcap.fill")
            .symbolEffect(.pulse, options: .repeating, isActive: isBusy)
            .help(status.menuBarTooltip)
    }
}

// MARK: - Root panel

/// Single menu bar panel: catalog scrape status, today’s schedule, and career openings.
struct CollegeMenuBarRoot: View {
    private var catalogStatus = CollegeMenuBarStatusModel.shared
    @AppStorage("ui.menuBarCalendarEnabled") private var menuBarCalendarEnabled = true
    @EnvironmentObject private var collegePersistence: CollegePersistence

    var body: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.sectionSpacing) {
            catalogSection
            Divider()
            if menuBarCalendarEnabled {
                todaySection
                Divider()
            }
            careerSection
            Divider()
            actionsSection
        }
        .padding(CollegeMenuBarMetrics.padding)
        .frame(width: CollegeMenuBarMetrics.panelWidth, alignment: .leading)
    }

    // MARK: Catalog

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.rowSpacing) {
            CollegeMenuBarSectionHeader(
                title: String(localized: "menubar.section.catalog", defaultValue: "Catalog import"),
                systemImage: "books.vertical.fill"
            )
            if showsCatalogPurgeSection {
                catalogPurgeStatusBody
                if catalogStatus.isCatalogPurgeRunning {
                    if let fraction = catalogPurgeProgressFraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } else {
                catalogStatusBody
                if let fraction = catalogStatus.catalogProgressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else if catalogStatus.isCatalogImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var showsCatalogPurgeSection: Bool {
        switch catalogStatus.catalogPurge {
        case .idle:
            return false
        case .inProgress, .succeeded, .failed:
            return true
        }
    }

    @ViewBuilder
    private var catalogPurgeStatusBody: some View {
        switch catalogStatus.catalogPurge {
        case .idle:
            EmptyView()
        case .inProgress:
            Text(catalogPurgeStatusLine)
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        case .succeeded:
            Label {
                Text(catalogPurgeStatusLine)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .labelStyle(.titleAndIcon)
        case .failed:
            Label {
                Text(catalogPurgeStatusLine)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var catalogPurgeStatusLine: String {
        switch catalogStatus.catalogPurge {
        case .idle:
            return ""
        case .inProgress(let title, _, _):
            return title
        case .succeeded(let summary):
            return summary
        case .failed(let message):
            return message
        }
    }

    private var catalogPurgeProgressFraction: Double? {
        guard case .inProgress(_, let fraction, let indeterminate) = catalogStatus.catalogPurge,
              !indeterminate,
              let fraction,
              fraction > 0,
              fraction.isFinite
        else { return nil }
        return min(1, max(0, fraction))
    }

    @ViewBuilder
    private var catalogStatusBody: some View {
        switch catalogStatus.catalog {
        case .idle:
            Text(String(localized: "menubar.catalog.body.idle", defaultValue: "Ready. Choosing a school in Profile starts a catalog import."))
                .font(DesignSystem.Fonts.main(size: 12))
                .foregroundStyle(.secondary)
        case .inProgress:
            Text(catalogStatus.statusLine)
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        case .succeeded:
            Label {
                Text(catalogStatus.statusLine)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .labelStyle(.titleAndIcon)
        case .failed:
            Label {
                Text(catalogStatus.statusLine)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.rowSpacing) {
            CollegeMenuBarSectionHeader(
                title: String(localized: "menubar.section.today", defaultValue: "Today"),
                systemImage: "calendar"
            )
            CollegeMenuBarTodayEvents()
        }
    }

    // MARK: Career

    private var careerSection: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.rowSpacing) {
            CollegeMenuBarSectionHeader(
                title: String(localized: "menubar.section.career", defaultValue: "Career"),
                systemImage: "briefcase.fill"
            )
            CollegeMenuBarCareerOpenings()
                .environmentObject(collegePersistence)
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(String(localized: "menubar.action.open_college", defaultValue: "Open College")) {
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(.defaultAction)

            if !menuBarCalendarEnabled {
                Button(String(localized: "menubar.action.open_settings", defaultValue: "Open Settings")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        .buttonStyle(.plain)
        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
    }
}

// MARK: - Today events (embedded)

private struct CollegeMenuBarTodayEvents: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var todayEvents: [OverviewEventSummary] = []

    var body: some View {
        Group {
            if todayEvents.isEmpty {
                Text(String(localized: "menubar.today.empty", defaultValue: "No events today."))
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayEvents.prefix(5)) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.title)
                            .font(DesignSystem.Fonts.main(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(event.startDate, style: .time)
                            .font(DesignSystem.Fonts.main(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .onAppear { refreshTodayEvents() }
        .onChange(of: collegePersistence.calendarDidChangeToken) { _, _ in refreshTodayEvents() }
    }

    private func refreshTodayEvents() {
        todayEvents = OverviewReadBridge.todayEventSummaries(collegePersistence: collegePersistence)
    }
}

// MARK: - Career openings (embedded)

private struct CollegeMenuBarCareerOpenings: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @ObservedObject private var coordinator = WorkdayJobBoardSyncCoordinator.shared
    @State private var recentPostings: [WorkdayJobPosting] = []

    var body: some View {
        Group {
            if coordinator.uiState.isAnyScrapeInFlight {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "menubar.career.syncing", defaultValue: "Checking job boards…"))
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if recentPostings.isEmpty {
                Text(String(localized: "menubar.career.empty", defaultValue: "No new openings right now."))
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentPostings, id: \.id) { posting in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(posting.title ?? String(localized: "menubar.career.untitled", defaultValue: "Untitled"))
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(posting.companyDisplayName ?? posting.companySlug)
                            .font(DesignSystem.Fonts.main(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Button(String(localized: "menubar.career.view_all", defaultValue: "View all openings")) {
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .jobBoardOpenOpenings, object: nil)
                }
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
            }
        }
        .onAppear { refreshRecentPostings() }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in refreshRecentPostings() }
        .onChange(of: coordinator.uiState.lastSuccessfulSyncAt) { _, _ in refreshRecentPostings() }
    }

    private func refreshRecentPostings() {
        recentPostings = WorkdayReadBridge.recentActivePostings(limit: 5)
    }
}
