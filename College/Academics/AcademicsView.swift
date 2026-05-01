// AcademicsView.swift
// Semester Planner — the "Academics" tab (card-shell pattern aligned with Profile).

import SwiftUI
import CoreData

// MARK: - Motion Infrastructure

private enum AcademicsMotion {
    static let cardStaggerStep: Double = 0.045
    static let revealDuration: Double = 0.30
    static let reducedRevealDuration: Double = 0.10
    static let hoverDuration: Double = 0.18
}

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
                    context.coreDataManager.fetchPlans()
                    onProgress(1)
                }
            )
        )
    }
}

private struct AcademicsEntranceModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 12))
            .scaleEffect(isVisible ? 1 : (reduceMotion ? 1 : 0.985), anchor: .top)
            .animation(
                reduceMotion
                    ? .easeOut(duration: AcademicsMotion.reducedRevealDuration)
                    : .spring(response: AcademicsMotion.revealDuration, dampingFraction: 0.88)
                        .delay(Double(index) * AcademicsMotion.cardStaggerStep),
                value: isVisible
            )
    }
}

private struct PressableCardStyle: ButtonStyle {
    var reduceMotion: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.spring(response: 0.10, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct AcademicsScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - AcademicsView

struct AcademicsView: View {
    @Binding var activePage: AppPage
    @Binding var isInspectorPresented: Bool

    @EnvironmentObject private var academicMetricsStore: AcademicMetricsStore
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator

    @EnvironmentObject private var toolbarCoordinator: AppToolbarCoordinator

    @FetchRequest(fetchRequest: AcademicsView.profileRequest)
    private var profiles: FetchedResults<ProfileEntity>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "year", ascending: false),
            NSSortDescriptor(key: "seasonOrder", ascending: false),
        ]
    ) private var semesters: FetchedResults<SemesterEntity>

    private static var profileRequest: NSFetchRequest<ProfileEntity> {
        let r = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
        r.fetchLimit = 1
        r.sortDescriptors = []
        return r
    }

    private var profile: ProfileEntity? { profiles.first }

    /// Total credits toward graduation: sum of scraped major+minor requirements, else profile override (no default 120).
    private var resolvedGraduationCreditsRequired: Int {
        let fromSnapshot = academicMetricsStore.snapshot?.creditsRequired ?? 0
        if fromSnapshot > 0 { return fromSnapshot }
        let live = Int(coreDataManager.aggregateDeclaredProgramsRequirementCredits().rounded())
        if live > 0 { return live }
        let pr = Int(profile?.creditsRequired ?? 0)
        return pr > 0 ? pr : 0
    }

    @State private var inspectorWidth: CGFloat = 296
    @StateObject private var linker = CalendarCourseLinker.shared

    @SceneStorage("academics.view.hasAnimatedIn") private var hasAnimatedIn = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    @State private var scrollOffset: CGFloat = 0

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                    .modifier(AcademicsEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        LandscapeDashboard(
                            profile: profile,
                            plannerGPAFormatted: Self.formatPlannerGPA(academicMetricsStore.snapshot),
                            plannerCreditsEarned: academicMetricsStore.snapshot?.completedCreditsTotal ?? Int(profile?.creditsEarned ?? 0),
                            plannerCreditsRequired: resolvedGraduationCreditsRequired
                        )
                        .environmentObject(coreDataManager)
                        .padding(.leading, 16)
                        .padding(.trailing, 32)
                        .modifier(AcademicsEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                        semesterListSection
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                            .modifier(AcademicsEntranceModifier(index: 2, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: AcademicsScrollOffsetKey.self,
                                value: geo.frame(in: .named("academicsScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "academicsScroll")
                .onPreferenceChange(AcademicsScrollOffsetKey.self) { value in
                    scrollOffset = max(0, -value)
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isInspectorPresented {
                Divider()
                    .overlay(
                        Color.clear
                            .frame(width: 8)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let proposed = inspectorWidth - value.translation.width
                                        inspectorWidth = min(max(proposed, 220), 420)
                                    }
                            )
                            .pointerStyle(.columnResize(directions: .all))
                    )

                AcademicsAuditPanel(
                    majors: coreDataManager.resolvedMajorNames(),
                    minors: coreDataManager.resolvedMinorNames(),
                    activePage: $activePage,
                    isInspectorPresented: $isInspectorPresented
                )
                .frame(width: inspectorWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color.secondary.opacity(0.04))
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.interactiveSpring(), value: inspectorWidth)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isInspectorPresented)
        .background(.windowBackground)
        .background(Material.regular)
        .onAppear {
            toolbarCoordinator.onAcademicsSidebarToggle = {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    toolbarCoordinator.academicsSidebarShown.toggle()
                }
            }
            
            guard !hasAnimatedIn else { return }
            withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.30, dampingFraction: 0.88)) {
                hasAnimatedIn = true
            }
        }
    }

    private var headerSection: some View {
        let subtitleOpacity = motionReduced ? 1.0 : max(0, 1.0 - Double(scrollOffset) / 40.0)
        let subtitleSpacing = motionReduced ? 4.0 : max(0, 4.0 - Double(scrollOffset) / 10.0)
        return UnifiedActionHeader(
            title: AppPage.academics.displayTitle,
            topPadding: 0,
            horizontalPadding: 0,
            bottomPadding: 0,
            titleToContentSpacing: subtitleSpacing
        ) {
            Text("Plan semesters and track requirement progress")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(subtitleOpacity)
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

    private func semesterGPA(_ semester: SemesterEntity) -> Double? {
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
            qp += pts * Double(c.credits); cr += Double(c.credits)
        }
        return cr > 0 ? (qp / cr * 100).rounded() / 100 : nil
    }

    // MARK: - Legend dot helper

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(DesignSystem.Fonts.main(size: 10)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Main card

    private var mainCard: some View {
        VStack(spacing: 0) {
            cardInnerHeader
            // Auto-linked banner
            if !linker.newCoursesFound.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-linked from your calendar")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(linker.newCoursesFound.joined(separator: ", "))
                            .font(DesignSystem.Fonts.main(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            linker.newCoursesFound.removeAll()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.08))
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            splitContent
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: linker.newCoursesFound.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    // MARK: - Card inner header

    private var cardInnerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Academic Journey")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Semester Planner")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {} label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                    Text("History")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {} label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                    Text("Save Plan")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.22), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }

    // MARK: - Split: left scroll + right audit panel

    private var splitContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // ── Left: scrollable main content ────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    degreeCardsSection
                    semesterListSection
                }
                .padding(28)
            }
            .scrollBounceBehavior(.basedOnSize)

            // ── Divider ───────────────────────────────────────────────────
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            // ── Right: audit sidebar ──────────────────────────────────────
            AcademicsAuditPanel(
                majors: coreDataManager.resolvedMajorNames(),
                minors: coreDataManager.resolvedMinorNames(),
                activePage: $activePage,
                isInspectorPresented: $isInspectorPresented
            )
            .frame(width: inspectorWidth)
            .animation(.interactiveSpring(), value: inspectorWidth)
        }
    }

    // MARK: - Degree cards section

    @ViewBuilder
    private var degreeCardsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section heading
            HStack(spacing: 10) {
                Text("Current Degrees")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)

                let sec = (profile?.secondaryMajor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !sec.isEmpty {
                    Text("DUAL DEGREE")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            // Cards
            HStack(alignment: .top, spacing: 16) {
                let majors = coreDataManager.resolvedMajorNames()
                let minors = coreDataManager.resolvedMinorNames()
                let major = majors.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let minor = minors.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let primaryProgress = major.isEmpty
                    ? CoreDataManager.CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
                    : coreDataManager.majorRequirementsCreditsProgress(forMajorDisplay: major)
                let secondaryName = majors.dropFirst().first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let secondaryProgress = secondaryName.isEmpty
                    ? CoreDataManager.CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
                    : coreDataManager.majorRequirementsCreditsProgress(forMajorDisplay: secondaryName)
                let minorProgress = minor.isEmpty
                    ? CoreDataManager.CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
                    : coreDataManager.minorRequirementsCreditsProgress(forMinorDisplay: minor)

                // Primary degree
                AcademicsDegreeCard(
                    badge: "DEGREE 1",
                    badgeColor: Color.accentColor,
                    title: major.isEmpty ? "Add Your Major" : major,
                    circleColor: Color.accentColor,
                    progress: primaryProgress,
                    rows: major.isEmpty ? [] : [
                        AcademicsDegreeCard.BarRow(
                            label: "Major: \(major)",
                            progress: primaryProgress,
                            color: Color.accentColor
                        ),
                    ] + (minor.isEmpty ? [] : [
                        AcademicsDegreeCard.BarRow(
                            label: "Minor: \(minor)",
                            progress: minorProgress,
                            color: .teal
                        ),
                    ])
                )

                // Secondary degree or credits fallback
                let sec = secondaryName
                if !sec.isEmpty {
                    AcademicsDegreeCard(
                        badge: "DEGREE 2",
                        badgeColor: .green,
                        title: sec,
                        circleColor: .green,
                        progress: secondaryProgress,
                        rows: [
                            AcademicsDegreeCard.BarRow(
                                label: "Major: \(sec)",
                                progress: secondaryProgress,
                                color: .green
                            ),
                        ]
                    )
                } else {
                    let earned = Double(semesters.reduce(0) { $0 + $1.totalCredits })
                    let agg = coreDataManager.aggregateDeclaredProgramsRequirementCredits()
                    let profileReq = Double(profile?.creditsRequired ?? 0)
                    let required = agg > 0 ? agg : profileReq
                    let credProg = CoreDataManager.CreditsProgressSummary(
                        completed: earned,
                        required: required,
                        fraction: required > 0 ? min(earned / required, 1) : 0
                    )
                    AcademicsDegreeCard(
                        badge: "CREDITS",
                        badgeColor: .green,
                        title: "Credits Progress",
                        circleColor: .green,
                        progress: credProg,
                        rows: [
                            AcademicsDegreeCard.BarRow(
                                label: "Credits Earned",
                                progress: credProg,
                                color: .green
                            ),
                        ]
                    )
                }
            }
        }
    }

    // MARK: - Semester list section

    @ViewBuilder
    private var semesterListSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Cumulative stats bar ──────────────────────────────────────
            if let prof = profile {
                CumulativeStatsBar(
                    profile: prof,
                    semesters: Array(semesters),
                    sapStats: coreDataManager.sapStats(),
                    graduationCreditsRequired: resolvedGraduationCreditsRequired
                )
            }

            VStack(alignment: .leading, spacing: 20) {
                ForEach(semesters) { semester in
                    AcademicsSemesterSection(semester: semester) {
                        modalCoordinator.activeModal = .addCatalogCourse(semesterObjectID: semester.objectID)
                    }
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.5)
                            .scaleEffect(phase.isIdentity ? 1 : 0.96, anchor: .top)
                            .offset(y: phase.isIdentity ? 0 : 8)
                    }
                }
            }
            .scrollTargetLayout()

            // Add Semester
            Button {
                modalCoordinator.activeModal = .addSemester
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16))
                        .symbolEffect(.bounce, value: hasAnimatedIn)
                    Text("Add Semester")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundStyle(Color.primary.opacity(0.15))
                )
            }
            .buttonStyle(PressableCardStyle(reduceMotion: motionReduced))
        }
    }
}

// MARK: - Degree Progress Card

private struct AcademicsDegreeCard: View {
    struct BarRow {
        let label: String
        let progress: CoreDataManager.CreditsProgressSummary
        let color: Color
    }

    let badge: String
    let badgeColor: Color
    let title: String
    let circleColor: Color
    let progress: CoreDataManager.CreditsProgressSummary
    let rows: [BarRow]

    @State private var isCardHovered = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pct: Int { Int((progress.fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row + progress circle
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(badge)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .tracking(0.8)
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(progress.fraction) : 0)
                        .stroke(circleColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48)
                .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)
            }

            Spacer(minLength: 0)

            // Progress bars
            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    let row = rows[i]
                    VStack(spacing: 4) {
                        HStack {
                            Text(row.label)
                                .font(DesignSystem.Fonts.main(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(
                                row.progress.requiredRoundedInt > 0
                                    ? "\(row.progress.completedRoundedInt)/\(row.progress.requiredRoundedInt) Cr"
                                    : "\(row.progress.completedRoundedInt) Cr"
                            )
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(row.color)
                                    .frame(
                                        width: appeared ? max(0, geo.size.width * CGFloat(row.progress.fraction)) : 0,
                                        height: 6
                                    )
                                    .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .scaleEffect(isCardHovered && !reduceMotion ? 1.015 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isCardHovered)
        .onHover { isCardHovered = $0 }
        .pointerStyle(.link)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Cumulative Stats Bar

private struct CumulativeStatsBar: View {
    let profile: ProfileEntity
    let semesters: [SemesterEntity]
    let sapStats: (attempted: Int, completed: Int, rate: Double)
    /// From scraped programs + minors (or profile); 0 means unknown.
    let graduationCreditsRequired: Int

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    private var completedCr: Int {
        var total = 0
        for s in semesters { for c in s.coursesArray where c.isCompleted { total += Int(c.credits) } }
        return total
    }
    private var inProgressCr: Int {
        var total = 0
        for s in semesters {
            for c in s.coursesArray {
                let st = c.status ?? ""
                if st == "In Progress" || st == "In-Progress" { total += Int(c.credits) }
            }
        }
        return total
    }
    private var plannedCr: Int {
        var total = 0
        for s in semesters {
            for c in s.coursesArray where (c.status ?? "") == "Planned" { total += Int(c.credits) }
        }
        return total
    }
    private var required: Int {
        if graduationCreditsRequired > 0 { return graduationCreditsRequired }
        if profile.creditsRequired > 0 { return Int(profile.creditsRequired) }
        return 0
    }
    private var remaining: Int { max(0, required - completedCr - inProgressCr - plannedCr) }
    private var gpa: Double { profile.gpa }

    private var gpaColor: Color {
        if gpa >= 3.5 { return .green }
        if gpa >= 2.0 { return Color.accentColor }
        return .red
    }
    private var gpaText: String { gpa > 0 ? String(format: "%.2f", gpa) : "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cumulative GPA")
                        .font(DesignSystem.Fonts.main(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(gpaText)
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundStyle(gpaColor)
                        .contentTransition(motionReduced ? .opacity : .numericText(value: gpa))
                        .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: gpaText)
                }
                Divider().frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Credits Earned")
                        .font(DesignSystem.Fonts.main(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(required > 0 ? "\(completedCr) / \(required)" : "\(completedCr) cr earned")
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundStyle(.secondary)
                        .contentTransition(motionReduced ? .opacity : .numericText(value: Double(completedCr)))
                        .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: completedCr)
                }
                Spacer()
                if sapStats.attempted > 0 {
                    let sapColor: Color = sapStats.rate >= 0.67 ? .green : .red
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SAP Rate")
                            .font(DesignSystem.Fonts.main(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.0f%%", sapStats.rate * 100))
                            .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                            .foregroundStyle(sapColor)
                            .contentTransition(motionReduced ? .opacity : .numericText(value: sapStats.rate))
                            .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: sapStats.rate)
                    }
                }
            }
            // Credits path bar
            CumulativeProgressBar(completedCr: completedCr, inProgressCr: inProgressCr,
                                   plannedCr: plannedCr, required: required)
            HStack(spacing: 12) {
                legendDot(color: .green, label: "Completed \(completedCr) cr")
                legendDot(color: .accentColor, label: "In Progress \(inProgressCr) cr")
                legendDot(color: Color.accentColor.opacity(0.35), label: "Planned \(plannedCr) cr")
                legendDot(color: Color.primary.opacity(0.10), label: "Remaining \(remaining) cr")
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1))
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(DesignSystem.Fonts.main(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct CumulativeProgressBar: View {
    let completedCr: Int
    let inProgressCr: Int
    let plannedCr: Int
    let required: Int

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                let total = max(Double(required), 1.0)
                let scale = appeared ? 1.0 : 0.0
                let cFrac = min(Double(completedCr) / total, 1.0) * scale
                let iFrac = min(Double(inProgressCr) / total, 1.0 - cFrac) * scale
                let pFrac = min(Double(plannedCr) / total, 1.0 - cFrac - iFrac) * scale
                let rFrac = max(0.0, 1.0 - cFrac - iFrac - pFrac)
                if cFrac > 0 { Rectangle().fill(Color.green).frame(width: geo.size.width * cFrac) }
                if iFrac > 0 { Rectangle().fill(Color.accentColor).frame(width: geo.size.width * iFrac) }
                if pFrac > 0 { Rectangle().fill(Color.accentColor.opacity(0.35)).frame(width: geo.size.width * pFrac) }
                if rFrac > 0 { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: geo.size.width * rFrac) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .animation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.15), value: appeared)
        }
        .frame(height: 8)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.15)) {
                    appeared = true
                }
            }
        }
    }
}

// MARK: - Semester Section

private struct AcademicsSemesterSection: View {
    @ObservedObject var semester: SemesterEntity
    let onAddCourse: () -> Void

    @State private var addCourseBounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var season: String {
        (semester.season ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var year: Int { Int(semester.year) }

    private var accentColor: Color {
        switch season.lowercased() {
        case "spring": return .indigo
        case "summer": return .green
        case "fall":   return .orange
        case "winter": return .cyan
        default: return .accentColor
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Section header
                HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 4, height: 36)

                Text(season.isEmpty ? "Semester \(String(year))" : "\(season) \(String(year))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                Text("\(semester.totalCredits) Credits")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)

                let semGPA: Double? = {
                    func gp(_ g: String) -> Double? {
                        let e: Set<String> = ["P","PASS","W","WD","I","INC","AU"]
                        let u = g.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if e.contains(u) { return nil }
                        switch u {
                        case "A+","A": return 4.0; case "A-": return 3.7; case "B+": return 3.3
                        case "B": return 3.0; case "B-": return 2.7; case "C+": return 2.3
                        case "C": return 2.0; case "C-": return 1.7; case "D+": return 1.3
                        case "D": return 1.0; case "D-": return 0.7; case "F": return 0.0
                        default: return nil
                        }
                    }
                    var qp = 0.0, cr = 0.0
                    for c in semester.coursesArray where c.isCompleted {
                        guard let g = c.grade, !g.isEmpty, let pts = gp(g) else { continue }
                        qp += pts * Double(c.credits); cr += Double(c.credits)
                    }
                    return cr > 0 ? (qp/cr*100).rounded()/100 : nil
                }()
                if let gpa = semGPA {
                    Text(String(format: "%.2f GPA", gpa))
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(gpa >= 3.0 ? Color.green : gpa >= 2.0 ? Color.orange : Color.red)
                }
                Spacer()

                Button {
                    addCourseBounce.toggle()
                    onAddCourse()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .symbolEffect(.bounce, value: addCourseBounce)
                }
                .buttonStyle(PressableCardStyle(reduceMotion: reduceMotion))
                .pointerStyle(.link)
                .help(String(localized: "academics.semester.add_course_help"))
                .sensoryFeedback(.impact(weight: .light), trigger: addCourseBounce)
            }

            // Course rows + add button
            VStack(spacing: 0) {
                let courses = semester.coursesArray
                ForEach(Array(courses.enumerated()), id: \.element.objectID) { index, course in
                    AcademicsCourseRow(course: course)

                    if index < courses.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(12)
        }
        }
}

    }

// MARK: - Course Row

private struct AcademicsCourseRow: View {
    @ObservedObject var course: CourseEntity
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var coreDataManager: CoreDataManager

    /// Set by the async catalog scour when no title is available on the entity.
    @State private var scouredTitle: String? = nil
    @State private var isHovered = false

    private var code: String        { course.code   ?? "" }
    private var name: String        { course.name   ?? "" }
    private var credits: Int        { Int(course.credits) }
    private var status: String      { course.status ?? "Draft" }
    /// Prefers the verified catalog title; falls back to scoured result, then stored name.
    private var catalogTitle: String {
        let c = code.replacingOccurrences(of: " ", with: "").uppercased()
        if let t = course.catalogCourse?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !t.isEmpty,
           t.replacingOccurrences(of: " ", with: "").uppercased() != c { return t }
        if let t = scouredTitle, !t.isEmpty,
           t.replacingOccurrences(of: " ", with: "").uppercased() != c { return t }
        // Only show stored name if it's genuinely different from the code
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty, n.replacingOccurrences(of: " ", with: "").uppercased() != c { return n }
        return code.isEmpty ? "Untitled" : code
    }

    /// True when the course's semester ended before today.
    private var isPastSemester: Bool {
        AcademicsCourseSchedule.semesterHasEnded(course)
    }
    /// Shows "Completed" for past-semester courses regardless of stored status (shared with requirements breakdown).
    private var displayStatus: String {
        AcademicsCourseSchedule.displayStatus(course: course)
    }
    /// True when the semester has passed but the user never marked the course completed.
    private var needsInfoFill: Bool {
        isPastSemester && !status.lowercased().contains("complet")
    }

    private var dept: String { String(code.prefix(while: { $0.isLetter })) }

    private var abbr: String {
        String(dept.prefix(3)).uppercased()
    }

    private var subjectColor: Color {
        let p = dept.lowercased()
        switch p {
        case "cs", "cse":        return .indigo
        case "mat", "math", "mth": return .cyan
        case "phy", "phys":      return .purple
        case "che", "chem":      return .red
        case "bio":              return .green
        case "eco", "econ":      return .mint
        case "eng", "engl":      return .orange
        case "sta", "stat":      return .orange
        case "psy", "psyc":      return .pink
        case "soc", "socl":      return .purple
        case "his", "hist":      return .brown
        default:                 return .accentColor
        }
    }

    private var statusTextColor: Color {
        let s = displayStatus.lowercased()
        if s.contains("enroll") || s.contains("in progress") { return .green }
        if s.contains("complet")                              { return .accentColor }
        if s.contains("waitlist")                            { return .orange }
        return .secondary
    }

    private var subjectPrefix: String {
        String(dept.prefix(3)).uppercased()
    }

    private var majorLabel: String {
        let p = dept.lowercased()
        switch p {
        case "cs", "cse":                  return "Computer Science Major"
        case "mat", "math", "mth":         return "Mathematics"
        case "eco", "econ":                return "Economics"
        case "sta", "stat":                return "Statistics"
        case "phy", "phys":                return "Physics"
        case "che", "chem":                return "Chemistry"
        case "bio", "biol":                return "Biology"
        case "eng", "engl":                return "English"
        case "psy", "psyc":                return "Psychology"
        case "soc", "socl":                return "Sociology"
        case "his", "hist":                return "History"
        case "mga", "mgt", "mgm", "mgq", "mis", "mkt", "fin", "acc", "oba", "bus":
                                           return "Business Administration Major"
        case "psc", "pol", "pols":         return "Political Science"
        case "nsg", "nrs":                 return "Nursing Major"
        case "ams", "aas":                 return "American Studies"
        case "geo", "geos":                return "Geosciences"
        case "art":                        return "Art History"
        case "mus":                        return "Music"
        default:
            if p.isEmpty { return "Gen Ed" }
            return p.prefix(1).uppercased() + p.dropFirst()
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Subject badge square
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(subjectColor.opacity(0.12))
                Text(abbr.isEmpty ? "?" : abbr)
                    .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                    .foregroundColor(subjectColor)
            }
            .frame(width: 40, height: 40)

            // Course info
            VStack(alignment: .leading, spacing: 3) {
                let displayText: String = {
                    if code.isEmpty { return catalogTitle }
                    // Only append " - title" when catalogTitle is genuinely different from code
                    let cNorm = code.replacingOccurrences(of: " ", with: "").uppercased()
                    let tNorm = catalogTitle.replacingOccurrences(of: " ", with: "").uppercased()
                    return tNorm == cNorm ? code : "\(code) - \(catalogTitle)"
                }()
                Text(displayText)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("\(credits) Cr")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 3, height: 3)

                    if !subjectPrefix.isEmpty {
                        Text(subjectPrefix)
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(subjectColor)
                    }
                    Text(majorLabel)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                        .foregroundColor(subjectColor.opacity(0.92))
                }
            }

            Spacer()

            // Auto-linked badge
            if course.autoLinked {
                HStack(spacing: 3) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 9, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text("Auto")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                }
                .foregroundStyle(.purple)
                .help("Auto-created from your calendar events")
            }

            // "Need to fill information" warning tag for past-semester courses
            if needsInfoFill {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text("Need to fill in information")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                }
                .foregroundStyle(.orange)
            }

                        // Status (no filled chip — reads against the card material)
                        Text(displayStatus.uppercased())
                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                            .foregroundStyle(statusTextColor)
                            .animation(.easeInOut(duration: 0.24), value: statusTextColor)

            // Grade badge
            if let grade = course.grade, !grade.isEmpty {
                Text(grade)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Season warning badge
            let offered = course.catalogCourse?.typicallyOffered?.lowercased() ?? ""
            let semSeason = (course.semester?.season ?? "").lowercased()
            let hasSeasonConflict: Bool = {
                if offered.isEmpty || semSeason.isEmpty { return false }
                let fallOnly = offered.contains("fall") && !offered.contains("spring") && !offered.contains("summer")
                let springOnly = offered.contains("spring") && !offered.contains("fall") && !offered.contains("summer")
                if fallOnly && semSeason == "spring" { return true }
                if springOnly && semSeason == "fall" { return true }
                return false
            }()
            if hasSeasonConflict {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help("Typically offered \(course.catalogCourse?.typicallyOffered ?? "") only")
            }

            // Course dashboard redirect button
            Button {
                let codeStr = code.isEmpty ? name : code
                let creditsStr = credits > 0 ? "\(credits)" : ""
                modalCoordinator.activeModal = .courseDashboard(
                    courseCode: codeStr,
                    defaultCourseName: name,
                    defaultCreditsText: creditsStr,
                    courseObjectID: course.objectID
                )
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            let codeStr = code.isEmpty ? name : code
            let creditsStr = credits > 0 ? "\(credits)" : ""
            modalCoordinator.activeModal = .editCourse(
                ModalCoordinator.CourseEditSelection(
                    courseCode: codeStr,
                    defaultCourseName: name,
                    defaultCreditsText: creditsStr
                )
            )
        }
        .contextMenu {
            Button {
                course.isCompleted.toggle()
                try? coreDataManager.viewContext.save()
            } label: {
                Label(course.isCompleted ? "Mark as Incomplete" : "Mark as Completed", systemImage: course.isCompleted ? "xmark.circle" : "checkmark.circle")
            }
            
            Button {
                let codeStr = code.isEmpty ? name : code
                let creditsStr = credits > 0 ? "\(credits)" : ""
                modalCoordinator.activeModal = .editCourse(
                    ModalCoordinator.CourseEditSelection(
                        courseCode: codeStr,
                        defaultCourseName: name,
                        defaultCreditsText: creditsStr
                    )
                )
            } label: {
                Label("Change Credits", systemImage: "number.circle")
            }
            
            /* No direct syllabus action available from row here, but adding placeholder as requested */
            Button {
                let codeStr = code.isEmpty ? name : code
                let creditsStr = credits > 0 ? "\(credits)" : ""
                modalCoordinator.activeModal = .courseDashboard(
                    courseCode: codeStr,
                    defaultCourseName: name,
                    defaultCreditsText: creditsStr,
                    courseObjectID: course.objectID
                )
            } label: {
                Label("View Syllabus", systemImage: "doc.text")
            }

            Divider()

            Button(role: .destructive) {
                let deletedID = course.objectID
                coreDataManager.deleteCourse(course)
                if case let .courseDashboard(_, _, _, coID) = modalCoordinator.activeModal, coID == deletedID {
                    modalCoordinator.activeModal = nil
                    modalCoordinator.courseDashboardTaskOverlay = nil
                }
            } label: {
                Label("Remove Course", systemImage: "trash")
            }
        }
        .task(id: course.objectID) {
            scouredTitle = nil
            await scourTitle()
        }
    }

    @MainActor
    private func scourTitle() async {
        let rawCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawCode.isEmpty else { return }
        // Skip if we already have a real title.
        // Normalize spaces+case so "MGS 425" is NOT treated as a real title for code "MGS425".
        let rawName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameIsRealTitle = !rawName.isEmpty &&
            rawName.replacingOccurrences(of: " ", with: "").uppercased() !=
            rawCode.replacingOccurrences(of: " ", with: "").uppercased()
        if nameIsRealTitle { return }
        if let t = course.catalogCourse?.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        var title: String?

        if let catalog = CoreDataManager.shared.fetchCatalogCourseForCodeBroadSearch(rawCode) {
            title = catalog.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if course.catalogCourse == nil {
                course.catalogCourse = catalog
            }
        }

        if title == nil || title?.isEmpty == true {
            // Strip trailing alpha section suffixes: CSE220LEC -> CSE220
            let stripped = rawCode.replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "",
                                                         options: .regularExpression)
                                  .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty && stripped.caseInsensitiveCompare(rawCode) != .orderedSame,
               let catalog = CoreDataManager.shared.fetchCatalogCourseForCodeBroadSearch(stripped) {
                title = catalog.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                if course.catalogCourse == nil {
                    course.catalogCourse = catalog
                }
            }
        }

        guard let found = title, !found.isEmpty else { return }
        scouredTitle = found

        // Wire the relationship for future loads
        try? CoreDataManager.shared.viewContext.save()
    }
}

// MARK: - Semester row ↔ requirement breakdown (shared rules)

/// Progress for a single requirement course row, derived from planner courses matching that code.
enum RequirementPlanProgress: Int, Comparable, Equatable {
    /// No matching course on any semester.
    case notOnPlan = 0
    /// On a semester but not active / not finished (draft, future term, etc.).
    case planned = 1
    case inProgress = 2
    case completed = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Keeps `AcademicsCourseRow` and the requirements breakdown on the same completion rules.
enum AcademicsCourseSchedule {
    static func semesterHasEnded(_ course: CourseEntity, asOf today: Date = Date()) -> Bool {
        guard let sem = course.semester else { return false }
        let yr = Int(sem.year)
        let month: Int
        switch (sem.season ?? "").lowercased() {
        case "winter": month = 1
        case "spring": month = 5
        case "summer": month = 8
        default:       month = 12
        }
        let end = Calendar.current.date(from: DateComponents(year: yr, month: month, day: 28)) ?? .distantPast
        return end < today
    }

    /// Same string the semester card shows as status (including past-term “Completed” override).
    static func displayStatus(course: CourseEntity, asOf today: Date = Date()) -> String {
        let status = course.status ?? "Draft"
        if semesterHasEnded(course, asOf: today), !status.lowercased().contains("complet") {
            return "Completed"
        }
        return status
    }

    /// Counts for degree requirement math and green checkmarks — not just the `isCompleted` Core Data flag.
    static func countsTowardRequirementCompletion(_ course: CourseEntity, asOf today: Date = Date()) -> Bool {
        if course.isCompleted { return true }
        let shown = displayStatus(course: course, asOf: today).lowercased()
        if shown.contains("incomplete") { return false }
        if shown.contains("complet") { return true }
        return false
    }

    static func singleCoursePlanProgress(_ course: CourseEntity, asOf today: Date = Date()) -> RequirementPlanProgress {
        if countsTowardRequirementCompletion(course, asOf: today) { return .completed }
        let raw = (course.status ?? "").lowercased()
        if raw.contains("enroll") || raw.contains("in progress") || raw.contains("registered") { return .inProgress }
        if raw.contains("waitlist") { return .inProgress }
        return .planned
    }

    static func mergeProgress(_ a: RequirementPlanProgress?, _ b: RequirementPlanProgress) -> RequirementPlanProgress {
        Swift.max(a ?? .notOnPlan, b)
    }
}

// MARK: - Detailed Audit Panel

struct AcademicsAuditPanel: View {
    let majors: [String]
    let minors: [String]
    @Binding var activePage: AppPage
    @Binding var isInspectorPresented: Bool

    @EnvironmentObject var coreDataManager: CoreDataManager

    private var auditRefreshToken: String {
        "\(majors.joined(separator: "\u{1e}"))|\(minors.joined(separator: "\u{1e}"))"
    }

    // MARK: Data model

    struct AuditItem: Identifiable {
        let id = UUID()
        let code: String
        let credits: String
        /// Aligned with semester-card status (completed / in progress / on plan / not scheduled).
        let planProgress: RequirementPlanProgress
        let isElective: Bool  // true = from selectFromJSON, false = required

        /// Only `.completed` rows count credit totals toward met requirements.
        var isCompleted: Bool { planProgress == .completed }
    }

    struct AuditCategory: Identifiable {
        let id = UUID()
        let title: String
        let items: [AuditItem]
        let selectCount: Int   // 0 = all required; >0 = "choose N from"
        let creditsRequired: Int
    }

    enum AuditDegreeKind { case major, minor }

    struct AuditDegree: Identifiable {
        let id = UUID()
        let label: String
        let rawName: String
        let kind: AuditDegreeKind
        let color: Color
        let categories: [AuditCategory]
        let programURL: String
        let degreeType: String
    }

    // MARK: State

    @State private var auditDegrees: [AuditDegree] = []
    @State private var expandedCategories: Set<UUID> = []
    @State private var isLoading = false
    @State private var selectedDegreeForDetail: AuditDegree? = nil

    // MARK: Body

    private var hasDeclaredPrograms: Bool {
        let m = majors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let n = minors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return !m.isEmpty || !n.isEmpty
    }

        var body: some View {
        RequirementsBreakdownView(
            primaryMajor: majors.first ?? "",
            hasDeclaredPrograms: hasDeclaredPrograms,
            auditDegrees: auditDegrees,
            isLoading: isLoading,
            expandedCategories: $expandedCategories,
            isInspectorPresented: $isInspectorPresented
        )
        .task(id: auditRefreshToken) {
            await loadAudit()
        }
    }

    private func loadAudit() async {
        isLoading = true

        // Planner progress by normalized course code — same rules as `AcademicsCourseRow` / `AcademicsCourseSchedule`.
        let today = Date()
        // Normalise a code by stripping trailing section suffixes (LEC/LAB/…) and spaces
        // so that enrolled code "CSE191" matches requirement code "CSE 191" or "CSE 191LEC".
        func normaliseCode(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        /// Drop duplicate course codes (by `normaliseCode`) while preserving first-seen order.
        func dedupeCodesPreservingOrder(_ codes: [String]) -> [String] {
            var seen = Set<String>()
            var out: [String] = []
            out.reserveCapacity(codes.count)
            for c in codes {
                let t = c.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                let key = normaliseCode(t)
                if seen.contains(key) { continue }
                seen.insert(key)
                out.append(t)
            }
            return out
        }
        let planCourses = coreDataManager.semesters.flatMap { $0.coursesArray }
        var planProgressByNormCode: [String: RequirementPlanProgress] = [:]
        for c in planCourses {
            guard let raw = c.code, !raw.isEmpty else { continue }
            let k = normaliseCode(raw)
            let piece = AcademicsCourseSchedule.singleCoursePlanProgress(c, asOf: today)
            planProgressByNormCode[k] = AcademicsCourseSchedule.mergeProgress(planProgressByNormCode[k], piece)
        }

        func planProgress(forRequirementCode code: String) -> RequirementPlanProgress {
            planProgressByNormCode[normaliseCode(code)] ?? .notOnPlan
        }

        // Resolve requirements via programURL so that:
        //  • Complex major names like "Business Administration BS - MIS Concentration, BS" resolve correctly.
        //  • Minor requirements are fetched with degreeType "Minor", not the student's major degree type.
        func buildDegree(label: String, rawName: String, kind: AuditDegreeKind, color: Color, programURL: String, degreeType: String) -> AuditDegree? {
            guard !programURL.isEmpty else { return nil }

            let reqs = coreDataManager.getDegreeRequirements(programURL: programURL, degreeType: degreeType)
            guard !reqs.isEmpty else { return nil }

            // Struct for decoding selectFromDetailedJSON
            struct SelectDetail: Decodable { let code: String }

            // Group requirements by requirementCategory
            var orderedKeys: [String] = []
            struct ReqGroup {
                var codes: [String] = []
                var electiveCodes: [String] = []
                var selectN: Int = 0
                var creditsRequired: Int = 0
            }
            var grouped: [String: ReqGroup] = [:]

            for req in reqs {
                let cat = (req.requirementCategory ?? "Requirements")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Mirror CoreDataManager.creditsProgressSummary: UB scrapes often store codes only in
                // `requiredCoursesDetailedJSON`, leaving `requiredCourses` empty — without this the panel stayed empty.
                let codes: [String] = {
                    var out: [String] = []
                    if let raw = req.requiredCourses, !raw.isEmpty {
                        out.append(contentsOf: raw.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                            .filter { !$0.isEmpty })
                    }
                    if let detailed = coreDataManager.decodeDetailedCourseList(req.requiredCoursesDetailedJSON) {
                        out.append(contentsOf: detailed.map {
                            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        }.filter { !$0.isEmpty })
                    }
                    return dedupeCodesPreservingOrder(out)
                }()
                // Parse selectFrom elective codes
                let electiveCodes: [String] = {
                    if let detailed = req.selectFromDetailedJSON, !detailed.isEmpty,
                       let data = detailed.data(using: .utf8),
                       let arr = try? JSONDecoder().decode([SelectDetail].self, from: data) {
                        return dedupeCodesPreservingOrder(
                            arr.map { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                                .filter { !$0.isEmpty }
                        )
                    }
                    if let raw = req.selectFromJSON, !raw.isEmpty,
                       let data = raw.data(using: .utf8),
                       let arr = try? JSONDecoder().decode([String].self, from: data) {
                        return dedupeCodesPreservingOrder(
                            arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }
                        )
                    }
                    return []
                }()
                let selectN = Int(req.selectCount)
                if grouped[cat] == nil {
                    orderedKeys.append(cat)
                    grouped[cat] = ReqGroup(
                        codes: codes,
                        electiveCodes: electiveCodes,
                        selectN: selectN,
                        creditsRequired: Int(req.creditsRequired)
                    )
                } else {
                    grouped[cat]?.codes.append(contentsOf: codes)
                    grouped[cat]?.electiveCodes.append(contentsOf: electiveCodes)
                    if selectN > (grouped[cat]?.selectN ?? 0) { grouped[cat]?.selectN = selectN }
                    if Int(req.creditsRequired) > (grouped[cat]?.creditsRequired ?? 0) {
                        grouped[cat]?.creditsRequired = Int(req.creditsRequired)
                    }
                }
            }

            let categories: [AuditCategory] = orderedKeys.compactMap { key in
                guard let group = grouped[key] else { return nil }
                let shownCodes = Array(dedupeCodesPreservingOrder(group.codes).prefix(7))
                let electiveShown = Array(dedupeCodesPreservingOrder(group.electiveCodes).prefix(8))
                guard !shownCodes.isEmpty || !electiveShown.isEmpty else { return nil }
                let requiredItems = shownCodes.map { code -> AuditItem in
                    let credits = coreDataManager.getCatalogCourse(code: code)
                        .map { c -> String in
                            let t = c.creditsDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
                            return t.isEmpty ? "" : t
                        } ?? ""
                    return AuditItem(code: code, credits: credits, planProgress: planProgress(forRequirementCode: code), isElective: false)
                }
                let electiveItems = electiveShown.map { code -> AuditItem in
                    let credits = coreDataManager.getCatalogCourse(code: code)
                        .map { c -> String in
                            let t = c.creditsDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
                            return t.isEmpty ? "" : t
                        } ?? ""
                    return AuditItem(code: code, credits: credits, planProgress: planProgress(forRequirementCode: code), isElective: true)
                }
                var mergedItems: [AuditItem] = []
                mergedItems.reserveCapacity(requiredItems.count + electiveItems.count)
                for item in requiredItems + electiveItems {
                    let k = normaliseCode(item.code)
                    if let idx = mergedItems.firstIndex(where: { normaliseCode($0.code) == k }) {
                        let existing = mergedItems[idx]
                        let mergedP = AcademicsCourseSchedule.mergeProgress(existing.planProgress, item.planProgress)
                        let elective = existing.isElective && item.isElective
                        mergedItems[idx] = AuditItem(
                            code: existing.code,
                            credits: existing.credits,
                            planProgress: mergedP,
                            isElective: elective
                        )
                    } else {
                        mergedItems.append(item)
                    }
                }
                return AuditCategory(title: key, items: mergedItems, selectCount: group.selectN, creditsRequired: group.creditsRequired)
            }

            guard !categories.isEmpty else { return nil }
            return AuditDegree(label: label, rawName: rawName, kind: kind, color: color, categories: categories, programURL: programURL, degreeType: degreeType)
        }

        let profileDegreeType = (coreDataManager.profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var degrees: [AuditDegree] = []

        let majorList = majors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let majorColors: [Color] = [Color.accentColor, .green, .orange, .cyan, .pink]

        for (idx, name) in majorList.enumerated() {
            let programURL: String? = {
                if idx == 0 {
                    return coreDataManager.resolveSelectedMajorProgramURL()
                        ?? coreDataManager.resolveNonMinorMajorProgramURL(display: name)
                }
                return coreDataManager.resolveNonMinorMajorProgramURL(display: name)
            }()
            guard let url = programURL else { continue }
            let color = majorColors[idx % majorColors.count]
            if let d = buildDegree(
                label: name,
                rawName: name,
                kind: .major,
                color: color,
                programURL: url,
                degreeType: profileDegreeType
            ) {
                degrees.append(d)
            }
        }

        let minorList = minors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let minorColors: [Color] = [.teal, .purple, .indigo]
        for (idx, minName) in minorList.enumerated() {
            guard let minURL = coreDataManager.resolveProgramProgramURL(programDisplay: minName, isMinor: true) else { continue }
            let color = minorColors[idx % minorColors.count]
            if let d = buildDegree(
                label: "Minor: \(minName)",
                rawName: minName,
                kind: .minor,
                color: color,
                programURL: minURL,
                degreeType: "Minor"
            ) {
                degrees.append(d)
            }
        }

        // Auto-expand the first *incomplete* category per degree on first load (met requirements stay collapsed).
        if auditDegrees.isEmpty, !degrees.isEmpty {
            for degree in degrees {
                guard let first = degree.categories.first else { continue }
                let parsed = RequirementBreakdownParser.parseTitle(first.title)
                if !RequirementBreakdownParser.isCategoryDone(category: first, parsed: parsed, items: first.items) {
                    expandedCategories.insert(first.id)
                }
            }
        }

        // GenEd section
        let genEdCourses = planCourses.filter { $0.countsTowardGenEd }
        if !genEdCourses.isEmpty {
            let genEdItems = genEdCourses.map { c -> AuditItem in
                AuditItem(
                    code: c.code ?? "—",
                    credits: "\(c.credits)",
                    planProgress: AcademicsCourseSchedule.singleCoursePlanProgress(c, asOf: today),
                    isElective: false
                )
            }
            let genEdCategory = AuditCategory(
                title: "General Education Courses",
                items: genEdItems,
                selectCount: 0,
                creditsRequired: 0
            )
            let genEdDegree = AuditDegree(
                label: "General Education",
                rawName: "General Education",
                kind: .major,
                color: .orange,
                categories: [genEdCategory],
                programURL: "",
                degreeType: ""
            )
            degrees.append(genEdDegree)
        }

        auditDegrees = degrees
        isLoading = false
    }
}


// MARK: - Academic Landscape UI Extensions

struct LandscapeDashboard: View {
    let profile: ProfileEntity?
    let plannerGPAFormatted: String
    let plannerCreditsEarned: Int
    let plannerCreditsRequired: Int

    @EnvironmentObject private var coreDataManager: CoreDataManager
    @State private var majorProgramsPopover = false
    @State private var minorProgramsPopover = false

    private let majorPalette: [Color] = [Color.accentColor, .orange, .green]
    private let minorPalette: [Color] = [.teal, .purple, .indigo]

    var body: some View {
        let majors = coreDataManager.resolvedMajorNames()
        let minors = coreDataManager.resolvedMinorNames()

        VStack(alignment: .leading, spacing: 24) {
            landscapeProgramRow(
                rowTag: "MAJOR",
                names: majors,
                isMinor: false,
                palette: majorPalette,
                overflowOpen: $majorProgramsPopover
            )

            landscapeProgramRow(
                rowTag: "MINOR",
                names: minors,
                isMinor: true,
                palette: minorPalette,
                overflowOpen: $minorProgramsPopover
            )

            LandscapeTimelineCard(
                totalCredits: Double(plannerCreditsEarned),
                requiredCredits: Double(plannerCreditsRequired),
                expectedGraduation: {
                    guard let s = profile?.expectedGraduation?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
                    return s
                }()
            )
            .padding(.top, 8)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
    }

    private func requirementProgress(isMinor: Bool, name: String) -> CoreDataManager.CreditsProgressSummary {
        if isMinor {
            return coreDataManager.minorRequirementsCreditsProgress(forMinorDisplay: name)
        }
        return coreDataManager.majorRequirementsCreditsProgress(forMajorDisplay: name)
    }

    @ViewBuilder
    private func landscapeProgramRow(
        rowTag: String,
        names: [String],
        isMinor: Bool,
        palette: [Color],
        overflowOpen: Binding<Bool>
    ) -> some View {
        let maxC = ProfileProgramLists.maxTrackColumns
        HStack(spacing: 16) {
            if names.isEmpty {
                LandscapeMajorCard(
                    type: rowTag,
                    name: String(
                        localized: isMinor
                            ? "academics.landscape.no_minors"
                            : "academics.landscape.no_majors",
                        defaultValue: isMinor ? "No minors declared" : "No majors declared"
                    ),
                    gpa: plannerGPAFormatted,
                    progress: CoreDataManager.CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
                    color: .secondary,
                    barColor: .secondary.opacity(0.35)
                )
                .frame(maxWidth: .infinity)
            } else if names.count > maxC {
                ForEach(0..<(maxC - 1), id: \.self) { idx in
                    let name = names[idx]
                    LandscapeMajorCard(
                        type: "\(rowTag) \(idx + 1)",
                        name: name,
                        gpa: plannerGPAFormatted,
                        progress: requirementProgress(isMinor: isMinor, name: name),
                        color: palette[idx % palette.count],
                        barColor: palette[idx % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }

                let extra = Array(names.dropFirst(maxC - 1))
                Button {
                    overflowOpen.wrappedValue.toggle()
                } label: {
                    LandscapeMajorCard(
                        type: "MORE",
                        name: "+\(extra.count) more",
                        gpa: plannerGPAFormatted,
                        progress: CoreDataManager.CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
                        color: palette[(maxC - 1) % palette.count],
                        barColor: palette[(maxC - 1) % palette.count]
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: overflowOpen) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(extra, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 280, minHeight: 140)
                }
            } else {
                ForEach(Array(names.enumerated()), id: \.offset) { slot, name in
                    LandscapeMajorCard(
                        type: "\(rowTag) \(slot + 1)",
                        name: name,
                        gpa: plannerGPAFormatted,
                        progress: requirementProgress(isMinor: isMinor, name: name),
                        color: palette[slot % palette.count],
                        barColor: palette[slot % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct LandscapeMajorCard: View {
    let type: String
    let name: String
    let gpa: String
    let progress: CoreDataManager.CreditsProgressSummary
    let color: Color
    let barColor: Color

    private var creditsTowardRequirementLine: String {
        let req = progress.requiredRoundedInt
        let done = progress.completedRoundedInt
        if req <= 0 { return "Requirement credits TBD" }
        return "\(done)/\(req) cr toward requirement"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(type.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("GPA")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(gpa)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("plan")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48, alignment: .topLeading)
                    .help(name)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(progress.fraction > 0 ? progress.fraction : 0.0))
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [barColor.opacity(0.5), barColor]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text(String(format: "%.0f%%", progress.fraction * 100))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requirement progress")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(creditsTowardRequirementLine)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LandscapeTimelineCard: View {
    let totalCredits: Double
    let requiredCredits: Double
    var expectedGraduation: String?

    var body: some View {
        GroupBox {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Graduation Timeline")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        if let expectedGraduation, !expectedGraduation.isEmpty {
                            Text(expectedGraduation.uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Combined progress across all declared majors and minors")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text("TOTAL CREDIT PROGRESS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        if requiredCredits > 0 {
                            Text("\(Int(totalCredits))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("/ \(Int(requiredCredits)) Credits")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(totalCredits)) cr earned")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                            .frame(maxWidth: .infinity)
                        GeometryReader { geo in
                            let frac = requiredCredits > 0 ? min(1.0, totalCredits / requiredCredits) : 0.0
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: CGFloat(frac) * geo.size.width, height: 8)
                        }
                    }
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(8)
        }
    }
}

struct LandscapeCurriculumCard: View {
    let semester: SemesterEntity
    @State private var isCollapsed = false
    @EnvironmentObject var coreDataManager: CoreDataManager

    var totalSemesterCredits: Int {
        Int(semester.coursesArray.compactMap { Double($0.credits) }.reduce(0, +))
    }

    private func resolvedTitle(for course: CourseEntity) -> String {
        let rawCode = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let codeNorm = rawCode.replacingOccurrences(of: " ", with: "").uppercased()
        let nameNorm = rawName.replacingOccurrences(of: " ", with: "").uppercased()

        if !rawName.isEmpty, nameNorm != codeNorm {
            return rawName
        }

        if let title = course.catalogCourse?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
            return title
        }

        if !rawCode.isEmpty {
            if let catalog = CoreDataManager.shared.fetchCatalogCourseForCodeBroadSearch(rawCode),
               let title = catalog.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty,
               title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
                return title
            }

            // Also try the base code without trailing alpha section suffixes,
            // e.g. "CSE220LEC" -> "CSE220", so catalog titles still resolve.
            let strippedCode = rawCode
                .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !strippedCode.isEmpty, strippedCode.caseInsensitiveCompare(rawCode) != .orderedSame,
               let catalog = CoreDataManager.shared.fetchCatalogCourseForCodeBroadSearch(strippedCode),
               let title = catalog.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty,
               title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
                return title
            }
        }

        return "No title available"
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(semester.name ?? "Current")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !isCollapsed {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("\(totalSemesterCredits) Total Credits")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.up.circle.fill")
                            .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                if !isCollapsed {
                    Table(semester.coursesArray) {
                        TableColumn("Course") { course in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.code ?? "")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(resolvedTitle(for: course))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .contextMenu {
                                Button("Remove Course", role: .destructive) {
                                    coreDataManager.deleteCourse(course)
                                }
                            }
                        }
                        TableColumn("Credits") { course in
                            Text("\(Int(course.credits))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .contextMenu {
                                    Button("Remove Course", role: .destructive) {
                                        coreDataManager.deleteCourse(course)
                                    }
                                }
                        }
                        TableColumn("Requirement") { course in
                            Text(course.status?.uppercased() ?? "CORE")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .contextMenu {
                                    Button("Remove Course", role: .destructive) {
                                        coreDataManager.deleteCourse(course)
                                    }
                                }
                        }
                        TableColumn("Status") { course in
                            HStack(spacing: 4) {
                                Image(systemName: course.isCompleted ? "checkmark.circle.fill" : "clock.fill")
                                    .contentTransition(.symbolEffect(.replace.offUp))
                                Text(course.isCompleted ? "Completed" : "Active")
                                    .contentTransition(.opacity)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(course.isCompleted ? .green : .accentColor)
                            .animation(.spring(response: 0.28, dampingFraction: 0.80), value: course.isCompleted)
                            .padding(.vertical, 8)
                            .contextMenu {
                                Button("Remove Course", role: .destructive) {
                                    coreDataManager.deleteCourse(course)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .alternatingRowBackgrounds(.disabled)
                    .frame(minHeight: CGFloat(semester.coursesArray.count * 46 + 40))
                }
            }
        }
    }
}

// MARK: - Requirements breakdown parsing (titles + credit progress)

/// Shared between audit loading (first-expand) and `RequirementsBreakdownView` UI.
fileprivate enum RequirementBreakdownParser {
    struct ParsedTitle: Equatable {
        var displayTitle: String
        var creditsLabel: String?
        var minCredits: Int?
        var maxCredits: Int?
    }

    /// Pulls `(6 credits)`, `(3-4 Credits)`, etc. out of the category title for a clean heading + right-column catalog label.
    static func parseTitle(_ raw: String) -> ParsedTitle {
        var work = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var minV: Int?
        var maxV: Int?
        var label: String?

        let parenRx = try? NSRegularExpression(pattern: #"(?i)\s*\((\d+)(?:\s*[-–]\s*(\d+))?\s*credits?\)"#, options: [])
        if let parenRx {
            let range = NSRange(work.startIndex..<work.endIndex, in: work)
            if let m = parenRx.firstMatch(in: work, options: [], range: range),
               let r1 = Range(m.range(at: 1), in: work),
               let lo = Int(work[r1]) {
                minV = lo
                if m.range(at: 2).location != NSNotFound,
                   let r2 = Range(m.range(at: 2), in: work),
                   let hi = Int(work[r2]), hi >= lo {
                    maxV = hi
                    label = "\(lo)–\(hi) Credits"
                } else {
                    maxV = lo
                    label = "\(lo) Credits"
                }
                work = parenRx.stringByReplacingMatches(in: work, options: [], range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if label == nil {
            let trailRx = try? NSRegularExpression(pattern: #"(?i)\s+(\d+)(?:\s*[-–]\s*(\d+))?\s*credits?\s*$"#, options: [])
            if let trailRx {
                let range = NSRange(work.startIndex..<work.endIndex, in: work)
                if let m = trailRx.firstMatch(in: work, options: [], range: range),
                   let r1 = Range(m.range(at: 1), in: work),
                   let lo = Int(work[r1]) {
                    minV = lo
                    if m.range(at: 2).location != NSNotFound,
                       let r2 = Range(m.range(at: 2), in: work),
                       let hi = Int(work[r2]), hi >= lo {
                        maxV = hi
                        label = "\(lo)–\(hi) Credits"
                    } else {
                        maxV = lo
                        label = "\(lo) Credits"
                    }
                    work = trailRx.stringByReplacingMatches(in: work, options: [], range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        work = work.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return ParsedTitle(displayTitle: work, creditsLabel: label, minCredits: minV, maxCredits: maxV)
    }

    static func creditValue(from raw: String) -> Int {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        if let direct = Double(text) { return Int(direct.rounded()) }
        let pattern = #"\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let tokenRange = Range(match.range, in: text),
              let numeric = Double(text[tokenRange]) else { return 0 }
        return Int(numeric.rounded())
    }

    static func sumCreditsAll(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        items.map { creditValue(from: $0.credits) }.reduce(0, +)
    }

    static func sumCompletedCredits(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        items.filter(\.isCompleted).map { creditValue(from: $0.credits) }.reduce(0, +)
    }

    static func progressTarget(category: AcademicsAuditPanel.AuditCategory, parsed: ParsedTitle, listedCreditsSum: Int) -> Int {
        if let m = parsed.minCredits, m > 0 { return m }
        if category.creditsRequired > 0 { return category.creditsRequired }
        return listedCreditsSum
    }

    static func isCategoryDone(category: AcademicsAuditPanel.AuditCategory, parsed: ParsedTitle, items: [AcademicsAuditPanel.AuditItem]) -> Bool {
        let completed = sumCompletedCredits(items: items)
        let listed = sumCreditsAll(items: items)
        let target = progressTarget(category: category, parsed: parsed, listedCreditsSum: listed)
        guard target > 0 else { return false }
        return completed >= target
    }

    /// Catalog-style reference lists (e.g. Comparative Politics **List**) — lighter visual tier for dense minors.
    static func isListStyleSubheader(_ displayTitle: String) -> Bool {
        displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"(?i)\blist\s*$"#, options: .regularExpression) != nil
    }
}

struct RequirementsBreakdownView: View {
    var primaryMajor: String
    /// True when Profile lists at least one major or minor (used for empty-state copy).
    var hasDeclaredPrograms: Bool = false
    var auditDegrees: [AcademicsAuditPanel.AuditDegree]
    var isLoading: Bool
    @Binding var expandedCategories: Set<UUID>
    @Binding var isInspectorPresented: Bool

    @State private var hideCompleted: Bool = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("accessibility.reduceMotion") private var prefReduceMotion: Bool = false

    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    /// Non-gray palette for requirements panel text and status rendering.
    private enum Palette {
        static let panelBackground = DesignSystem.Colors.bgMain
        static let primaryText = Color.primary
        static let secondaryText = Color.accentColor
        static let subduedText = Color.accentColor.opacity(0.75)
        static let statusNeutral = Color.orange
    }

    /// Panel title (largest) > degree section label > category row (same body size, weight differs).
    private enum Typography {
        static let panelTitle = Font.system(size: 18, weight: .semibold)
        static let degreeSection = Font.system(size: 13, weight: .semibold)
        static let categoryTitle = Font.system(size: 12, weight: .semibold)
        static let listSubcategoryTitle = Font.system(size: 11, weight: .semibold)
        static let rowMeta = Font.system(size: 12, weight: .medium)
        static let body = Font.system(size: 12, weight: .regular)
        static let bodySemibold = Font.system(size: 12, weight: .semibold)
    }

    /// Aligns expanded rows and collapsed preview chips with the category title (past the disclosure chevron).
    private var categoryBodyLeadingInset: CGFloat { 22 }

    private func contentLeadingInset(listSubheader: Bool) -> CGFloat {
        categoryBodyLeadingInset + (listSubheader ? 8 : 0)
    }

    private var allCategoryIDs: Set<UUID> {
        Set(auditDegrees.flatMap { degree in
            degree.categories.map(\.id)
        })
    }

    @ViewBuilder
    private func collapsedPreview(for items: [AcademicsAuditPanel.AuditItem]) -> some View {
        let extraCount = max(items.count - 2, 0)

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(items.prefix(2))) { item in
                    PillTag(text: item.code, bg: Color.accentColor.opacity(0.16), fg: Palette.secondaryText)
                }
                if extraCount > 0 {
                    Text("+\(extraCount) Options")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                if let first = items.first {
                    PillTag(text: first.code, bg: Color.accentColor.opacity(0.16), fg: Palette.secondaryText)
                }
                if extraCount > 0 {
                    Text("+\(extraCount) Options")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }

            if extraCount > 0 {
                Text("+\(extraCount) Options")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
    
    @EnvironmentObject private var toolbarCoordinator: AppToolbarCoordinator
    
    var body: some View {
        Group {
            if toolbarCoordinator.academicsSidebarShown {
                requirementsSidebar
            }
        }
    }
    
    private var requirementsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            UnifiedActionHeader(
                title: "Requirements Breakdown",
                titleFont: Typography.panelTitle,
                subtitleFont: Typography.rowMeta,
                topPadding: 16,
                horizontalPadding: 24,
                bottomPadding: 16,
                titleToContentSpacing: 10
            ) {
                Toggle("Hide Met", isOn: $hideCompleted)
                    .toggleStyle(.switch)
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: true, vertical: true)
            }
            
            if isLoading {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            Capsule().fill(Color.primary.opacity(0.12)).frame(width: 180, height: 16)
                            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 240, height: 12)
                            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 200, height: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.horizontal, 24)
            } else if auditDegrees.isEmpty {
                Text(
                    hasDeclaredPrograms
                        ? String(
                            localized: "academics.requirements_breakdown.empty_declared",
                            defaultValue: "No requirement course lists matched your declared programs yet. Open Settings and run a catalog sync, or check that major and minor names in Profile match the catalog."
                        )
                        : String(
                            localized: "academics.requirements_breakdown.empty_none",
                            defaultValue: "Add a major in your Profile to see your requirements breakdown here."
                        )
                )
                    .font(Typography.body)
                    .foregroundStyle(Palette.subduedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                List {
                    ForEach(auditDegrees) { degree in
                        Section {
                            ForEach(degree.categories) { category in
                                categoryView(category: category)
                                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                                    .listRowSeparator(.visible, edges: .bottom)
                            }
                        } header: {
                            Text(degree.label.uppercased())
                                .font(Typography.degreeSection)
                                .foregroundStyle(degree.color)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .help(degree.label)
                                .padding(.bottom, 2)
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 36)
                .scrollContentBackground(.hidden)
                .background(Palette.panelBackground)
                .animation(
                    motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86),
                    value: hideCompleted
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.panelBackground)
    }
    
    @ViewBuilder
    private func categoryView(category: AcademicsAuditPanel.AuditCategory) -> some View {
        let items = category.items
        let parsed = RequirementBreakdownParser.parseTitle(category.title)
        let displayTitle = parsed.displayTitle
        let listSubheader = RequirementBreakdownParser.isListStyleSubheader(displayTitle)
        let completedCredits = RequirementBreakdownParser.sumCompletedCredits(items: items)
        let totalListedCredits = RequirementBreakdownParser.sumCreditsAll(items: items)
        let progressTarget = RequirementBreakdownParser.progressTarget(
            category: category,
            parsed: parsed,
            listedCreditsSum: totalListedCredits
        )
        let isDone = RequirementBreakdownParser.isCategoryDone(category: category, parsed: parsed, items: items)
        let isExpanded = expandedCategories.contains(category.id)
        let hasProgressNumbers = progressTarget > 0 || completedCredits > 0
        let isSubsectionRollup = !hasProgressNumbers && category.selectCount > 0 && parsed.creditsLabel == nil
        let trailingLabel: String? = {
            if let lab = parsed.creditsLabel { return lab }
            if category.creditsRequired > 0 { return "\(category.creditsRequired) Credits" }
            if progressTarget > 0 { return "\(progressTarget) Credits" }
            return nil
        }()
        let trailingTooltip: String = {
            var lines: [String] = [category.title]
            if let trailingLabel { lines.append(trailingLabel) }
            if progressTarget > 0 {
                lines.append(
                    String(
                        localized: "academics.requirements_breakdown.tooltip_progress",
                        defaultValue: "Progress: \(completedCredits) of \(progressTarget) credits from your courses count toward this row."
                    )
                )
            }
            return lines.joined(separator: "\n")
        }()
        // Collapsed chip preview only while incomplete; satisfied rows stay clean until the user expands.
        let showCollapsedPillPreview =
            !isDone
            && !isExpanded
            && !items.isEmpty
            && category.creditsRequired > 0
            && category.selectCount > 0
        let bodyInset = contentLeadingInset(listSubheader: listSubheader)

        if !hideCompleted || !isDone {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Button(action: {
                        withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.28, dampingFraction: 0.84)) {
                            if isExpanded {
                                expandedCategories.remove(category.id)
                            } else {
                                expandedCategories.insert(category.id)
                            }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 14, height: 14, alignment: .center)
                            .padding(.top, 2)
                            .animation(
                                motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.80),
                                value: isExpanded
                            )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle)
                            .font(listSubheader ? Typography.listSubcategoryTitle : Typography.categoryTitle)
                            .foregroundStyle(listSubheader ? Palette.secondaryText : Palette.primaryText)
                            .lineLimit(listSubheader ? 2 : 1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.85)
                            .help(category.title)

                        if showCollapsedPillPreview {
                            collapsedPreview(for: items)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 2)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Spacer(minLength: 8)

                    if let trailingLabel {
                        Text(trailingLabel)
                            .font(Typography.rowMeta)
                            .foregroundStyle(isDone ? Color.accentColor : Palette.secondaryText)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: true, vertical: false)
                            .help(trailingTooltip)
                            .padding(.top, 2)
                    } else if isSubsectionRollup {
                        Text(String(localized: "academics.requirements_breakdown.subsection_rollup", defaultValue: "Included in main requirement"))
                            .font(Typography.rowMeta)
                            .foregroundStyle(Palette.subduedText)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, listSubheader ? 8 : 0)
                .padding(.vertical, 4)

                if isExpanded {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            CourseProgressRow(
                                code: item.code,
                                title: item.credits,
                                planProgress: item.planProgress
                            )
                        }
                    }
                    .padding(.leading, bodyInset)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
            }
            .animation(
                motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.30, dampingFraction: 0.86),
                value: isExpanded
            )
            .animation(
                motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.82),
                value: isDone
            )
            .onChange(of: isDone) { wasDone, nowDone in
                if nowDone, !wasDone {
                    withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.28, dampingFraction: 0.84)) {
                        expandedCategories.insert(category.id)
                    }
                }
            }
        }
    }
}

private struct CourseProgressRow: View {
    var code: String
    var title: String
    var planProgress: RequirementPlanProgress

    private var badgeLabel: String {
        switch planProgress {
        case .completed:
            return String(localized: "academics.requirements_breakdown.badge_completed", defaultValue: "COMPLETED")
        case .inProgress:
            return String(localized: "academics.requirements_breakdown.badge_in_progress", defaultValue: "IN PROGRESS")
        case .planned:
            return String(localized: "academics.requirements_breakdown.badge_on_plan", defaultValue: "ON PLAN")
        case .notOnPlan:
            return String(localized: "academics.requirements_breakdown.badge_not_scheduled", defaultValue: "NOT ON PLAN")
        }
    }

    private var statusIconName: String {
        switch planProgress {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "clock.fill"
        case .planned: return "calendar.circle"
        case .notOnPlan: return "circle"
        }
    }

    private var titleColor: Color {
        switch planProgress {
        case .completed: return Color.accentColor.opacity(0.75)
        case .notOnPlan: return .orange
        default: return .primary
        }
    }

    private var subtitleStyle: AnyShapeStyle {
        planProgress == .completed
            ? AnyShapeStyle(Color.accentColor.opacity(0.75))
            : AnyShapeStyle(Color.accentColor)
    }

    private var badgeForeground: Color {
        switch planProgress {
        case .completed, .inProgress: return .green
        case .planned: return .blue
        case .notOnPlan: return .orange
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(code)

                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(subtitleStyle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(title)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: statusIconName)
                Text(badgeLabel)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(badgeForeground)
            .help(badgeLabel)
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 0)
    }
}



private struct PillTag: View {
    var text: String
    var bg: Color
    var fg: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
            .help(text)
    }
}
