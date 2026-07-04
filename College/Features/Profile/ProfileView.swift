// ProfileView.swift
// Feature: Profile
// Purpose: Profile module — CardSurfaceModifier.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

enum ProfileFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "profile",
                title: "Profile snapshot",
                criticality: .bestEffort,
                timeoutSeconds: 0.8,
                retryLimit: 0,
                run: { context, onProgress, _ in
                    LaunchBootstrapCache.fetchProfileIfNeeded()
                    onProgress(1)
                }
            )
        )
    }
}

struct CardSurfaceModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.glassCardBase.background(.ultraThinMaterial))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 40, x: 0, y: 15)
    }
}

extension View {
    func profileCardSurface(padding: CGFloat = 24) -> some View {
        modifier(CardSurfaceModifier(padding: padding))
    }
}

private enum ProfileActiveSheet: Identifiable {
    case advisorPrep
    case editProfile(Profile)
    case addProject(Profile)
    case editProject(Profile, PortfolioProject)
    case addExperience
    case editExperience(Experience)
    case addAchievement
    case editAchievement(Achievement)

    var id: String {
        switch self {
        case .advisorPrep: return "advisorPrep"
        case .editProfile: return "editProfile"
        case .addProject: return "addProject"
        case .editProject(_, let project): return "editProject-\(project.id.uuidString)"
        case .addExperience: return "addExperience"
        case .editExperience(let experience): return "editExperience-\(experience.id.uuidString)"
        case .addAchievement: return "addAchievement"
        case .editAchievement(let achievement): return "editAchievement-\(achievement.id.uuidString)"
        }
    }
}

struct ProfileView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    private var academicMetricsStore: AcademicMetricsStore { container.academicMetricsStore }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var activeSheet: ProfileActiveSheet?
    @State private var toolbarHandlerToken: ToolbarHandlerToken?
    /// Primary-major degree audit credits (same source as Academics `LandscapeDashboard` major ring).
    @State private var primaryMajorProgress = CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
    @State private var plannerRefreshToken = 0

    private var resumeAvailability: ResumeAvailability {
        _ = plannerRefreshToken
        _ = collegePersistence.careerDidChangeToken
        return CareerReadBridge.resumeAvailability(collegePersistence: collegePersistence)
    }

    private var profile: Profile? {
        _ = plannerRefreshToken
        return ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence)
    }

    private var displayedGPA: Double? {
        if let g = academicMetricsStore.snapshot?.cumulativeGPA { return g }
        let stored = collegePersistence.primaryGPA()
        return stored > 0 ? stored : nil
    }

    /// When the loaded major has degree requirements, show audit credits (listed requirements only).
    private var usesAuditForDegreeProgressCard: Bool {
        let major = (collegePersistence.resolvedMajorNames().first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !major.isEmpty else { return false }
        return primaryMajorProgress.required > 0
    }

    private var creditsEarnedDisplay: Int {
        if usesAuditForDegreeProgressCard {
            return primaryMajorProgress.completedRoundedInt
        }
        if let snap = academicMetricsStore.snapshot {
            return snap.completedCreditsTotal
        }
        return collegePersistence.primaryCreditsEarned()
    }

    private var creditsRequiredDisplay: Int {
        if usesAuditForDegreeProgressCard {
            return max(primaryMajorProgress.requiredRoundedInt, 1)
        }
        let snap = academicMetricsStore.snapshot?.creditsRequired ?? 0
        if snap > 0 { return snap }
        let live = collegePersistence.declaredProgramsCreditsBreakdown().primary.requiredRoundedInt
        if live > 0 { return live }
        return collegePersistence.primaryCreditsRequired()
    }

    private var degreeProgressBarFraction: Double {
        if usesAuditForDegreeProgressCard {
            return primaryMajorProgress.fraction
        }
        let req = Double(max(creditsRequiredDisplay, 1))
        return min(Double(creditsEarnedDisplay) / req, 1.0)
    }

    private func openExternalURL(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openResumeBuilder() {
        if let documentID = resumeAvailability.draftDocumentID
            ?? resumeAvailability.primaryDocumentID {
            ResumeNavigationPort.openResumeBuilder(openWindow: openWindow, documentID: documentID)
        } else {
            ResumeNavigationPort.openResumeBuilder(openWindow: openWindow)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    IdentityCard(profile: profile, onEditProfile: openProfileEditor)
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 24) {
                        GPAStandingCard(
                            gpa: displayedGPA,
                            countedCourses: academicMetricsStore.snapshot?.gpaCoursesCounted
                        )
                        DegreeProgressCard(
                            creditsEarned: creditsEarnedDisplay,
                            creditsRequired: creditsRequiredDisplay,
                            progressBarFraction: degreeProgressBarFraction,
                            progressSubtitle: collegePersistence.primaryClassStanding().nilIfEmpty
                        )
                    }
                    .frame(width: 320)
                }

                HStack(alignment: .top, spacing: 24) {
                    CurrentTermCard(
                        termLabel: academicMetricsStore.snapshot?.currentSemesterLabel,
                        termProgress: academicMetricsStore.snapshot?.currentTermProgress ?? 0,
                        courses: academicMetricsStore.snapshot?.currentTermCourses ?? []
                    )
                    .frame(maxWidth: .infinity)

                        TechnicalPortfolioCard(profile: profile, onAddProject: {
                            openPortfolioProjectSheet()
                        }, onEditProject: { project in
                            openPortfolioProjectEditor(project)
                        })
                    .frame(maxWidth: .infinity)
                }

                ProfileResumeCard(
                    availability: resumeAvailability,
                    onBuildResume: openResumeBuilder,
                    onOpenCareerResumes: { activePage = .career }
                )

                if let profile {
                    ProfileSkillsCard(profile: profile)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: 24) {
                        ExperienceView(profile: profile)
                            .frame(maxWidth: .infinity)
                        AchievementsView(profile: profile)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 24) {
                    QuickAccessCard(
                        icon: "book.fill",
                        title: String(localized: "profile.quick.library.title"),
                        subtitle: String(localized: "profile.quick.library.subtitle"),
                        color: .orange,
                        tint: Color.orange.opacity(0.14),
                        action: { openExternalURL(AppExternalLinks.universityLibrary) }
                    )
                    QuickAccessCard(
                        icon: "doc.text.fill",
                        title: String(localized: "profile.quick.transcript.title"),
                        subtitle: String(localized: "profile.quick.transcript.subtitle"),
                        color: .accentColor,
                        tint: Color.accentColor.opacity(0.14),
                        action: { activePage = .documents }
                    )
                    QuickAccessCard(
                        icon: "banknote.fill",
                        title: String(localized: "profile.quick.finances.title"),
                        subtitle: String(localized: "profile.quick.finances.subtitle"),
                        color: .green,
                        tint: Color.green.opacity(0.14),
                        action: { openExternalURL(AppExternalLinks.studentAccounts) }
                    )
                    QuickAccessCard(
                        icon: "bag.fill",
                        title: String(localized: "profile.quick.career.title"),
                        subtitle: String(localized: "profile.quick.career.subtitle"),
                        color: .purple,
                        tint: Color.purple.opacity(0.14),
                        action: { openExternalURL(AppExternalLinks.careerHandshake) }
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(DesignSystem.Spacing.section)
        }
        .background(.windowBackground)
        .shellDynamicTypeReadable()
        .onAppear {
            Task { @MainActor in
                academicMetricsStore.refresh()
                loadPrimaryMajorProgress()
            }
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            plannerRefreshToken &+= 1
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            plannerRefreshToken &+= 1
        }
        .background {
            ProfilePlannerQueryHost {
                plannerRefreshToken &+= 1
            }
        }
        .task(id: "\(collegePersistence.resolvedMajorNames().joined(separator: "|"))|\(profile?.id.uuidString ?? "")") {
            loadPrimaryMajorProgress()
        }
        .onChange(of: collegePersistence.catalogDataRevision) { _, _ in
            loadPrimaryMajorProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileOpenAdvisorPrep)) { _ in
            activeSheet = .advisorPrep
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeProfileEditProfile)) { _ in
            openProfileEditor()
        }
        .onChange(of: container.modalCoordinator.activeModal) { _, modal in
            guard let modal else { return }
            switch modal {
            case .addExperience:
                activeSheet = .addExperience
                container.modalCoordinator.activeModal = nil
            case .editExperience(let experience):
                activeSheet = .editExperience(experience)
                container.modalCoordinator.activeModal = nil
            case .addAchievement:
                activeSheet = .addAchievement
                container.modalCoordinator.activeModal = nil
            case .editAchievement(let achievement):
                activeSheet = .editAchievement(achievement)
                container.modalCoordinator.activeModal = nil
            default:
                break
            }
        }
        .onAppear {
            registerProfileToolbar()
        }
        .onDisappear {
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
        }
        // Single sheet host: multiple `.sheet` modifiers stacked on one view conflict
        // on macOS, so all profile sheets are routed through one enum-driven presenter.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .advisorPrep:
                AdvisorMeetingPrepView()
                    .dismissOnOutsideClickForSheet()
            case .editProfile(let editedProfile):
                ProfileEditSheet(profile: editedProfile)
                    .dismissOnOutsideClickForSheet()
            case .addProject(let owner):
                AddEditProjectSheet(profile: owner)
                    .dismissOnOutsideClickForSheet()
            case .editProject(let owner, let project):
                AddEditProjectSheet(profile: owner, existingProject: project)
                    .dismissOnOutsideClickForSheet()
            case .addExperience:
                AddExperienceView(
                    isPresented: profileSheetDismissBinding,
                    experience: nil,
                    embedInSheet: true
                )
                .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 700)
                .dismissOnOutsideClickForSheet()
            case .editExperience(let experience):
                AddExperienceView(
                    isPresented: profileSheetDismissBinding,
                    experience: experience,
                    embedInSheet: true
                )
                .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 700)
                .dismissOnOutsideClickForSheet()
            case .addAchievement:
                AddAchievementOverlay(
                    isPresented: profileSheetDismissBinding,
                    achievement: nil,
                    embedInSheet: true
                )
                .frame(minWidth: 520, idealWidth: 640, minHeight: 520, idealHeight: 640)
                .dismissOnOutsideClickForSheet()
            case .editAchievement(let achievement):
                AddAchievementOverlay(
                    isPresented: profileSheetDismissBinding,
                    achievement: achievement,
                    embedInSheet: true
                )
                .frame(minWidth: 520, idealWidth: 640, minHeight: 520, idealHeight: 640)
                .dismissOnOutsideClickForSheet()
            }
        }
    }

    private var profileSheetDismissBinding: Binding<Bool> {
        Binding(
            get: { activeSheet != nil },
            set: { isPresented in
                if !isPresented { activeSheet = nil }
            }
        )
    }

    private func registerProfileToolbar() {
        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = container.toolbarDispatcher.register(owner: .profile) { action in
            guard case .profile(let profileAction) = action else { return }
            switch profileAction {
            case .advisorPrep:
                activeSheet = .advisorPrep
            case .editProfile:
                openProfileEditor()
            }
        }
    }

    private func openProfileEditor() {
        guard let owner = collegePersistence.ensurePrimaryProfile() else { return }
        activeSheet = .editProfile(owner)
    }

    private func openPortfolioProjectSheet() {
        guard let owner = collegePersistence.ensurePrimaryProfile() else { return }
        activeSheet = .addProject(owner)
    }

    private func openPortfolioProjectEditor(_ project: PortfolioProject) {
        guard let owner = collegePersistence.ensurePrimaryProfile() else { return }
        activeSheet = .editProject(owner, project)
    }

    private func loadPrimaryMajorProgress() {
        let major = (collegePersistence.resolvedMajorNames().first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !major.isEmpty else {
            primaryMajorProgress = CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
            return
        }
        primaryMajorProgress = collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: major)
    }
}

// MARK: - Identity Card

struct IdentityCard: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    let profile: Profile?
    var onEditProfile: () -> Void = {}

    private var collegePersistence: CollegePersistence { container.persistence }
    private static let avatarSize: CGFloat = 80

    /// Converts stored degree type + major into a compact display string.
    /// "Bachelor of Science (BS)" + "Business Administration" → "B.S. Business Administration"
    private func compactDegreeLine(degreeType: String, major: String) -> String {
        let abbrev = abbreviateDegreeType(degreeType)
        let cleanMajor = stripRedundantDegreeLabel(from: major)
        if !abbrev.isEmpty, !cleanMajor.isEmpty {
            return "\(abbrev) · \(cleanMajor)"
        }
        return cleanMajor.isEmpty ? abbrev : cleanMajor
    }

    private func abbreviateDegreeType(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("bachelor of science") { return "B.S." }
        if lower.contains("bachelor of arts")    { return "B.A." }
        if lower.contains("bachelor of fine arts"){ return "B.F.A." }
        if lower.contains("master of science")   { return "M.S." }
        if lower.contains("master of arts")      { return "M.A." }
        if lower.contains("master of business")  { return "M.B.A." }
        if lower.contains("doctor")              { return "Ph.D." }
        if raw.isEmpty { return "" }
        // Already abbreviated or unknown: strip any parenthetical
        if let paren = raw.firstIndex(of: "(") {
            return String(raw[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    /// Removes trailing " BS", " BA", " MS", " - … BS" patterns that the catalog sometimes appends.
    private func stripRedundantDegreeLabel(from major: String) -> String {
        // Remove " BS" or " B.S." (and similar) at the end or after " - "
        var result = major
        let patterns = [
            #"\s*[-–]\s+[A-Z][a-z].*,\s*(BS|BA|MS|MA|B\.S\.|B\.A\.)\s*$"#,
            #",?\s*(BS|BA|MS|MA|B\.S\.|B\.A\.)$"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
                let range = Range(match.range, in: result)!
                result = String(result[..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalTrimmed(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                    Group {
                        if let data = profile?.profilePhotoData, let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: Self.avatarSize, height: Self.avatarSize)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        } else {
                            avatarPlaceholder
                        }
                    }

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(DesignSystem.Fonts.main(size: 18))
                        .background(Circle().fill(.background).padding(DesignSystem.Spacing.xs))
                        .offset(x: -4, y: -4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let name = profile?.trimmedDisplayName, !name.isEmpty {
                        Text(name)
                            .font(DesignSystem.Fonts.main(size: 28, weight: .bold))
                            .foregroundStyle(.primary)
                    } else {
                        Text(String(localized: "profile.identity.placeholder_name"))
                            .font(DesignSystem.Fonts.main(size: 28, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }

                    let degreeType = collegePersistence.primaryDegreeType()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let major = collegePersistence.resolvedMajorNames().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Button(action: onEditProfile) {
                        Group {
                            if !degreeType.isEmpty || !major.isEmpty {
                                Text(compactDegreeLine(degreeType: degreeType, major: major))
                                    .font(DesignSystem.Fonts.main(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(String(localized: "profile.identity.placeholder_degree"))
                                    .font(DesignSystem.Fonts.main(size: 15, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "profile.edit.open_help"))

                    HStack(spacing: 16) {
                        metaPill(icon: "at", text: optionalTrimmed(profile?.universityEmail) ?? String(localized: "profile.identity.add_email"), isPlaceholder: optionalTrimmed(profile?.universityEmail) == nil)
                        metaPill(icon: "mappin.and.ellipse", text: optionalTrimmed(profile?.permanentAddress) ?? String(localized: "profile.identity.add_location"), isPlaceholder: optionalTrimmed(profile?.permanentAddress) == nil)
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .profileCardSurface(padding: 28)

            HStack(spacing: 8) {
                Button(action: onEditProfile) {
                    Text(String(localized: "profile.edit.title"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "profile.edit.open_help"))

                Button(action: onEditProfile) {
                    Image(systemName: "pencil")
                        .symbolRenderingMode(.hierarchical)
                        .font(DesignSystem.Fonts.main(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "profile.edit.open_help"))
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    @ViewBuilder
    private func metaPill(icon: String, text: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(isPlaceholder ? .tertiary : .secondary)
                .font(DesignSystem.Fonts.main(size: 13))
            Text(text)
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(isPlaceholder ? .tertiary : .secondary)
        }
    }
}

// MARK: - GPA Standing Card

struct GPAStandingCard: View {
    let gpa: Double?
    var countedCourses: Int?

    private var valueLine: String {
        guard let gpa else { return "—" }
        return String(format: "%.2f", gpa)
    }

    private var footnote: String? {
        guard let n = countedCourses, n > 0 else { return nil }
        return "\(n) letter-graded course\(n == 1 ? "" : "s") in plan"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GPA STANDING")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .kerning(1)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            DashboardMetricValue(
                valueText: valueLine,
                caption: gpa == nil ? "Complete letter-graded courses to compute GPA." : "Cumulative (active plan)",
                footnote: footnote
            )

            DashboardGPAScaleBar(gpa: gpa)
                .padding(.top, 8)
        }
        .profileCardSurface(padding: 24)
    }
}

// MARK: - Degree Progress Card

struct DegreeProgressCard: View {
    let creditsEarned: Int
    let creditsRequired: Int
    /// When set (e.g. degree-audit fraction), drives the bar; otherwise `creditsEarned / creditsRequired`.
    var progressBarFraction: Double?
    var progressSubtitle: String?

    private var barFill: CGFloat {
        let raw = progressBarFraction ?? (Double(creditsEarned) / Double(max(creditsRequired, 1)))
        return CGFloat(min(max(raw, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DEGREE PROGRESS")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .kerning(1)
                Spacer()
                Image(systemName: "graduationcap.fill")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 4)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(creditsEarned)")
                    .font(DesignSystem.Fonts.main(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("/ \(creditsRequired)")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let progressSubtitle, !progressSubtitle.isEmpty {
                Text(progressSubtitle)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * barFill, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.top, 12)
        }
        .profileCardSurface(padding: 24)
    }
}

// MARK: - Current Term Card (formerly "Semestrial Pulse")

struct CurrentTermCard: View {
    let termLabel: String?
    let termProgress: Double
    let courses: [AcademicTermCourseRow]

    private func rowTitle(_ row: AcademicTermCourseRow) -> String {
        if !row.code.isEmpty, !row.name.isEmpty { return "\(row.code) · \(row.name)" }
        if !row.name.isEmpty { return row.name }
        if !row.code.isEmpty { return row.code }
        return "Course"
    }

    private func rowFraction(_ row: AcademicTermCourseRow) -> Double {
        if row.isCompleted { return 1 }
        return min(max(termProgress, 0), 1)
    }

    /// Gradient from teal→blue for early progress, blue→indigo for mid, indigo→purple for near-complete.
    private func progressGradient(for fraction: Double) -> LinearGradient {
        switch fraction {
        case ..<0.33:
            return LinearGradient(colors: [.teal, .accentColor], startPoint: .leading, endPoint: .trailing)
        case 0.33..<0.66:
            return LinearGradient(colors: [.accentColor, .indigo], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(String(localized: "profile.pulse.card_title"))
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                if let termLabel, !termLabel.isEmpty {
                    Text(termLabel)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.green)
                }
            }

            if courses.isEmpty {
                emptyStateBox(
                    title: String(localized: "profile.pulse.empty_title"),
                    message: String(localized: "profile.pulse.empty_message"),
                    systemImage: "calendar.badge.plus"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(courses) { row in
                        let frac = rowFraction(row)
                        VStack(spacing: 8) {
                            HStack {
                                Text(rowTitle(row))
                                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(frac * 100))%")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(frac >= 1.0 ? AnyShapeStyle(.green) : AnyShapeStyle(Color.accentColor))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 5)
                                    Capsule()
                                        .fill(progressGradient(for: frac))
                                        .frame(width: geo.size.width * CGFloat(frac), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .profileCardSurface(padding: 28)
    }

    @ViewBuilder
    private func emptyStateBox(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(DesignSystem.Fonts.main(size: 24, weight: .regular))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(DesignSystem.Fonts.main(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.primary.opacity(0.18))
        )
    }
}

// MARK: - Technical Portfolio Card

struct TechnicalPortfolioCard: View {
    let profile: Profile?
    var onAddProject: () -> Void
    var onEditProject: (PortfolioProject) -> Void = { _ in }

    @State private var expandedProjectIDs: Set<UUID> = []

    private var projects: [PortfolioProject] {
        profile?.portfolioProjectsList ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(String(localized: "profile.portfolio.title"))
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onAddProject) {
                    Image(systemName: "plus.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 18))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "profile.portfolio.add_help"))
            }

            if projects.isEmpty {
                portfolioEmptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(projects) { project in
                        portfolioProjectRow(project)
                            .onTapGesture {
                                onEditProject(project)
                            }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .profileCardSurface(padding: 28)
    }

    // MARK: Rich empty state

    private var portfolioEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(DesignSystem.Fonts.main(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(String(localized: "profile.portfolio.empty_title"))
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(String(localized: "profile.portfolio.empty_message"))
                .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.primary.opacity(0.18))
        )
    }

    @ViewBuilder
    private func integrationHook(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Project row

    @ViewBuilder
    private func portfolioProjectRow(_ project: PortfolioProject) -> some View {
        let isExpanded = expandedProjectIDs.contains(project.id)
        let visibleBullets = isExpanded ? project.bullets : Array(project.bullets.prefix(3))

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.title)
                    .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let start = project.startDateString, !start.isEmpty {
                    let end = project.endDateString ?? ""
                    Text(end.isEmpty ? start : "\(start) – \(end)")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            if !project.role.isEmpty {
                Text(project.role)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !project.technologies.isEmpty {
                Text(project.technologies)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            if !project.summary.isEmpty {
                Text(project.summary)
                    .font(DesignSystem.Fonts.main(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if !visibleBullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleBullets.indices, id: \.self) { index in
                        Text("• \(visibleBullets[index])")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if project.bullets.count > 3 {
                        Button(isExpanded ? "Show less" : "Show more") {
                            if isExpanded {
                                expandedProjectIDs.remove(project.id)
                            } else {
                                expandedProjectIDs.insert(project.id)
                            }
                        }
                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                if let github = project.githubURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !github.isEmpty,
                   let url = URL(string: github), url.scheme != nil {
                    Link(destination: url) {
                        Label("GitHub", systemImage: "link")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    }
                }
                if !project.projectURL.isEmpty,
                   let url = URL(string: project.projectURL), url.scheme != nil {
                    Link(project.projectURL, destination: url)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Quick Access Card

struct QuickAccessCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let tint: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity)
            .profileCardSurface(padding: 0)
        }
        .buttonStyle(.plain)
    }
}
