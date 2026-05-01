import SwiftUI
import CoreData
import Observation

private enum OnboardingCatalogSyncPhase {
    case idle
    case inProgress
    case succeeded
    case failed
}

private enum OnboardingCatalogSyncVisualPhase {
    case discovering
    case downloading
    case importing
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case identity
    case academicSetup
    case academicHistory
    case integrations
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .identity: return "Identity"
        case .academicSetup: return "Academic Setup"
        case .academicHistory: return "Academic History"
        case .integrations: return "Integrations"
        case .finish: return "Ready"
        }
    }

    var subtitle: String {
        switch self {
        case .identity: return "Name, school, and contact"
        case .academicSetup: return "Degrees, majors, and minors"
        case .academicHistory: return "Transfer details (optional)"
        case .integrations: return "LMS and dashboard widgets"
        case .finish: return "Review and enter workspace"
        }
    }
}

private enum OnboardingLMSProvider: String, CaseIterable, Identifiable {
    case brightspace = "Brightspace"
    case canvas = "Canvas"
    case blackboard = "Blackboard"
    case moodle = "Moodle"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .brightspace: return "network"
        case .canvas: return "square.grid.3x3"
        case .blackboard: return "book.closed"
        case .moodle: return "graduationcap"
        }
    }
}

private enum DashboardWidgetOption: String, CaseIterable, Identifiable {
    case assignments = "Upcoming Assignments"
    case nextClass = "Next Class"
    case gpaSnapshot = "GPA Snapshot"
    case deadlines = "Deadlines"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .assignments: return "checklist"
        case .nextClass: return "calendar.badge.clock"
        case .gpaSnapshot: return "chart.bar"
        case .deadlines: return "hourglass"
        }
    }
}

private struct OnboardingAcademicDraft: Codable {
    var degreeCount: Int
    var majorCount: Int
    var minorCount: Int
    var selectedDegreeLevels: [String]
    var selectedCatalogCatoid: String
    var selectedMajors: [String]
    var selectedMinors: [String]
}

private struct OnboardingCatalogTypeOption: Identifiable, Hashable {
    let catoid: String
    let label: String
    let rawTitle: String

    var id: String { catoid }
}

private struct OnboardingMajorSection: Identifiable, Hashable {
    let title: String
    let majors: [String]

    var id: String { title }
}

private struct OnboardingDraft {
    var name: String = ""
    var email: String = ""
    var schoolName: String = ""

    var degreeCount: Int = 1
    var majorCount: Int = 1
    var minorCount: Int = 0

    var selectedDegreeLevels: [String] = [DegreeConfiguration.allLevels.first ?? "Undergraduate"]
    var selectedCatalogCatoid: String = ""
    var selectedMajors: [String] = [""]
    var selectedMinors: [String] = []

    var transferNotes: String = ""

    var selectedLMS: Set<OnboardingLMSProvider> = []
    var selectedWidgets: Set<DashboardWidgetOption> = [.assignments, .nextClass]

    mutating func reconcileCounts() {
        degreeCount = max(1, degreeCount)
        majorCount = max(1, majorCount)
        minorCount = max(0, minorCount)

        Self.reconcileArray(&selectedDegreeLevels, target: degreeCount, fallback: DegreeConfiguration.allLevels.first ?? "Undergraduate")
        Self.reconcileArray(&selectedMajors, target: majorCount, fallback: "")
        Self.reconcileArray(&selectedMinors, target: minorCount, fallback: "")
    }

    private static func reconcileArray(_ array: inout [String], target: Int, fallback: String) {
        if array.count < target {
            array.append(contentsOf: Array(repeating: fallback, count: target - array.count))
        } else if array.count > target {
            array.removeLast(array.count - target)
        }
    }
}

@MainActor
@Observable
private final class OnboardingCoordinator {
    var currentStep: OnboardingStep = .identity
    var validationMessage: String?
    var isCommitting = false

    var canGoBack: Bool {
        currentStep.rawValue > 0
    }

    var isLastStep: Bool {
        currentStep == .finish
    }

    func goBack() {
        guard canGoBack else { return }
        if let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            validationMessage = nil
            currentStep = previous
        }
    }

    func goNext() {
        guard !isLastStep else { return }
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            validationMessage = nil
            currentStep = next
        }
    }
}

struct OnboardingRootView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var notifications: AppNotificationCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(OnboardingPreferenceBridge.completedKey) private var onboardingCompleted = false

    let onComplete: () -> Void

    @State private var draft = OnboardingDraft()
    @State private var coordinator = OnboardingCoordinator()

    @State private var universityOptions: [String] = []
    @State private var catalogTypeOptions: [OnboardingCatalogTypeOption] = []
    @State private var majorOptions: [String] = []
    @State private var majorOptionsBySection: [OnboardingMajorSection] = []
    @State private var minorOptions: [String] = []
    @State private var isLoadingUniversityOptions = false
    @State private var isLoadingCatalogTypeOptions = false
    @State private var universityOptionsLoadError: String?

    @State private var catalogSyncPhase: OnboardingCatalogSyncPhase = .idle
    @State private var catalogSyncProgress: Double = 0
    @State private var catalogSyncMessage: String = "Catalog sync has not started yet."
    @State private var autoStartedSyncForSchool: String?
    @State private var catalogSyncVisualPhase: OnboardingCatalogSyncVisualPhase = .discovering
    @State private var lockedCourseDenominator: Int = 0
    @State private var handoffReady = false
    @State private var catalogSyncStartDate: Date?
    @State private var catalogSyncTask: Task<Void, Never>?
    @State private var handoffThresholdTask: Task<Void, Never>?
    @State private var lastScrapeAuditPath: String?

    private let githubService = GitHubDataService()

    var body: some View {
        HStack(spacing: 0) {
            stepRail

            Divider()

            VStack(spacing: 0) {
                contentArea
                Divider()
                actionBar
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(.regularMaterial)
        .onAppear {
            reloadContextOptions()
            draft.reconcileCounts()
            bootstrapUniversityOptionsIfNeeded()
            refreshCatalogTypeOptionsForSelectedSchool()
        }
        .onDisappear {
            catalogSyncTask?.cancel()
            catalogSyncTask = nil
            handoffThresholdTask?.cancel()
            handoffThresholdTask = nil
        }
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to College")
                .font(.system(size: 26, weight: .bold))

            Text("Set up your workspace once. You can refine everything later in Profile and Settings.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ForEach(OnboardingStep.allCases) { step in
                let isActive = coordinator.currentStep == step
                HStack(alignment: .top, spacing: 10) {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 22, height: 22)
                        .background(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundStyle(isActive ? Color.white : Color.primary)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.system(size: 13, weight: isActive ? .bold : .semibold))
                        Text(step.subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 320, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if shouldShowCatalogSyncGateBanner {
                    catalogSyncGateBanner
                }

                switch coordinator.currentStep {
                case .identity:
                    identityStep
                case .academicSetup:
                    academicSetupStep
                case .academicHistory:
                    academicHistoryStep
                case .integrations:
                    integrationsStep
                case .finish:
                    finishStep
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Back") {
                coordinator.goBack()
            }
            .disabled(!coordinator.canGoBack || coordinator.isCommitting || catalogSyncPhase == .inProgress)

            Spacer()

            if let message = coordinator.validationMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Spacer()

            Button(primaryActionTitle) {
                handleContinue()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(coordinator.isCommitting || isForwardNavigationBlockedByCatalogSync || (coordinator.isLastStep && catalogSyncPhase == .inProgress && !handoffReady))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.thinMaterial)
    }

    private var shouldShowCatalogSyncGateBanner: Bool {
        catalogSyncRequired && (catalogSyncPhase != .idle || coordinator.currentStep != .identity)
    }

    private var isForwardNavigationBlockedByCatalogSync: Bool {
        catalogSyncRequired && catalogSyncPhase == .inProgress
    }

    @ViewBuilder
    private var catalogSyncGateBanner: some View {
        GroupBox("Catalog Preparation") {
            VStack(alignment: .leading, spacing: 8) {
                switch catalogSyncPhase {
                case .idle:
                    Text("Waiting to start catalog sync for your selected school.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                    Button("Start Catalog Sync") {
                        startCatalogSyncTask()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Start scraper and catalog import for this school")
                case .inProgress:
                    ProgressView(value: catalogSyncProgress, total: 1)
                        .progressViewStyle(.linear)
                    Text(catalogSyncMessage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("Please wait. You can continue once catalog sync is complete.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                case .failed:
                    Text("Catalog sync failed. Retry to continue onboarding.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.orange)
                    Button("Retry Catalog Sync") {
                        startCatalogSyncTask()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Retry scraper and import")
                case .succeeded:
                    Label("Catalog synced. You can continue onboarding.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.top, 4)
        }
    }

    private var primaryActionTitle: String {
        guard coordinator.isLastStep else { return "Continue" }

        if !catalogSyncRequired {
            return "Enter Workspace"
        }

        switch catalogSyncPhase {
        case .idle:
            return "Start Catalog Sync"
        case .inProgress:
            return handoffReady ? "Enter Workspace" : "Syncing..."
        case .succeeded:
            return "Enter Workspace"
        case .failed:
            return "Retry Catalog Sync"
        }
    }

    private var identityStep: some View {
        GroupBox("Identity") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)

                TextField("School email (optional)", text: $draft.email)
                    .textFieldStyle(.roundedBorder)

                Picker("School", selection: Binding(
                    get: { draft.schoolName },
                    set: { newValue in
                        let prior = draft.schoolName
                        draft.schoolName = newValue
                        if prior != newValue {
                            resetCatalogSyncState()
                            resetCatalogTypeState()
                            refreshCatalogTypeOptionsForSelectedSchool()
                        }
                        reloadContextOptions()
                    }
                )) {
                    Text("Select a school").tag("")
                    ForEach(universityOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)

                if universityOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if isLoadingUniversityOptions {
                            ProgressView("Loading schools...")
                                .controlSize(.small)
                        } else {
                            Text(universityOptionsLoadError ?? "No schools loaded yet.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)

                            Button("Load School List") {
                                refreshUniversityOptionsFromManifest()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .help("Fetch school list from the catalog manifest")
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var academicSetupStep: some View {
        GroupBox("Academic Setup") {
            VStack(alignment: .leading, spacing: 14) {
                if catalogSyncRequired {
                    VStack(alignment: .leading, spacing: 8) {
                        switch catalogSyncPhase {
                        case .idle, .inProgress:
                            ProgressView("Preparing school catalog for majors/minors...")
                                .controlSize(.small)
                            Text(catalogSyncMessage)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        case .failed:
                            Text("Catalog sync failed. Retry to load majors/minors for dropdown selection.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.orange)
                            Button("Retry Catalog Sync") {
                                startCatalogSyncTask()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .help("Retry scraping/importing catalog for this school")
                        case .succeeded:
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Catalog sync completed", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                                ProgressView(value: 1, total: 1)
                                    .progressViewStyle(.linear)
                                    .tint(.green)
                            }
                        }
                    }
                }

                Text("How many degrees, majors, and minors do you want to track?")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 14) {
                    countControl(title: "Degrees", value: Binding(
                        get: { draft.degreeCount },
                        set: { newValue in
                            draft.degreeCount = newValue
                            draft.reconcileCounts()
                        }
                    ), minimum: 1)

                    countControl(title: "Majors", value: Binding(
                        get: { draft.majorCount },
                        set: { newValue in
                            draft.majorCount = newValue
                            draft.reconcileCounts()
                        }
                    ), minimum: 1)

                    countControl(title: "Minors", value: Binding(
                        get: { draft.minorCount },
                        set: { newValue in
                            draft.minorCount = newValue
                            draft.reconcileCounts()
                        }
                    ), minimum: 0)
                }

                Divider()

                Text("Degree Level")
                    .font(.system(size: 12, weight: .bold))
                ForEach(draft.selectedDegreeLevels.indices, id: \.self) { index in
                    Picker("Degree Level \(index + 1)", selection: Binding(
                        get: { draft.selectedDegreeLevels[index] },
                        set: { newValue in
                            draft.selectedDegreeLevels[index] = newValue
                            if let matched = catalogTypeOptions.first(where: { $0.label == newValue || $0.catoid == newValue }) {
                                draft.selectedCatalogCatoid = matched.catoid
                            }
                            reloadContextOptions()
                        }
                    )) {
                        Text("Select degree level").tag("")
                        if !catalogTypeOptions.isEmpty {
                            ForEach(catalogTypeOptions) { option in
                                Text(option.label).tag(option.label)
                            }
                        } else {
                            ForEach(DegreeConfiguration.allLevels, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }

                if isLoadingCatalogTypeOptions {
                    ProgressView("Loading degree level options...")
                        .controlSize(.small)
                }

                Text("Majors")
                    .font(.system(size: 12, weight: .bold))
                ForEach(draft.selectedMajors.indices, id: \.self) { index in
                    if catalogSyncRequired && catalogSyncPhase != .succeeded && majorOptions.isEmpty && majorOptionsBySection.isEmpty {
                        Text("Majors will appear after catalog sync completes.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if catalogSyncPhase == .succeeded && majorOptions.isEmpty && majorOptionsBySection.isEmpty {
                        Text("No majors found for this Degree Level in the selected catalog.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if majorOptions.isEmpty && majorOptionsBySection.isEmpty {
                        TextField("Major \(index + 1)", text: Binding(
                            get: { draft.selectedMajors[index] },
                            set: { draft.selectedMajors[index] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Major \(index + 1)", selection: Binding(
                            get: { draft.selectedMajors[index] },
                            set: { draft.selectedMajors[index] = $0 }
                        )) {
                            Text("Select major").tag("")
                            if !majorOptionsBySection.isEmpty {
                                ForEach(majorOptionsBySection) { section in
                                    Section(section.title) {
                                        ForEach(section.majors, id: \.self) { major in
                                            Text(major).tag(major)
                                        }
                                    }
                                }
                            } else {
                                ForEach(majorOptions, id: \.self) { major in
                                    Text(major).tag(major)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Text("Minors")
                    .font(.system(size: 12, weight: .bold))
                ForEach(draft.selectedMinors.indices, id: \.self) { index in
                    if catalogSyncRequired && catalogSyncPhase != .succeeded && minorOptions.isEmpty {
                        Text("Minors/certificates will appear after catalog sync completes.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if catalogSyncPhase == .succeeded && minorOptions.isEmpty {
                        Text("No minors or certificates found for this Degree Level in the selected catalog.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if minorOptions.isEmpty {
                        TextField("Minor \(index + 1)", text: Binding(
                            get: { draft.selectedMinors[index] },
                            set: { draft.selectedMinors[index] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Minor \(index + 1)", selection: Binding(
                            get: { draft.selectedMinors[index] },
                            set: { draft.selectedMinors[index] = $0 }
                        )) {
                            Text("Select minor").tag("")
                            ForEach(minorOptions, id: \.self) { minor in
                                Text(minor).tag(minor)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var academicHistoryStep: some View {
        GroupBox("Academic History (Optional)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Share transfer context now, or skip and add transcript details later.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)

                TextField("Transfer notes (optional)", text: $draft.transferNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 6)
        }
    }

    private var integrationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Choose LMS Integrations") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select the platforms you want to connect first. You can connect others later.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                        ForEach(OnboardingLMSProvider.allCases) { provider in
                            let selected = draft.selectedLMS.contains(provider)
                            Button {
                                if selected {
                                    draft.selectedLMS.remove(provider)
                                } else {
                                    draft.selectedLMS.insert(provider)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: provider.icon)
                                    Text(provider.rawValue)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Toggle \(provider.rawValue) connection intent")
                        }
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Choose Dashboard Widgets") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommended widgets are pre-selected. Adjust now or later in settings.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(DashboardWidgetOption.allCases) { widget in
                            let selected = draft.selectedWidgets.contains(widget)
                            Button {
                                if selected {
                                    draft.selectedWidgets.remove(widget)
                                } else {
                                    draft.selectedWidgets.insert(widget)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: widget.icon)
                                    Text(widget.rawValue)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Toggle \(widget.rawValue) widget")
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingSyncMotionCard(
                phase: catalogSyncPhase,
                progress: catalogSyncProgress,
                statusMessage: catalogSyncMessage,
                reduceMotion: reduceMotion
            )

            if handoffReady && catalogSyncPhase == .inProgress {
                OnboardingDecisionCard(
                    title: "Your workspace is ready",
                    message: "We are downloading the complete catalog in the background. You can enter now and keep planning.",
                    status: "Background sync continues after handoff"
                )
            }

            GroupBox("Catalog Sync") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(catalogSyncDetailText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)

                    if catalogSyncRequired {
                        Text(catalogSyncPhaseLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        if showsDeterminateSync {
                            ProgressView(value: catalogSyncProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(catalogSyncPhase == .succeeded ? .green : .accentColor)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let eta = catalogSyncETA, catalogSyncPhase == .inProgress {
                            Text(eta)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(catalogSyncMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(catalogSyncPhase == .failed ? .orange : (catalogSyncPhase == .succeeded ? .green : .primary))
                    } else {
                        Label("Catalog already available for your selected school.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Ready to Enter Workspace") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your profile draft is ready. Enter Workspace will commit your onboarding identity and preferences.")
                        .font(.system(size: 13, weight: .regular))

                    keyValueRow(label: "Name", value: draft.name)
                    keyValueRow(label: "School", value: draft.schoolName)
                    keyValueRow(label: "Majors", value: draft.selectedMajors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", "))
                    keyValueRow(label: "LMS", value: draft.selectedLMS.map(\.rawValue).sorted().joined(separator: ", "))
                    keyValueRow(label: "Widgets", value: draft.selectedWidgets.map(\.rawValue).sorted().joined(separator: ", "))
                }
                .padding(.top, 6)
            }
        }
    }

    private var catalogSyncRequired: Bool {
        let school = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !school.isEmpty else { return false }
        return !coreDataManager.hasUniversityCatalog(name: school)
    }

    private var catalogSyncDetailText: String {
        if !catalogSyncRequired {
            return "No additional sync is required. You can enter your workspace immediately."
        }
        switch catalogSyncPhase {
        case .idle:
            return "Start sync to import your school catalog before entering the workspace."
        case .inProgress:
            return handoffReady
                ? "Sync is still running in the background. Enter now or wait for completion here."
                : "Sync is in progress. Back navigation is disabled to keep onboarding state consistent."
        case .succeeded:
            return "Catalog sync completed. Your workspace is now ready with school data."
        case .failed:
            return "Sync failed. Retry now, or adjust your school selection and try again."
        }
    }

    private var catalogSyncPhaseLabel: String {
        switch catalogSyncPhase {
        case .idle:
            return "Not started"
        case .succeeded:
            return "Completed"
        case .failed:
            return "Failed"
        case .inProgress:
            switch catalogSyncVisualPhase {
            case .discovering:
                return "Phase 1: Discovering Curriculum"
            case .downloading:
                return "Phase 2: Downloading Courses"
            case .importing:
                return "Phase 2: Importing Courses"
            }
        }
    }

    private var showsDeterminateSync: Bool {
        if catalogSyncPhase == .succeeded { return true }
        return catalogSyncPhase == .inProgress && catalogSyncVisualPhase != .discovering
    }

    private var catalogSyncETA: String? {
        guard showsDeterminateSync else { return nil }
        guard let started = catalogSyncStartDate else { return nil }

        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 1, catalogSyncProgress > 0.01, catalogSyncProgress < 0.99 else { return nil }

        let remaining = elapsed * ((1.0 - catalogSyncProgress) / catalogSyncProgress)
        guard remaining.isFinite, remaining > 0 else { return nil }

        if remaining < 60 {
            return "About \(Int(remaining.rounded()))s remaining"
        }

        return "About \(Int((remaining / 60.0).rounded()))m remaining"
    }

    private func keyValueRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 90, alignment: .leading)
            Text(value.isEmpty ? "Not set" : value)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
        }
    }

    private func countControl(title: String, value: Binding<Int>, minimum: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Button {
                value.wrappedValue = max(minimum, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("Decrease \(title)")

            Text("\(value.wrappedValue)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(minWidth: 22)
                .monospacedDigit()

            Button {
                value.wrappedValue += 1
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .help("Increase \(title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func reloadContextOptions() {
        // Onboarding should use the scraper-backed school manifest first so the
        // picker mirrors the schools that are implemented in the catalog scraper flow.
        let cached = cachedSchoolNames()
        if !cached.isEmpty {
            universityOptions = cached
            universityOptionsLoadError = nil
        } else if universityOptions.isEmpty {
            // Fallback: show any locally imported universities if manifest data is unavailable.
            let localUniversities = fetchUniversityNames()
            if !localUniversities.isEmpty {
                universityOptions = localUniversities
                universityOptionsLoadError = nil
            }
        }

        let school = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeLevel = draft.selectedDegreeLevels.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let catalogSelectedFromDegree = catalogTypeOptions.first(where: { option in
            option.label.compare(degreeLevel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            option.catoid.compare(degreeLevel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })?.catoid.trimmingCharacters(in: .whitespacesAndNewlines)

        let selectedCatoid: String = {
            if let catalogSelectedFromDegree, !catalogSelectedFromDegree.isEmpty {
                return catalogSelectedFromDegree
            }
            return draft.selectedCatalogCatoid.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        let useLegacyCatoidFallback = catalogTypeOptions.isEmpty

        guard !school.isEmpty, !degreeLevel.isEmpty else {
            majorOptions = []
            majorOptionsBySection = []
            minorOptions = []
            return
        }

        if catalogTypeOptions.count == 1,
           draft.selectedCatalogCatoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let only = catalogTypeOptions.first {
            draft.selectedCatalogCatoid = only.catoid
        }

        let availableLevelsFromCatalog = catalogTypeOptions
            .map { DegreeConfiguration.canonicalLevel($0.label) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let levelsToQuery = DegreeConfiguration.queryLevels(
            for: degreeLevel,
            availableLevels: availableLevelsFromCatalog
        )

        func fetchMajorUniverse(department: String? = nil, allowCatoidFallback: Bool = true) -> [String] {
            var collected: [String] = []
            var seen = Set<String>()
            for level in levelsToQuery {
                let majors = coreDataManager.fetchMajors(
                    for: school,
                    degreeLevel: level,
                    department: department,
                    degreeType: nil,
                    includeMinors: false,
                    sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid
                )
                for major in majors where seen.insert(major).inserted {
                    collected.append(major)
                }
            }

            // Fallback for legacy/imported rows missing source catoid provenance.
            if collected.isEmpty, !selectedCatoid.isEmpty, allowCatoidFallback, useLegacyCatoidFallback {
                for level in levelsToQuery {
                    let majors = coreDataManager.fetchMajors(
                        for: school,
                        degreeLevel: level,
                        department: department,
                        degreeType: nil,
                        includeMinors: false,
                        sourceCatoid: nil
                    )
                    for major in majors where seen.insert(major).inserted {
                        collected.append(major)
                    }
                }
            }

            return collected
        }

        let resolvedMajors = fetchMajorUniverse()

        let filteredMajors = resolvedMajors.filter(isSelectableMajorLabel(_:))
        majorOptions = Array(Set(filteredMajors)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var departmentGroups: [(group: String, departments: [String])] = []
        var seenDepartmentGroupKeys = Set<String>()
        for level in levelsToQuery {
            let groupsForLevel = coreDataManager.fetchDepartmentGroups(
                for: school,
                degreeLevel: level,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid
            )
            for group in groupsForLevel {
                let key = group.group.lowercased() + "|" + group.departments.joined(separator: "|").lowercased()
                if seenDepartmentGroupKeys.insert(key).inserted {
                    departmentGroups.append(group)
                }
            }
        }
        var groupedSections: [OnboardingMajorSection] = []

        for group in departmentGroups {
            for department in group.departments {
                let majorsForDepartment = fetchMajorUniverse(department: department, allowCatoidFallback: false)
                .filter(isSelectableMajorLabel(_:))

                if majorsForDepartment.isEmpty { continue }
                let unique = Array(Set(majorsForDepartment)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                groupedSections.append(OnboardingMajorSection(title: "\(group.group) > \(department)", majors: unique))
            }
        }
        majorOptionsBySection = groupedSections

        var minors: [String] = []
        var seenMinors = Set<String>()
        for level in levelsToQuery {
            let fetchedMinors = coreDataManager.fetchMinors(
                for: school,
                degreeLevel: level,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid
            )
            for minor in fetchedMinors where seenMinors.insert(minor).inserted {
                minors.append(minor)
            }
        }

        if minors.isEmpty, !selectedCatoid.isEmpty, useLegacyCatoidFallback {
            for level in levelsToQuery {
                let fetchedMinors = coreDataManager.fetchMinors(
                    for: school,
                    degreeLevel: level,
                    sourceCatoid: nil
                )
                for minor in fetchedMinors where seenMinors.insert(minor).inserted {
                    minors.append(minor)
                }
            }
        }

        if minors.isEmpty {
            var certificates = coreDataManager.fetchCertificates(
                for: school,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid
            )
            if certificates.isEmpty, !selectedCatoid.isEmpty, useLegacyCatoidFallback {
                certificates = coreDataManager.fetchCertificates(
                    for: school,
                    sourceCatoid: nil
                )
            }
            minorOptions = certificates
        } else {
            minorOptions = minors
        }
    }

    private func isSelectableMajorLabel(_ major: String) -> Bool {
        let normalized = major.uppercased()
        if normalized.hasSuffix(", UNKNOWN") { return false }
        if normalized.contains("CERTIFICATE") { return false }
        if normalized.contains("MICRO-CREDENTIAL") { return false }
        if normalized.contains("MICRO CREDENTIAL") { return false }
        if normalized.contains(" CREDENTIAL") { return false }
        return true
    }

    private func bootstrapUniversityOptionsIfNeeded() {
        guard universityOptions.isEmpty else { return }
        let cached = cachedSchoolNames()
        if !cached.isEmpty {
            universityOptions = cached
            universityOptionsLoadError = nil
        } else {
            // Fallback immediately for offline startup while manifest fetch is pending.
            let localUniversities = fetchUniversityNames()
            if !localUniversities.isEmpty {
                universityOptions = localUniversities
            }
            refreshUniversityOptionsFromManifest()
        }
    }

    private func cachedSchoolNames() -> [String] {
        let cached = githubService.loadCachedSchoolsList() ?? []
        return schoolNames(from: cached)
    }

    private func schoolNames(from schools: [SchoolManifest]) -> [String] {
        Array(Set(schools
            .filter(isScraperBackedSchool)
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isScraperBackedSchool(_ school: SchoolManifest) -> Bool {
        let catalogURL = (school.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else { return false }

        let format = school.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return format == "acalog" || format == "banner" || format == "custom" || format == "moderncampus"
    }

    private func refreshUniversityOptionsFromManifest() {
        guard !isLoadingUniversityOptions else { return }
        isLoadingUniversityOptions = true
        universityOptionsLoadError = nil

        Task {
            do {
                let schools = try await githubService.fetchSchoolsList()
                try? githubService.cacheSchoolsList(schools)
                let names = schoolNames(from: schools)

                await MainActor.run {
                    isLoadingUniversityOptions = false
                    universityOptions = names
                    if names.isEmpty {
                        universityOptionsLoadError = "No scraper-backed schools were returned from the manifest."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingUniversityOptions = false
                    universityOptionsLoadError = error.localizedDescription
                }
            }
        }
    }

    private func resetCatalogTypeState() {
        catalogTypeOptions = []
        draft.selectedCatalogCatoid = ""
        majorOptionsBySection = []
    }

    private func refreshCatalogTypeOptionsForSelectedSchool() {
        guard !isLoadingCatalogTypeOptions else { return }

        let selectedSchool = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedSchool.isEmpty else {
            resetCatalogTypeState()
            return
        }

        isLoadingCatalogTypeOptions = true

        Task {
            do {
                let manifest = try await resolveSchoolManifest(named: selectedSchool)
                let format = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard format == "acalog" || format == "moderncampus" else {
                    await MainActor.run {
                        isLoadingCatalogTypeOptions = false
                        resetCatalogTypeState()
                        reloadContextOptions()
                    }
                    return
                }

                let catalogURL = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !catalogURL.isEmpty else {
                    await MainActor.run {
                        isLoadingCatalogTypeOptions = false
                        resetCatalogTypeState()
                        reloadContextOptions()
                    }
                    return
                }

                let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
                let discovered = (try? await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedCatalogURL)) ?? []
                let reducedDiscovered = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: discovered)

                let descriptors: [ModernCampusCatalogDescriptor]
                if !reducedDiscovered.isEmpty {
                    descriptors = reducedDiscovered
                } else if let catoidHint, !catoidHint.isEmpty {
                    descriptors = [ModernCampusCatalogDescriptor(catoid: catoidHint, title: "Catalog")]
                } else {
                    let current = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL)
                    descriptors = [ModernCampusCatalogDescriptor(catoid: current, title: "Catalog")]
                }

                let options = normalizedCatalogTypeOptions(from: descriptors)

                await MainActor.run {
                    isLoadingCatalogTypeOptions = false
                    catalogTypeOptions = options

                    syncDegreeSelectionWithCatalogOptions()

                    reloadContextOptions()
                }
            } catch {
                await MainActor.run {
                    isLoadingCatalogTypeOptions = false
                    resetCatalogTypeState()
                    reloadContextOptions()
                }
            }
        }
    }

    private func normalizedCatalogTypeOptions(from descriptors: [ModernCampusCatalogDescriptor]) -> [OnboardingCatalogTypeOption] {
        var seen = Set<String>()
        var out: [OnboardingCatalogTypeOption] = []

        for descriptor in descriptors {
            let catoid = descriptor.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !catoid.isEmpty else { continue }
            guard seen.insert(catoid).inserted else { continue }

            out.append(OnboardingCatalogTypeOption(
                catoid: catoid,
                label: normalizedCatalogTypeLabel(from: descriptor.title, catoid: catoid),
                rawTitle: descriptor.title
            ))
        }

        return out
    }

    private func syncDegreeSelectionWithCatalogOptions() {
        guard !catalogTypeOptions.isEmpty else {
            draft.selectedCatalogCatoid = ""
            return
        }

        let fallback = catalogTypeOptions[0]

        for idx in draft.selectedDegreeLevels.indices {
            let current = draft.selectedDegreeLevels[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if let matched = catalogTypeOptions.first(where: {
                $0.label.compare(current, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                $0.catoid.compare(current, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                draft.selectedDegreeLevels[idx] = matched.label
            } else {
                draft.selectedDegreeLevels[idx] = fallback.label
            }
        }

        let firstDegreeSelection = draft.selectedDegreeLevels.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let matched = catalogTypeOptions.first(where: {
            $0.label.compare(firstDegreeSelection, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            $0.catoid.compare(firstDegreeSelection, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            draft.selectedCatalogCatoid = matched.catoid
        } else {
            draft.selectedCatalogCatoid = fallback.catoid
        }
    }

    private func normalizedCatalogTypeLabel(from rawTitle: String, catoid: String) -> String {
        ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: rawTitle, catoid: catoid)
    }

    private func fetchUniversityNames() -> [String] {
        let request = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let rows = (try? coreDataManager.viewContext.fetch(request)) ?? []
        return rows
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func handleContinue() {
        let currentStep = coordinator.currentStep

        draft.reconcileCounts()
        coordinator.validationMessage = validateCurrentStep()

        guard coordinator.validationMessage == nil else { return }

        if currentStep == .identity && catalogSyncRequired {
            switch catalogSyncPhase {
            case .idle, .failed:
                startCatalogSyncTask()
                coordinator.validationMessage = "Preparing your school catalog."
                return
            case .inProgress:
                coordinator.validationMessage = "Catalog sync is still in progress."
                return
            case .succeeded:
                break
            }
        } else if currentStep != .identity && catalogSyncRequired {
            switch catalogSyncPhase {
            case .idle, .failed:
                startCatalogSyncTask()
                coordinator.validationMessage = "Preparing your school catalog."
                return
            case .inProgress:
                coordinator.validationMessage = "Catalog sync is still in progress."
                return
            case .succeeded:
                break
            }
        }

        if coordinator.isLastStep {
            handleFinishContinue()
        } else {
            coordinator.goNext()
            reloadContextOptions()
        }
    }

    private func resetCatalogSyncState() {
        catalogSyncTask?.cancel()
        handoffThresholdTask?.cancel()
        catalogSyncPhase = .idle
        catalogSyncProgress = 0
        catalogSyncMessage = "Catalog sync has not started yet."
        autoStartedSyncForSchool = nil
        catalogSyncVisualPhase = .discovering
        lockedCourseDenominator = 0
        handoffReady = false
        catalogSyncStartDate = nil
        lastScrapeAuditPath = nil
    }

    private func autoStartCatalogSyncIfNeeded() {
        guard catalogSyncRequired else { return }
        guard catalogSyncPhase == .idle else { return }

        let school = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !school.isEmpty else { return }
        guard autoStartedSyncForSchool != school else { return }

        autoStartedSyncForSchool = school
        startCatalogSyncTask()
    }

    private func startCatalogSyncTask() {
        guard catalogSyncPhase != .inProgress else { return }
        catalogSyncTask?.cancel()
        catalogSyncTask = Task {
            await runCatalogSyncForSelectedSchool()
        }
    }

    private func scheduleAutoHandoffThreshold() {
        handoffThresholdTask?.cancel()
        handoffThresholdTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            guard catalogSyncPhase == .inProgress else { return }
            handoffReady = true
        }
    }

    private func handleFinishContinue() {
        guard !coordinator.isCommitting else { return }

        if catalogSyncRequired {
            switch catalogSyncPhase {
            case .idle, .failed:
                startCatalogSyncTask()
                return
            case .inProgress:
                coordinator.validationMessage = "Catalog sync is still in progress. Please wait for completion before entering your workspace."
                return
            case .succeeded:
                break
            }
        }

        commitAndFinish()
    }

    private func runCatalogSyncForSelectedSchool() async {
        defer {
            catalogSyncTask = nil
            handoffThresholdTask?.cancel()
            handoffThresholdTask = nil
        }

        let schoolName = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schoolName.isEmpty else { return }

        catalogSyncPhase = .inProgress
        catalogSyncVisualPhase = .discovering
        catalogSyncProgress = 0.05
        catalogSyncMessage = "Resolving school profile..."
        coordinator.validationMessage = nil
        handoffReady = false
        catalogSyncStartDate = Date()
        lockedCourseDenominator = 0
        scheduleAutoHandoffThreshold()

        let toastID = notifications.post(
            kind: .progress,
            title: "Catalog Sync",
            message: "Resolving \(schoolName)…",
            progress: 0.05,
            isDismissible: true
        )

        do {
            notifications.update(id: toastID, message: "Loading school manifest…", progress: 0.15)
            catalogSyncProgress = 0.15
            catalogSyncMessage = "Loading school manifest..."

            let manifest = try await resolveSchoolManifest(named: schoolName)
            let canonicalSchoolName = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !canonicalSchoolName.isEmpty {
                draft.schoolName = canonicalSchoolName
                if !universityOptions.contains(where: { $0.caseInsensitiveCompare(canonicalSchoolName) == .orderedSame }) {
                    universityOptions.append(canonicalSchoolName)
                    universityOptions.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
            }

            let format = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let shouldRunModernCampusScraper = format == "acalog" || format == "moderncampus"

            if shouldRunModernCampusScraper {
                try await runModernCampusCatalogSync(manifest: manifest, toastID: toastID)
            } else {
                notifications.update(id: toastID, message: "Discovering catalog profile…", progress: 0.2)
                catalogSyncProgress = 0.2
                catalogSyncMessage = "Discovering curriculum metadata..."

                let profile = try await githubService.downloadSchoolProfile(schoolID: manifest.id)

                catalogSyncVisualPhase = .downloading
                lockedCourseDenominator = max(1, profile.courses.count)
                notifications.update(id: toastID, message: "Downloading courses…", progress: 0.45)
                catalogSyncProgress = 0.45
                catalogSyncMessage = "Downloading 0 of \(lockedCourseDenominator) courses..."

                catalogSyncVisualPhase = .importing
                notifications.update(id: toastID, message: "Importing catalog to local database…", progress: 0.75)
                catalogSyncProgress = 0.75
                catalogSyncMessage = "Importing \(lockedCourseDenominator) courses into local database..."

                try await coreDataManager.importSchoolCatalog(profile)
                _ = coreDataManager.setActiveUniversity(named: canonicalSchoolName.isEmpty ? schoolName : canonicalSchoolName)
            }
            UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)

            notifications.complete(
                id: toastID,
                kind: .success,
                title: "Catalog Ready",
                message: "\(canonicalSchoolName.isEmpty ? schoolName : canonicalSchoolName) is synced and ready.",
                autoDismissAfter: 4
            )

            catalogSyncPhase = .succeeded
            catalogSyncProgress = 1
            if let auditPath = lastScrapeAuditPath, !auditPath.isEmpty {
                catalogSyncMessage = "Catalog sync completed. Audit CSV: \(auditPath)"
            } else {
                catalogSyncMessage = "Catalog sync completed."
            }
            reloadContextOptions()
        } catch {
            notifications.dismiss(id: toastID)
            notifications.post(
                kind: .error,
                title: "Catalog Sync Failed",
                message: error.localizedDescription,
                isDismissible: true,
                autoDismissAfter: 6
            )

            catalogSyncPhase = .failed
            catalogSyncProgress = 0
            catalogSyncMessage = "Sync failed: \(error.localizedDescription)"
            coordinator.validationMessage = "Catalog sync failed. Retry to continue."
            UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
        }
    }

    private func runModernCampusCatalogSync(manifest: SchoolManifest, toastID: UUID) async throws {
        let catalogURL = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else {
            throw ScraperError.invalidURL
        }

        notifications.update(id: toastID, message: "Discovering catalogs…", progress: 0.2)
        catalogSyncVisualPhase = .discovering
        catalogSyncProgress = 0.2
        catalogSyncMessage = "Discovering ModernCampus catalogs..."

        let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
        guard let baseURL = URL(string: normalizedCatalogURL) else {
            throw ScraperError.invalidURL
        }

        let discovered = (try? await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedCatalogURL)) ?? []
        let reducedDiscovered = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: discovered)
        let catalogsToScrape: [ModernCampusCatalogDescriptor]
        if !reducedDiscovered.isEmpty {
            catalogsToScrape = reducedDiscovered
        } else {
            let catalogID: String
            if let catoidHint, !catoidHint.isEmpty {
                catalogID = catoidHint
            } else {
                catalogID = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL)
            }
            catalogsToScrape = [ModernCampusCatalogDescriptor(catoid: catalogID, title: "Catalog")]
        }

        let normalizedOptions = normalizedCatalogTypeOptions(from: catalogsToScrape)
        if !normalizedOptions.isEmpty {
            catalogTypeOptions = normalizedOptions
            syncDegreeSelectionWithCatalogOptions()
        }

        var coursesByCode: [String: CatalogCourse] = [:]
        var programsByCatalogAndURL: [String: ScrapedProgram] = [:]
        var perCatalogCourseRows: [(catoid: String, title: String, course: CatalogCourse)] = []

        func normalizeCourseCode(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }

        for (index, catalog) in catalogsToScrape.enumerated() {
            let ordinal = index + 1
            let fraction = Double(ordinal) / Double(max(1, catalogsToScrape.count))
            let progress = 0.2 + (0.45 * fraction)

            notifications.update(
                id: toastID,
                message: "Scraping \(catalog.title.isEmpty ? "catalog" : catalog.title)… (\(ordinal)/\(catalogsToScrape.count))",
                progress: progress
            )
            catalogSyncVisualPhase = .downloading
            catalogSyncProgress = progress
            catalogSyncMessage = "Scraping \(catalog.title.isEmpty ? "catalog" : catalog.title)... (\(ordinal)/\(catalogsToScrape.count))"

            let scrapedCourses = try await ModernCampusEngine.fetchAllCourses(baseURL: normalizedCatalogURL, catoid: catalog.catoid)
            for course in scrapedCourses {
                perCatalogCourseRows.append((catoid: catalog.catoid, title: catalog.title, course: course))
            }
            for course in scrapedCourses {
                let key = normalizeCourseCode(course.courseCode)
                if coursesByCode[key] == nil {
                    coursesByCode[key] = CatalogCourse(
                        id: course.id,
                        courseCode: key,
                        title: course.title,
                        description: course.description,
                        credits: course.credits,
                        department: course.department,
                        prerequisites: course.prerequisites,
                        prerequisiteText: course.prerequisiteText,
                        corequisites: course.corequisites,
                        typicallyOffered: course.typicallyOffered
                    )
                }
            }

            let programScraper = UniversalCatalogScraper()
            let catalogIDInt = Int(catalog.catoid) ?? 0
            let scrapedPrograms = try await programScraper.scrapeAllPrograms(baseURL: baseURL, catalogID: catalogIDInt)
            for program in scrapedPrograms {
                let normalizedURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
                let dedupStem = normalizedURL.isEmpty
                    ? program.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    : normalizedURL
                let dedupKey = "\(catalog.catoid)|\(dedupStem)"
                programsByCatalogAndURL[dedupKey] = program
            }
        }

        let courses = Array(coursesByCode.values)
        let programs = Array(programsByCatalogAndURL.values)

        do {
            let csvURL = try writeOnboardingScrapeCSV(manifest: manifest, rows: perCatalogCourseRows)
            lastScrapeAuditPath = csvURL.path
            notifications.update(
                id: toastID,
                message: "Saved scrape audit: \(csvURL.path)",
                progress: 0.7
            )
            catalogSyncMessage = "Saved scrape audit to \(csvURL.path)."
        } catch {
            lastScrapeAuditPath = nil
            notifications.post(
                kind: .error,
                title: "Scrape Export Failed",
                message: error.localizedDescription,
                isDismissible: true,
                autoDismissAfter: 8
            )
            catalogSyncMessage = "Catalog scraped, but CSV export failed: \(error.localizedDescription)"
        }

        catalogSyncVisualPhase = .importing
        notifications.update(id: toastID, message: "Importing scraped catalog…", progress: 0.78)
        catalogSyncProgress = 0.78
        catalogSyncMessage = "Importing \(courses.count) courses and \(programs.count) programs..."
        lockedCourseDenominator = max(1, courses.count)

        let profile = SchoolProfile(
            schoolID: manifest.id,
            schoolName: manifest.name,
            catalogURL: normalizedCatalogURL,
            version: "1.0.0-onboarding-scraped",
            lastUpdated: Date(),
            courses: courses,
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )

        // Import even when the live crawl returned zero courses so UniversityEntity/context
        // still exists and downstream saveMajors/fetchMajors can resolve the selected school.
        try await coreDataManager.importSchoolCatalog(profile)

        var departmentToGroup: [String: String] = [:]
        for (dedupKey, program) in programsByCatalogAndURL {
            let department = (program.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !department.isEmpty else { continue }

            let catoidFromKey = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToScrape.first { $0.catoid == catoidFromKey }
            let catalogLabel = catalogMeta.map {
                normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid)
            } ?? "Catalog \(catoidFromKey)"

            let preferredGroup = (program.college ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let group = preferredGroup.isEmpty ? catalogLabel : preferredGroup

            if departmentToGroup[department] == nil {
                departmentToGroup[department] = group
            }
        }

        if !departmentToGroup.isEmpty {
            let deptRows = departmentToGroup.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { dept in
                (name: dept, code: nil as String?, school: departmentToGroup[dept])
            }
            try coreDataManager.saveDepartments(deptRows, for: manifest.name)
        }

        func inferDegreeLevel(programType: String, degreeType: String?) -> String {
            if programType.lowercased().contains("minor") {
                return "Undergraduate"
            }

            let token = (degreeType ?? "").uppercased()
            if token.contains("PHD") { return "PhD" }

            let undergrad = ["BA", "BS", "BFA", "BM", "BARCH"]
            if undergrad.contains(where: { token.contains($0) }) { return "Undergraduate" }

            let graduate = ["MA", "MS", "MBA", "MENG", "MFA", "JD", "MD", "DDS", "DMD", "PHARMD"]
            if graduate.contains(where: { token.contains($0) }) { return "Graduate" }

            return "Undergraduate"
        }

        func acalogURLForcingCatoid(_ rawURL: String, catoid: String) -> String {
            guard var components = URLComponents(string: rawURL) else { return rawURL }
            var queryItems = components.queryItems ?? []
            if let idx = queryItems.firstIndex(where: { $0.name.lowercased() == "catoid" }) {
                queryItems[idx] = URLQueryItem(name: "catoid", value: catoid)
            } else {
                queryItems.append(URLQueryItem(name: "catoid", value: catoid))
            }
            components.queryItems = queryItems
            return components.string ?? rawURL
        }

        var rows = programsByCatalogAndURL.sorted(by: { $0.key < $1.key }).map { dedupKey, program in
            let catoidFromKey = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToScrape.first { $0.catoid == catoidFromKey }
            let catalogBucket = catalogMeta.map {
                normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid)
            } ?? "Catalog \(catoidFromKey)"

            let normalizedType = program.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawDegreeType = program.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDegreeType = (rawDegreeType ?? "").lowercased()

            let isCredentialLike = normalizedType.contains("certificate") ||
                normalizedType.contains("credential") ||
                normalizedDegreeType.contains("certificate") ||
                normalizedDegreeType.contains("credential")
            let isMinor = normalizedType.contains("minor") && !isCredentialLike

            let degreeType: String?
            if let rawDegreeType, !rawDegreeType.isEmpty {
                degreeType = rawDegreeType
            } else if normalizedType.contains("certificate") {
                degreeType = "Certificate"
            } else if normalizedType.contains("credential") {
                degreeType = "Credential"
            } else if isMinor {
                degreeType = "Minor"
            } else {
                degreeType = nil
            }

            let trimmedURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlForStorage: String? = {
                guard !trimmedURL.isEmpty else { return nil }
                guard !catoidFromKey.isEmpty else { return trimmedURL }
                return acalogURLForcingCatoid(trimmedURL, catoid: catoidFromKey)
            }()

            return (
                name: program.name,
                degreeLevel: catalogBucket,
                degreeType: degreeType,
                isMinor: isMinor,
                department: program.department,
                url: urlForStorage,
                resolvedDepartment: program.department,
                resolvedCollege: program.college,
                mappingConfidence: nil as Double?,
                mappingSource: "onboarding.moderncampus" as String?,
                requirements: program.requirements,
                sourceCatalogCatoid: catoidFromKey.isEmpty ? nil : catoidFromKey
            )
        }

        // Fallback: if program scraping returned no rows, derive majors/minors from profile
        // degree requirements so Academic Setup dropdowns still populate.
        if rows.isEmpty {
            if let downloaded = try? await githubService.downloadSchoolProfile(schoolID: manifest.id) {
                var seen = Set<String>()
                rows = downloaded.degreeRequirements.compactMap { req in
                    let major = req.major.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !major.isEmpty else { return nil }

                    let degreeType = req.degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isMinor = degreeType.lowercased().contains("minor") || major.lowercased().contains("minor")
                    let key = "\(major.lowercased())|\(degreeType.lowercased())|\(isMinor)"
                    guard seen.insert(key).inserted else { return nil }

                    return (
                        name: major,
                        degreeLevel: inferDegreeLevel(programType: isMinor ? "Minor" : "Major", degreeType: degreeType),
                        degreeType: degreeType.isEmpty ? (isMinor ? "Minor" : nil) : degreeType,
                        isMinor: isMinor,
                        department: nil as String?,
                        url: nil as String?,
                        resolvedDepartment: nil as String?,
                        resolvedCollege: nil as String?,
                        mappingConfidence: nil as Double?,
                        mappingSource: "onboarding.profile-fallback" as String?,
                        requirements: nil as [DegreeRequirement]?,
                        sourceCatalogCatoid: nil as String?
                    )
                }
            }
        }

        if !rows.isEmpty {
            try coreDataManager.saveMajors(rows, for: manifest.name)
        }

        _ = coreDataManager.setActiveUniversity(named: manifest.name)
    }

    private func writeOnboardingScrapeCSV(
        manifest: SchoolManifest,
        rows: [(catoid: String, title: String, course: CatalogCourse)]
    ) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let safeSchoolID = manifest.id
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "_", options: .regularExpression)
        let filename = "\(safeSchoolID)_onboarding_scrape_\(timestamp).csv"

        func csvCell(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        var lines: [String] = []
        lines.append("school_id,school_name,catalog_catoid,catalog_title,course_code,course_title,credits,department,description")

        for row in rows {
            let course = row.course
            let line = [
                csvCell(manifest.id),
                csvCell(manifest.name),
                csvCell(row.catoid),
                csvCell(row.title),
                csvCell(course.courseCode),
                csvCell(course.title),
                String(course.credits),
                csvCell(course.department ?? ""),
                csvCell(course.description ?? "")
            ].joined(separator: ",")
            lines.append(line)
        }

        let content = lines.joined(separator: "\n")

        let candidateDirectories = try resolveOnboardingScrapeExportDirectories()
        var lastError: Error?

        for directory in candidateDirectories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fileURL = directory.appendingPathComponent(filename)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return fileURL
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw CocoaError(.fileWriteUnknown)
    }

    private func resolveOnboardingScrapeExportDirectories() throws -> [URL] {
        // Preferred in local dev: repo-level exports directory next to project files.
        // #filePath points to .../College/College/App/OnboardingRootView.swift.
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // College
            .deletingLastPathComponent() // repo root
        let repoExports = repoRoot.appendingPathComponent("exports", isDirectory: true)

        // Explicit non-sandbox user home path for local debug runs.
        let userHomeAppSupportExports = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)

        // Runtime-safe fallback for sandboxed builds.
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appSupportExports = appSupport
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)

        // Try repo exports first, then explicit home Application Support,
        // then container/sandbox Application Support.
        return [repoExports, userHomeAppSupportExports, appSupportExports]
    }

    private func resolveSchoolManifest(named schoolName: String) async throws -> SchoolManifest {
        let normalizedTarget = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else {
            throw GitHubError.invalidData
        }

        let cached = githubService.loadCachedSchoolsList() ?? []
        if let found = matchSchoolManifest(named: normalizedTarget, in: cached) {
            return found
        }

        let fetched = try await githubService.fetchSchoolsList()
        try? githubService.cacheSchoolsList(fetched)

        if let found = matchSchoolManifest(named: normalizedTarget, in: fetched) {
            return found
        }

        throw GitHubError.invalidData
    }

    private func matchSchoolManifest(named schoolName: String, in schools: [SchoolManifest]) -> SchoolManifest? {
        let target = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let exact = schools.first(where: { $0.name.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact
        }

        return schools.first(where: {
            let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.localizedCaseInsensitiveContains(target) || target.localizedCaseInsensitiveContains(name)
        })
    }

    private func validateCurrentStep() -> String? {
        switch coordinator.currentStep {
        case .identity:
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter your name to continue."
            }
            if draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Select your school to continue."
            }
            return nil

        case .academicSetup:
            if catalogSyncRequired {
                switch catalogSyncPhase {
                case .idle, .inProgress:
                    return "Catalog is still syncing. Wait for majors/minors to load."
                case .failed:
                    return "Catalog sync failed. Retry sync to continue."
                case .succeeded:
                    break
                }
            }

            if draft.selectedDegreeLevels.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return "Select degree level values for all degree entries."
            }

            if draft.selectedMajors.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return "Select or enter majors for all major entries."
            }

            if draft.selectedMinors.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return "Fill or clear minor entries before continuing."
            }

            if !majorOptions.isEmpty && draft.majorCount > majorOptions.count {
                return "Your selected major count exceeds currently available programs for this school/degree context."
            }

            if !minorOptions.isEmpty && draft.minorCount > minorOptions.count {
                return "Your selected minor count exceeds currently available minor/certificate options in this context."
            }

            return nil

        case .academicHistory:
            return nil

        case .integrations:
            return nil

        case .finish:
            return nil
        }
    }

    private func commitAndFinish() {
        coordinator.isCommitting = true

        if coreDataManager.profile == nil {
            coreDataManager.fetchProfile()
        }

        guard let profile = coreDataManager.profile else {
            coordinator.validationMessage = "Could not load your profile. Please try again."
            coordinator.isCommitting = false
            return
        }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchool = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)

        let validMajors = draft.selectedMajors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let validMinors = draft.selectedMinors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        profile.name = trimmedName.isEmpty ? nil : trimmedName
        profile.universityEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
        profile.collegeName = trimmedSchool.isEmpty ? nil : trimmedSchool
        profile.degreeLevel = draft.selectedDegreeLevels.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.major = validMajors.first
        profile.secondaryMajor = validMajors.count > 1 ? validMajors[1] : nil
        profile.minor = validMinors.first

        if !trimmedSchool.isEmpty {
            _ = coreDataManager.setActiveUniversity(named: trimmedSchool)
        }

        coreDataManager.save()

        let lmsRaw = draft.selectedLMS.map(\.rawValue).sorted()
        let widgetsRaw = draft.selectedWidgets.map(\.rawValue).sorted()
        UserDefaults.standard.set(lmsRaw, forKey: OnboardingPreferenceBridge.selectedLMSKey)
        UserDefaults.standard.set(widgetsRaw, forKey: OnboardingPreferenceBridge.selectedWidgetsKey)
        UserDefaults.standard.set(widgetsRaw, forKey: OnboardingPreferenceBridge.dashboardWidgetsKey)
        UserDefaults.standard.set(lmsRaw, forKey: OnboardingPreferenceBridge.pendingLMSConnectKey)

        if OnboardingPreferenceBridge.shouldOpenBrightspace(from: lmsRaw) {
            UserDefaults.standard.set(true, forKey: BrightspaceWebCoordinator.pendingLoadPortalKey)
        }

        let academicDraft = OnboardingAcademicDraft(
            degreeCount: draft.degreeCount,
            majorCount: draft.majorCount,
            minorCount: draft.minorCount,
            selectedDegreeLevels: draft.selectedDegreeLevels,
            selectedCatalogCatoid: draft.selectedCatalogCatoid,
            selectedMajors: draft.selectedMajors,
            selectedMinors: draft.selectedMinors
        )
        if let data = try? JSONEncoder().encode(academicDraft) {
            UserDefaults.standard.set(data, forKey: OnboardingPreferenceBridge.academicDraftKey)
        }

        if catalogSyncPhase == .inProgress {
            UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
        } else {
            UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
        }

        // Prevent late async onboarding updates from racing the root-view handoff.
        catalogSyncTask?.cancel()
        catalogSyncTask = nil
        handoffThresholdTask?.cancel()
        handoffThresholdTask = nil

        onboardingCompleted = true
        coordinator.isCommitting = false

        // Execute the app-level handoff on the next runloop turn so state commits
        // settle before the root view swaps from onboarding to the main workspace.
        DispatchQueue.main.async {
            onComplete()
        }
    }
}

private struct OnboardingSyncMotionCard: View {
    let phase: OnboardingCatalogSyncPhase
    let progress: Double
    let statusMessage: String
    let reduceMotion: Bool

    @State private var isHovering = false

    private var tint: Color {
        switch phase {
        case .idle: return .secondary
        case .inProgress: return .accentColor
        case .succeeded: return .green
        case .failed: return .orange
        }
    }

    private var symbolName: String {
        switch phase {
        case .idle: return "sparkles"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            syncIcon
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Catalog Handoff")
                    .font(.system(size: 12, weight: .bold))
                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if phase == .inProgress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(isHovering ? 0.7 : 0.35), lineWidth: isHovering ? 1.2 : 1)
        )
        .phaseAnimator([false, true]) { content, phaseValue in
            content
                .scaleEffect(reduceMotion ? 1 : (phaseValue && phase == .inProgress ? 1.01 : 1))
        } animation: { _ in
            reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 1.1)
        }
        .onContinuousHover { hover in
            guard !reduceMotion else {
                isHovering = false
                return
            }

            switch hover {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: isHovering)
    }

    private var backgroundStyle: AnyShapeStyle {
        switch phase {
        case .idle:
            return AnyShapeStyle(Color.secondary.opacity(0.08))
        case .inProgress:
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        case .succeeded:
            return AnyShapeStyle(Color.green.opacity(0.12))
        case .failed:
            return AnyShapeStyle(Color.orange.opacity(0.12))
        }
    }

    private var syncIcon: some View {
        Image(systemName: symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .keyframeAnimator(initialValue: 1.0, repeating: phase == .inProgress && !reduceMotion) { icon, scale in
                icon.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    CubicKeyframe(1.0, duration: 0.0)
                    CubicKeyframe(1.12, duration: 0.45)
                    CubicKeyframe(1.0, duration: 0.45)
                }
            }
    }
}

private struct OnboardingDecisionCard: View {
    let title: String
    let message: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
    }
}
