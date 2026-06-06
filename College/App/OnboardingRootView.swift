// OnboardingRootView.swift
// Feature: App
// Purpose: App module — OnboardingAcademicDraft.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
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

private enum OnboardingCatalogScrapeStatus: Equatable {
    case pending
    case scraping
    case completed
    case failed
}

private struct OnboardingCatalogScrapeProgressItem: Identifiable, Equatable {
    let catoid: String
    let title: String
    var status: OnboardingCatalogScrapeStatus

    var id: String { catoid }
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
    @Environment(AppContainer.self) private var container
    private var brightspaceCoordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var coordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
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
    @State private var minorOptionsBySection: [OnboardingMajorSection] = []
    @State private var courseLeafCatalogNeedsRefresh = false
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
    @State private var catalogScrapeProgress: [OnboardingCatalogScrapeProgressItem] = []
    @State private var reloadContextOptionsTask: Task<Void, Never>?
    @State private var reloadContextOptionsToken = UUID()
    @State private var lastAppliedContextOptionsKey = ""

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
            scheduleReloadContextOptions()
            draft.reconcileCounts()
            bootstrapUniversityOptionsIfNeeded()
            refreshCatalogTypeOptionsForSelectedSchool()
        }
        .onDisappear {
            reloadContextOptionsTask?.cancel()
            reloadContextOptionsTask = nil
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
                        scheduleReloadContextOptions()
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

                if !draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()

                    Text("Catalogs at this school")
                        .font(.system(size: 12, weight: .bold))

                    if isLoadingCatalogTypeOptions {
                        ProgressView("Discovering catalogs…")
                            .controlSize(.small)
                    } else if catalogTypeOptions.isEmpty {
                        Text("No catalogs discovered yet. Continue to import your school catalog, or pick another school.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Names match your school's catalog site. Continue to run a fast program index for each.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)

                        catalogDiscoveryOrScrapeList
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
                            if !catalogScrapeProgress.isEmpty {
                                catalogDiscoveryOrScrapeList
                            }
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
                                if courseLeafCatalogNeedsRefresh {
                                    Label("Program list needs a full refresh", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.orange)
                                    Text("A quick sync reused old cached programs. Refresh re-indexes the full bulletin (a few minutes).")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                    Button("Refresh program list") {
                                        refreshCourseLeafProgramIndex()
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                } else {
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
                } else if courseLeafCatalogNeedsRefresh {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your program list looks incomplete. Refresh to index the full school bulletin.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.orange)
                        Button("Refresh program list") {
                            refreshCourseLeafProgramIndex()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
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
                            scheduleReloadContextOptions()
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
                    if catalogSyncRequired && catalogSyncPhase != .succeeded && minorOptions.isEmpty && minorOptionsBySection.isEmpty {
                        Text("Minors/certificates will appear after catalog sync completes.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if catalogSyncPhase == .succeeded && minorOptions.isEmpty && minorOptionsBySection.isEmpty {
                        Text("No minors or certificates found for this Degree Level in the selected catalog.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if minorOptions.isEmpty && minorOptionsBySection.isEmpty {
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
                            if !minorOptionsBySection.isEmpty {
                                ForEach(minorOptionsBySection) { section in
                                    Section(section.title) {
                                        ForEach(section.majors, id: \.self) { minor in
                                            Text(minor).tag(minor)
                                        }
                                    }
                                }
                            } else {
                                ForEach(minorOptions, id: \.self) { minor in
                                    Text(minor).tag(minor)
                                }
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
        if catalogSyncPhase == .succeeded { return false }
        if isModernCampusBackedSchoolSelection(school) { return true }
        return !CatalogAvailability.hasUniversityCatalog(name: school)
    }

    @ViewBuilder
    private var catalogDiscoveryOrScrapeList: some View {
        let rows = catalogScrapeProgress.isEmpty
            ? catalogTypeOptions.map {
                OnboardingCatalogScrapeProgressItem(
                    catoid: $0.catoid,
                    title: $0.label,
                    status: .pending
                )
            }
            : catalogScrapeProgress

        ForEach(rows) { item in
            HStack(spacing: 10) {
                catalogScrapeStatusIcon(item.status)
                    .frame(width: 18, height: 18)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if catalogSyncPhase == .inProgress, item.status == .scraping {
                    Text("Indexing…")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func catalogScrapeStatusIcon(_ status: OnboardingCatalogScrapeStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .scraping:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func isModernCampusBackedSchoolSelection(_ schoolName: String) -> Bool {
        let schools = githubService.loadResolvedSchoolsList()
        guard let manifest = CatalogBackgroundSyncRunner.matchSchoolManifest(named: schoolName, in: schools) else {
            return false
        }
        let format = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: format)
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

    private func contextOptionsInputsKey() -> String {
        let school = draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeLevel = draft.selectedDegreeLevels.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let catoid = draft.selectedCatalogCatoid.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            school,
            degreeLevel,
            catoid,
            String(catalogTypeOptions.count),
            String(catalogSyncPhase == .succeeded),
        ].joined(separator: "\u{1f}")
    }

    private func scheduleReloadContextOptions() {
        reloadContextOptionsTask?.cancel()
        let token = UUID()
        reloadContextOptionsToken = token
        reloadContextOptionsTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, reloadContextOptionsToken == token else { return }

            let key = contextOptionsInputsKey()
            guard key != lastAppliedContextOptionsKey else { return }

            await Task.yield()
            guard !Task.isCancelled, reloadContextOptionsToken == token else { return }
            guard contextOptionsInputsKey() == key else { return }

            reloadContextOptions()
            lastAppliedContextOptionsKey = key
        }
    }

    private func reloadContextOptionsImmediately() {
        reloadContextOptionsTask?.cancel()
        reloadContextOptions()
        lastAppliedContextOptionsKey = contextOptionsInputsKey()
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
                let majors = CatalogProgramReadBridge.fetchMajors(
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
                    let majors = CatalogProgramReadBridge.fetchMajors(
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

        let includeCollegeBuckets = isCourseLeafBackedSchoolSelection(school)
        var departmentGroups: [(group: String, departments: [String])] = []
        var seenDepartmentGroupKeys = Set<String>()
        for level in levelsToQuery {
            let groupsForLevel = collegePersistence.fetchDepartmentGroups(
                for: school,
                degreeLevel: level,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid,
                includeCollegeBuckets: includeCollegeBuckets
            )
            for group in groupsForLevel {
                let key = group.group.lowercased() + "|" + group.departments.joined(separator: "|").lowercased()
                if seenDepartmentGroupKeys.insert(key).inserted {
                    departmentGroups.append(group)
                }
            }
        }
        if includeCollegeBuckets {
            majorOptionsBySection = collegePersistence.fetchProgramPickerSections(
                for: school,
                degreeLevels: levelsToQuery,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid,
                includeMinors: false,
                includeCollegeBuckets: true,
                allowLegacyCatoidFallback: useLegacyCatoidFallback
            )
            .compactMap { section in
                let majors = section.labels.filter(isSelectableMajorLabel(_:))
                guard !majors.isEmpty else { return nil }
                return OnboardingMajorSection(title: section.title, majors: majors)
            }
        } else {
            majorOptionsBySection = buildProgramSections(
                from: departmentGroups,
                programFetcher: { department in
                    fetchMajorUniverse(department: department, allowCatoidFallback: true)
                }
            )
        }

        if majorOptionsBySection.isEmpty, !majorOptions.isEmpty, includeCollegeBuckets {
            majorOptionsBySection = collegePersistence.fetchProgramPickerSections(
                for: school,
                degreeLevels: levelsToQuery,
                sourceCatoid: nil,
                includeMinors: false,
                includeCollegeBuckets: true,
                allowLegacyCatoidFallback: false
            )
            .compactMap { section in
                let majors = section.labels.filter(isSelectableMajorLabel(_:))
                guard !majors.isEmpty else { return nil }
                return OnboardingMajorSection(title: section.title, majors: majors)
            }
        }

        func fetchMinorUniverse(department: String? = nil, allowCatoidFallback: Bool = true) -> [String] {
            var collected: [String] = []
            var seen = Set<String>()
            for level in levelsToQuery {
                let minorsForLevel = CatalogProgramReadBridge.fetchMajors(
                    for: school,
                    degreeLevel: level,
                    department: department,
                    degreeType: nil,
                    includeMinors: true,
                    sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid
                )
                for minor in minorsForLevel where seen.insert(minor).inserted {
                    collected.append(minor)
                }
            }

            if collected.isEmpty, !selectedCatoid.isEmpty, allowCatoidFallback, useLegacyCatoidFallback {
                for level in levelsToQuery {
                    let minorsForLevel = CatalogProgramReadBridge.fetchMajors(
                        for: school,
                        degreeLevel: level,
                        department: department,
                        degreeType: nil,
                        includeMinors: true,
                        sourceCatoid: nil
                    )
                    for minor in minorsForLevel where seen.insert(minor).inserted {
                        collected.append(minor)
                    }
                }
            }
            return collected
        }

        if includeCollegeBuckets {
            minorOptionsBySection = collegePersistence.fetchProgramPickerSections(
                for: school,
                degreeLevels: levelsToQuery,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid,
                includeMinors: true,
                includeCollegeBuckets: true,
                allowLegacyCatoidFallback: useLegacyCatoidFallback
            )
            .compactMap { section in
                let programs = section.labels.filter(isSelectableMajorLabel(_:))
                guard !programs.isEmpty else { return nil }
                return OnboardingMajorSection(title: section.title, majors: programs)
            }
        } else {
            minorOptionsBySection = buildProgramSections(
                from: departmentGroups,
                programFetcher: { department in
                    fetchMinorUniverse(department: department, allowCatoidFallback: true)
                }
            )
        }

        var minors = fetchMinorUniverse(allowCatoidFallback: true)
            .filter(isSelectableMajorLabel(_:))
        minors = Array(Set(minors)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if minors.isEmpty {
            var certificates = collegePersistence.fetchCertificates(
                for: school,
                sourceCatoid: selectedCatoid.isEmpty ? nil : selectedCatoid
            )
            if certificates.isEmpty, !selectedCatoid.isEmpty, useLegacyCatoidFallback {
                certificates = collegePersistence.fetchCertificates(
                    for: school,
                    sourceCatoid: nil
                )
            }
            minorOptions = certificates
        } else {
            minorOptions = minors
        }

        updateCourseLeafRefreshHint(school: school)
    }

    private func updateCourseLeafRefreshHint(school: String) {
        guard isCourseLeafBackedSchoolSelection(school) else {
            courseLeafCatalogNeedsRefresh = false
            return
        }
        let programCount = max(
            majorOptions.count,
            majorOptionsBySection.reduce(0) { $0 + $1.majors.count }
        )
        courseLeafCatalogNeedsRefresh = programCount > 0 && programCount < 25
    }

    private func isCourseLeafBackedSchoolSelection(_ schoolName: String) -> Bool {
        let schools = githubService.loadResolvedSchoolsList()
        guard let manifest = CatalogBackgroundSyncRunner.matchSchoolManifest(named: schoolName, in: schools) else {
            return false
        }
        return manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "courseleaf"
    }

    private func refreshCourseLeafProgramIndex() {
        CatalogBackgroundSyncRunner.setForceNextRescrape(true)
        resetCatalogSyncState()
        courseLeafCatalogNeedsRefresh = false
        startCatalogSyncTask()
    }

    private func buildProgramSections(
        from departmentGroups: [(group: String, departments: [String])],
        programFetcher: (String?) -> [String]
    ) -> [OnboardingMajorSection] {
        var groupedSections: [OnboardingMajorSection] = []
        for group in departmentGroups {
            for department in group.departments {
                let programsForDepartment = programFetcher(department)
                    .filter(isSelectableMajorLabel(_:))
                if programsForDepartment.isEmpty { continue }
                let unique = Array(Set(programsForDepartment)).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                groupedSections.append(OnboardingMajorSection(title: "\(group.group) > \(department)", majors: unique))
            }
        }
        return groupedSections
    }

    private func isSelectableMajorLabel(_ major: String) -> Bool {
        let baseName = major
            .replacingOccurrences(of: ",\\s*[A-Z./]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if CourseLeafProgramURLParser.isJunkProgramTitle(baseName) { return false }

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
        SchoolManifestSelection.scraperBackedNames(from: githubService.loadResolvedSchoolsList())
    }

    private func refreshUniversityOptionsFromManifest() {
        guard !isLoadingUniversityOptions else { return }
        isLoadingUniversityOptions = true
        universityOptionsLoadError = nil

        let cachedNames = cachedSchoolNames()
        if !cachedNames.isEmpty {
            universityOptions = cachedNames
        }

        Task {
            do {
                let schools = try await githubService.refreshResolvedSchoolsList()
                let names = SchoolManifestSelection.scraperBackedNames(from: schools)

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
                    if universityOptions.isEmpty {
                        universityOptionsLoadError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func resetCatalogTypeState() {
        catalogTypeOptions = []
        catalogScrapeProgress = []
        draft.selectedCatalogCatoid = ""
        majorOptionsBySection = []
        minorOptionsBySection = []
        lastAppliedContextOptionsKey = ""
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
                guard CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: format) else {
                    await MainActor.run {
                        isLoadingCatalogTypeOptions = false
                        resetCatalogTypeState()
                        scheduleReloadContextOptions()
                    }
                    return
                }

                let catalogURL = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !catalogURL.isEmpty else {
                    await MainActor.run {
                        isLoadingCatalogTypeOptions = false
                        resetCatalogTypeState()
                        scheduleReloadContextOptions()
                    }
                    return
                }

                let descriptors: [ModernCampusCatalogDescriptor]
                if format == "courseleaf" {
                    let catalogs = try await CourseLeafCatalogSegmentDiscoverer.onboardingCatalogs(
                        baseURL: catalogURL,
                        schoolID: manifest.id
                    )
                    descriptors = CourseLeafCatalogSegmentDiscoverer.catalogDescriptors(from: catalogs)
                } else {
                    let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
                    let discovered = (try? await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedCatalogURL)) ?? []

                    if !discovered.isEmpty {
                        descriptors = discovered
                    } else if let catoidHint, !catoidHint.isEmpty {
                        descriptors = [ModernCampusCatalogDescriptor(catoid: catoidHint, title: "Catalog")]
                    } else {
                        let current = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL)
                        descriptors = [ModernCampusCatalogDescriptor(catoid: current, title: "Catalog")]
                    }
                }

                await MainActor.run {
                    isLoadingCatalogTypeOptions = false
                    applyDiscoveredCatalogs(descriptors)
                    reloadContextOptionsImmediately()
                }
            } catch {
                await MainActor.run {
                    isLoadingCatalogTypeOptions = false
                    resetCatalogTypeState()
                    scheduleReloadContextOptions()
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
                label: ModernCampusCatalogLabels.postedDisplayTitle(from: descriptor.title),
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

    private func fetchUniversityNames() -> [String] {
        guard let repo = collegePersistence.catalogRepository,
              let universities = try? repo.fetchUniversities(limit: 500) else {
            return []
        }
        return universities
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
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
                coordinator.goNext()
                reloadContextOptionsImmediately()
                return
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
            scheduleReloadContextOptions()
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
        catalogScrapeProgress = []
    }

    private func applyDiscoveredCatalogs(_ descriptors: [ModernCampusCatalogDescriptor]) {
        let posted = ModernCampusCatalogLabels.filterPostedCatalogs(from: descriptors)
        catalogTypeOptions = posted.map { descriptor in
            OnboardingCatalogTypeOption(
                catoid: descriptor.catoid,
                label: ModernCampusCatalogLabels.postedDisplayTitle(from: descriptor.title),
                rawTitle: descriptor.title
            )
        }
        catalogScrapeProgress = catalogTypeOptions.map {
            OnboardingCatalogScrapeProgressItem(catoid: $0.catoid, title: $0.label, status: .pending)
        }
        syncDegreeSelectionWithCatalogOptions()
    }

    private func markCatalogScrapeStatus(catoid: String, status: OnboardingCatalogScrapeStatus) {
        guard let index = catalogScrapeProgress.firstIndex(where: { $0.catoid == catoid }) else { return }
        catalogScrapeProgress[index].status = status
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
            let shouldUseCatalogIngestCoordinator = CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: format)

            if shouldUseCatalogIngestCoordinator {
                catalogSyncVisualPhase = .downloading
                _ = try await CatalogIngestCoordinator.runCatalogSync(
                    manifest: manifest,
                    toastID: toastID,
                    collegePersistence: collegePersistence,
                    notifications: notifications,
                    githubService: githubService,
                    depth: .light,
                    hooks: CatalogBackgroundSyncRunner.Hooks(
                        onVisualPhase: { phase in
                            catalogSyncVisualPhase = phase == .importing ? .importing : .downloading
                        },
                        onProgress: { progress, message in
                            catalogSyncProgress = progress
                            catalogSyncMessage = message
                        },
                        onCatalogsDiscovered: { catalogs in
                            applyDiscoveredCatalogs(catalogs)
                        },
                        onCatalogIndexStarted: { catoid, _ in
                            markCatalogScrapeStatus(catoid: catoid, status: .scraping)
                        },
                        onCatalogIndexFinished: { catoid, succeeded in
                            markCatalogScrapeStatus(catoid: catoid, status: succeeded ? .completed : .failed)
                        }
                    )
                )
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

                try await collegePersistence.importSchoolCatalog(profile)
                _ = collegePersistence.setActiveUniversity(named: canonicalSchoolName.isEmpty ? schoolName : canonicalSchoolName)
                if let uni = collegePersistence.getActiveUniversity() {
                    CatalogIngestPipeline.postCatalogDataDidCommit(
                        universityID: uni.id,
                        reason: "catalog onboarding profile committed"
                    )
                }
            }
            UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)

            notifications.complete(
                id: toastID,
                kind: .success,
                title: "Catalog Ready",
                message: "\(canonicalSchoolName.isEmpty ? schoolName : canonicalSchoolName) is synced and ready.",
                autoDismissAfter: 4
            )

            if !catalogSyncMessage.localizedCaseInsensitiveContains("skipped")
                && !catalogSyncMessage.localizedCaseInsensitiveContains("unchanged") {
                catalogSyncMessage = "Catalog sync completed."
            }
            catalogSyncPhase = .succeeded
            catalogSyncProgress = 1
            reloadContextOptionsImmediately()

            if coordinator.currentStep == .identity {
                coordinator.validationMessage = nil
                coordinator.goNext()
                reloadContextOptionsImmediately()
            }
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

    private func resolveSchoolManifest(named schoolName: String) async throws -> SchoolManifest {
        let normalizedTarget = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else {
            throw GitHubError.invalidData
        }

        let cached = githubService.loadResolvedSchoolsList()
        if let found = CatalogBackgroundSyncRunner.matchSchoolManifest(named: normalizedTarget, in: cached) {
            return found
        }

        let fetched = try await githubService.refreshResolvedSchoolsList()

        if let found = CatalogBackgroundSyncRunner.matchSchoolManifest(named: normalizedTarget, in: fetched) {
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

        if collegePersistence.profile == nil {
            collegePersistence.fetchProfile()
        }

        guard let profile = collegePersistence.profile else {
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
        if let primary = collegePersistence.ensurePrimaryAcademicProfile() {
            let level = draft.selectedDegreeLevels.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            primary.degreeLevel = level.isEmpty ? nil : level
            let college = trimmedSchool.isEmpty ? nil : trimmedSchool
            if let college, (primary.collegeName ?? "").isEmpty {
                primary.collegeName = college
            }
        }
        ProfileProgramLists.syncToProfile(majors: validMajors, minors: validMinors, collegePersistence: collegePersistence)
        if let primary = collegePersistence.ensurePrimaryAcademicProfile(),
           let primaryMajor = validMajors.first,
           let departmentBucket = ProfileEditProgramMenuData.departmentBucket(
            forMajor: primaryMajor,
            sections: majorOptionsBySection.map {
                ProfileEditMajorSection(title: $0.title, majors: $0.majors)
            }
           ) {
            primary.department = departmentBucket
        }
        collegePersistence.reconcileDeclaredProgramDegreeMetadata()

        if !trimmedSchool.isEmpty {
            _ = collegePersistence.setActiveUniversity(named: trimmedSchool)
        }

        collegePersistence.save()

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
