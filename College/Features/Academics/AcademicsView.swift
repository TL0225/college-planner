// AcademicsView.swift
// Feature: Academics
// Purpose: Academics module — AcademicsEntranceModifier.
// Data: CollegePersistence / repositories when applicable.

// AcademicsView.swift
// Semester Planner — the "Academics" tab (card-shell pattern aligned with Profile).

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CollegeAcademics

// MARK: - Motion Infrastructure


enum AcademicsFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "academics",
                title: "Academics planning",
                criticality: .requiredBeforeReady,
                timeoutSeconds: 1.2,
                retryLimit: 1,
                run: { context, onProgress, _ in
                    LaunchBootstrapCache.fetchPlansIfNeeded()
                    onProgress(1)
                }
            )
        )
    }
}


// MARK: - AcademicsView

struct AcademicsView: View {
    @Binding var activePage: AppPage
    @Binding var isInspectorPresented: Bool

    @Environment(AppContainer.self) private var appContainer
    private var persistence: CollegePersistence { appContainer.persistence }
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    private var appDataStore: AppDataStore { appContainer.appDataStore }
    private var academicMetricsStore: AcademicMetricsStore { appContainer.academicMetricsStore }
    private var auditSnapshotStore: AuditSnapshotStore { appContainer.auditSnapshotStore }
    private var modalCoordinator: ModalCoordinator { appContainer.modalCoordinator }
    private var academicsScene: AcademicsSceneState { appContainer.academicsScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    @State private var toolbarHandlerToken: ToolbarHandlerToken?

    private var profile: Profile? { ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) }

    @State private var plannerSemesters: [PlannerSemester] = []

    private var academicProfiles: [AcademicProfile] {
        AcademicProfileReadBridge.profiles()
    }

    private var selectedAcademicProfile: AcademicProfile? {
        if let id = academicsScene.selectedAcademicProfileID,
           let match = academicProfiles.first(where: { $0.id == id }) {
            return match
        }
        return academicProfiles.first
    }

    @State private var plannerCourseCount: Int = 0

    private var creditLayoutToken: String {
        let courseCount = max(
            plannerCourseCount,
            AcademicsPlannerReadBridge.semesterCourseCount(appDataStore: appDataStore)
        )
        let majors = selectedAcademicProfile.map { collegePersistence.resolvedMajorNames(for: $0) }
            ?? collegePersistence.resolvedMajorNames()
        let minors = selectedAcademicProfile.map { collegePersistence.resolvedMinorNames(for: $0) }
            ?? collegePersistence.resolvedMinorNames()
        return AuditSnapshotStore.creditLayoutToken(
            academicProfileID: selectedAcademicProfile?.id,
            majors: majors,
            minors: minors,
            semesterCourseCount: courseCount,
            specializationSelectionVersion: specializationSelectionVersion,
            metricsCreditsRequired: academicMetricsStore.snapshot?.creditsRequired
        )
    }

    /// Fixed width of the left stats column. The requirements canvas keeps the
    /// remaining space via `layoutPriority`; the column is not in a 50/50 split.
    private let leftSidebarWidth: CGFloat = 300
    @StateObject private var linker = CalendarCourseLinker.shared

    /// Tap target for the Phase B Graduation Timeline configuration sheet.
    /// `CompactGraduationTimelineCard` flips this; the sheet is mounted on this view so
    /// the modal participates in the same window lifecycle as the rest of the page.
    @State private var showGraduationSheet: Bool = false
    /// Mirror modals for the GPA + Credits stat cards, presented from this view.
    @State private var showGPASheet: Bool = false
    @State private var showCreditsSheet: Bool = false

    /// Bumped whenever the user picks a different specialization option in the audit sidebar.
    /// Major-card credit progress reads from local store each `body` render, so we need a
    /// State value that SwiftUI tracks to invalidate the cached `body` and trigger a fresh
    /// computation through `applySpecializationFilter`. Without this, the picker would
    /// update the sidebar UI immediately but the "Credits Earned" / "Total Credit Progress"
    /// numbers would stay frozen until something else in the view caused a re-render.
    @State private var specializationSelectionVersion = 0
    /// Set by the bottom program picker; `RequirementsBreakdownView` scrolls to the matching section.
    @State private var requirementsScrollTargetID: String?

    @SceneStorage("academics.view.hasAnimatedIn") private var hasAnimatedIn = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    // MARK: - Body

    var body: some View {
        let resolvedCreditsEarned = academicMetricsStore.snapshot?.completedCreditsTotal
            ?? collegePersistence.primaryCreditsEarned()
        let majors = selectedAcademicProfile.map { collegePersistence.resolvedMajorNames(for: $0) }
            ?? collegePersistence.resolvedMajorNames()
        let minors = selectedAcademicProfile.map { collegePersistence.resolvedMinorNames(for: $0) }
            ?? collegePersistence.resolvedMinorNames()
        let layout = auditSnapshotStore.creditLayout
        let breakdown = layout?.programsBreakdown
            ?? CollegePersistence.DeclaredProgramsCreditsBreakdown(
                primary: CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
                additionalPrograms: []
            )
        let resolvedGraduationCreditsRequired = layout?.resolvedGraduationCreditsRequired ?? (academicMetricsStore.snapshot?.creditsRequired ?? 0)
        let buckets = layout?.buckets ?? AcademicsCreditBuckets()
        let programCreditRows = layout?.programCreditRows ?? []

        GeometryReader { proxy in
            VStack(spacing: 0) {
                AcademicsAuditPanel(
                    majors: majors,
                    minors: minors,
                    academicProfile: selectedAcademicProfile,
                    activePage: $activePage,
                    isInspectorPresented: $isInspectorPresented,
                    scrollToProgramID: $requirementsScrollTargetID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(AcademicsEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                AcademicsBottomSummaryStrip(
                    programs: programCreditRows,
                    onSelectProgram: { stripID in
                        requirementsScrollTargetID = AcademicsProgramRequirementsScrollID
                            .forStripSelection(stripID)
                    }
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(id: "academics.inspectorToggle", placement: .primaryAction) {
                AcademicsToolbarSidebarToggleView(isInspectorPresented: $isInspectorPresented)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .inspector(isPresented: $isInspectorPresented) {
            AcademicsLeftStatsSidebar(
                profile: profile,
                academicProfile: selectedAcademicProfile,
                plannerGPAFormatted: Self.formatPlannerGPA(academicMetricsStore.snapshot),
                plannerCreditsEarned: resolvedCreditsEarned,
                plannerCreditsRequired: resolvedGraduationCreditsRequired,
                programsBreakdown: breakdown,
                sapStats: collegePersistence.sapStats(),
                majors: majors,
                minors: minors,
                showGraduationSheet: $showGraduationSheet,
                showGPASheet: $showGPASheet,
                showCreditsSheet: $showCreditsSheet
            )
            .inspectorColumnWidth(min: leftSidebarWidth, ideal: leftSidebarWidth, max: leftSidebarWidth + 80)
            .modifier(AcademicsEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Stats inspector")
        }
        .animation(DesignSystem.Motion.springOrEase(reduceMotion: motionReduced), value: isInspectorPresented)
        .onChange(of: isInspectorPresented) { _, shown in
            academicsScene.statsSidebarShown = shown
        }
        .background(DesignSystem.Colors.bgMain)
        .shellDynamicTypeReadable()
        .accessibilityIdentifier("academics.root")
        .task(id: creditLayoutToken) {
            auditSnapshotStore.scheduleCreditLayoutRefresh(
                token: creditLayoutToken,
                collegePersistence: collegePersistence,
                academicProfile: selectedAcademicProfile,
                majors: majors,
                minors: minors,
                plannerSemesters: plannerSemesters.isEmpty
                    ? collegePersistence.semesters
                    : plannerSemesters,
                metricsCreditsRequired: academicMetricsStore.snapshot?.creditsRequired
            )
        }
        // Anchor a hidden reference so SwiftUI tracks `specializationSelectionVersion` as
        // a dependency of `body`. Whenever the audit sidebar picker bumps it, the body
        // recomputes — and the embedded `requirementProgress(...)` local store lookup picks
        // up the new specialization choice through `applySpecializationFilter`.
        .background(
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .id(specializationSelectionVersion)
        )
        .onReceive(NotificationCenter.default.publisher(for: .auditSpecializationSelectionChanged)) { _ in
            specializationSelectionVersion &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .auditRequirementExclusionChanged)) { _ in
            // Reuse the same version dependency so `creditLayoutToken` changes and the bottom
            // summary strip recomputes with the newly excluded / re-included category.
            specializationSelectionVersion &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .graduationPlanChanged)) { _ in
            // Bump the same version dependency so the Graduation Timeline card and any
            // credit-progress reads pick up the new structured target / per-term caps.
            specializationSelectionVersion &+= 1
        }
        .background {
            AcademicsSemesterQueryHost(
                onSemesterCountChange: { count in
                    plannerCourseCount = count
                },
                onPlannerSemestersChange: { semesters in
                    plannerSemesters = semesters
                }
            )
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            
        }
        .sheet(isPresented: $showGraduationSheet) {
            GraduationTimelineConfigSheet(
                academicProfile: selectedAcademicProfile,
                requiredCredits: resolvedGraduationCreditsRequired,
                completedCredits: buckets.completed,
                inProgressCredits: buckets.inProgress,
                plannedCredits: buckets.planned
            )
            }
        .sheet(isPresented: $showGPASheet) {
            CumulativeGPADetailSheet(academicProfile: selectedAcademicProfile)
        }
        .sheet(isPresented: $showCreditsSheet) {
            CreditsEarnedDetailSheet(
                creditsEarned: resolvedCreditsEarned,
                creditsRequired: resolvedGraduationCreditsRequired,
                buckets: buckets,
                programsBreakdown: breakdown
            )
        }
        .onChange(of: isInspectorPresented) { _, shown in
            academicsScene.statsSidebarShown = shown
        }
        .onAppear {
            
            collegePersistence.fetchSemesters()
            collegePersistence.fetchProfile()
            collegePersistence.reconcileDeclaredProgramDegreeMetadata()
            academicsScene.statsSidebarShown = isInspectorPresented
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = toolbarDispatcher.register(owner: .academics) { action in
                handleAcademicsToolbarAction(action)
            }

            guard !hasAnimatedIn else { return }
            hasAnimatedIn = true
        }
        .onDisappear {
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeAcademicsAddCourse)) { _ in
            handleAcademicsToolbarAction(.academics(.addCourse))
        }
    }

    private func handleAcademicsToolbarAction(_ action: ToolbarAction) {
        guard case .academics(let academicsAction) = action else { return }
        switch academicsAction {
        case .statsSidebarToggle:
            withAnimation(DesignSystem.Motion.springOrEase(reduceMotion: motionReduced)) {
                isInspectorPresented.toggle()
                academicsScene.statsSidebarShown = isInspectorPresented
            }
        case .addCourse:
            let activePlanSemesters = collegePersistence.getActivePlan()?.semestersArray ?? []
            let source = activePlanSemesters.isEmpty ? collegePersistence.semesters : activePlanSemesters
            let semester = AcademicTermResolver.resolveCurrentSemester(from: source)
                ?? source.first(where: { !$0.isPlanned })
                ?? source.last
            if let semesterID = semester?.id {
                modalCoordinator.activeModal = .addCatalogCourse(semesterID: semesterID)
            } else {
                modalCoordinator.activeModal = .addCatalogCourseGlobal(tagAsGenEd: false)
            }
        }
    }

    private var isCourseDashboardActive: Bool {
        if case .courseDashboard = modalCoordinator.activeModal { return true }
        return false
    }

    private static func formatPlannerGPA(_ snapshot: AcademicMetricsSnapshot?) -> String {
        guard let g = snapshot?.cumulativeGPA else { return "—" }
        return String(format: "%.2f", g)
    }

    // MARK: - Semester GPA helper

    private func semesterGPA(_ semester: PlannerSemester) -> Double? {
        func gradePoints(_ grade: String) -> Double? {
            let g = grade.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let excluded: Set<String> = ["P","PASS","S","SAT","W","WD","I","INC","AU","NG","NR"]
            if excluded.contains(g) { return nil }
            switch g {
            case "A+","A": return 4.0
            case "A-": return 3.7
            case "B+": return 3.3
            case "B": return 3.0
            case "B-": return 2.7
            case "C+": return 2.3
            case "C": return 2.0
            case "C-": return 1.7
            case "D+": return 1.3
            case "D": return 1.0
            case "D-": return 0.7
            case "F": return 0.0
            default:
                let stripped = g.replacingOccurrences(of: "%", with: "")
                if let pct = Double(stripped) {
                    switch pct {
                    case 93...: return 4.0
                    case 90..<93: return 3.7
                    case 87..<90: return 3.3
                    case 83..<87: return 3.0
                    case 80..<83: return 2.7
                    case 77..<80: return 2.3
                    case 73..<77: return 2.0
                    case 70..<73: return 1.7
                    case 67..<70: return 1.3
                    case 63..<67: return 1.0
                    case 60..<63: return 0.7
                    default: return 0.0
                    }
                }
                return nil
            }
        }
        var qp = 0.0; var cr = 0.0
        for c in semester.coursesArray {
            guard c.isCompleted, let g = c.grade, !g.isEmpty,
                  let pts = gradePoints(g) else { continue }
            qp += pts * Double(c.credits)
            cr += Double(c.credits)
        }
        return cr > 0 ? (qp / cr * 100).rounded() / 100 : nil
    }

    // Legacy `mainCard / cardInnerHeader / splitContent / degreeCardsSection /
    // semesterListSection / legendDot` helpers powered the old horizontal-dashboard
    // layout. They were removed when this view was restructured to the new
    // `AcademicsLeftStatsSidebar` + wide Requirements canvas in `body`. Their
    // backing helper types (`AcademicsDegreeCard`, `LandscapeDashboard`, etc.)
    // remain in this file as `private struct`s for possible reuse later.
}


