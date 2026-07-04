// OverviewView.swift
// Feature: Overview
// Purpose: Overview module — ShimmerEffect.
// Data: CollegePersistence / repositories when applicable.

//
//  OverviewView.swift
//  College
//

import CollegeCalendar
import SwiftUI
import CoreLocation
import PDFKit
import Combine
import os
import AppKit
import Quartz

// MARK: - Shimmer Modifier

struct ShimmerEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false
    @State private var phase: CGFloat = 0

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    func body(content: Content) -> some View {
        if motionReduced {
            content
        } else {
            content
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [.black.opacity(0.3), .black, .black.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .offset(x: phase * 200, y: 0)
                )
                .onAppear {
                    withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

enum OverviewFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "degree",
                title: "Overview data",
                criticality: .requiredBeforeReady,
                timeoutSeconds: 1.2,
                retryLimit: 1,
                run: { context, onProgress, _ in
                    LaunchBootstrapCache.fetchSemestersIfNeeded()
                    onProgress(0.33)
                    LaunchBootstrapCache.fetchPlansIfNeeded()
                    onProgress(0.66)
                    LaunchBootstrapCache.fetchProfileIfNeeded()
                    onProgress(1)
                }
            )
        )
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerEffect())
    }
}

private enum OverviewMotion {
    static let cardStaggerStep: Double = 0.04
    static let revealDuration: Double = 0.32
    static let reducedRevealDuration: Double = 0.12
    static let hoverDuration: Double = 0.18
}

private struct OverviewEntranceModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity((isVisible || reduceMotion) ? 1 : 0)
            .animation(CollegeMotion.standardOrNone(reduced: reduceMotion), value: isVisible)
    }
}

private struct AnimatedMetricValueText: View {
    let value: Double?
    let fallback: String
    let reduceMotion: Bool

    private var displayText: String {
        guard let value else { return fallback }
        return String(format: "%.3f", value)
    }

    var body: some View {
        Text(displayText)
            .font(DesignSystem.Fonts.main(size: 38, weight: .heavy))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText(value: value ?? 0))
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24),
                value: value ?? -1
            )
    }
}

// MARK: - OverviewView

struct OverviewView: View {
    @Environment(AppContainer.self) private var container
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private let perfLog = OSLog(subsystem: "Timothy.College", category: "OverviewViewPerf")
    private var academicMetricsStore: AcademicMetricsStore { container.academicMetricsStore }
    private var collegePersistence: CollegePersistence { container.persistence }
        private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
            @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @Binding var activePage: AppPage

    @State private var isShowingProfileSheet = false
    @State private var isShowingOfficeHoursPopover = false
    @State private var hasAnimatedIn = false
    @State private var majorProgramsOverflowPopover = false
    @State private var minorProgramsOverflowPopover = false
    @State private var selectedOverviewDegreePage = 0
    @State private var isBuildingSyllabusPreview = false
    @AppStorage("overview.gettingStarted.dismissed.v1") private var gettingStartedDismissed = false

    private enum DashboardWidgetPreferences {
        static let assignments = "Upcoming Assignments"
        static let nextClass = "Next Class"
        static let gpaSnapshot = "GPA Snapshot"
        static let deadlines = "Deadlines"
        static let careerPipeline = "Career Pipeline"
        static let careerFollowUps = "Career Follow-ups"
        static let recentDocuments = "Recent Documents"
        static let academicCalendar = "Academic Calendar"
        static let quickActions = "Quick Actions"
    }

    private enum OverviewDeclaredProgramKind {
        case major
        case minor

        func creditsProgress(collegePersistence: CollegePersistence, displayName: String) -> CollegePersistence.CreditsProgressSummary {
            switch self {
            case .major:
                return MainActor.assumeIsolated {
                    collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: displayName)
                }
            case .minor:
                return MainActor.assumeIsolated {
                    collegePersistence.minorRequirementsCreditsProgress(forMinorDisplay: displayName)
                }
            }
        }

        func degreeTrack(displayName: String) -> DegreeTrack {
            switch self {
            case .major: return .major(displayName)
            case .minor: return .minor(displayName)
            }
        }
    }

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    private var selectedDashboardWidgets: Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: OnboardingPreferenceBridge.dashboardWidgetsKey)
        return OnboardingPreferenceBridge.resolvedDashboardWidgets(from: stored)
    }

    private var showsAssignmentsWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.assignments)
    }

    private var showsNextClassWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.nextClass)
    }

    private var showsGPASnapshotWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.gpaSnapshot)
    }

    private var showsDeadlinesWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.deadlines)
    }

    private var showsCareerPipelineWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.careerPipeline)
    }

    private var showsCareerFollowUpsWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.careerFollowUps)
    }

    private var showsRecentDocumentsWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.recentDocuments)
    }

    private var showsAcademicCalendarWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.academicCalendar)
    }

    private var showsQuickActionsWidget: Bool {
        selectedDashboardWidgets.contains(DashboardWidgetPreferences.quickActions)
    }

    private var currentResolvedSemester: PlannerSemester? {
        let activePlanSemesters = collegePersistence.getActivePlan()?.semestersArray ?? []
        let source = activePlanSemesters.isEmpty ? collegePersistence.semesters : activePlanSemesters
        return AcademicTermResolver.resolveCurrentSemester(from: source)
            ?? source.first(where: { !$0.isPlanned })
            ?? source.last
    }

    // MARK: - Content presence (empty-state collapsing)

    private var hasActiveCourses: Bool {
        !(currentResolvedSemester?.coursesArray.isEmpty ?? true)
    }

    private var hasTodayEvents: Bool {
        !OverviewReadBridge.todayEventSummaries(
            calendarManager: container.calendarManager,
            collegePersistence: collegePersistence
        ).isEmpty
    }

    private var hasUpcomingDeadlines: Bool {
        OverviewReadBridge.hasPendingTasks(collegePersistence: collegePersistence)
    }

    private var hasCareerData: Bool {
        OverviewReadBridge.hasCareerActivity(collegePersistence: collegePersistence)
    }

    private var hasAcademicProfiles: Bool {
        !OverviewReadBridge.academicProfiles(collegePersistence: collegePersistence).isEmpty
    }

    private var hasRecentDocuments: Bool {
        OverviewReadBridge.recentDocuments(limit: 2, collegePersistence: collegePersistence).count >= 2
    }

    private func routeAttentionItem(_ item: OverviewAttentionItem) {
        switch item.kind {
        case .event, .deadline:
            activePage = .calendar
        case .interview:
            activePage = .career
        }
    }

    private func shortProgramName(from rawName: String, fallbackKey: String) -> String {
        rawName.components(separatedBy: " ").first(where: { $0.count > 3 })
        ?? String(localized: LocalizedStringResource(stringLiteral: fallbackKey))
    }

    // MARK: - Getting Started Checklist

    private var hasConnectedCalendar: Bool {
        let manager = container.calendarManager
        return manager.googleStatus == .connected
            || manager.appleStatus == .connected
            || manager.outlookStatus == .connected
            || manager.iCloudStatus == .connected
    }

    private var hasUploadedResume: Bool {
        CareerReadBridge.hasCareerResume(collegePersistence: collegePersistence)
    }

    private var hasVisitedJobBoards: Bool {
        UserDefaults.standard.bool(forKey: "career.jobBoards.visited.v1")
    }

    private var hasLinkedLMS: Bool {
        LMSProvider.allCases.contains { !LMSPortalConfiguration.portalURLString(for: $0).isEmpty }
    }

    private var gettingStartedItems: [GettingStartedItem] {
        [
            GettingStartedItem(
                id: "semesters",
                title: String(localized: "overview.getting_started.semesters", defaultValue: "Add your first semester and courses"),
                systemImage: "calendar.badge.plus",
                isComplete: !collegePersistence.semesters.isEmpty,
                action: { activePage = .academics }
            ),
            GettingStartedItem(
                id: "calendar",
                title: String(localized: "overview.getting_started.calendar", defaultValue: "Connect your calendar"),
                systemImage: "calendar",
                isComplete: hasConnectedCalendar,
                action: { MacPreferencesWindow.show(section: .calendar) }
            ),
            GettingStartedItem(
                id: "resume",
                title: String(localized: "overview.getting_started.resume", defaultValue: "Upload your resume"),
                systemImage: "doc.text",
                isComplete: hasUploadedResume,
                action: { activePage = .career }
            ),
            GettingStartedItem(
                id: "jobBoards",
                title: String(localized: "overview.getting_started.job_boards", defaultValue: "Configure job boards"),
                systemImage: "briefcase",
                isComplete: hasVisitedJobBoards,
                action: { MacPreferencesWindow.show(section: .career) }
            ),
            GettingStartedItem(
                id: "lms",
                title: String(localized: "overview.getting_started.lms", defaultValue: "Link your LMS"),
                systemImage: "link",
                isComplete: hasLinkedLMS,
                action: { activePage = .lms }
            ),
        ]
    }

    private var shouldShowGettingStarted: Bool {
        guard !gettingStartedDismissed else { return false }
        return gettingStartedItems.contains { !$0.isComplete }
    }

    var body: some View {
        // NavigationStack removed — the NavigationSplitView detail column in ContentView already provides
        // a navigation stack context for .navigationDestination, and a nested NavigationStack was causing
        // the shell toolbar's .principal title to bleed into the sidebar column rather than the detail toolbar.
        ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .modifier(OverviewEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                        if shouldShowGettingStarted {
                            GettingStartedChecklist(
                                items: gettingStartedItems,
                                onDismiss: {
                                    withAnimation(DesignSystem.Motion.standardOrNone(reduceMotion: motionReduced)) {
                                        gettingStartedDismissed = true
                                    }
                                }
                            )
                            .modifier(OverviewEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        }

                        NeedsAttentionCard(
                            onSelect: { routeAttentionItem($0) },
                            onAskAssistant: { activePage = .assistant }
                        )
                        .modifier(OverviewEntranceModifier(index: 2, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                        academicStandingAndCoursesRow
                            .modifier(OverviewEntranceModifier(index: 3, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                        secondaryStatusGrid
                            .modifier(OverviewEntranceModifier(index: 4, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                        if showsQuickActionsWidget {
                            quickAccessTier
                                .modifier(OverviewEntranceModifier(index: 5, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .frame(maxWidth: .infinity)
            }
        .accessibilityIdentifier("overview.root")
        .shellDynamicTypeReadable()
        .onAppear {
            WidgetRegistry.shared.bootstrapBuiltIns()
            Task { @MainActor in
                academicMetricsStore.refresh()
            }
            guard !hasAnimatedIn else { return }
            hasAnimatedIn = true
        }
        .navigationDestination(for: DegreeTrack.self) { track in
            DegreeTrackDetailView(track: track)
        }
        .background(.windowBackground)
        .sheet(isPresented: $isShowingProfileSheet) {
            StudentProfileSheet()
                .dismissOnOutsideClickForSheet()
        }
        .background(MainContentReadySignal(ready: true))
    }

    @ViewBuilder
    private func declaredProgramsEqualWidthRow(
        kind: OverviewDeclaredProgramKind,
        names: [String],
        palette: [Color],
        overflowPopover: Binding<Bool>
    ) -> some View {
        let maxC = ProfileProgramLists.maxTrackColumns
        HStack(spacing: 24) {
            if names.isEmpty {
                emptyDeclaredProgramPlaceholder(kind: kind, palette: palette)
                    .frame(maxWidth: .infinity)
            } else if names.count > maxC {
                ForEach(0..<(maxC - 1), id: \.self) { slot in
                    let name = names[slot]
                    let progress = kind.creditsProgress(collegePersistence: collegePersistence, displayName: name)
                    degreeProgramRow(
                        isConfigured: true,
                        roleLabel: kind == .major ? "MAJOR" : "MINOR",
                        track: kind.degreeTrack(displayName: name),
                        cardTitle: overviewDeclaredProgramCardTitle(kind: kind, displayName: name),
                        subtitle: name,
                        stat: "\(progress.completedRoundedInt)/\(max(progress.requiredRoundedInt, 1)) cr toward requirement",
                        percent: "\(Int(progress.fraction * 100))%",
                        progress: progress.fraction,
                        accent: palette[slot % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }
                let extra = Array(names.dropFirst(maxC - 1))
                degreeProgramOverflowTile(
                    kind: kind,
                    extraCount: extra.count,
                    extraNames: extra,
                    accent: palette[(maxC - 1) % palette.count],
                    showPopover: overflowPopover
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    let progress = kind.creditsProgress(collegePersistence: collegePersistence, displayName: name)
                    degreeProgramRow(
                        isConfigured: true,
                        roleLabel: kind == .major ? "MAJOR" : "MINOR",
                        track: kind.degreeTrack(displayName: name),
                        cardTitle: overviewDeclaredProgramCardTitle(kind: kind, displayName: name),
                        subtitle: name,
                        stat: "\(progress.completedRoundedInt)/\(max(progress.requiredRoundedInt, 1)) cr toward requirement",
                        percent: "\(Int(progress.fraction * 100))%",
                        progress: progress.fraction,
                        accent: palette[idx % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func declaredProgramsStackedColumns(
        kind: OverviewDeclaredProgramKind,
        names: [String],
        palette: [Color],
        overflowPopover: Binding<Bool>
    ) -> some View {
        let maxC = ProfileProgramLists.maxTrackColumns
        VStack(spacing: 24) {
            if names.isEmpty {
                emptyDeclaredProgramPlaceholder(kind: kind, palette: palette)
                    .frame(maxWidth: .infinity)
            } else if names.count > maxC {
                ForEach(0..<(maxC - 1), id: \.self) { slot in
                    let name = names[slot]
                    let progress = kind.creditsProgress(collegePersistence: collegePersistence, displayName: name)
                    degreeProgramRow(
                        isConfigured: true,
                        roleLabel: kind == .major ? "MAJOR" : "MINOR",
                        track: kind.degreeTrack(displayName: name),
                        cardTitle: overviewDeclaredProgramCardTitle(kind: kind, displayName: name),
                        subtitle: name,
                        stat: "\(progress.completedRoundedInt)/\(max(progress.requiredRoundedInt, 1)) cr toward requirement",
                        percent: "\(Int(progress.fraction * 100))%",
                        progress: progress.fraction,
                        accent: palette[slot % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }
                let extra = Array(names.dropFirst(maxC - 1))
                degreeProgramOverflowTile(
                    kind: kind,
                    extraCount: extra.count,
                    extraNames: extra,
                    accent: palette[(maxC - 1) % palette.count],
                    showPopover: overflowPopover
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    let progress = kind.creditsProgress(collegePersistence: collegePersistence, displayName: name)
                    degreeProgramRow(
                        isConfigured: true,
                        roleLabel: kind == .major ? "MAJOR" : "MINOR",
                        track: kind.degreeTrack(displayName: name),
                        cardTitle: overviewDeclaredProgramCardTitle(kind: kind, displayName: name),
                        subtitle: name,
                        stat: "\(progress.completedRoundedInt)/\(max(progress.requiredRoundedInt, 1)) cr toward requirement",
                        percent: "\(Int(progress.fraction * 100))%",
                        progress: progress.fraction,
                        accent: palette[idx % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyDeclaredProgramPlaceholder(kind: OverviewDeclaredProgramKind, palette: [Color]) -> some View {
        degreeProgramRow(
            isConfigured: false,
            roleLabel: kind == .major ? "MAJOR" : "MINOR",
            track: kind == .major ? .major("") : .minor(""),
            cardTitle: kind == .major
                ? String(localized: "overview.degree.primary_card_title")
                : String(localized: "overview.degree.tertiary_card_title"),
            subtitle: String(localized: "overview.degree.placeholder_subtitle"),
            stat: String(localized: "overview.degree.placeholder_stat"),
            percent: String(localized: "overview.degree.placeholder_percent"),
            progress: 0,
            accent: palette[0].opacity(0.45)
        )
    }

    private func overviewDeclaredProgramCardTitle(kind: OverviewDeclaredProgramKind, displayName: String) -> String {
        let fb = kind == .major ? "overview.degree.major_fallback_short" : "overview.degree.secondary_fallback_short"
        let short = shortProgramName(from: displayName, fallbackKey: fb)
        switch kind {
        case .major: return "\(short) Major"
        case .minor: return "\(short) Minor"
        }
    }

    @ViewBuilder
    private func degreeProgramOverflowTile(
        kind: OverviewDeclaredProgramKind,
        extraCount: Int,
        extraNames: [String],
        accent: Color,
        showPopover: Binding<Bool>
    ) -> some View {
        Button {
            showPopover.wrappedValue.toggle()
        } label: {
            DegreeJourneyCard(
                title: "+\(extraCount) more",
                subtitle: kind == .major ? "Declared majors" : "Declared minors",
                stat: "View full list",
                percent: "\(extraCount)",
                progress: 0.12,
                accent: accent,
                roleLabel: "MORE",
                isInteractive: true
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .popover(isPresented: showPopover) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(extraNames, id: \.self) { name in
                        Text(name)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .frame(minWidth: 280, minHeight: 140)
        }
    }

    @ViewBuilder
    private func degreeProgramRow(
        isConfigured: Bool,
        roleLabel: String,
        track: DegreeTrack,
        cardTitle: String,
        subtitle: String,
        stat: String,
        percent: String,
        progress: Double,
        accent: Color
    ) -> some View {
        let card = DegreeJourneyCard(
            title: cardTitle,
            subtitle: subtitle,
            stat: stat,
            percent: percent,
            progress: progress,
            accent: accent,
            roleLabel: roleLabel,
            isInteractive: true
        )
        .frame(maxWidth: .infinity)

        if isConfigured {
            NavigationLink(value: track) {
                card
            }
            .buttonStyle(.plain)
        } else {
            Button {
                activePage = .profile
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    private func presentAddCourse() {
        let currentSemester = currentResolvedSemester
        if let semesterID = currentSemester?.id {
            modalCoordinator.activeModal = .addCatalogCourse(semesterID: semesterID)
        } else {
            modalCoordinator.activeModal = .addCatalogCourseGlobal(tagAsGenEd: false)
        }
    }

    // MARK: - Tier 2: status

    @ViewBuilder
    private var academicStandingAndCoursesRow: some View {
        let standing = AcademicStandingCard(
            selectedDegreePage: $selectedOverviewDegreePage
        ) {
            isShowingProfileSheet = true
        }

        if showsAssignmentsWidget && hasActiveCourses {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    standing.frame(minWidth: 320, maxWidth: 380)
                    ActiveCoursesCard().frame(maxWidth: .infinity)
                }
                VStack(spacing: 24) {
                    standing
                    ActiveCoursesCard()
                }
            }
        } else {
            standing.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var secondaryStatusGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 340), spacing: 24)],
            alignment: .leading,
            spacing: 24
        ) {
            if showsCareerPipelineWidget && hasCareerData {
                CareerSummaryWidget(onNavigateToCareer: { _ in activePage = .career })
                    .frame(minHeight: 180)
                    .overviewWidgetSurface(id: "career_summary", title: "Career")
            }

            if showsNextClassWidget && hasTodayEvents {
                UnifiedTimelineCard()
                    .frame(minHeight: 300)
                    .accessibilityIdentifier("overview.widget.schedule")
            }

            if showsDeadlinesWidget && hasUpcomingDeadlines {
                DeadlinesWidget()
                    .frame(minHeight: 200)
                    .overviewWidgetSurface(id: "deadlines", title: "Upcoming Deadlines")
            }

            if showsAcademicCalendarWidget && hasAcademicProfiles {
                AcademicCalendarWidget()
                    .frame(minHeight: 180)
                    .overviewWidgetSurface(id: "academic_calendar", title: "Academic Calendar")
            }

            if showsRecentDocumentsWidget && hasRecentDocuments {
                Button {
                    activePage = .documents
                } label: {
                    DocumentsWidget()
                        .frame(minHeight: 190)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent Documents")
                .accessibilityHint("Opens Documents")
                .overviewWidgetSurface(id: "documents", title: "Recent Documents")
            }
        }
    }

    // MARK: - Tier 3: quick access

    @ViewBuilder
    private var quickAccessTier: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUICK ACCESS")
                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                Button {
                    activePage = .assistant
                } label: {
                    ActionCard(
                        title: String(localized: "overview.action.ask_assistant.title", defaultValue: "Ask Assistant"),
                        subtitle: String(localized: "overview.action.ask_assistant.subtitle", defaultValue: "Plan, search, or summarize"),
                        systemImage: "sparkles",
                        accent: .accentColor
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        guard !isBuildingSyllabusPreview else { return }
                        isBuildingSyllabusPreview = true
                        defer { isBuildingSyllabusPreview = false }
                        await presentCombinedSyllabusQuickLook()
                    }
                } label: {
                    ActionCard(
                        title: String(localized: "overview.action.combined_syllabus.title"),
                        subtitle: String(localized: "overview.action.combined_syllabus.subtitle"),
                        systemImage: "doc.text.fill",
                        accent: .accentColor
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button {
                    isShowingOfficeHoursPopover.toggle()
                } label: {
                    ActionCard(
                        title: String(localized: "overview.action.office_hours.title"),
                        subtitle: String(localized: "overview.action.office_hours.subtitle"),
                        systemImage: "message.fill",
                        accent: .accentColor
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingOfficeHoursPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    OfficeHoursPopoverContent(courses: academicMetricsStore.snapshot?.currentTermCourses ?? [])
                        .padding(DesignSystem.Spacing.lg)
                        .frame(minWidth: 280, maxWidth: 340)
                }
            }

            Divider()
                .overlay(Color.primary.opacity(0.06))
                .padding(.vertical, 2)

            Button {
                activePage = .lms
            } label: {
                ActionCard(
                    title: String(localized: "overview.action.open_lms.title", defaultValue: "Open LMS"),
                    subtitle: String(localized: "overview.action.open_lms.subtitle", defaultValue: "Opens your course portal"),
                    systemImage: "graduationcap.circle.fill",
                    accent: .secondary,
                    isExternal: true
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        let currentTerm = currentAcademicTerm
        let termText = "ACADEMIC TERM \(currentTerm.season.uppercased()) \(currentTerm.year.formatted(.number.grouping(.never)))"
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(collegePersistence.profile?.overviewWelcomeTitle ?? Profile.welcomePlaceholder)
                    .font(.largeTitle.weight(.semibold))
                Text(termText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer(minLength: 12)
            NextUpPill()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview welcome")
    }

    private var currentAcademicTerm: (season: String, year: Int) {
        let now = Date()
        let month = Calendar.current.component(.month, from: now)
        let year = Calendar.current.component(.year, from: now)

        switch month {
        case 3...5:
            return ("Spring", year)
        case 6...8:
            return ("Summer", year)
        case 9...11:
            return ("Fall", year)
        default:
            return ("Winter", year)
        }
    }

    @MainActor
    private func presentCombinedSyllabusQuickLook() async {
        let signpostID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "presentCombinedSyllabusQuickLook", signpostID: signpostID)
        defer { os_signpost(.end, log: perfLog, name: "presentCombinedSyllabusQuickLook", signpostID: signpostID) }

        let currentSemester = currentResolvedSemester
        let activeCourses = currentSemester?.coursesArray ?? []
        let activeCodes = Set(activeCourses.map { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })

        let syllabusDocs = VaultReadBridge.syllabusDocuments(
            activeCourseCodes: activeCodes,
            collegePersistence: collegePersistence
        )

        guard !syllabusDocs.isEmpty else {
            appNotifications.post(kind: .info, title: "No Syllabi Found", message: "Import syllabi for active courses to preview.")
            return
        }

        var sourceURLs: [URL] = []
        for doc in syllabusDocs {
            guard let url = await VaultDocumentAccess.decryptedTempURL(for: doc.id, collegePersistence: collegePersistence) else { continue }
            sourceURLs.append(url)
        }

        let previewURL = await Task.detached(priority: .userInitiated) {
            OverviewSyllabusPDFMerger.mergedPreviewURL(from: sourceURLs)
        }.value

        guard let previewURL else {
            appNotifications.post(kind: .warning, title: "Preview Unavailable", message: "No readable PDF pages were found.")
            return
        }

        OverviewQuickLookPresenter.shared.present(url: previewURL)
    }
}

private enum OverviewSyllabusPDFMerger {
    static func mergedPreviewURL(from sourceURLs: [URL]) -> URL? {
        let merged = PDFDocument()
        var pageIndex = 0

        for url in sourceURLs {
            guard let pdf = PDFDocument(url: url) else { continue }
            for idx in 0..<pdf.pageCount {
                if let page = pdf.page(at: idx) {
                    merged.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }
        }

        guard pageIndex > 0 else { return nil }

        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CombinedSyllabus-\(UUID().uuidString).pdf")
        return merged.write(to: previewURL) ? previewURL : nil
    }
}

@MainActor
private final class OverviewQuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = OverviewQuickLookPresenter()

    private var itemURL: URL?

    func present(url: URL) {
        itemURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        itemURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        (itemURL ?? URL(fileURLWithPath: "/")) as NSURL
    }
}

private struct OfficeHoursPopoverContent: View {
    let courses: [AcademicTermCourseRow]

    private var withHours: [AcademicTermCourseRow] {
        courses.filter { ($0.officeHours ?? "").isEmpty == false }
    }

    private func courseLineTitle(_ c: AcademicTermCourseRow) -> String {
        if !c.code.isEmpty, !c.name.isEmpty { return "\(c.code) · \(c.name)" }
        if !c.name.isEmpty { return c.name }
        if !c.code.isEmpty { return c.code }
        return "Course"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Office hours")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            if withHours.isEmpty {
                DashboardEmptyHint(
                    title: "No office hours on file",
                    message: "Add office hours when editing a course in your current term.",
                    systemImage: "calendar.badge.clock"
                )
            } else {
                ForEach(withHours) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(courseLineTitle(c))
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                        if let professor = c.professor, !professor.isEmpty {
                            Text(professor)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(c.officeHours ?? "")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if c.id != withHours.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct NextUpPill: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @State private var dataRefreshToken = 0
    @State private var phase: CGFloat = 0

    private static let nextUpFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a z"
        return formatter
    }()

    private var nextEvent: OverviewEventSummary? {
        _ = collegePersistence.calendarDidChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.nextUpcomingEvent(collegePersistence: collegePersistence)
    }

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    var body: some View {
        if let nextEvent {
            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.35))
                            .frame(width: 8, height: 8)
                            .scaleEffect(motionReduced ? 1 : 1 + (phase * 1.5))
                            .opacity(motionReduced ? 1 : 1.0 - phase)
                            .animation(motionReduced ? nil : .easeOut(duration: 1.5).repeatForever(autoreverses: false), value: phase)
                        
                        Circle()
                            .fill(Color.green.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                    .onAppear {
                        if !motionReduced {
                            phase = 1
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT UP")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundStyle(.green)

                        Text("\(nextEvent.title) (\(Self.nextUpFormatter.string(from: nextEvent.startDate)))")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                if let location = nextEvent.location, !location.isEmpty {
                    Divider()
                        .frame(height: 24)
                        .overlay(Color.primary.opacity(0.08))

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(location)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
            .background {
                OverviewQueryHost { dataRefreshToken += 1 }
            }
        }
    }
}

private struct CardSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.glassCardBase.background(.ultraThinMaterial))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 40, x: 0, y: 15)
    }
}

private struct AcademicStandingCard: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var academicMetricsStore: AcademicMetricsStore { container.academicMetricsStore }
    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @Binding var selectedDegreePage: Int
    let onOpenProfile: () -> Void
    @State private var standingPageCache: [String: StandingPageSnapshot] = [:]

    private struct GPAMetrics {
        let primaryDisplay: String
        let primaryValue: Double?
        let schoolDisplay: String
        let schoolValue: Double?
    }

    private struct StandingPageSnapshot {
        let programRows: [ProgramStandingRow.RowData]
        let gpaMetrics: GPAMetrics
    }

    private var degreeProfiles: [AcademicProfile] {
        OverviewReadBridge.academicProfiles(collegePersistence: collegePersistence)
    }

    private var standingCacheRefreshToken: String {
        let profileToken = degreeProfiles
            .map { "\($0.id.uuidString):\($0.gpa ?? -1)" }
            .joined(separator: ",")
        let metricsToken = academicMetricsStore.snapshot.map {
            "\($0.cumulativeGPA ?? -1)|\($0.completedCreditsTotal)|\($0.gpaCoursesCounted)"
        } ?? "none"
        return "\(degreeProfiles.count)|\(collegePersistence.plannerChangeToken)|\(profileToken)|\(metricsToken)"
    }

    private var usesDegreePaging: Bool {
        degreeProfiles.count > 1
    }

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    private func standingCacheKey(for academicProfile: AcademicProfile?) -> String {
        academicProfile?.id.uuidString ?? "legacy"
    }

    private func rebuildStandingPageCache() {
        var cache: [String: StandingPageSnapshot] = [:]
        if degreeProfiles.isEmpty {
            let key = standingCacheKey(for: nil)
            cache[key] = StandingPageSnapshot(
                programRows: computeProgramRows(for: nil),
                gpaMetrics: computeGPAMetrics(for: nil)
            )
        } else {
            for profile in degreeProfiles {
                let key = standingCacheKey(for: profile)
                cache[key] = StandingPageSnapshot(
                    programRows: computeProgramRows(for: profile),
                    gpaMetrics: computeGPAMetrics(for: profile)
                )
            }
        }
        standingPageCache = cache
    }

    private func computeProgramRows(for academicProfile: AcademicProfile?) -> [ProgramStandingRow.RowData] {
        let majorColors: [Color] = [Color.accentColor, .orange, .green]
        let minorColors: [Color] = [.purple, .pink, .teal]
        var rows: [ProgramStandingRow.RowData] = []

        let majorNames: [String]
        let minorNames: [String]
        if let academicProfile {
            majorNames = collegePersistence.resolvedMajorNames(for: academicProfile)
            minorNames = collegePersistence.resolvedMinorNames(for: academicProfile)
        } else {
            majorNames = collegePersistence.resolvedMajorNames()
            minorNames = collegePersistence.resolvedMinorNames()
        }

        for (idx, majorName) in majorNames.enumerated() {
            let reqs: [DegreeRequirementEntity]
            let creditProgress: CollegePersistence.CreditsProgressSummary
            if let academicProfile {
                reqs = collegePersistence.getDegreeRequirementsForMajorDisplay(
                    majorName,
                    degreeType: academicProfile.degreeType,
                    degreeLevel: academicProfile.degreeLevel
                )
                creditProgress = collegePersistence.majorRequirementsCreditsProgress(
                    forMajorDisplay: majorName,
                    academicProfile: academicProfile
                )
            } else {
                reqs = collegePersistence.getDegreeRequirementsForMajorDisplay(majorName)
                creditProgress = collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: majorName)
            }
            let gpaSummary = collegePersistence.majorGPASummary(requirements: reqs)
            rows.append(ProgramStandingRow.RowData(
                id: "major-\(idx)-\(academicProfile?.id.uuidString ?? "legacy")",
                name: majorName,
                shortLabel: "MAJOR",
                gpa: gpaSummary?.gpa,
                creditProgress: creditProgress,
                color: majorColors[idx % majorColors.count],
                isMinor: false
            ))
        }

        for (idx, minorName) in minorNames.enumerated() {
            let creditProgress: CollegePersistence.CreditsProgressSummary
            if let academicProfile {
                creditProgress = collegePersistence.minorRequirementsCreditsProgress(
                    forMinorDisplay: minorName,
                    academicProfile: academicProfile
                )
            } else {
                creditProgress = collegePersistence.minorRequirementsCreditsProgress(forMinorDisplay: minorName)
            }
            let gpaSummary = collegePersistence.minorGPASummary(minorName: minorName)
            rows.append(ProgramStandingRow.RowData(
                id: "minor-\(idx)-\(academicProfile?.id.uuidString ?? "legacy")",
                name: minorName,
                shortLabel: "MINOR",
                gpa: gpaSummary?.gpa,
                creditProgress: creditProgress,
                color: minorColors[idx % minorColors.count],
                isMinor: true
            ))
        }
        return rows
    }

    private func computeGPAMetrics(for academicProfile: AcademicProfile?) -> GPAMetrics {
        if let academicProfile, let gpa = academicProfile.gpa, gpa > 0 {
            return GPAMetrics(
                primaryDisplay: String(format: "%.3f", gpa),
                primaryValue: gpa,
                schoolDisplay: "—",
                schoolValue: nil
            )
        }

        let plannerGPA = academicMetricsStore.snapshot?.cumulativeGPA
        let storedPrimaryGPA = collegePersistence.primaryGPA()
        let primaryValue = plannerGPA ?? (storedPrimaryGPA > 0 ? storedPrimaryGPA : nil)
        let primaryDisplay = primaryValue.map { String(format: "%.3f", $0) } ?? "—"

        let storedSchoolGPA = collegePersistence.primaryGPA()
        let schoolValue = storedSchoolGPA > 0 ? storedSchoolGPA : nil
        let schoolDisplay = schoolValue.map { String(format: "%.3f", $0) } ?? "—"

        return GPAMetrics(
            primaryDisplay: primaryDisplay,
            primaryValue: primaryValue,
            schoolDisplay: schoolDisplay,
            schoolValue: schoolValue
        )
    }

    var body: some View {
        Button(action: onOpenProfile) {
            CardSurface {
                if usesDegreePaging {
                    VStack(alignment: .leading, spacing: 16) {
                        standingHeader

                        HStack(alignment: .center, spacing: 8) {
                            degreeStepButton(systemImage: "chevron.left", enabled: selectedDegreePage > 0) {
                                selectedDegreePage -= 1
                            }

                            standingPage(for: degreeProfiles[safe: selectedDegreePage])
                                .frame(maxWidth: .infinity)
                                .id(selectedDegreePage)
                                .transition(motionReduced ? .opacity : .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))

                            degreeStepButton(
                                systemImage: "chevron.right",
                                enabled: selectedDegreePage < degreeProfiles.count - 1
                            ) {
                                selectedDegreePage += 1
                            }
                        }
                        .frame(minHeight: 280)
                        .gesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { value in
                                    if value.translation.width < -40, selectedDegreePage < degreeProfiles.count - 1 {
                                        selectedDegreePage += 1
                                    } else if value.translation.width > 40, selectedDegreePage > 0 {
                                        selectedDegreePage -= 1
                                    }
                                }
                        )

                        degreePageIndicator
                        achievementsSection
                    }
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        standingPage(for: degreeProfiles.first)
                        achievementsSection
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: degreeProfiles.count) { _, newCount in
            selectedDegreePage = min(selectedDegreePage, max(0, newCount - 1))
        }
        .task(id: standingCacheRefreshToken) {
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard !Task.isCancelled else { return }
            await Task.yield()
            await Task(priority: .utility) { @MainActor in
                rebuildStandingPageCache()
            }.value
        }
    }

    private var standingHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .foregroundStyle(Color.accentColor)
            Text("Academic Standing")
                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    @ViewBuilder
    private func standingPage(for academicProfile: AcademicProfile?) -> some View {
        let snapshot = standingPageCache[standingCacheKey(for: academicProfile)]
        let metrics = snapshot?.gpaMetrics ?? GPAMetrics(
            primaryDisplay: "—",
            primaryValue: nil,
            schoolDisplay: "—",
            schoolValue: nil
        )
        let rows = snapshot?.programRows ?? []

        VStack(alignment: .leading, spacing: 22) {
            if usesDegreePaging, let academicProfile {
                Text(academicProfile.resolvedShortLabel(among: degreeProfiles))
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(academicProfile.accentColor)
            } else if !usesDegreePaging {
                standingHeader
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                AnimatedMetricValueText(
                    value: metrics.primaryValue,
                    fallback: metrics.primaryDisplay,
                    reduceMotion: motionReduced
                )
                Image(systemName: "circlebadge.fill")
                    .font(DesignSystem.Fonts.main(size: 10))
                    .foregroundStyle(academicProfile?.accentColor ?? Color.accentColor)
                    .padding(.top, 8)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(usesDegreePaging ? "DEGREE GPA" : "CUMULATIVE GPA")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    if !usesDegreePaging, let n = academicMetricsStore.snapshot?.gpaCoursesCounted, n > 0 {
                        Text("\(n) course\(n == 1 ? "" : "s") graded")
                            .font(DesignSystem.Fonts.main(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !rows.isEmpty {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        ProgramStandingRow(row: row, motionReduced: motionReduced)
                    }
                }
            }
        }
    }

    private func degreeStepButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            guard enabled else { return }
            withAnimation(motionReduced ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                action()
            }
        }) {
            Image(systemName: systemImage)
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(enabled ? 0.06 : 0.03)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var degreePageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Array(degreeProfiles.enumerated()), id: \.element.objectID) { index, profile in
                Circle()
                    .fill(index == selectedDegreePage ? profile.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == selectedDegreePage ? 8 : 6, height: index == selectedDegreePage ? 8 : 6)
                    .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: selectedDegreePage)
            }
            Spacer()
            if degreeProfiles.indices.contains(selectedDegreePage) {
                Text(degreeProfiles[selectedDegreePage].resolvedShortLabel(among: degreeProfiles))
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var achievementsSection: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
            .padding(.vertical, 4)

        let achievements = ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence)?.achievementsArray ?? []
        if !achievements.isEmpty {
            HStack {
                let sorted = achievements.sorted { ($0.dateReceived ?? Date()) > ($1.dateReceived ?? Date()) }
                if let first = sorted.first {
                    achievementPill(title: first.name ?? "Award", subtitle: first.descriptionText ?? "", color: .orange, alignment: .leading)
                }

                Spacer()

                if sorted.count > 1 {
                    let second = sorted[1]
                    achievementPill(title: second.name ?? "Award", subtitle: second.descriptionText ?? "", color: Color.accentColor, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func achievementPill(title: String, subtitle: String, color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundStyle(color)
            if !subtitle.isEmpty {
                Text(subtitle.uppercased())
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
    }

}

private struct ProgressItem: View {
    let label: String
    let value: String
    let note: String?
    let color: Color
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(value)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .foregroundStyle(color)
                    if let note {
                        Text(note)
                            .font(DesignSystem.Fonts.main(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(fraction > 0 ? 0.14 : 0.08))
                    if fraction > 0 {
                        Rectangle()
                            .fill(color)
                            .frame(width: max(0, proxy.size.width * fraction))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Per-program standing row

private struct ProgramStandingRow: View {
    struct RowData: Identifiable {
        let id: String
        let name: String
        let shortLabel: String
        let gpa: Double?
        let creditProgress: CollegePersistence.CreditsProgressSummary
        let color: Color
        let isMinor: Bool
    }

    let row: RowData
    let motionReduced: Bool

    private var gpaColor: Color {
        guard let gpa = row.gpa else { return .secondary }
        if gpa >= 3.5 { return Color(red: 0.18, green: 0.72, blue: 0.40) }
        if gpa >= 2.5 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Program badge + name + GPA
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.shortLabel)
                            .font(DesignSystem.Fonts.main(size: 9, weight: .heavy))
                            .foregroundStyle(row.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(row.color.opacity(0.14))
                            .clipShape(Capsule())
                        if row.creditProgress.required > 0 {
                            Text("\(row.creditProgress.completedRoundedInt) / \(row.creditProgress.requiredRoundedInt) cr")
                                .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(row.name.uppercased())
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // GPA number
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .top, spacing: 3) {
                        Text(row.gpa.map { String(format: "%.3f", $0) } ?? "—")
                            .font(DesignSystem.Fonts.main(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(gpaColor)
                            .monospacedDigit()
                            .contentTransition(motionReduced ? .opacity : .numericText(value: row.gpa ?? 0))
                            .animation(
                                motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24),
                                value: row.gpa ?? -1
                            )
                        if row.gpa != nil {
                            Image(systemName: "circlebadge.fill")
                                .font(DesignSystem.Fonts.main(size: 9))
                                .foregroundStyle(gpaColor)
                                .padding(.top, 5)
                        }
                    }
                    Text("/ 4.000")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            // GPA scale bar
            DashboardGPAScaleBar(gpa: row.gpa)

            // Credits progress bar
            if row.creditProgress.required > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(row.color.opacity(row.creditProgress.fraction > 0 ? 0.12 : 0.07))
                        if row.creditProgress.fraction > 0 {
                            Capsule()
                                .fill(row.color)
                                .frame(width: max(0, geo.size.width * CGFloat(row.creditProgress.fraction)))
                        }
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(row.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(row.color.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct UnifiedTimelineCard: View {
    @Environment(AppContainer.self) private var container
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
        private var appActivity: AppActivityCoordinator { container.appActivity }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false

    @State private var dataRefreshToken = 0
    @State private var currentTime = Date()
    @State private var lastScrolledActiveEventID: String?
    @State private var expandedEventIDs: Set<String> = []
    @FocusState private var focusedTimelineEventID: String?
    @State private var keyboardFocusVisualsEnabled = false
    @State private var inputEventMonitor: Any?

    private var todayEvents: [OverviewEventSummary] {
        _ = collegePersistence.calendarDidChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.todayEventSummaries(
            calendarManager: calendarManager,
            collegePersistence: collegePersistence
        )
    }

    /// First event that has not ended yet; drives which row is “active” and auto-scroll target.
    private var activeTimelineRowID: String? {
        todayEvents.first(where: { $0.endDate >= currentTime })
            .map(timelineStableID(for:))
    }

    private func timelineStableID(for event: OverviewEventSummary) -> String {
        event.stableTimelineID
    }

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private func formatTimeRemaining(from current: Date, to target: Date) -> String {
        let diff = target.timeIntervalSince(current)
        if diff <= 0 { return "Now" }
        let minutes = Int(diff / 60)
        
        if minutes <= 10 {
            return "\(minutes) Min"
        } else {
            let intervals = minutes / 30
            let hours = (intervals * 30) / 60
            let mins = (intervals * 30) % 60
            if hours > 0 {
                return "\(hours) Hour\(hours > 1 ? "s" : "")\(mins > 0 ? " \(mins) Min" : "")"
            } else {
                return "\(mins) Min"
            }
        }
    }

    private func formatDuration(start: Date, end: Date) -> String {
        let totalMinutes = max(Int(end.timeIntervalSince(start) / 60), 0)
        if totalMinutes == 0 { return "< 1 min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    private func toggleExpansion(for eventID: String) {
        if motionReduced {
            if expandedEventIDs.contains(eventID) {
                expandedEventIDs.remove(eventID)
            } else {
                expandedEventIDs.insert(eventID)
            }
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.1)) {
            if expandedEventIDs.contains(eventID) {
                expandedEventIDs.remove(eventID)
            } else {
                expandedEventIDs.insert(eventID)
            }
        }
    }

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                    Text("Today's Timeline")
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Click row for details")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                if todayEvents.isEmpty {
                    Text("No events scheduled for today.")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 8) { // Reduced spacing between items to connect the line better
                                let firstActiveID = todayEvents.first(where: { $0.endDate >= currentTime })
                                    .map(timelineStableID(for:))
                                ForEach(todayEvents) { event in
                                    let eventStableID = timelineStableID(for: event)
                                    let isFirstActive = eventStableID == firstActiveID
                                    timelineEventRow(event: event, isFirstActive: isFirstActive)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .frame(maxHeight: .infinity)
                        .onAppear {
                            if let id = activeTimelineRowID {
                                lastScrolledActiveEventID = id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                }
                            }
                        }
                        .onChange(of: activeTimelineRowID) { _, newID in
                            guard let id = newID, id != lastScrolledActiveEventID else { return }
                            lastScrolledActiveEventID = id
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                    Spacer(minLength: 0)

            }
        }
        .onReceive(timer) { input in
            guard !appActivity.isResourceThrottled else { return }
            currentTime = input
        }
        .onChange(of: appActivity.isResourceThrottled) { _, throttled in
            if !throttled {
                currentTime = Date()
            }
        }
        .onAppear {
            guard inputEventMonitor == nil else { return }
            inputEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
                switch event.type {
                case .keyDown, .flagsChanged:
                    keyboardFocusVisualsEnabled = true
                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    keyboardFocusVisualsEnabled = false
                default:
                    break
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = inputEventMonitor {
                NSEvent.removeMonitor(monitor)
                inputEventMonitor = nil
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    @ViewBuilder
    private func timelineEventRow(event: OverviewEventSummary, isFirstActive: Bool) -> some View {
        let startDate = event.startDate
        let endDate = event.endDate
        let stableID = timelineStableID(for: event)
        let isPast = endDate < currentTime
        let isCurrent = !isPast && startDate <= currentTime
        let isFuture = startDate > currentTime
        let isExpanded = expandedEventIDs.contains(stableID)
        let isKeyboardFocused = (focusedTimelineEventID == stableID) && keyboardFocusVisualsEnabled
        let eventTitle = event.title
        let eventLocation = event.location ?? "No location"
        let timeText = Self.eventTimeFormatter.string(from: startDate)
        let countdown = isFuture ? formatTimeRemaining(from: currentTime, to: startDate) : (isCurrent ? "NOW" : "Ended")
        let leftRailColor: Color = isFirstActive ? Color.accentColor : (isPast ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.35))
        let rowFillStyle: AnyShapeStyle = isFirstActive ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.primary.opacity(0.04))
        let rowBorderColor: Color = isFirstActive ? Color.accentColor : Color.primary.opacity(0.08)
        let countdownForeground: Color = isFirstActive ? .white : Color.accentColor
        let countdownBackground: Color = isFirstActive ? (isCurrent ? .red : Color.accentColor) : Color.accentColor.opacity(0.12)

        Button {
            toggleExpansion(for: stableID)
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(leftRailColor)
                    .frame(width: 4)
                    .padding(.vertical, 0)
                    .padding(.trailing, 12)

                VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(eventTitle)
                                .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("\(timeText) • \(eventLocation)")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            if !isPast {
                                Text(countdown)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(countdownForeground)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(countdownBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            Image(systemName: "chevron.down")
                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: isExpanded)
                        }
                    }

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Label(Self.eventTimeFormatter.string(from: startDate), systemImage: "clock")
                                Text("→")
                                    .foregroundStyle(.tertiary)
                                Label(Self.eventTimeFormatter.string(from: endDate), systemImage: "clock.badge.checkmark")
                            }
                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                Label(formatDuration(start: startDate, end: endDate), systemImage: "hourglass")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                if let location = event.location, !location.isEmpty {
                                    Label(location, systemImage: "mappin.and.ellipse")
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 2)
                        .transition(
                            motionReduced
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .top)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.98, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                            )
                        )
                    }
                }
                .padding(.vertical, 16)
                .padding(.trailing, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(true)
    .focused($focusedTimelineEventID, equals: stableID)
        .padding(.leading, 12)
        .background(rowFillStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rowBorderColor, lineWidth: isFirstActive ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 4)
        .shadow(
            color: isKeyboardFocused ? Color.black.opacity(0.14) : (isFirstActive ? Color.black.opacity(0.15) : Color.clear),
            radius: isKeyboardFocused ? 16 : 12,
            x: 0,
            y: isKeyboardFocused ? 8 : 5
        )
        .scaleEffect(isKeyboardFocused ? 1.03 : ((isFirstActive || isExpanded) ? 1.02 : 0.985))
        .offset(y: isKeyboardFocused ? -1.5 : 0)
        .saturation((isFirstActive || isExpanded) ? 1.0 : 0.65)
        .opacity((isFirstActive || isExpanded) ? 1.0 : 0.78)
        .animation(motionReduced ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: isFirstActive)
        .animation(motionReduced ? nil : .spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.1), value: isExpanded)
        .animation(motionReduced ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: isKeyboardFocused)
        .id(stableID)
    }
}

private struct ActiveCoursesCard: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @State private var cachedVisibleCourses: [PlannerCourse] = []

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    private func resolvedTitle(for course: PlannerCourse) -> String {
        let rawCode = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeNorm = rawCode.replacingOccurrences(of: " ", with: "").uppercased()
        let nameNorm = rawName.replacingOccurrences(of: " ", with: "").uppercased()

        if !rawName.isEmpty, nameNorm != codeNorm {
            return rawName
        }

        if let title = collegePersistence.getCatalogCourse(code: rawCode)?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
            return title
        }

        if !rawCode.isEmpty {
            if let catalog = CollegePersistence.shared.fetchCatalogCourseForCodeBroadSearch(rawCode) {
                let title = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty,
                   title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
                    return title
                }
            }

            let strippedCode = rawCode
                .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !strippedCode.isEmpty,
               strippedCode.caseInsensitiveCompare(rawCode) != .orderedSame,
               let catalog = CollegePersistence.shared.fetchCatalogCourseForCodeBroadSearch(strippedCode) {
                let title = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty,
                   title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
                    return title
                }
            }
        }

        return rawCode.isEmpty ? "No title available" : rawCode
    }

    private func requirementText(for course: PlannerCourse) -> String {
        let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
        return status.isEmpty ? "CORE" : status.uppercased()
    }

    private var totalSemesterCredits: Int {
        cachedVisibleCourses.reduce(0) { $0 + Int($1.credits) }
    }

    private func refreshVisibleCourses(courses: [PlannerCourse], animated: Bool) {
        if animated {
            withAnimation(motionReduced ? nil : .easeInOut(duration: 0.18)) {
                cachedVisibleCourses = courses
            }
        } else {
            cachedVisibleCourses = courses
        }
    }

    var body: some View {
        let activePlanSemesters = collegePersistence.getActivePlan()?.semestersArray ?? []
        let sourceSemesters = activePlanSemesters.isEmpty ? collegePersistence.semesters : activePlanSemesters
        let currentSemester = AcademicTermResolver.resolveCurrentSemester(from: sourceSemesters)
            ?? sourceSemesters.first(where: { !$0.isPlanned })
            ?? sourceSemesters.last
        let activeCourses = currentSemester?.coursesArray ?? []
        let activeCourseIDs = activeCourses.map(\.objectID)
        let visibleCourses = cachedVisibleCourses
        
        CardSurface {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "calendar")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Active Courses")
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !visibleCourses.isEmpty {
                        HStack(spacing: 6) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            Text("\(totalSemesterCredits) Total Credits")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 12)

                if visibleCourses.isEmpty {
                    VStack(spacing: 16) {
                        Text("No courses for \(currentSemester?.name ?? "this semester").")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("Ready to get started?")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                } else {
                    Table(visibleCourses) {
                        TableColumn("Course") { course in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.code)
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(resolvedTitle(for: course))
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        TableColumn("Credits") { course in
                            Text("\(Int(course.credits))")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                        }
                        TableColumn("Requirement") { course in
                            Text(requirementText(for: course))
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                        }
                        TableColumn("Status") { course in
                            HStack(spacing: 4) {
                                Image(systemName: course.isCompleted ? "checkmark.circle.fill" : "clock.fill")
                                Text(course.isCompleted ? "Completed" : "Active")
                            }
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(course.isCompleted ? .green : Color.accentColor)
                            .padding(.vertical, 6)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .alternatingRowBackgrounds(.disabled)
                    .frame(minHeight: min(CGFloat(max(visibleCourses.count, 1) * 42 + 40), 420))
                }
            }
        }
        .onAppear {
            refreshVisibleCourses(courses: activeCourses, animated: false)
        }
        .onChange(of: activeCourseIDs) { _, _ in
            refreshVisibleCourses(courses: activeCourses, animated: false)
        }
    }
}

private struct DegreeJourneyCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    let title: String
    let subtitle: String
    let stat: String
    let percent: String
    let progress: Double
    let accent: Color
    var roleLabel: String = ""
    var isInteractive: Bool = false

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    private var resolvedRoleLabel: String {
        let trimmed = roleLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed.uppercased() }
        return title.localizedCaseInsensitiveContains("minor") ? "MINOR" : "MAJOR"
    }

    private var usesMinorChrome: Bool {
        resolvedRoleLabel == "MINOR"
    }

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: usesMinorChrome ? "chart.bar.fill" : "network")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(accent.opacity(0.1))
                        .clipShape(Circle())

                    Spacer()

                    Text(resolvedRoleLabel)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checklist")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(stat)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(percent)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(progress > 0 ? 0.08 : 0.12))
                            if progress > 0 {
                                Capsule()
                                    .fill(accent)
                                    .frame(width: max(0, proxy.size.width * progress))
                            }
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(isInteractive && isHovered ? 0.08 : 0.03), radius: isInteractive && isHovered ? 22 : 14, x: 0, y: isInteractive && isHovered ? 10 : 6)
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.52) : .clear, lineWidth: 1.5)
        }
        .animation(motionReduced ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
        .onHover { hovering in
            guard isInteractive else { return }
            isHovered = hovering
        }
        .focusable(isInteractive)
        .focused($isFocused)
    }
}

private enum DegreeTrack: Hashable {
    case major(String)
    case minor(String)
}

private struct DegreeTrackDetailView: View {
    let track: DegreeTrack

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                Text("This detail view is ready for the requirement breakdown list.")
                    .foregroundStyle(.secondary)
                Text("Courses remaining and requirement nodes will appear here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Color.accentColor.opacity(0.06)
                Rectangle().fill(.thinMaterial)
            }
        }
    }

    private var title: String {
        switch track {
        case .major(let name):
            return "\(name) Major Detail"
        case .minor(let name):
            return "\(name) Minor Detail"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct StudentProfileSheet: View {
    @State private var activeSheetPage: AppPage = .profile

    var body: some View {
        ProfileView(activePage: $activeSheetPage)
            .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 640)
    }
}

private struct ActionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    let title: String
    let subtitle: String
    let systemImage: String
    var accent: Color = .secondary
    /// When true the action leaves the app (e.g. opens an external LMS portal).
    /// Rendered with a distinct outward-arrow affordance so it reads differently
    /// from in-app actions like Ask Assistant.
    var isExternal: Bool = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    var body: some View {
        CardSurface {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isExternal {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.46) : .clear, lineWidth: 1.5)
        }
        .animation(motionReduced ? nil : .easeOut(duration: OverviewMotion.hoverDuration), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .focusable(true)
        .focused($isFocused)
    }
}
