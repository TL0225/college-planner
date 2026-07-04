// CollegeMenuBarRoot.swift
// Feature: App
// Purpose: Unified menu bar panel — background activity, today, career openings.

import SwiftUI

// MARK: - Metrics & chrome

enum CollegeMenuBarMetrics {
    static let panelWidth: CGFloat = 320
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

private struct CollegeMenuBarDomainHeader: View {
    let domain: BackgroundActivityDomain

    var body: some View {
        Label(domain.displayName, systemImage: domain.systemImage)
            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

private struct CollegeMenuBarActivityRow: View {
    let item: BackgroundActivityItem

    private var progressTint: Color {
        switch item.phase {
        case .failed:
            return .orange
        case .succeeded:
            return .green
        case .running:
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                phaseIcon
                Text(item.title)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let percent = item.percentText {
                    Text(percent)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            switch item.phase {
            case .running:
                if let fraction = item.displayFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(progressTint)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(progressTint)
                }
            case .succeeded(let summary):
                Text(summary)
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ProgressView(value: 1)
                    .progressViewStyle(.linear)
                    .tint(.green)
            case .failed(let message):
                Text(message)
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch item.phase {
        case .running:
            EmptyView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Menu bar icon

struct CollegeMenuBarLabel: View {
    private var backgroundCenter = BackgroundActivityCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    var body: some View {
        Image(systemName: backgroundCenter.hasRunningWork ? "arrow.triangle.2.circlepath" : "graduationcap.fill")
            .symbolEffect(.pulse, options: .repeating, isActive: !motionReduced && backgroundCenter.hasRunningWork)
            .help(backgroundCenter.menuBarTooltip)
    }
}

// MARK: - Root panel

/// Single menu bar panel: background work, today's schedule, and career openings.
struct CollegeMenuBarRoot: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.isPresented) private var isMenuPresented
    private var backgroundCenter = BackgroundActivityCenter.shared
    @AppStorage("ui.menuBarCalendarEnabled") private var menuBarCalendarEnabled = true
    @State private var refreshToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.sectionSpacing) {
            backgroundSection
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
        .onChange(of: isMenuPresented) { _, presented in
            guard presented else { return }
            refreshToken &+= 1
        }
    }

    // MARK: Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.rowSpacing) {
            CollegeMenuBarSectionHeader(
                title: String(localized: "menubar.section.background", defaultValue: "Background"),
                systemImage: "arrow.triangle.2.circlepath"
            )

            if backgroundCenter.menuBarActivityRows.isEmpty {
                Text(String(
                    localized: "menubar.background.idle",
                    defaultValue: "No background work running."
                ))
                .font(DesignSystem.Fonts.main(size: 12))
                .foregroundStyle(.secondary)
            } else {
                ForEach(backgroundCenter.menuBarActivityRows) { row in
                    switch row {
                    case .domainHeader(let domain):
                        CollegeMenuBarDomainHeader(domain: domain)
                    case .activity(let item):
                        CollegeMenuBarActivityRow(item: item)
                    }
                }
            }
        }
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.rowSpacing) {
            CollegeMenuBarSectionHeader(
                title: String(localized: "menubar.section.today", defaultValue: "Today"),
                systemImage: "calendar"
            )
            CollegeMenuBarTodayEvents(refreshToken: refreshToken)
        }
    }

    // MARK: Career

    private var careerSection: some View {
        VStack(alignment: .leading, spacing: CollegeMenuBarMetrics.rowSpacing) {
            CollegeMenuBarSectionHeader(
                title: String(localized: "menubar.section.career", defaultValue: "Career"),
                systemImage: "briefcase.fill"
            )
            CollegeMenuBarCareerOpenings(refreshToken: refreshToken)
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
    @Environment(AppContainer.self) private var container
    private var collegePersistence: CollegePersistence { container.persistence }
    let refreshToken: Int
    @State private var todayEvents: [OverviewEventSummary] = []

    var body: some View {
        Group {
            if todayEvents.isEmpty {
                Text(String(localized: "menubar.today.empty", defaultValue: "No events today."))
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayEvents.prefix(5)) { event in
                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        AppTypedNavigationRouter.openPage(.calendar)
                    } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(event.title), \(event.startDate.formatted(date: .omitted, time: .shortened))")
                    .accessibilityHint("Opens Calendar")
                }
            }
        }
        .onAppear { refreshTodayEvents() }
        .onChange(of: refreshToken) { _, _ in refreshTodayEvents() }
        .onChange(of: collegePersistence.calendarDidChangeToken) { _, _ in refreshTodayEvents() }
    }

    private func refreshTodayEvents() {
        todayEvents = OverviewReadBridge.todayEventSummaries(collegePersistence: collegePersistence)
    }
}

// MARK: - Career openings (embedded)

private struct CollegeMenuBarCareerOpenings: View {
    @Environment(AppContainer.self) private var container
    let refreshToken: Int
    @State private var recentPostings: [JobBoardPosting] = []

    var body: some View {
        Group {
            if recentPostings.isEmpty {
                Text(String(localized: "menubar.career.empty", defaultValue: "No new openings right now."))
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentPostings, id: \.id) { posting in
                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        AppTypedNavigationRouter.openPage(.career)
                    } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(posting.title ?? "Opening"), \(posting.companyDisplayName ?? posting.companySlug)")
                    .accessibilityHint("Opens Career")
                }
                Button(String(localized: "menubar.career.view_all", defaultValue: "View all openings")) {
                    NSApp.activate(ignoringOtherApps: true)
                    container.careerNavigationRouter.jobOpenings()
                }
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
            }
        }
        .onAppear { refreshRecentPostings() }
        .onChange(of: refreshToken) { _, _ in refreshRecentPostings() }
        .onChange(of: container.persistence.careerDidChangeToken) { _, _ in refreshRecentPostings() }
        .onChange(of: JobBoardSyncCoordinator.shared.uiState.lastSuccessfulSyncAt) { _, _ in
            refreshRecentPostings()
        }
    }

    private func refreshRecentPostings() {
        recentPostings = JobBoardReadBridge.recentActivePostings(limit: 5)
    }
}
