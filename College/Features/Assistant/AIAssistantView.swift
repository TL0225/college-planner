// AIAssistantView.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantMessage.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

private enum AssistantTargetReference {
    static func uri(for id: UUID) -> URL {
        URL(string: "college-assistant-target://\(id.uuidString)")!
    }

    static func id(from uri: URL?) -> UUID? {
        guard let uri, uri.scheme == "college-assistant-target" else { return nil }
        return UUID(uuidString: uri.host ?? "")
    }
}

enum AssistantAgentRole: String, CaseIterable, Identifiable {
    case academicAdvisor = "Academic Advisor"
    case financialAid = "Financial Aid"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .academicAdvisor: return "graduationcap"
        case .financialAid: return "dollarsign.circle"
        }
    }
}

private struct AssistantMessage: Identifiable, Hashable {
    let id: UUID
    let isUser: Bool
    let role: AssistantAgentRole
    var text: String
    let timestamp: Date
    /// Filenames shown as chips on user bubbles (on-device attachments).
    var attachmentDisplayNames: [String] = []
    /// Original prompt text used for model generation (preserved for replay).
    var modelPromptOverride: String?
    /// Attachment context used when generating this turn (for faithful regenerate/edit replay).
    var attachmentContextBlock: String?
    /// Citations from web search / fetch tools for this turn.
    var sources: [AssistantReplySource] = []
    var toolTrace: [AssistantToolTraceEntry] = []
    var feedback: AssistantReplyFeedback?
    /// Prior assistant texts replaced by Regenerate (newest first), capped in the UI.
    var supersededReplyTexts: [String] = []

    init(
        id: UUID = UUID(),
        isUser: Bool,
        role: AssistantAgentRole,
        text: String,
        timestamp: Date,
        attachmentDisplayNames: [String] = [],
        modelPromptOverride: String? = nil,
        attachmentContextBlock: String? = nil,
        sources: [AssistantReplySource] = [],
        toolTrace: [AssistantToolTraceEntry] = [],
        feedback: AssistantReplyFeedback? = nil,
        supersededReplyTexts: [String] = []
    ) {
        self.id = id
        self.isUser = isUser
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachmentDisplayNames = attachmentDisplayNames
        self.modelPromptOverride = modelPromptOverride
        self.attachmentContextBlock = attachmentContextBlock
        self.sources = sources
        self.toolTrace = toolTrace
        self.feedback = feedback
        self.supersededReplyTexts = supersededReplyTexts
    }
}

private struct AssistantTurnResult: Sendable {
    let text: String
    let sources: [AssistantReplySource]
    let toolTrace: [AssistantToolTraceEntry]

    init(text: String, sources: [AssistantReplySource], toolTrace: [AssistantToolTraceEntry] = []) {
        self.text = text
        self.sources = sources
        self.toolTrace = toolTrace
    }
}

private struct PersistedAssistantMessage: Codable {
    var id: UUID?
    let isUser: Bool
    let roleRawValue: String
    let text: String
    let timestamp: Date
    var attachmentDisplayNames: [String]?
    var modelPromptOverride: String?
    var attachmentContextBlock: String?
    var sources: [AssistantReplySource]?
    var toolTrace: [AssistantToolTraceEntry]?
    var feedbackRaw: String?
    var supersededReplyTexts: [String]?
}

private struct AssistantPendingAction: Identifiable {
    enum Kind {
        case createTask
        case createEvent
        case editTask
        case editEvent
        case deleteTask
        case deleteEvent
        case saveWebLearning
    }

    let id: UUID
    let kind: Kind
    let title: String
    let originalTitle: String?
    let dueDate: Date?
    let startDate: Date?
    let endDate: Date?
    let allDay: Bool
    let previousDueDate: Date?
    let previousStartDate: Date?
    let previousEndDate: Date?
    let previousAllDay: Bool?
    let targetObjectURI: URL?
    /// Populated for `saveWebLearning` confirmation.
    let webLearningSummary: String?
    let webLearningSourceURLs: [String]?
    let webLearningTags: String?

    init(
        kind: Kind,
        title: String,
        originalTitle: String?,
        dueDate: Date?,
        startDate: Date?,
        endDate: Date?,
        allDay: Bool,
        previousDueDate: Date?,
        previousStartDate: Date?,
        previousEndDate: Date?,
        previousAllDay: Bool?,
        targetObjectURI: URL?,
        webLearningSummary: String? = nil,
        webLearningSourceURLs: [String]? = nil,
        webLearningTags: String? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.originalTitle = originalTitle
        self.dueDate = dueDate
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.previousDueDate = previousDueDate
        self.previousStartDate = previousStartDate
        self.previousEndDate = previousEndDate
        self.previousAllDay = previousAllDay
        self.targetObjectURI = targetObjectURI
        self.webLearningSummary = webLearningSummary
        self.webLearningSourceURLs = webLearningSourceURLs
        self.webLearningTags = webLearningTags
    }
}

private struct AssistantComposerTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isEnabled: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let accessibilityIdentifier: String

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AssistantComposerTextField

        init(parent: AssistantComposerTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChanged(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChanged(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isEditable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEnabled = isEnabled
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.setAccessibilityIdentifier(accessibilityIdentifier)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.isEnabled = isEnabled
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
    }
}

struct AIAssistantView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    @Environment(\.accessibilityReduceMotion) private var motionReduced
    @Environment(\.scenePhase) private var scenePhase
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var assistantContextEvents: [CalendarEvent] = []
    @State private var assistantContextTasks: [PlannerTask] = []
    @State private var plannerSnapshotCache: AssistantPlannerSnapshot?
    @State private var plannerSnapshotCacheKey: Int = 0

    @State private var selectedRole: AssistantAgentRole = .academicAdvisor
    @State private var draftText: String = ""
    @State private var messages: [AssistantMessage] = []
    @State private var hasLoadedInitialMessages: Bool = false
    @StateObject private var viewModel = AIAssistantViewModel()
    @State private var hasInstalledAssistantModel: Bool = false
    @State private var isCheckingAssistantModel: Bool = true
    @State private var isInstallingAssistantModel: Bool = false
    @State private var assistantInstallProgress: Double = 0
    @State private var assistantInstallDetail: String = ""
    @State private var assistantInstallError: String?
    @State private var pendingAction: AssistantPendingAction?
    @State private var pendingActionPulse: Bool = false
    @State private var pendingSecurityScopedURLs: [URL] = []
    @State private var showAttachmentImporter = false
    @State private var showWebMemoryLibrary = false
    /// Avoid encoding + UserDefaults writes on every streaming token (was a major main-thread hitch).
    @State private var messagesPersistTask: Task<Void, Never>?
    private let messagesPersistDebounceNs: UInt64 = 650_000_000
    @State private var editingUserMessageID: UUID?
    @State private var editingUserMessageDraft: String = ""
    @State private var lastSubmittedPrompt: String = ""
    @State private var lastAssistantReplyCharacterCount: Int = 0
    @State private var persistGeneration: Int = 0
    @State private var persistWriteTask: Task<Void, Never>?
    @AppStorage("assistant.streaming.enabled") private var assistantStreamingEnabled: Bool = true
    @AppStorage("assistant.runtime.showDiagnostics") private var assistantDiagnosticsEnabled: Bool = false
    @AppStorage("assistant.response.lengthPreset") private var assistantResponseLengthPreset: String = "balanced"
    @AppStorage(AssistantWebSearchSettings.searxBaseURLKey) private var searxBaseURL: String = AssistantWebSearchSettings.defaultSearxBaseURL

    private let messageStoreKey = "assistant.messages.v1"
    @AppStorage("assistant.deferInitialLoadOneTick") private var deferInitialLoadOneTick: Bool = true
    private let assistantAutoScrollEnabled = true
    private let assistantBreadcrumbKey = "assistant.debug.lastBreadcrumb"
    private let assistantLocalLLMEnabledKey = "assistant.localLLM.enabled"
    private let preferredAssistantSpecs: [ModelSpec] = [.jsonWorker]
    private static let snapshotEventLimit = 240
    private static let snapshotTaskLimit = 320
    private static let snapshotPendingCourseLimit = 32
    private static let toolHopPlanDebounceNs: UInt64 = 60_000_000
    private let streamChunkCharacterCount = 48
    private let streamChunkDelayNanoseconds: UInt64 = 40_000_000

    private var dynamicMaxToolHops: Int {
        switch assistantResponseLengthPreset {
        case "short":
            return 2
        case "detailed":
            return 6
        default:
            return 4
        }
    }

    private func logAssistant(_ message: String, level: DebugLogger.Level = .info) {
        DebugLogger.shared.log(AssistantLogRedactor.redactForLog(message), category: .intelligence, level: level)
    }

    private static func truncateContextString(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIdx = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = String(text[..<endIdx])
        if let range = prefix.range(of: "\n", options: .backwards) {
            return String(prefix[..<range.lowerBound])
        }
        return prefix
    }

    private func replyContextMergingFullRAG(contextSummary: String, fullRagContext: String?) -> String {
        let trimmed = fullRagContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return contextSummary }
        return contextSummary + "\n\n---\n\n" + trimmed
    }

    private static func canonicalJSONValueForToolArg(_ value: AssistantJSONValue) -> String {
        switch value {
        case .string(let s):
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .number(let n):
            return n == floor(n) ? String(Int(n)) : String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let items):
            return "[\(items.map { canonicalJSONValueForToolArg($0) }.joined(separator: ","))]"
        case .object(let obj):
            let keys = obj.keys.sorted()
            let inner = keys.map { key in "\(key):\(canonicalJSONValueForToolArg(obj[key]!))" }.joined(separator: ",")
            return "{\(inner)}"
        }
    }

    private static func canonicalToolCallSignature(for call: AssistantToolCallEnvelope) -> String {
        let sortedKeys = call.arguments.keys.sorted()
        let args = sortedKeys.map { key in
            let v = call.arguments[key]!
            return "\(key)=\(canonicalJSONValueForToolArg(v))"
        }.joined(separator: "|")
        return "\(call.tool)[\(args)]"
    }

    private func persistMessagesImmediatelyFromState() {
        messagesPersistTask?.cancel()
        messagesPersistTask = nil
        schedulePersistMessages(messages)
    }

    private func scheduleDebouncedPersistWhileResponding() {
        messagesPersistTask?.cancel()
        messagesPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: messagesPersistDebounceNs)
            guard !Task.isCancelled else { return }
            messagesPersistTask = nil
            schedulePersistMessages(messages)
        }
    }

    private func setAssistantBreadcrumb(_ value: String) {
#if DEBUG
        let stamp = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set("\(stamp) | \(value)", forKey: assistantBreadcrumbKey)
#else
        if value.contains("failure") || value.contains("success") {
            UserDefaults.standard.set(value, forKey: assistantBreadcrumbKey)
        }
#endif
    }

    private var activeBadgeText: String {
        "Detected Advisor: \(selectedRole.rawValue)"
    }

    private var isResponding: Bool {
        viewModel.isResponding
    }

    private var streamingMessageID: UUID? {
        viewModel.streamingMessageID
    }

    private var canRegenerateLastTurn: Bool {
        let n = messages.count
        guard n >= 2 else { return false }
        return !messages[n - 1].isUser && messages[n - 2].isUser
    }

    private var canEditWhileIdle: Bool {
        !isResponding
    }

    var body: some View {
        GeometryReader { proxy in
            let shellTopInset = proxy.safeAreaInsets.top
            let shellBottomInset = proxy.safeAreaInsets.bottom
            Group {
                if hasInstalledAssistantModel {
                    assistantChatLayout(
                        shellTopInset: shellTopInset,
                        shellBottomInset: shellBottomInset
                    )
                } else {
                    assistantInstallRequiredState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.bgMain)
        .task {
            setAssistantBreadcrumb("view.task.begin")
            LLMOnDemandPrewarm.prewarmJsonWorkerIfInstalled()
            await refreshAssistantModelAvailability()
        }
        .onAppear {
            refreshAssistantPlannerContext()
            Task { await refreshAssistantModelAvailability() }
        }
        .onChange(of: collegePersistence.calendarDidChangeToken) { _, _ in
            refreshAssistantPlannerContext()
        }
        .onDisappear {
            persistMessagesImmediatelyFromState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshAssistantModelAvailability() }
        }
        .onChange(of: hasInstalledAssistantModel) { _, installed in
            guard installed else { return }
            scheduleInitialMessageLoad()
        }
        .onChange(of: messages) { _, updated in
            if isResponding {
                scheduleDebouncedPersistWhileResponding()
            } else {
                persistMessagesImmediatelyFromState()
                logAssistant("Assistant messages updated. count=\(updated.count) responding=\(isResponding)")
            }
        }
        .onChange(of: isResponding) { _, responding in
            if !responding {
                persistMessagesImmediatelyFromState()
            }
        }
        .sheet(isPresented: $showWebMemoryLibrary) {
            AssistantWebMemoryLibraryView()
                .dismissOnOutsideClickForSheet()
        }
        .fileImporter(
            isPresented: $showAttachmentImporter,
            allowedContentTypes: [.pdf, .plainText, .image, .jpeg, .png, .gif, .webP, .tiff],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                pendingSecurityScopedURLs.append(contentsOf: urls)
                logAssistant("Assistant picked \(urls.count) attachment(s)")
            case .failure(let error):
                logAssistant("Assistant attachment import failed: \(error.localizedDescription)", level: .warn)
            }
        }
    }

    private func assistantChatLayout(
        shellTopInset: CGFloat,
        shellBottomInset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
                header(shellTopInset: shellTopInset)
            Divider()
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                composer(shellBottomInset: shellBottomInset)
            }
            .background(DesignSystem.Colors.bgMain)
        }
    }

    @ViewBuilder
    private var assistantInstallRequiredState: some View {
        VStack(spacing: 18) {
            if isCheckingAssistantModel {
                ProgressView()
                    .controlSize(.small)
                Text("Checking AI model status…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Install an LLM to use AI Assistant")
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text("The assistant chat is disabled until the on-device JSON model is installed.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isInstallingAssistantModel {
                    VStack(spacing: 8) {
                        ProgressView(value: assistantInstallProgress)
                            .frame(maxWidth: 320)
                        Text(assistantInstallDetail.isEmpty ? "Preparing download…" : assistantInstallDetail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let assistantInstallError {
                    Text(assistantInstallError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }

                Button {
                    installAssistantModels()
                } label: {
                    Label(isInstallingAssistantModel ? "Installing…" : "Install JSON model", systemImage: "arrow.down.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstallingAssistantModel || isCheckingAssistantModel)
                .help("Install on-device Qwen JSON model")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func header(shellTopInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(activeBadgeText)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DesignSystem.Colors.sidebarSelectionFill, in: Capsule())
                Spacer()
                Button {
                    showWebMemoryLibrary = true
                } label: {
                    Label("Web Memory", systemImage: "books.vertical")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Open saved web memory")
                .accessibilityIdentifier("assistant.webMemoryButton")
                Menu {
                    Button {
                        regenerateLastAssistantTurn()
                    } label: {
                        Label("Regenerate Last Reply", systemImage: "arrow.clockwise")
                    }
                    .disabled(!canRegenerateLastTurn || isResponding)
                    Button {
                        showWebMemoryLibrary = true
                    } label: {
                        Label("Open Saved Web Notes", systemImage: "books.vertical")
                    }
                    Button {
                        exportTranscript()
                    } label: {
                        Label("Export Transcript", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        messages.removeAll()
                        hasLoadedInitialMessages = false
                        loadMessagesIfNeeded()
                    } label: {
                        Label("Clear Thread", systemImage: "trash")
                    }
                    Divider()
                    Toggle(isOn: $assistantDiagnosticsEnabled) {
                        Label("Show Runtime Diagnostics", systemImage: "waveform.path.ecg")
                    }
                    Toggle(isOn: $assistantStreamingEnabled) {
                        Label("Stream Replies", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("Assistant actions")
                .accessibilityIdentifier("assistant.actionsMenu")
            }
            .foregroundStyle(DesignSystem.Colors.textLight)
            .padding(.top, 2)
            .padding(.bottom, 2)
            Divider()
        }
        .padding(.horizontal, 12)
        .padding(.top, shellTopInset + 6)
        .padding(.bottom, 6)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        AssistantStudentGuidePanel(
                            selectedRole: selectedRole,
                            localModelInstalled: hasInstalledAssistantModel,
                            webSearchEnabled: !searxBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: message.isUser ? .trailing : .leading).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    if let pendingAction {
                        pendingActionCard(pendingAction)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if isResponding {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(streamingMessageID == nil ? "Thinking..." : "Streaming...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Button("Stop") {
                                    viewModel.cancelActiveGeneration()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if assistantDiagnosticsEnabled {
                                Text("lastReplyChars: \(lastAssistantReplyCharacterCount) · stream: \(assistantStreamingEnabled ? "on" : "off") · lengthPreset: \(assistantResponseLengthPreset)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .animation(motionReduced ? nil : .easeOut(duration: 0.22), value: messages.count)
                .animation(motionReduced ? nil : .easeOut(duration: 0.22), value: pendingAction != nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                guard assistantAutoScrollEnabled else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                guard let last = messages.last else { return }
                guard assistantAutoScrollEnabled else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composerCanSend: Bool {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || !pendingSecurityScopedURLs.isEmpty) && !isResponding
    }

    private func composer(shellBottomInset: CGFloat) -> some View {
        let bottomSpacing = max(8, shellBottomInset)
        return VStack(alignment: .leading, spacing: 8) {
            if !pendingSecurityScopedURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pendingSecurityScopedURLs.indices, id: \.self) { idx in
                            let url = pendingSecurityScopedURLs[idx]
                            HStack(spacing: 4) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    pendingSecurityScopedURLs.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesignSystem.Colors.surface.opacity(0.65), in: Capsule())
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showAttachmentImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isResponding)
                .help("Attach file")
                .accessibilityIdentifier("assistant.attachButton")

                AssistantComposerTextField(
                    placeholder: "Ask about planning, deadlines, degree progress, or actions...",
                    text: $draftText,
                    isEnabled: !isResponding,
                    onFocusChanged: { focused in
                        if focused {
                            setAssistantBreadcrumb("composer.tap")
                            logAssistant("Assistant composer focused")
                        }
                    },
                    onSubmit: {
                        sendMessage()
                    },
                    accessibilityIdentifier: "assistant.composerField"
                )
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .frame(minHeight: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DesignSystem.Colors.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8)
                )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [DesignSystem.Colors.primary, DesignSystem.Colors.info],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!composerCanSend)
                .opacity(composerCanSend ? 1 : 0.5)
                .help("Send")
                .accessibilityIdentifier("assistant.sendButton")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, bottomSpacing)
    }

    @ViewBuilder
    private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 6) {
                if !message.isUser {
                    Label(message.role.rawValue, systemImage: message.role.symbol)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }

                Text(message.text)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(
                        message.isUser
                            ? "assistant.bubble.user"
                            : "assistant.bubble.assistant"
                    )

                if streamingMessageID == message.id && !message.isUser {
                    Text("Receiving…")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }

                if message.isUser, editingUserMessageID == message.id {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Edit prompt", text: $editingUserMessageDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .lineLimit(1...4)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        HStack(spacing: 8) {
                            Button("Save + Regenerate") {
                                commitUserMessageEdit(messageID: message.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(editingUserMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)

                            Button("Cancel") {
                                cancelUserMessageEdit()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }

                if !message.isUser, !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        ForEach(message.sources, id: \.self) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                if let urlStr = source.url,
                                   let url = URL(string: urlStr),
                                   url.scheme == "http" || url.scheme == "https" {
                                    Link(destination: url) {
                                        Text(source.title)
                                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                            .foregroundStyle(DesignSystem.Colors.info)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(source.title)
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                }
                                if let snippet = source.snippet, !snippet.isEmpty {
                                    Text(snippet)
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                        .lineLimit(2)
                                }
                                if source.toolName != nil || source.hopIndex != nil || source.latencyMS != nil {
                                    Text(sourceMetadataLabel(source))
                                        .font(DesignSystem.Fonts.main(size: 9, weight: .medium))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                if !message.isUser, !message.toolTrace.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(message.toolTrace.enumerated()), id: \.offset) { _, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: step.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(step.ok ? DesignSystem.Colors.primary : DesignSystem.Colors.warning)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Step \(step.hopIndex + 1) · \(step.toolName) · \(step.latencyMS)ms")
                                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                                            .foregroundStyle(DesignSystem.Colors.textMain)
                                        if !step.summary.isEmpty {
                                            Text(step.summary)
                                                .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                                .foregroundStyle(DesignSystem.Colors.textLight)
                                                .lineLimit(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Tool trace (\(message.toolTrace.count))")
                        }
                    }
                    .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                    .padding(.top, 2)
                }

                if !message.isUser, !message.supersededReplyTexts.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(message.supersededReplyTexts.enumerated()), id: \.offset) { _, draft in
                            Text(draft)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Previous drafts (\(message.supersededReplyTexts.count))")
                        }
                    }
                    .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                    .padding(.top, 2)
                }

                if !message.isUser {
                    HStack(spacing: 6) {
                        Button {
                            copyMessageText(message.text)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Copy response")

                        Button {
                            setMessageFeedback(messageID: message.id, feedback: message.feedback == .helpful ? nil : .helpful)
                        } label: {
                            Image(systemName: message.feedback == .helpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.feedback == .helpful ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Helpful")

                        Button {
                            setMessageFeedback(messageID: message.id, feedback: message.feedback == .notHelpful ? nil : .notHelpful)
                        } label: {
                            Image(systemName: message.feedback == .notHelpful ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.feedback == .notHelpful ? DesignSystem.Colors.warning : DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Not helpful")
                    }
                    .padding(.top, 2)
                }

                if message.isUser, editingUserMessageID != message.id {
                    HStack(spacing: 6) {
                        Button {
                            beginUserMessageEdit(message)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Edit prompt")
                        .disabled(!canEditMessage(message))
                    }
                    .padding(.top, 2)
                }

                if message.isUser, !message.attachmentDisplayNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(message.attachmentDisplayNames.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DesignSystem.Colors.surface.opacity(0.65), in: Capsule())
                            }
                        }
                    }
                }

                Text(timeLabel(message.timestamp))
                    .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                AnyShapeStyle(DesignSystem.Colors.glassCardBase),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8)
            )
            .frame(maxWidth: 560, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer(minLength: 30) }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func sourceMetadataLabel(_ source: AssistantReplySource) -> String {
        var parts: [String] = []
        if let tool = source.toolName, !tool.isEmpty {
            parts.append(tool)
        }
        if let hop = source.hopIndex {
            parts.append("hop \(hop + 1)")
        }
        if let latencyMS = source.latencyMS {
            parts.append("\(latencyMS)ms")
        }
        return parts.joined(separator: " · ")
    }

    private func toolTraceSummary(from envelope: AssistantToolResultEnvelope) -> String {
        let trimmed = envelope.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(200))
        }
        if let err = envelope.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
            return String(err.prefix(200))
        }
        return envelope.ok ? "Completed." : "No details."
    }

    @MainActor
    private func appendRuntimeStreamChunk(messageID: UUID, role: AssistantAgentRole, chunk: String) {
        guard !chunk.isEmpty else { return }
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            messages[idx].text += chunk
        } else {
            messages.append(
                AssistantMessage(
                    id: messageID,
                    isUser: false,
                    role: role,
                    text: chunk,
                    timestamp: Date()
                )
            )
        }
    }

    private func extractStreamingReplyPrefix(from raw: String) -> String {
        guard let keyRange = raw.range(of: #""reply"\s*:\s*""#, options: .regularExpression) else {
            return ""
        }
        var idx = keyRange.upperBound
        var out = ""
        var escaping = false
        while idx < raw.endIndex {
            let ch = raw[idx]
            idx = raw.index(after: idx)
            if escaping {
                switch ch {
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "/": out.append("/")
                case "u": out.append("?")
                default: out.append(ch)
                }
                escaping = false
                continue
            }
            if ch == "\\" {
                escaping = true
                continue
            }
            if ch == "\"" {
                break
            }
            out.append(ch)
        }
        return out
    }

    private func ingestResult(from userMessage: AssistantMessage) -> AssistantAttachmentIngestor.Result {
        AssistantAttachmentIngestor.Result(
            contextBlock: userMessage.attachmentContextBlock ?? "",
            displayNames: userMessage.attachmentDisplayNames
        )
    }

    private var replyLengthCap: Int {
        switch assistantResponseLengthPreset {
        case "short":
            return 700
        case "detailed":
            return 3000
        default:
            return 1600
        }
    }

    private var contextPackaging: AssistantContextBudget {
        AssistantContextBudget.forLengthPreset(assistantResponseLengthPreset)
    }

    @MainActor
    private func streamAssistantReply(role: AssistantAgentRole, turn: AssistantTurnResult, supersededReplyTexts: [String] = []) async throws {
        let messageID = UUID()
        viewModel.streamingMessageID = messageID
        messages.append(
            AssistantMessage(
                id: messageID,
                isUser: false,
                role: role,
                text: "",
                timestamp: Date(),
                sources: turn.sources
                ,
                toolTrace: turn.toolTrace,
                supersededReplyTexts: supersededReplyTexts
            )
        )

        let boundedText = String(turn.text.prefix(replyLengthCap))
        lastAssistantReplyCharacterCount = boundedText.count
        let chars = Array(boundedText)
        var index = 0
        if !assistantStreamingEnabled {
            if let msgIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[msgIndex].text = boundedText
            }
            viewModel.streamingMessageID = nil
            return
        }
        while index < chars.count {
            try Task.checkCancellation()
            let end = min(index + streamChunkCharacterCount, chars.count)
            let chunk = String(chars[index..<end])
            if let msgIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[msgIndex].text += chunk
            }
            index = end
            if index < chars.count {
                try await Task.sleep(nanoseconds: streamChunkDelayNanoseconds)
            }
        }
        viewModel.streamingMessageID = nil
    }

    private func sendMessage() {
        setAssistantBreadcrumb("send.start")
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlsToIngest = pendingSecurityScopedURLs
        pendingSecurityScopedURLs = []
        guard !trimmed.isEmpty || !urlsToIngest.isEmpty else { return }

        let promptForModel: String = {
            if trimmed.isEmpty, !urlsToIngest.isEmpty {
                return "Summarize and explain these attachments in the context of my college planner."
            }
            return trimmed
        }()
        lastSubmittedPrompt = promptForModel

        let bubbleText: String = {
            if trimmed.isEmpty, !urlsToIngest.isEmpty {
                return "\(urlsToIngest.count) attachment(s)"
            }
            return trimmed
        }()

        let requestID = viewModel.nextRequestID()
        let requestRole = AssistantIntentSemantics.inferredAgentRole(message: promptForModel, fallback: selectedRole)
        selectedRole = requestRole
        logAssistant("Assistant send start id=\(requestID) role=\(requestRole.rawValue) chars=\(trimmed.count) attachments=\(urlsToIngest.count)")

        let userMessageID = UUID()
        messages.append(
            AssistantMessage(
                id: userMessageID,
                isUser: true,
                role: requestRole,
                text: bubbleText,
                timestamp: Date(),
                attachmentDisplayNames: urlsToIngest.map(\.lastPathComponent),
                modelPromptOverride: promptForModel
            )
        )
        draftText = ""

        if !trimmed.isEmpty, let action = parsePendingAction(from: trimmed) {
            pendingAction = action
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: requestRole,
                    text: "I can apply that action. Review the confirmation card below and choose Confirm or Cancel.",
                    timestamp: Date()
                )
            )
            return
        }

        viewModel.startGeneration {
            setAssistantBreadcrumb("send.request.\(requestID).generate.begin")
            logAssistant("Assistant generate begin id=\(requestID)")
            let ingest = await AssistantAttachmentIngestor.ingest(securityScopedURLs: urlsToIngest)
            let hadAttachments = !urlsToIngest.isEmpty
            if let userIndex = messages.firstIndex(where: { $0.id == userMessageID }) {
                messages[userIndex].attachmentContextBlock = ingest.contextBlock
            }
            let runtimeMessageID = UUID()
            var didRuntimeStream = false
            var rawStreamBuffer = ""
            var emittedReplyPrefix = ""
            if assistantStreamingEnabled {
                viewModel.streamingMessageID = runtimeMessageID
                messages.append(
                    AssistantMessage(
                        id: runtimeMessageID,
                        isUser: false,
                        role: requestRole,
                        text: "",
                        timestamp: Date()
                    )
                )
            }
            let turn: AssistantTurnResult
            do {
                turn = try await generateReply(
                    for: promptForModel,
                    role: requestRole,
                    hadAttachments: hadAttachments,
                    ingest: ingest,
                    onRawChunk: { chunk in
                        await MainActor.run {
                            rawStreamBuffer += chunk
                            let currentReplyPrefix = extractStreamingReplyPrefix(from: rawStreamBuffer)
                            guard currentReplyPrefix.count > emittedReplyPrefix.count else { return }
                            let delta = String(currentReplyPrefix.dropFirst(emittedReplyPrefix.count))
                            emittedReplyPrefix = currentReplyPrefix
                            guard !delta.isEmpty else { return }
                            didRuntimeStream = true
                            appendRuntimeStreamChunk(messageID: runtimeMessageID, role: requestRole, chunk: delta)
                        }
                    }
                )
            } catch is CancellationError {
                setAssistantBreadcrumb("send.request.\(requestID).cancelled")
                logAssistant("Assistant generate cancelled id=\(requestID)", level: .info)
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: requestRole,
                        text: "Generation stopped.",
                        timestamp: Date()
                    )
                )
                return
            } catch {
                setAssistantBreadcrumb("send.request.\(requestID).error")
                logAssistant("Assistant generate error id=\(requestID): \(error.localizedDescription)", level: .warn)
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: requestRole,
                        text: "Something went wrong while generating a reply. Try again.",
                        timestamp: Date()
                    )
                )
                return
            }
            setAssistantBreadcrumb("send.request.\(requestID).generate.end")
            guard !Task.isCancelled else {
                return
            }
            if didRuntimeStream, let idx = messages.firstIndex(where: { $0.id == runtimeMessageID }) {
                messages[idx].text = turn.text
                messages[idx].sources = turn.sources
                messages[idx].toolTrace = turn.toolTrace
            } else {
                if let idx = messages.firstIndex(where: { $0.id == runtimeMessageID }),
                   messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.remove(at: idx)
                }
                do {
                    try await streamAssistantReply(role: requestRole, turn: turn)
                } catch is CancellationError {
                    if let streamID = streamingMessageID,
                       let msgIdx = messages.firstIndex(where: { $0.id == streamID }),
                       messages[msgIdx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages[msgIdx].text = "Generation stopped."
                    }
                    return
                } catch {
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: requestRole,
                            text: "Something went wrong while streaming a reply.",
                            timestamp: Date()
                        )
                    )
                    return
                }
            }
            setAssistantBreadcrumb("send.request.\(requestID).ui.appended")
            logAssistant("Assistant generate end id=\(requestID) replyChars=\(turn.text.count) sources=\(turn.sources.count)")
        }
    }

    private func regenerateLastAssistantTurn() {
        guard canRegenerateLastTurn, !isResponding else { return }
        let userMessage = messages[messages.count - 2]
        let removedAssistant = messages[messages.count - 1]
        viewModel.cancelActiveGeneration()
        var inheritedSuperseded = removedAssistant.supersededReplyTexts
        let trimmedPrior = removedAssistant.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrior.isEmpty {
            inheritedSuperseded = [removedAssistant.text] + inheritedSuperseded
        }
        if inheritedSuperseded.count > 5 {
            inheritedSuperseded = Array(inheritedSuperseded.prefix(5))
        }
        messages.removeLast()

        let bubble = userMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptForModel: String = {
            if let override = userMessage.modelPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty {
                return override
            }
            if bubble.range(of: #"^\d+ attachment\(s\)$"#, options: .regularExpression) != nil {
                return "Summarize and explain these attachments in the context of my college planner."
            }
            return bubble.isEmpty ? "Summarize and explain these attachments in the context of my college planner." : bubble
        }()
        let requestRole = userMessage.role
        let requestID = viewModel.nextRequestID()
        viewModel.startGeneration {
            setAssistantBreadcrumb("regenerate.\(requestID).begin")
            logAssistant("Assistant regenerate begin id=\(requestID)")
            let ingest = ingestResult(from: userMessage)
            let runtimeMessageID = UUID()
            var didRuntimeStream = false
            var rawStreamBuffer = ""
            var emittedReplyPrefix = ""
            if assistantStreamingEnabled {
                viewModel.streamingMessageID = runtimeMessageID
                messages.append(
                    AssistantMessage(
                        id: runtimeMessageID,
                        isUser: false,
                        role: requestRole,
                        text: "",
                        timestamp: Date(),
                        supersededReplyTexts: inheritedSuperseded
                    )
                )
            }
            let turn: AssistantTurnResult
            do {
                turn = try await generateReply(
                    for: promptForModel,
                    role: requestRole,
                    hadAttachments: !userMessage.attachmentDisplayNames.isEmpty,
                    ingest: ingest,
                    onRawChunk: { chunk in
                        await MainActor.run {
                            rawStreamBuffer += chunk
                            let currentReplyPrefix = extractStreamingReplyPrefix(from: rawStreamBuffer)
                            guard currentReplyPrefix.count > emittedReplyPrefix.count else { return }
                            let delta = String(currentReplyPrefix.dropFirst(emittedReplyPrefix.count))
                            emittedReplyPrefix = currentReplyPrefix
                            guard !delta.isEmpty else { return }
                            didRuntimeStream = true
                            appendRuntimeStreamChunk(messageID: runtimeMessageID, role: requestRole, chunk: delta)
                        }
                    }
                )
            } catch is CancellationError {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: requestRole,
                        text: "Generation stopped.",
                        timestamp: Date()
                    )
                )
                return
            } catch {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: requestRole,
                        text: "Something went wrong while regenerating. Try again.",
                        timestamp: Date()
                    )
                )
                return
            }
            guard !Task.isCancelled else {
                return
            }
            if didRuntimeStream, let idx = messages.firstIndex(where: { $0.id == runtimeMessageID }) {
                messages[idx].text = turn.text
                messages[idx].sources = turn.sources
                messages[idx].toolTrace = turn.toolTrace
                messages[idx].supersededReplyTexts = inheritedSuperseded
            } else {
                if let idx = messages.firstIndex(where: { $0.id == runtimeMessageID }),
                   messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.remove(at: idx)
                }
                do {
                    try await streamAssistantReply(role: requestRole, turn: turn, supersededReplyTexts: inheritedSuperseded)
                } catch is CancellationError {
                    if let streamID = streamingMessageID,
                       let msgIdx = messages.firstIndex(where: { $0.id == streamID }),
                       messages[msgIdx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages[msgIdx].text = "Generation stopped."
                    }
                    return
                } catch {
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: requestRole,
                            text: "Something went wrong while streaming a reply.",
                            timestamp: Date()
                        )
                    )
                    return
                }
            }
            logAssistant("Assistant regenerate end id=\(requestID) replyChars=\(turn.text.count)")
        }
    }

    private func setMessageFeedback(messageID: UUID, feedback: AssistantReplyFeedback?) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].feedback = feedback
        guard feedback == .helpful else { return }
        let message = messages[idx]
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let query = inferPromptForAssistantMessage(at: idx)
        AssistantConversationMemory.recordHelpful(userQuery: query, assistantReply: message.text)
        guard !message.sources.isEmpty else { return }
        let role = message.role
        let university = collegePersistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceStrings = message.sources.compactMap { src -> [String: String]? in
            guard let url = src.url else { return nil }
            return ["title": src.title, "url": url]
        }
        guard let sourceData = try? JSONEncoder().encode(sourceStrings),
              let sourceJSON = String(data: sourceData, encoding: .utf8) else { return }
        let key = acceptedWebAnswerCacheKey(query: query, role: role, universityName: university)
        Task {
            try? await AssistantWebMemoryStore.shared.saveAcceptedWebAnswer(
                cacheKey: key,
                query: query,
                role: role.rawValue,
                universityName: university,
                answer: message.text,
                sourcesJSON: sourceJSON
            )
        }
    }

    private func inferPromptForAssistantMessage(at index: Int) -> String {
        guard index > 0 else { return lastSubmittedPrompt }
        for idx in stride(from: index - 1, through: 0, by: -1) where messages[idx].isUser {
            if let prompt = messages[idx].modelPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                return prompt
            }
            return messages[idx].text
        }
        return lastSubmittedPrompt
    }

    private func acceptedWebAnswerCacheKey(query: String, role: AssistantAgentRole, universityName: String?) -> String {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let uni = (universityName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(role.rawValue.lowercased())|\(uni)|\(normalizedQuery)"
    }

    private func copyMessageText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportTranscript() {
        let payload = messages.map { message in
            PersistedAssistantMessage(
                id: message.id,
                isUser: message.isUser,
                roleRawValue: message.role.rawValue,
                text: message.text,
                timestamp: message.timestamp,
                attachmentDisplayNames: message.attachmentDisplayNames.isEmpty ? nil : message.attachmentDisplayNames,
                modelPromptOverride: message.modelPromptOverride,
                attachmentContextBlock: message.attachmentContextBlock,
                sources: message.sources.isEmpty ? nil : message.sources,
                toolTrace: message.toolTrace.isEmpty ? nil : message.toolTrace,
                feedbackRaw: message.feedback?.rawValue,
                supersededReplyTexts: message.supersededReplyTexts.isEmpty ? nil : message.supersededReplyTexts
            )
        }
        guard let data = try? JSONEncoder().encode(payload),
              let pretty = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: pretty, options: [.prettyPrinted]),
              let raw = String(data: prettyData, encoding: .utf8) else {
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Assistant Transcript"
        panel.nameFieldStringValue = "assistant-transcript-\(ISO8601DateFormatter().string(from: Date())).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? raw.write(to: url, atomically: true, encoding: .utf8)
    }

    private func canEditMessage(_ message: AssistantMessage) -> Bool {
        guard message.isUser else { return false }
        guard canEditWhileIdle else { return false }
        guard message.text.range(of: #"^\d+ attachment\(s\)$"#, options: .regularExpression) == nil else { return false }
        return true
    }

    private func beginUserMessageEdit(_ message: AssistantMessage) {
        guard canEditMessage(message) else { return }
        editingUserMessageID = message.id
        editingUserMessageDraft = message.text
    }

    private func cancelUserMessageEdit() {
        editingUserMessageID = nil
        editingUserMessageDraft = ""
    }

    private func commitUserMessageEdit(messageID: UUID) {
        let trimmed = editingUserMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = messages.firstIndex(where: { $0.id == messageID && $0.isUser }) else { return }
        guard canEditWhileIdle else { return }

        let original = messages[idx]
        messages[idx] = AssistantMessage(
            id: original.id,
            isUser: true,
            role: original.role,
            text: trimmed,
            timestamp: original.timestamp,
            attachmentDisplayNames: original.attachmentDisplayNames,
            modelPromptOverride: trimmed,
            attachmentContextBlock: original.attachmentContextBlock,
            sources: original.sources,
            feedback: original.feedback
        )

        if messages.count > idx + 1 {
            messages.removeSubrange((idx + 1)..<messages.count)
        }

        cancelUserMessageEdit()
        regenerateFromEditedUserMessage(messages[idx])
    }

    private func regenerateFromEditedUserMessage(_ userMessage: AssistantMessage) {
        let promptForModel = userMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptForModel.isEmpty else { return }
        let requestRole = userMessage.role
        let requestID = viewModel.nextRequestID()

        viewModel.startGeneration {

            setAssistantBreadcrumb("edit.regenerate.\(requestID).begin")
            let ingest = ingestResult(from: userMessage)
            let runtimeMessageID = UUID()
            var didRuntimeStream = false
            var rawStreamBuffer = ""
            var emittedReplyPrefix = ""
            if assistantStreamingEnabled {
                viewModel.streamingMessageID = runtimeMessageID
                messages.append(
                    AssistantMessage(
                        id: runtimeMessageID,
                        isUser: false,
                        role: requestRole,
                        text: "",
                        timestamp: Date()
                    )
                )
            }
            let turn: AssistantTurnResult
            do {
                turn = try await generateReply(
                    for: promptForModel,
                    role: requestRole,
                    hadAttachments: !userMessage.attachmentDisplayNames.isEmpty,
                    ingest: ingest,
                    onRawChunk: { chunk in
                        await MainActor.run {
                            rawStreamBuffer += chunk
                            let currentReplyPrefix = extractStreamingReplyPrefix(from: rawStreamBuffer)
                            guard currentReplyPrefix.count > emittedReplyPrefix.count else { return }
                            let delta = String(currentReplyPrefix.dropFirst(emittedReplyPrefix.count))
                            emittedReplyPrefix = currentReplyPrefix
                            guard !delta.isEmpty else { return }
                            didRuntimeStream = true
                            appendRuntimeStreamChunk(messageID: runtimeMessageID, role: requestRole, chunk: delta)
                        }
                    }
                )
            } catch is CancellationError {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: requestRole,
                        text: "Generation stopped.",
                        timestamp: Date()
                    )
                )
                return
            } catch {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: requestRole,
                        text: "Something went wrong while regenerating. Try again.",
                        timestamp: Date()
                    )
                )
                return
            }

            guard !Task.isCancelled else { return }
            if didRuntimeStream, let idx = messages.firstIndex(where: { $0.id == runtimeMessageID }) {
                messages[idx].text = turn.text
                messages[idx].sources = turn.sources
                messages[idx].toolTrace = turn.toolTrace
            } else {
                if let idx = messages.firstIndex(where: { $0.id == runtimeMessageID }),
                   messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.remove(at: idx)
                }
                do {
                    try await streamAssistantReply(role: requestRole, turn: turn)
                } catch is CancellationError {
                    if let streamID = streamingMessageID,
                       let msgIdx = messages.firstIndex(where: { $0.id == streamID }),
                       messages[msgIdx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages[msgIdx].text = "Generation stopped."
                    }
                    return
                } catch {
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: requestRole,
                            text: "Something went wrong while streaming a reply.",
                            timestamp: Date()
                        )
                    )
                    return
                }
            }
            setAssistantBreadcrumb("edit.regenerate.\(requestID).end")
        }
    }

    @ViewBuilder
    private func pendingActionCard(_ action: AssistantPendingAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pending Assistant Action")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)

            Text(actionTitle(action))
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Text(actionDetail(action))
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textLight)

            Text(actionDiffPreview(action))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                Button("Confirm") {
                    confirmPendingAction(action)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assistant.pendingAction.confirm")

                Button("Cancel") {
                    cancelPendingAction()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("assistant.pendingAction.cancel")
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.glassCardBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8)
        )
        .scaleEffect(motionReduced ? 1 : (pendingActionPulse ? 1 : 0.985))
        .shadow(color: DesignSystem.Colors.primary.opacity(motionReduced ? 0.08 : 0.18), radius: pendingActionPulse ? 16 : 8, x: 0, y: 4)
        .onAppear {
            guard !motionReduced else { return }
            pendingActionPulse = false
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                pendingActionPulse = true
            }
        }
        .onDisappear {
            pendingActionPulse = false
        }
    }

    private func actionTitle(_ action: AssistantPendingAction) -> String {
        switch action.kind {
        case .createTask:
            return "Create Task: \(action.title)"
        case .createEvent:
            return "Create Event: \(action.title)"
        case .editTask:
            return "Edit Task: \(action.originalTitle ?? action.title)"
        case .editEvent:
            return "Edit Event: \(action.originalTitle ?? action.title)"
        case .deleteTask:
            return "Delete Task: \(action.title)"
        case .deleteEvent:
            return "Delete Event: \(action.title)"
        case .saveWebLearning:
            return "Save Web Learning: \(action.title)"
        }
    }

    private func actionDetail(_ action: AssistantPendingAction) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        switch action.kind {
        case .createTask:
            if let dueDate = action.dueDate {
                return "Due: \(formatter.string(from: dueDate))"
            }
            return "Due: Not set"
        case .createEvent:
            guard let startDate = action.startDate, let endDate = action.endDate else {
                return "Time: Not set"
            }
            if action.allDay {
                return "Time: All day on \(formatter.string(from: startDate))"
            }
            return "Time: \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
        case .editTask:
            let dueText: String
            if let dueDate = action.dueDate {
                dueText = formatter.string(from: dueDate)
            } else {
                dueText = "No due time"
            }
            return "Updated title: \(action.title) | Updated due: \(dueText)"
        case .editEvent:
            guard let startDate = action.startDate, let endDate = action.endDate else {
                return "Updated event time is incomplete"
            }
            if action.allDay {
                return "Updated time: All day on \(formatter.string(from: startDate))"
            }
            return "Updated time: \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
        case .deleteTask:
            return "Delete the existing task that best matches this title."
        case .deleteEvent:
            return "Delete the existing event that best matches this title."
        case .saveWebLearning:
            let urlCount = action.webLearningSourceURLs?.count ?? 0
            return "Stores a short summary on this Mac (\(urlCount) source URL(s)). Tags: \(action.webLearningTags ?? "none")"
        }
    }

    private func actionDiffPreview(_ action: AssistantPendingAction) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        switch action.kind {
        case .createTask:
            return "Before: Task \"\(action.title)\" not present\nAfter:  Task \"\(action.title)\" created"
        case .createEvent:
            return "Before: Event \"\(action.title)\" not present\nAfter:  Event \"\(action.title)\" created"
        case .editTask:
            let oldDue = action.previousDueDate.map { formatter.string(from: $0) } ?? "No due time"
            let newDue = action.dueDate.map { formatter.string(from: $0) } ?? "No due time"
            return "Before: Task \"\(action.originalTitle ?? action.title)\" | Due: \(oldDue)\nAfter:  Task \"\(action.title)\" | Due: \(newDue)"
        case .editEvent:
            let oldStart = action.previousStartDate.map { formatter.string(from: $0) } ?? "—"
            let oldEnd = action.previousEndDate.map { formatter.string(from: $0) } ?? "—"
            let newStart = action.startDate.map { formatter.string(from: $0) } ?? "—"
            let newEnd = action.endDate.map { formatter.string(from: $0) } ?? "—"
            return "Before: Event \"\(action.originalTitle ?? action.title)\" | \(oldStart) to \(oldEnd)\nAfter:  Event \"\(action.title)\" | \(newStart) to \(newEnd)"
        case .deleteTask:
            return "Before: Task \"\(action.title)\" present\nAfter:  Task \"\(action.title)\" removed"
        case .deleteEvent:
            return "Before: Event \"\(action.title)\" present\nAfter:  Event \"\(action.title)\" removed"
        case .saveWebLearning:
            let preview = String((action.webLearningSummary ?? "").prefix(400))
            return "Before: Not saved\nAfter:  Saved note \"\(action.title)\"\n\n\(preview)"
        }
    }

    private func confirmPendingAction(_ action: AssistantPendingAction) {
        switch action.kind {
        case .createTask:
            _ = collegePersistence.addTask(
                title: action.title,
                dueDate: action.dueDate,
                semester: nil,
                course: nil
            )
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I created the task '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .createEvent:
            guard let startDate = action.startDate, let endDate = action.endDate else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not confirm that event because the date/time was incomplete.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            _ = collegePersistence.addCalendarEvent(
                title: action.title,
                startDate: startDate,
                endDate: endDate,
                allDay: action.allDay,
                semester: nil,
                course: nil
            )
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I created the event '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .editTask:
            guard let uri = action.targetObjectURI,
                  let taskID = AssistantTargetReference.id(from: uri),
                  let task = try? collegePersistence.calendarRepository.fetchPlannerTask(id: taskID)
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that task to edit. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.updateTask(
                id: taskID,
                title: action.title,
                dueDate: action.dueDate,
                semester: task.semester,
                course: task.course,
                notes: task.notes,
                priority: task.priority,
                categoryName: task.categoryName,
                gradingCategory: task.gradingCategory,
                categoryWeightPercent: task.categoryWeightPercent,
                weightPercent: task.weightPercent,
                estimatedEffortMinutes: task.estimatedEffortMinutes
            )

            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I updated the task to '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .editEvent:
            guard let uri = action.targetObjectURI,
                  let eventID = AssistantTargetReference.id(from: uri),
                  let event = try? collegePersistence.calendarRepository.fetchCalendarEvent(id: eventID),
                  let startDate = action.startDate,
                  let endDate = action.endDate
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that event to edit. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.updateCalendarEvent(
                id: eventID,
                title: action.title,
                startDate: startDate,
                endDate: endDate,
                allDay: action.allDay,
                semester: event.semester,
                course: event.course,
                notes: event.notes,
                location: event.location
            )

            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I updated the event to '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .deleteTask:
            guard let uri = action.targetObjectURI,
                  let taskID = AssistantTargetReference.id(from: uri)
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that task to delete. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.deleteTask(id: taskID)
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I deleted the task '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .deleteEvent:
            guard let uri = action.targetObjectURI,
                  let eventID = AssistantTargetReference.id(from: uri)
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that event to delete. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.deleteCalendarEvent(id: eventID)
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I deleted the event '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .saveWebLearning:
            let body = (action.webLearningSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !body.isEmpty else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not save that learning because the title or summary was empty.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }
            let urls = action.webLearningSourceURLs ?? []
            let role = selectedRole
            let embeddingBlob: Data? = {
                guard AssistantWebSearchSettings.isSemanticMemoryEnabled else { return nil }
                let combined = title + "\n" + body
                let vec = AssistantWebMemoryEmbedding.vector(for: String(combined.prefix(4000)))
                return AssistantWebMemoryEmbedding.data(from: vec)
            }()
            Task { @MainActor in
                do {
                    try await AssistantWebMemoryStore.shared.insert(
                        title: title,
                        body: body,
                        sourceURLs: urls,
                        tags: action.webLearningTags,
                        embedding: embeddingBlob
                    )
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: role,
                            text: "Confirmed. I saved '\(title)' to your on-device web learnings.",
                            timestamp: Date()
                        )
                    )
                } catch {
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: role,
                            text: "I could not save that learning: \(error.localizedDescription)",
                            timestamp: Date()
                        )
                    )
                }
            }
        }

        pendingAction = nil
    }

    private func cancelPendingAction() {
        pendingAction = nil
        messages.append(
            AssistantMessage(
                isUser: false,
                role: selectedRole,
                text: "Cancelled. I did not make any changes.",
                timestamp: Date()
            )
        )
    }

    private func parsePendingAction(from prompt: String) -> AssistantPendingAction? {
        let normalized = prompt.lowercased()

        if normalized.contains("edit task") || normalized.contains("update task") {
            let requested = extractTitle(from: prompt, keywords: ["edit task", "update task"])
            let matched = assistantContextTasks.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            let existingTitle = matched?.title ?? requested
            let newTitle = parseUpdatedTitle(from: prompt, fallbackTitle: existingTitle)
            let newDueDate = parseRelativeDateTime(from: normalized) ?? matched?.dueDate
            return AssistantPendingAction(
                kind: .editTask,
                title: newTitle,
                originalTitle: existingTitle,
                dueDate: newDueDate,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: matched?.dueDate,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("edit event") || normalized.contains("update event") {
            let requested = extractTitle(from: prompt, keywords: ["edit event", "update event"])
            let matched = assistantContextEvents.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            let existingTitle = matched?.title ?? requested
            let newTitle = parseUpdatedTitle(from: prompt, fallbackTitle: existingTitle)
            let allDay = normalized.contains("all day") ? true : (matched?.allDay ?? false)
            let startDate = parseRelativeDateTime(from: normalized) ?? matched?.startDate ?? defaultEventStartDate(from: normalized)
            let endDate = Calendar.current.date(byAdding: .hour, value: allDay ? 24 : 1, to: startDate)
            return AssistantPendingAction(
                kind: .editEvent,
                title: newTitle,
                originalTitle: existingTitle,
                dueDate: nil,
                startDate: startDate,
                endDate: endDate,
                allDay: allDay,
                previousDueDate: nil,
                previousStartDate: matched?.startDate,
                previousEndDate: matched?.endDate,
                previousAllDay: matched?.allDay,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("delete task") || normalized.contains("remove task") {
            let requested = extractTitle(from: prompt, keywords: ["delete task", "remove task"])
            let matched = assistantContextTasks.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            return AssistantPendingAction(
                kind: .deleteTask,
                title: matched?.title ?? requested,
                originalTitle: matched?.title ?? requested,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: matched?.dueDate,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("delete event") || normalized.contains("remove event") {
            let requested = extractTitle(from: prompt, keywords: ["delete event", "remove event"])
            let matched = assistantContextEvents.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            return AssistantPendingAction(
                kind: .deleteEvent,
                title: matched?.title ?? requested,
                originalTitle: matched?.title ?? requested,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: matched?.startDate,
                previousEndDate: matched?.endDate,
                previousAllDay: matched?.allDay,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("create task") || normalized.contains("add task") || normalized.contains("new task") || normalized.contains("create todo") {
            let title = extractTitle(from: prompt, keywords: ["create task", "add task", "new task", "create todo", "add todo"])
            let dueDate = parseRelativeDateTime(from: normalized)
            return AssistantPendingAction(
                kind: .createTask,
                title: title,
                originalTitle: nil,
                dueDate: dueDate,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil
            )
        }

        if normalized.contains("create event") ||
            normalized.contains("create an event") ||
            normalized.contains("add event") ||
            normalized.contains("new event") {
            let title = extractTitle(from: prompt, keywords: ["create event", "add event", "new event"])
            let allDay = normalized.contains("all day")
            let startDate = parseRelativeDateTime(from: normalized)
            let resolvedStart = startDate ?? defaultEventStartDate(from: normalized)
            let endDate = Calendar.current.date(byAdding: .hour, value: allDay ? 24 : 1, to: resolvedStart)
            return AssistantPendingAction(
                kind: .createEvent,
                title: title,
                originalTitle: nil,
                dueDate: nil,
                startDate: resolvedStart,
                endDate: endDate,
                allDay: allDay,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil
            )
        }

        return nil
    }

    private func extractTitle(from prompt: String, keywords: [String]) -> String {
        let lowered = prompt.lowercased()
        for keyword in keywords {
            if let range = lowered.range(of: keyword) {
                let suffix = prompt[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = suffix
                    .replacingOccurrences(of: "called", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "named", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "titled", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return "Assistant item"
    }

    private func parseUpdatedTitle(from prompt: String, fallbackTitle: String) -> String {
        let parts = prompt.components(separatedBy: " to ")
        if let last = parts.last, parts.count > 1 {
            let updated = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if !updated.isEmpty {
                return updated
            }
        }
        return fallbackTitle
    }

    private func defaultEventStartDate(from prompt: String) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let baseDate: Date
        if prompt.contains("tomorrow") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else {
            baseDate = now
        }
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? now
    }

    private func parseRelativeDateTime(from prompt: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var baseDate = now

        if prompt.contains("tomorrow") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else if prompt.contains("today") {
            baseDate = now
        }

        do {
            let regex = try NSRegularExpression(pattern: "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)", options: [.caseInsensitive])
            let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
            if let match = regex.firstMatch(in: prompt, options: [], range: range),
               let hourRange = Range(match.range(at: 1), in: prompt) {
                let minuteRange = Range(match.range(at: 2), in: prompt)
                let periodRange = Range(match.range(at: 3), in: prompt)

                guard var hour = Int(prompt[hourRange]) else { return nil }
                let minute = minuteRange.flatMap { Int(prompt[$0]) } ?? 0
                let period = periodRange.map { prompt[$0].lowercased() } ?? "am"

                if period == "pm" && hour < 12 { hour += 12 }
                if period == "am" && hour == 12 { hour = 0 }

                var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
                components.hour = hour
                components.minute = minute
                return calendar.date(from: components)
            }
        } catch {
            return nil
        }

        return nil
    }

    @MainActor
    private func refreshAssistantModelAvailability() async {
        isCheckingAssistantModel = true
        assistantInstallError = nil

        if UITestLaunchFlags.forcesMainUI && UITestLaunchFlags.fakeAssistantModelForUITest {
            hasInstalledAssistantModel = true
            UserDefaults.standard.set(true, forKey: assistantLocalLLMEnabledKey)
            isCheckingAssistantModel = false
            scheduleInitialMessageLoad()
            return
        }

        for spec in preferredAssistantSpecs {
            if await ModelManager.shared.isModelInstalled(spec) {
                hasInstalledAssistantModel = true
                UserDefaults.standard.set(true, forKey: assistantLocalLLMEnabledKey)
                isCheckingAssistantModel = false
                scheduleInitialMessageLoad()
                return
            }
        }

        hasInstalledAssistantModel = false
        isCheckingAssistantModel = false
    }

    private func installAssistantModels() {
        guard !isInstallingAssistantModel else { return }

        isInstallingAssistantModel = true
        assistantInstallProgress = 0
        assistantInstallDetail = "Preparing…"
        assistantInstallError = nil

        Task {
            do {
                for (index, spec) in preferredAssistantSpecs.enumerated() {
                    let completedModelCount = Double(index)
                    let totalModelCount = Double(preferredAssistantSpecs.count)

                    if await ModelManager.shared.isModelInstalled(spec) {
                        await MainActor.run {
                            assistantInstallProgress = totalModelCount > 0 ? (completedModelCount + 1) / totalModelCount : 1
                            assistantInstallDetail = "Already installed \(spec.displayName)"
                        }
                        continue
                    }

                    _ = try await ModelManager.shared.ensureModelInstalled(spec) { progress in
                        Task { @MainActor in
                            let modelFraction = progress.fractionCompleted
                            let overallFraction = totalModelCount > 0
                                ? (completedModelCount + modelFraction) / totalModelCount
                                : modelFraction
                            assistantInstallProgress = overallFraction
                            assistantInstallDetail = "Installing \(spec.displayName) (\(progress.completedFiles)/\(progress.totalFiles))"
                        }
                    }

                    await MainActor.run {
                        assistantInstallProgress = totalModelCount > 0 ? (completedModelCount + 1) / totalModelCount : 1
                        assistantInstallDetail = "Installed \(spec.displayName)"
                    }
                }

                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: assistantLocalLLMEnabledKey)
                    isInstallingAssistantModel = false
                    assistantInstallProgress = 1
                    assistantInstallDetail = "Installed JSON model"
                    hasInstalledAssistantModel = true
                    scheduleInitialMessageLoad()
                }
            } catch {
                await MainActor.run {
                    isInstallingAssistantModel = false
                    assistantInstallError = "Install failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadMessagesIfNeeded() {
        guard !hasLoadedInitialMessages else { return }
        hasLoadedInitialMessages = true

        if let last = UserDefaults.standard.string(forKey: assistantBreadcrumbKey), !last.isEmpty {
            logAssistant("Assistant previous breadcrumb: \(last)", level: .warn)
        }
        setAssistantBreadcrumb("view.onAppear")
        logAssistant("Assistant view appeared. existingMessages=\(messages.count)")
        if messages.isEmpty {
            let restored = loadPersistedMessages()
            if restored.isEmpty {
                messages = [
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I can help with academic planning, financial aid questions, and quick timeline asks like 'What is for tomorrow?'.",
                        timestamp: Date()
                    )
                ]
                logAssistant("Assistant seeded with default welcome message")
            } else {
                messages = restored
                logAssistant("Assistant restored persisted messages. restoredCount=\(restored.count)")
            }
        }
    }

    private func refreshAssistantPlannerContext() {
        assistantContextEvents = AssistantContextBridge.boundedCalendarEvents(
            collegePersistence: collegePersistence
        )
        assistantContextTasks = AssistantContextBridge.boundedPlannerTasks(
            collegePersistence: collegePersistence
        )
    }

    private func scheduleInitialMessageLoad() {
        if deferInitialLoadOneTick {
            Task { @MainActor in
                await Task.yield()
                loadMessagesIfNeeded()
            }
        } else {
            loadMessagesIfNeeded()
        }
    }

    @MainActor
    private func generateReply(
        for prompt: String,
        role: AssistantAgentRole,
        hadAttachments: Bool,
        ingest: AssistantAttachmentIngestor.Result,
        onRawChunk: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AssistantTurnResult {
        try Task.checkCancellation()
        setAssistantBreadcrumb("generateReply.snapshot.begin")
        let snapshot = plannerSnapshotForTurn()
        setAssistantBreadcrumb("generateReply.snapshot.end")
        let serviceRole: AIAssistantService.Role = role == .academicAdvisor ? .academicAdvisor : .financialAid
        let persona: AssistantPersona = role == .academicAdvisor ? .academicAdvisor : .financialAdvisor
        let recentConversation = makeRecentConversationSummary(currentPrompt: prompt)

        let attachmentBlock = ingest.contextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        let routerSeesAttachments = hadAttachments || !attachmentBlock.isEmpty

        let decision = AIAssistantToolRouter.routeDecision(
            for: prompt,
            role: serviceRole,
            snapshot: snapshot,
            activePage: activePage,
            hasAttachments: routerSeesAttachments
        )

        switch decision {
        case .deterministic(let deterministicReply):
            setAssistantBreadcrumb("generateReply.router.deterministic")
            return AssistantTurnResult(text: deterministicReply, sources: [])
        case .llmPreferred(let seed):
            setAssistantBreadcrumb("generateReply.router.llmPreferred")
            var contextSummary = await makeAssistantContextSummary(from: snapshot, userPrompt: prompt)
            if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contextSummary += "\n\nDeterministic planner seed:\n\(seed)\n\nUse this seed as grounding context, but provide a personalized explanation and recommendations instead of repeating the template verbatim."
            }
            return try await generateToolAwareReply(
                for: prompt,
                serviceRole: serviceRole,
                persona: persona,
                snapshot: snapshot,
                contextSummary: contextSummary,
                recentConversation: recentConversation,
                attachmentContextBlock: attachmentBlock.isEmpty ? nil : attachmentBlock,
                deterministicSeed: seed,
                onRawChunk: onRawChunk
            )
        case .none:
            setAssistantBreadcrumb("generateReply.router.miss")
            if AssistantIntentSemantics.isEnabled,
               let suggestion = AssistantIntentSemantics.classify(message: prompt, role: serviceRole),
               suggestion.confidence >= 0.7 {
                logAssistant("Semantic route hit intent=\(suggestion.matchedIntent) confidence=\(suggestion.confidence)")
                switch suggestion.decision {
                case .deterministic(let text):
                    return AssistantTurnResult(text: text, sources: [])
                case .llmPreferred(let seed):
                    var semanticContext = await makeAssistantContextSummary(from: snapshot, userPrompt: prompt)
                    if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        semanticContext += "\n\nSemantic seed:\n\(seed)"
                    }
                    return try await generateToolAwareReply(
                        for: prompt,
                        serviceRole: serviceRole,
                        persona: persona,
                        snapshot: snapshot,
                        contextSummary: semanticContext,
                        recentConversation: recentConversation,
                        attachmentContextBlock: attachmentBlock.isEmpty ? nil : attachmentBlock,
                        deterministicSeed: seed,
                        onRawChunk: onRawChunk
                    )
                case .none:
                    break
                }
            }
        }

        let contextSummary = await makeAssistantContextSummary(from: snapshot, userPrompt: prompt)
        return try await generateToolAwareReply(
            for: prompt,
            serviceRole: serviceRole,
            persona: persona,
            snapshot: snapshot,
            contextSummary: contextSummary,
            recentConversation: recentConversation,
            attachmentContextBlock: attachmentBlock.isEmpty ? nil : attachmentBlock,
            onRawChunk: onRawChunk
        )
    }

    @MainActor
    private func generateToolAwareReply(
        for prompt: String,
        serviceRole: AIAssistantService.Role,
        persona: AssistantPersona,
        snapshot: AssistantPlannerSnapshot,
        contextSummary: String,
        recentConversation: String,
        attachmentContextBlock: String?,
        deterministicSeed: String? = nil,
        onRawChunk: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AssistantTurnResult {
        let planningCatalogJSON = AIAssistantToolRegistry.planningCatalogJSON(for: persona)
        let planningToolNames = AIAssistantToolRegistry.planningToolNames(for: persona)
        let policyContext = makeAssistantPolicyContext(for: prompt)
        let fullRagContext = await makeAssistantPolicyRAGContext(for: prompt, serviceRole: serviceRole, policyContext: policyContext)
        let slimRagContext: String? = {
            guard let text = fullRagContext?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            if text.count <= 500 { return text }
            return String(text.prefix(500)) + "\n...(truncated for planning)"
        }()
        var planningToolContext: String? = slimRagContext
        var toolExecutionRecords: [String: AssistantToolCallDedupeRecord] = [:]
        var accumulatedSources: [AssistantReplySource] = []
        var accumulatedToolTrace: [AssistantToolTraceEntry] = []
        let executor = AIAssistantToolExecutor(
            context: AssistantToolExecutionContext(
                collegePersistence: collegePersistence,
                activePage: activePage,
                selectedPersona: persona,
                snapshot: snapshot,
                currentDate: Date()
            )
        )

        // Hard bypass: explicit web-search prompts should not depend on model planning.
        // This guarantees web lookup still works even when local planning/generation fails.
        if let webQuery = explicitWebSearchQuery(from: prompt) {
            let universityName = collegePersistence.getActiveUniversityName()
            let cacheKey = acceptedWebAnswerCacheKey(query: webQuery, role: selectedRole, universityName: universityName)
            if let cached = try? await AssistantWebMemoryStore.shared.lookupAcceptedWebAnswer(cacheKey: cacheKey, maxAgeDays: 14) {
                let cachedSources = decodeSavedSources(json: cached.sourcesJSON)
                return AssistantTurnResult(
                    text: """
Saved answer (from prior thumbs-up):
\(cached.answer)
""",
                    sources: cachedSources
                )
            }
            let directSearchStart = Date()
            let directSearch = await executor.execute(
                call: AssistantToolCallEnvelope(
                    tool: "searxWebSearch",
                    arguments: [
                        "query": .string(webQuery),
                        "maxResults": .number(6)
                    ]
                )
            )
            let directSearchLatencyMS = max(0, Int(Date().timeIntervalSince(directSearchStart) * 1000.0))
            let directSearchTrace = AssistantToolTraceEntry(
                toolName: "searxWebSearch",
                hopIndex: 0,
                latencyMS: directSearchLatencyMS,
                ok: directSearch.ok,
                summary: toolTraceSummary(from: directSearch)
            )

            if directSearch.ok {
                let webSources = AssistantToolSources.extract(
                    from: directSearch,
                    toolName: "searxWebSearch",
                    hopIndex: 0,
                    latencyMS: directSearchLatencyMS
                )
                let lines = webSources.prefix(6).enumerated().map { idx, source in
                    let urlText = source.url ?? ""
                    return "\(idx + 1). \(source.title)\(urlText.isEmpty ? "" : " - \(urlText)")"
                }
                if !lines.isEmpty {
                    return AssistantTurnResult(
                        text: """
Web results for: \(webQuery)

\(lines.joined(separator: "\n"))
""",
                        sources: webSources,
                        toolTrace: [directSearchTrace]
                    )
                }
            }

            let searchFailureSummary = directSearch.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchFailureText = searchFailureSummary.isEmpty ? "Direct web search failed." : searchFailureSummary
            return AssistantTurnResult(
                text: """
I tried a direct web search for "\(webQuery)", but it failed:
\(searchFailureText)

Check Assistant web-search settings and try again.
""",
                sources: [],
                toolTrace: [directSearchTrace]
            )
        }

        assistantToolHop: for hop in 0..<dynamicMaxToolHops {
            try Task.checkCancellation()
            if hop > 0 {
                await Task.yield()
                try await Task.sleep(nanoseconds: Self.toolHopPlanDebounceNs)
                try Task.checkCancellation()
            }
            let planning = await AIAssistantService.shared.planResponse(
                message: prompt,
                role: serviceRole,
                contextSummary: contextSummary,
                recentConversation: recentConversation,
                toolCatalogJSON: planningCatalogJSON,
                allowedPlanningToolNames: planningToolNames,
                planningToolContext: planningToolContext,
                attachmentContextBlock: attachmentContextBlock,
                policyContext: policyContext
            )

            if let fallbackReply = planning.fallbackReply {
                if let reason = planning.failureReason {
                    setAssistantBreadcrumb("generateReply.plan.failure.\(reason.rawValue)")
                }
                if let seed = deterministicSeed?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !seed.isEmpty,
                   planning.failureReason != nil {
                    let combined = """
\(seed)

---

\(fallbackReply)
"""
                    return AssistantTurnResult(text: combined, sources: accumulatedSources, toolTrace: accumulatedToolTrace)
                }
                return AssistantTurnResult(text: fallbackReply, sources: accumulatedSources, toolTrace: accumulatedToolTrace)
            }

            guard let action = planning.action else {
                setAssistantBreadcrumb("generateReply.plan.empty")
                let replyContext = replyContextMergingFullRAG(contextSummary: contextSummary, fullRagContext: fullRagContext)
                let outcome = await AIAssistantService.shared.generateReplyOutcome(
                    message: prompt,
                    role: serviceRole,
                    contextSummary: replyContext,
                    recentConversation: recentConversation,
                    toolContext: planningToolContext,
                    attachmentContextBlock: attachmentContextBlock,
                    policyContext: policyContext,
                    onRawChunk: onRawChunk
                )
                try Task.checkCancellation()
                return AssistantTurnResult(text: outcome.reply, sources: accumulatedSources, toolTrace: accumulatedToolTrace)
            }

            switch action {
            case .finalAnswer(let reply):
                setAssistantBreadcrumb("generateReply.plan.direct.hop\(hop)")
                return AssistantTurnResult(text: reply, sources: accumulatedSources, toolTrace: accumulatedToolTrace)
            case .toolCall(let call):
                setAssistantBreadcrumb("generateReply.plan.tool.\(call.tool).hop\(hop)")
                if let descriptor = AIAssistantToolRegistry.descriptor(named: call.tool),
                   descriptor.requiresConfirmation {
                    if let pending = pendingAction(from: call) {
                        pendingAction = pending
                        return AssistantTurnResult(
                            text: "I drafted that action. Review the confirmation card below and choose Confirm or Cancel.",
                            sources: accumulatedSources,
                            toolTrace: accumulatedToolTrace
                        )
                    }
                    return AssistantTurnResult(
                        text: "I understood that you want to make a change, but the action details were incomplete. Please include the title and timing details.",
                        sources: accumulatedSources,
                        toolTrace: accumulatedToolTrace
                    )
                }
                let signature = Self.canonicalToolCallSignature(for: call)
                if let existing = toolExecutionRecords[signature] {
                    if existing.lastOk {
                        logAssistant("Breaking tool loop: duplicate successful call to \(call.tool)", level: .info)
                        break assistantToolHop
                    }
                    if existing.consumedFailedRetry {
                        logAssistant("Breaking tool loop: duplicate call after failed retry for \(call.tool)", level: .info)
                        break assistantToolHop
                    }
                }
                let toolStart = Date()
                let toolResult = await executor.execute(call: call)
                let ok = toolResult.ok
                if var existing = toolExecutionRecords[signature] {
                    if !existing.lastOk && !existing.consumedFailedRetry {
                        existing.consumedFailedRetry = true
                        existing.lastOk = ok
                        toolExecutionRecords[signature] = existing
                    } else {
                        toolExecutionRecords[signature] = AssistantToolCallDedupeRecord(
                            lastOk: ok,
                            consumedFailedRetry: existing.consumedFailedRetry
                        )
                    }
                } else {
                    toolExecutionRecords[signature] = AssistantToolCallDedupeRecord(lastOk: ok, consumedFailedRetry: false)
                }
                let toolLatencyMS = max(0, Int(Date().timeIntervalSince(toolStart) * 1000.0))
                accumulatedToolTrace.append(
                    AssistantToolTraceEntry(
                        toolName: call.tool,
                        hopIndex: hop,
                        latencyMS: toolLatencyMS,
                        ok: toolResult.ok,
                        summary: toolTraceSummary(from: toolResult)
                    )
                )
                accumulatedSources = AssistantToolSources.mergeUnique(
                    accumulatedSources,
                    AssistantToolSources.extract(
                        from: toolResult,
                        toolName: call.tool,
                        hopIndex: hop,
                        latencyMS: toolLatencyMS
                    )
                )
                let piece = makeToolContext(from: toolResult)
                if let existing = planningToolContext, !existing.isEmpty {
                    planningToolContext = existing + "\n\n---\n\n" + piece
                } else {
                    planningToolContext = piece
                }
            }
        }

        setAssistantBreadcrumb("generateReply.plan.maxHops")
        let replyContextMaxHops = replyContextMergingFullRAG(contextSummary: contextSummary, fullRagContext: fullRagContext)
        let outcome = await AIAssistantService.shared.generateReplyOutcome(
            message: prompt,
            role: serviceRole,
            contextSummary: replyContextMaxHops,
            recentConversation: recentConversation,
            toolContext: planningToolContext,
            attachmentContextBlock: attachmentContextBlock,
            policyContext: policyContext,
            onRawChunk: onRawChunk
        )
        if let reason = outcome.failureReason {
            setAssistantBreadcrumb("generateReply.service.failure.\(reason.rawValue)")
        }
        try Task.checkCancellation()
        if let seed = deterministicSeed?.trimmingCharacters(in: .whitespacesAndNewlines),
           !seed.isEmpty,
           outcome.failureReason != nil {
            let combined = """
\(seed)

---

\(outcome.reply)
"""
            return AssistantTurnResult(text: combined, sources: accumulatedSources, toolTrace: accumulatedToolTrace)
        }
        return AssistantTurnResult(text: outcome.reply, sources: accumulatedSources, toolTrace: accumulatedToolTrace)
    }

    private func makeAssistantPolicyContext(for prompt: String) -> AssistantPolicyContext {
        AssistantPolicyContext.from(
            metadata: collegePersistence.activeSchoolPolicyMetadata(),
            activeUniversityName: collegePersistence.getActiveUniversityName(),
            message: prompt
        )
    }

    private func makeAssistantPolicyRAGContext(for prompt: String, serviceRole: AIAssistantService.Role, policyContext: AssistantPolicyContext) async -> String? {
        let financialPrompt = serviceRole == .financialAid
        let academicIntent = AssistantIntentSemantics.classify(message: prompt, role: .academicAdvisor)?.matchedIntent
        let academicPrompt = academicIntent.map {
            ["first_semester_plan", "next_semester_plan", "multi_semester_plan", "semester_plan"].contains($0)
        } ?? false
        guard financialPrompt || academicPrompt else { return nil }
        let topics: Set<AssistantPolicyTopic> = financialPrompt
            ? [.schoolFinancialAid, .fafsa, .stateAid, .verification, .sap, .enrollmentIntensity]
            : [.academicCatalog]
        let evidence = AssistantPolicyEvidenceStore.evidence(for: topics, jurisdiction: policyContext.jurisdiction)
        await AssistantPolicyRAGStore.shared.upsert(
            AssistantPolicyRAGSeeder.chunks(from: evidence, jurisdiction: policyContext.jurisdiction)
        )
        let filter = AssistantPolicyRAGFilter.financialAid(context: policyContext)
        let hits = await AssistantPolicyRAGStore.shared.retrieve(query: prompt, filter: filter, limit: 5)
        let block = AssistantPolicyRAGFormatter.promptBlock(hits: hits).trimmingCharacters(in: .whitespacesAndNewlines)
        return block.isEmpty ? nil : block
    }

    private func explicitWebSearchQuery(from prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let markers = [
            "search the web for ",
            "search web for ",
            "web search for ",
            "search online for ",
            "search the internet for ",
            "look up on the web "
        ]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let suffix = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !suffix.isEmpty { return suffix }
            }
        }
        if lower.contains("search the web") || lower.contains("web search") || lower.contains("search online") {
            return trimmed
        }
        return nil
    }

    private func computePlannerSnapshotCacheKey() -> Int {
        var hasher = Hasher()
        hasher.combine(collegePersistence.calendarDidChangeToken)
        hasher.combine(collegePersistence.plannerChangeToken)
        hasher.combine(collegePersistence.profileRevision)
        hasher.combine(collegePersistence.catalogDataRevision)
        hasher.combine(assistantContextEvents.count)
        hasher.combine(assistantContextTasks.count)
        return hasher.finalize()
    }

    private func plannerSnapshotForTurn() -> AssistantPlannerSnapshot {
        let key = computePlannerSnapshotCacheKey()
        if let cached = plannerSnapshotCache, plannerSnapshotCacheKey == key {
            return cached
        }
        let built = makePlannerSnapshot()
        plannerSnapshotCache = built
        plannerSnapshotCacheKey = key
        return built
    }

    private func makePlannerSnapshot() -> AssistantPlannerSnapshot {
        let eventItems = assistantContextEvents
            .prefix(Self.snapshotEventLimit)
            .map { event in
            AssistantPlannerSnapshot.EventItem(
                title: event.title,
                startDate: event.startDate,
                allDay: event.allDay
            )
        }

        let taskItems = assistantContextTasks
            .prefix(Self.snapshotTaskLimit)
            .map {
                AssistantPlannerSnapshot.TaskItem(
                    title: $0.title,
                    dueDate: $0.dueDate,
                    isCompleted: $0.isCompleted
                )
            }

        let majors = collegePersistence.resolvedMajorNames()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let minors = collegePersistence.resolvedMinorNames()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let majorPrograms = majors.map { majorName in
            let progress = collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: majorName)
            let buckets = collegePersistence.majorRequirementCreditBuckets(forMajorDisplay: majorName)
            var requirements = collegePersistence.getDegreeRequirementsForMajorDisplay(majorName)
            if requirements.isEmpty {
                let degreeType = (collegePersistence.primaryDegreeType() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let profileMajor = (collegePersistence.resolvedMajorNames().first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedURL: String?
                if majorName == profileMajor {
                    resolvedURL = collegePersistence.resolveSelectedMajorProgramURL()
                } else {
                    resolvedURL = collegePersistence.resolveNonMinorMajorProgramURL(display: majorName)
                }
                if let resolvedURL {
                    requirements = collegePersistence.getDegreeRequirements(programURL: resolvedURL, degreeType: degreeType)
                }
            }
            return AssistantPlannerSnapshot.ProgramItem(
                name: majorName,
                kind: .major,
                completedCredits: progress.completed,
                requiredCredits: progress.required,
                requiredCoreCredits: buckets.requiredCore,
                requiredElectiveCredits: buckets.requiredElective,
                pendingCourses: pendingRequirementCourses(from: requirements)
            )
        }

        let minorPrograms = minors.map { minorName in
            let progress = collegePersistence.minorRequirementsCreditsProgress(forMinorDisplay: minorName)
            let buckets = collegePersistence.minorRequirementCreditBuckets(forMinorDisplay: minorName)
            let requirements: [DegreeRequirementEntity] = {
                guard let programURL = collegePersistence.resolveProgramProgramURL(programDisplay: minorName, isMinor: true) else {
                    return []
                }
                return collegePersistence.getDegreeRequirements(programURL: programURL, degreeType: "Minor")
            }()
            return AssistantPlannerSnapshot.ProgramItem(
                name: minorName,
                kind: .minor,
                completedCredits: progress.completed,
                requiredCredits: progress.required,
                requiredCoreCredits: buckets.requiredCore,
                requiredElectiveCredits: buckets.requiredElective,
                pendingCourses: pendingRequirementCourses(from: requirements)
            )
        }

        let programs = majorPrograms + minorPrograms

        return AssistantPlannerSnapshot(
            events: eventItems,
            tasks: taskItems,
            majors: majors,
            minors: minors,
            programs: programs
        )
    }

    private func pendingRequirementCourses(from requirements: [DegreeRequirementEntity]) -> [AssistantPlannerSnapshot.ProgramItem.CourseItem] {
        struct Candidate {
            let code: String
            let title: String
            let credits: Double
        }

        func normalizeCode(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }

        func parseCredits(_ raw: String?) -> Double? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let first = trimmed.split(separator: "-").first {
                return Double(first.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return Double(trimmed)
        }

        var candidates: [Candidate] = []
        for req in requirements {
            let selectCount = Int(req.selectCount)
            if selectCount > 0 {
                var choices: [CourseDetail] = []
                if let json = req.selectFromDetailedJSON,
                   let detailed = collegePersistence.decodeDetailedCourseList(json),
                   !detailed.isEmpty {
                    choices = detailed
                } else if let json = req.requiredCoursesDetailedJSON,
                          let detailed = collegePersistence.decodeDetailedCourseList(json),
                          !detailed.isEmpty {
                    choices = detailed
                } else {
                    let rawCodes = collegePersistence.decodeJSONCourseList(req.selectFromJSON)
                    if !rawCodes.isEmpty {
                        choices = rawCodes.map { CourseDetail(code: $0, title: nil, credits: nil) }
                    } else {
                        let fallbackCodes = (req.requiredCourses ?? "")
                            .split(separator: ",")
                            .map { String($0) }
                        choices = fallbackCodes.map { CourseDetail(code: $0, title: nil, credits: nil) }
                    }
                }

                for detail in choices.prefix(max(1, selectCount)) {
                    let code = normalizeCode(detail.code)
                    guard !code.isEmpty else { continue }
                    let catalog = collegePersistence.getCatalogCourse(code: code)
                    let title = detail.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedTitle = (title?.isEmpty == false ? title! : (catalog?.title ?? "Untitled course"))
                    let credits = parseCredits(detail.credits) ?? (catalog.map { Double($0.credits) } ?? 3)
                    candidates.append(Candidate(code: code, title: resolvedTitle, credits: max(1, credits)))
                }
                continue
            }

            if let json = req.requiredCoursesDetailedJSON,
               let detailed = collegePersistence.decodeDetailedCourseList(json),
               !detailed.isEmpty {
                for detail in detailed {
                    let code = normalizeCode(detail.code)
                    guard !code.isEmpty else { continue }
                    let catalog = collegePersistence.getCatalogCourse(code: code)
                    let title = detail.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedTitle = (title?.isEmpty == false ? title! : (catalog?.title ?? "Untitled course"))
                    let credits = parseCredits(detail.credits) ?? (catalog.map { Double($0.credits) } ?? 3)
                    candidates.append(Candidate(code: code, title: resolvedTitle, credits: max(1, credits)))
                }
                continue
            }

            let legacyCodes = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { normalizeCode(String($0)) }
                .filter { !$0.isEmpty }
            for code in legacyCodes {
                let catalog = collegePersistence.getCatalogCourse(code: code)
                candidates.append(
                    Candidate(
                        code: code,
                        title: catalog?.title ?? "Untitled course",
                        credits: max(1, catalog.map { Double($0.credits) } ?? 3)
                    )
                )
            }
        }

        var seen: Set<String> = []
        var deduped: [AssistantPlannerSnapshot.ProgramItem.CourseItem] = []
        deduped.reserveCapacity(candidates.count)
        for candidate in candidates {
            if seen.contains(candidate.code) { continue }
            seen.insert(candidate.code)
            deduped.append(
                AssistantPlannerSnapshot.ProgramItem.CourseItem(
                    code: candidate.code,
                    title: candidate.title,
                    credits: candidate.credits
                )
            )
        }
        return Array(deduped.prefix(Self.snapshotPendingCourseLimit))
    }

    private func makeAssistantContextSummary(from snapshot: AssistantPlannerSnapshot, userPrompt: String) async -> String {
        let now = Date()
        let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let gpa = collegePersistence.primaryGPA()
        let creditsEarned = collegePersistence.primaryCreditsEarned()
        let creditsRequired = max(collegePersistence.primaryCreditsRequired(), 0)
        let creditsRequiredDisplay = creditsRequired > 0 ? creditsRequired : 120
        let graduationTarget = collegePersistence.primaryExpectedGraduation()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sap = collegePersistence.sapStats()
        let storedFullTimeThreshold = collegePersistence.activeSchoolPolicies()?.minCreditsForFullTime
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        let upcomingEvents = snapshot.events
            .filter { $0.startDate >= now && $0.startDate <= sevenDays }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)

        let upcomingTasks = snapshot.tasks
            .filter {
                guard let due = $0.dueDate else { return false }
                return due >= now && due <= sevenDays && !$0.isCompleted
            }
            .sorted {
                guard let lhs = $0.dueDate, let rhs = $1.dueDate else { return false }
                return lhs < rhs
            }
            .prefix(6)

        var lines: [String] = []
        let majorsText = snapshot.majors.isEmpty ? "none" : snapshot.majors.joined(separator: ", ")
        let minorsText = snapshot.minors.isEmpty ? "none" : snapshot.minors.joined(separator: ", ")

        lines.append("Current role: \(selectedRole.rawValue)")
        lines.append("Active page: \(activePage.rawValue)")
        let activeUniversityName = collegePersistence.getActiveUniversityName()
        let schoolMetadata = collegePersistence.activeSchoolPolicyMetadata()
        let jurisdiction = schoolMetadata.map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
            ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: activeUniversityName)
        let fullTimeThreshold = storedFullTimeThreshold ?? (jurisdiction.allowsFederalFAFSA ? 12 : nil)
        let fullTimeSource = storedFullTimeThreshold == nil && fullTimeThreshold != nil
            ? "planning benchmark; verify with school"
            : "school policy"
        lines.append("Active university: \(activeUniversityName ?? "unknown")")
        lines.append("Aid jurisdiction policy: \(jurisdiction.policySummary)")
        if let schoolID = jurisdiction.schoolID {
            lines.append("School ID: \(schoolID)")
        }
        if let unitID = jurisdiction.unitID {
            lines.append("NCES UnitID: \(unitID)")
        }
        if let opeID = jurisdiction.opeID {
            lines.append("OPEID: \(opeID)")
        }
        if let stateCode = jurisdiction.normalizedStateCode {
            lines.append("State code: \(stateCode)")
        }
        if let financialAidURL = jurisdiction.financialAidURL {
            lines.append("School financial-aid source: \(financialAidURL)")
        }
        if let stateAidURL = jurisdiction.stateAidAgencyURL {
            lines.append("State aid extra-resource: \(stateAidURL)")
        }
        lines.append("Majors: \(majorsText)")
        lines.append("Minors: \(minorsText)")
        lines.append("Credits earned/required: \(creditsEarned)/\(creditsRequiredDisplay)")
        lines.append("Current GPA: \(gpa > 0 ? String(format: "%.2f", gpa) : "unknown")")
        lines.append("Expected graduation: \((graduationTarget?.isEmpty == false ? graduationTarget! : "unknown"))")
        lines.append("SAP completion rate: attempted \(sap.attempted), completed \(sap.completed), rate \(Int((sap.rate * 100).rounded()))%")
        lines.append("Full-time threshold: \(fullTimeThreshold.map(String.init) ?? "unknown") credits (\(fullTimeSource))")
        if snapshot.programs.isEmpty {
            lines.append("Program progress: none detected")
        } else {
            lines.append("Program progress:")
            for program in snapshot.programs.prefix(4) {
                let kind = program.kind == .major ? "Major" : "Minor"
                lines.append("- \(kind) \(program.name): \(Int(program.completedCredits.rounded()))/\(Int(program.requiredCredits.rounded())) credits")
            }
        }
        lines.append("Upcoming events (7 days): \(upcomingEvents.count)")
        for event in upcomingEvents {
            let when = event.allDay ? "All day" : formatter.string(from: event.startDate)
            lines.append("- Event: \(event.title) @ \(when)")
        }

        lines.append("Upcoming open tasks (7 days): \(upcomingTasks.count)")
        for task in upcomingTasks {
            let dueText: String
            if let dueDate = task.dueDate {
                dueText = formatter.string(from: dueDate)
            } else {
                dueText = "No due time"
            }
            lines.append("- Task: \(task.title) due \(dueText)")
        }

        let base = lines.joined(separator: "\n")
        let semantic = AssistantWebSearchSettings.isSemanticMemoryEnabled
        let budget = contextPackaging
        let queryMemory = await AssistantWebMemoryStore.shared.contextForUserQuery(
            userPrompt,
            charBudget: budget.queryMemoryCharBudget,
            maxRows: budget.queryMemoryMaxRows,
            semanticEnabled: semantic
        )
        let recentMemory = await AssistantWebMemoryStore.shared.recentSummaries(
            charBudget: budget.recentMemoryCharBudget,
            maxRows: budget.recentMemoryMaxRows
        )
        let helpfulSnippets = AssistantConversationMemory.contextBlock(charBudget: budget.helpfulMemoryCharBudget)
        let memoryParts = [queryMemory, recentMemory, helpfulSnippets].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let memoryJoined = memoryParts.joined(separator: "\n\n")
        let memoryCap = budget.maxCombinedWebMemoryChars
        let cappedMemory: String = {
            guard memoryJoined.count > memoryCap else { return memoryJoined }
            return Self.truncateContextString(memoryJoined, limit: memoryCap) + "\n...(truncated)"
        }()
        var blocks: [String] = [base]
        if !cappedMemory.isEmpty { blocks.append(cappedMemory) }
        return blocks.joined(separator: "\n\n")
    }

    @MainActor
    private func makeRecentConversationSummary(currentPrompt: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d h:mm a"
        let recent = messages.suffix(contextPackaging.recentMessageCount)
        guard !recent.isEmpty else { return "No earlier conversation in this session." }
        let lines = recent.map { message in
            let speaker = message.isUser ? "User" : message.role.rawValue
            let safeText: String = {
                let t = message.text
                if t.count <= 300 { return t }
                return String(t.prefix(300)) + "..."
            }()
            return "[\(formatter.string(from: message.timestamp))] \(speaker): \(safeText)"
        }
        if let last = lines.last, last.contains(currentPrompt) {
            return lines.joined(separator: "\n")
        }
        return (lines + ["[Now] User: \(currentPrompt)"]).joined(separator: "\n")
    }

    private func makeToolContext(from result: AssistantToolResultEnvelope) -> String {
        let summaryCap = 2000
        let summaryLine: String = {
            let s = result.summary
            if s.count <= summaryCap { return s }
            return String(s.prefix(summaryCap)) + "...(truncated)"
        }()
        let encoded: String = {
            guard let data = try? JSONEncoder().encode(result),
                  let raw = String(data: data, encoding: .utf8) else {
                return "{\"tool\":\"\(result.tool)\",\"ok\":\(result.ok ? "true" : "false"),\"summary\":\"\(summaryLine)\"}"
            }
            return raw
        }()
        let jsonCap = 800
        let jsonString = encoded.count > jsonCap
            ? String(encoded.prefix(jsonCap)) + "...(truncated)"
            : encoded
        return "Tool execution summary:\n\(summaryLine)\n\nTool result JSON:\n\(jsonString)"
    }

    private func pendingAction(from call: AssistantToolCallEnvelope) -> AssistantPendingAction? {
        switch call.tool {
        case "createTask":
            guard let title = call.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return nil
            }
            let dueDate = call.arguments["dueDateISO8601"]?.stringValue.flatMap(parseISO8601Date)
            return AssistantPendingAction(
                kind: .createTask,
                title: title,
                originalTitle: nil,
                dueDate: dueDate,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil
            )
        case "updateTask":
            guard let requested = call.arguments["existingTitle"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !requested.isEmpty else {
                return nil
            }
            let matched = assistantContextTasks.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            let existingTitle = matched?.title ?? requested
            let newTitle = normalizedAssistantTitle(call.arguments["title"]?.stringValue) ?? existingTitle
            let dueDate = call.arguments["dueDateISO8601"]?.stringValue.flatMap(parseISO8601Date) ?? matched?.dueDate
            return AssistantPendingAction(
                kind: .editTask,
                title: newTitle,
                originalTitle: existingTitle,
                dueDate: dueDate,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: matched?.dueDate,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        case "createCalendarEvent":
            guard let title = call.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  let startRaw = call.arguments["startDateISO8601"]?.stringValue,
                  let startDate = parseISO8601Date(startRaw) else {
                return nil
            }
            let allDay = call.arguments["allDay"]?.boolValue ?? false
            let endDate: Date = {
                if let endRaw = call.arguments["endDateISO8601"]?.stringValue,
                   let parsed = parseISO8601Date(endRaw) {
                    return parsed
                }
                return Calendar.current.date(byAdding: .hour, value: allDay ? 24 : 1, to: startDate) ?? startDate
            }()
            return AssistantPendingAction(
                kind: .createEvent,
                title: title,
                originalTitle: nil,
                dueDate: nil,
                startDate: startDate,
                endDate: endDate,
                allDay: allDay,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil
            )
        case "updateCalendarEvent":
            guard let requested = call.arguments["existingTitle"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !requested.isEmpty else {
                return nil
            }
            let matched = assistantContextEvents.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            let existingTitle = matched?.title ?? requested
            let title = normalizedAssistantTitle(call.arguments["title"]?.stringValue) ?? existingTitle
            let allDay = call.arguments["allDay"]?.boolValue ?? matched?.allDay ?? false
            let startDate = call.arguments["startDateISO8601"]?.stringValue.flatMap(parseISO8601Date) ?? matched?.startDate
            guard let resolvedStart = startDate else { return nil }
            let endDate: Date = {
                if let raw = call.arguments["endDateISO8601"]?.stringValue,
                   let parsed = parseISO8601Date(raw) {
                    return parsed
                }
                if let matchedEnd = matched?.endDate {
                    return matchedEnd
                }
                return Calendar.current.date(byAdding: .hour, value: allDay ? 24 : 1, to: resolvedStart) ?? resolvedStart
            }()
            return AssistantPendingAction(
                kind: .editEvent,
                title: title,
                originalTitle: existingTitle,
                dueDate: nil,
                startDate: resolvedStart,
                endDate: endDate,
                allDay: allDay,
                previousDueDate: nil,
                previousStartDate: matched?.startDate,
                previousEndDate: matched?.endDate,
                previousAllDay: matched?.allDay,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        case "deleteTask":
            guard let requested = call.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !requested.isEmpty else {
                return nil
            }
            let matched = assistantContextTasks.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            return AssistantPendingAction(
                kind: .deleteTask,
                title: matched?.title ?? requested,
                originalTitle: matched?.title ?? requested,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: matched?.dueDate,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        case "deleteCalendarEvent":
            guard let requested = call.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !requested.isEmpty else {
                return nil
            }
            let matched = assistantContextEvents.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            return AssistantPendingAction(
                kind: .deleteEvent,
                title: matched?.title ?? requested,
                originalTitle: matched?.title ?? requested,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: matched?.startDate,
                previousEndDate: matched?.endDate,
                previousAllDay: matched?.allDay,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        case "saveWebLearning":
            guard let title = call.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  let summaryBody = call.arguments["summaryBody"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summaryBody.isEmpty else {
                return nil
            }
            let urls = assistantPendingSourceURLList(from: call.arguments["sourceURLs"])
            let tagsRaw = call.arguments["tags"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tags: String? = tagsRaw.isEmpty ? nil : tagsRaw
            return AssistantPendingAction(
                kind: .saveWebLearning,
                title: title,
                originalTitle: nil,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil,
                webLearningSummary: summaryBody,
                webLearningSourceURLs: urls,
                webLearningTags: tags
            )
        default:
            return nil
        }
    }

    private func assistantPendingSourceURLList(from value: AssistantJSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .array(let items):
            return items.compactMap(\.stringValue).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [t]
        default:
            return []
        }
    }

    private func parseISO8601Date(_ raw: String) -> Date? {
        let fullFormatter = ISO8601DateFormatter()
        fullFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = fullFormatter.date(from: raw) {
            return value
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: raw)
    }

    private func normalizedAssistantTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func decodeSavedSources(json: String) -> [AssistantReplySource] {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return []
        }
        return rows.compactMap { row in
            guard let title = row["title"], !title.isEmpty else { return nil }
            return AssistantReplySource(title: title, url: row["url"], kind: .webSearch)
        }
    }

    private func loadPersistedMessages() -> [AssistantMessage] {
        guard var raw = UserDefaults.standard.string(forKey: messageStoreKey) else {
            return []
        }
        if let sanitized = ModelMigrationService.sanitizeAssistantMessagesJSON(raw), sanitized != raw {
            raw = sanitized
            UserDefaults.standard.set(sanitized, forKey: messageStoreKey)
        }
        guard let data = raw.data(using: .utf8),
              let persisted = try? JSONDecoder().decode([PersistedAssistantMessage].self, from: data) else {
            return []
        }

        return persisted.compactMap { item in
            guard let role = AssistantAgentRole(rawValue: item.roleRawValue) else { return nil }
            return AssistantMessage(
                id: item.id ?? UUID(),
                isUser: item.isUser,
                role: role,
                text: item.text,
                timestamp: item.timestamp,
                attachmentDisplayNames: item.attachmentDisplayNames ?? [],
                modelPromptOverride: item.modelPromptOverride,
                attachmentContextBlock: item.attachmentContextBlock,
                sources: item.sources ?? [],
                toolTrace: item.toolTrace ?? [],
                feedback: item.feedbackRaw.flatMap { AssistantReplyFeedback(rawValue: $0) },
                supersededReplyTexts: item.supersededReplyTexts ?? []
            )
        }
    }

    private func persistMessages(_ items: [AssistantMessage]) {
        let capped = Array(items.suffix(120))
        let payload = capped.map {
            PersistedAssistantMessage(
                id: $0.id,
                isUser: $0.isUser,
                roleRawValue: $0.role.rawValue,
                text: $0.text,
                timestamp: $0.timestamp,
                attachmentDisplayNames: $0.attachmentDisplayNames.isEmpty ? nil : $0.attachmentDisplayNames,
                modelPromptOverride: $0.modelPromptOverride,
                attachmentContextBlock: $0.attachmentContextBlock,
                sources: $0.sources.isEmpty ? nil : $0.sources,
                toolTrace: $0.toolTrace.isEmpty ? nil : $0.toolTrace,
                feedbackRaw: $0.feedback?.rawValue,
                supersededReplyTexts: $0.supersededReplyTexts.isEmpty ? nil : $0.supersededReplyTexts
            )
        }

        guard let data = try? JSONEncoder().encode(payload),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(raw, forKey: messageStoreKey)
    }

    private func schedulePersistMessages(_ items: [AssistantMessage]) {
        persistGeneration += 1
        let generation = persistGeneration
        let snapshot = items
        persistWriteTask?.cancel()
        persistWriteTask = Task.detached(priority: .utility) {
            let capped = Array(snapshot.suffix(120))
            let payload = capped.map {
                PersistedAssistantMessage(
                    id: $0.id,
                    isUser: $0.isUser,
                    roleRawValue: $0.role.rawValue,
                    text: $0.text,
                    timestamp: $0.timestamp,
                    attachmentDisplayNames: $0.attachmentDisplayNames.isEmpty ? nil : $0.attachmentDisplayNames,
                    modelPromptOverride: $0.modelPromptOverride,
                    attachmentContextBlock: $0.attachmentContextBlock,
                    sources: $0.sources.isEmpty ? nil : $0.sources,
                    toolTrace: $0.toolTrace.isEmpty ? nil : $0.toolTrace,
                    feedbackRaw: $0.feedback?.rawValue,
                    supersededReplyTexts: $0.supersededReplyTexts.isEmpty ? nil : $0.supersededReplyTexts
                )
            }
            guard !Task.isCancelled,
                  let data = try? JSONEncoder().encode(payload),
                  let raw = String(data: data, encoding: .utf8) else {
                return
            }
            await MainActor.run {
                guard generation == persistGeneration else { return }
                UserDefaults.standard.set(raw, forKey: messageStoreKey)
            }
        }
    }
}

private struct AssistantToolCallDedupeRecord {
    var lastOk: Bool
    var consumedFailedRetry: Bool
}

enum AIAssistantFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "assistant",
                title: "Assistant model readiness",
                criticality: .bestEffort,
                timeoutSeconds: 2.4,
                retryLimit: 0,
                run: { _, onProgress, onDetail in
                    onDetail("Checking JSON worker model")
                    if await ModelManager.shared.isModelInstalled(.jsonWorker) {
                        onProgress(1)
                        return
                    }

                    // Never block launch on multi-GB model downloads. Startup only verifies
                    // readiness here; background bootstrap continues after main content appears.
                    onDetail("JSON model not installed yet; download continues after launch")
                    onProgress(1)
                }
            )
        )
    }
}