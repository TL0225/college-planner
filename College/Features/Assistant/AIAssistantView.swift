// AIAssistantView.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantMessage.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import UniformTypeIdentifiers
import AppKit


private enum AssistantLaunchState: Equatable {
    case checking
    case installRequired
    case ready
}

struct AIAssistantView: View {
    @Environment(AppContainer.self) private var container
    @Environment(NetworkConnectivityMonitor.self) private var networkMonitor
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    @Environment(\.accessibilityReduceMotion) var motionReduced
    @Environment(\.scenePhase) private var scenePhase
    var collegePersistence: CollegePersistence { container.persistence }
    @State var assistantContextEvents: [CalendarEvent] = []
    @State var assistantContextTasks: [PlannerTask] = []
    @State private var plannerSnapshotCache: AssistantPlannerSnapshot?
    @State private var plannerSnapshotCacheKey: Int = 0

    @State var hoveredTranscriptMessageID: UUID?
    @State var selectedRole: AssistantAgentRole = .academicAdvisor
    @State private var draftText: String = ""
    @State var messages: [AssistantMessage] = []
    @State private var hasLoadedInitialMessages: Bool = false
    @StateObject var viewModel = AIAssistantViewModel()
    @State private var launchState: AssistantLaunchState = .checking
    @State private var inferenceAvailability: AssistantInferenceAvailability?
    /// Defers mounting the chat shell (NSTextField composer, transcript) until after readiness settles.
    @State private var showAssistantChatShell = false
    @State private var isInstallingAssistantModel: Bool = false
    @State private var assistantInstallProgress: Double = 0
    @State private var assistantInstallDetail: String = ""
    @State private var assistantInstallError: String?
    @State var pendingAction: AssistantPendingAction?
    @State private var pendingSecurityScopedURLs: [URL] = []
    @State private var showAttachmentImporter = false
    @State private var showWebMemoryLibrary = false
    @State private var toolbarHandlerToken: ToolbarHandlerToken?
    /// Avoid encoding + UserDefaults writes on every streaming token (was a major main-thread hitch).
    @State private var messagesPersistTask: Task<Void, Never>?
    private let messagesPersistDebounceNs: UInt64 = 650_000_000
    @State var editingUserMessageID: UUID?
    @State var editingUserMessageDraft: String = ""
    @State private var lastSubmittedPrompt: String = ""
    @State private var lastAssistantReplyCharacterCount: Int = 0
    @State private var autoPromptRunStarted = false
    @State private var autoPromptNextIndex = 0
    @State private var autoPromptFinished = false
    @State private var persistGeneration: Int = 0
    @State private var persistWriteTask: Task<Void, Never>?
    @AppStorage("assistant.streaming.enabled") private var assistantStreamingEnabled: Bool = true
    @AppStorage("assistant.runtime.showDiagnostics") private var assistantDiagnosticsEnabled: Bool = false
    @AppStorage("assistant.response.lengthPreset") private var assistantResponseLengthPreset: String = "balanced"
    @AppStorage(AssistantWebSearchSettings.webSearchEnabledKey) private var webSearchEnabled: Bool = true

    private let messageStoreKey = "assistant.messages.v1"
    @AppStorage("assistant.deferInitialLoadOneTick") private var deferInitialLoadOneTick: Bool = true
    private let assistantAutoScrollEnabled = true
    private let assistantBreadcrumbKey = "assistant.debug.lastBreadcrumb"
    let assistantLocalLLMEnabledKey = "assistant.localLLM.enabled"
    private let preferredAssistantSpecs: [ModelSpec] = [.jsonWorker]
    private static let snapshotEventLimit = 240
    private static let snapshotTaskLimit = 320
    private static let snapshotPendingCourseLimit = 32
    static let toolHopPlanDebounceNs: UInt64 = 60_000_000
    private let streamChunkCharacterCount = 48
    private let streamChunkDelayNanoseconds: UInt64 = 40_000_000

    var dynamicMaxToolHops: Int {
        switch assistantResponseLengthPreset {
        case "short":
            return 2
        case "detailed":
            return 6
        default:
            return 4
        }
    }

    func logAssistant(_ message: String, level: DebugLogger.Level = .info) {
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

    func replyContextMergingFullRAG(contextSummary: String, fullRagContext: String?) -> String {
        let trimmed = fullRagContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return contextSummary }
        return contextSummary + "\n\n---\n\n" + trimmed
    }

    static func canonicalJSONValueForToolArg(_ value: AssistantJSONValue) -> String {
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

    static func canonicalToolCallSignature(for call: AssistantToolCallEnvelope) -> String {
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

    func setAssistantBreadcrumb(_ value: String) {
#if DEBUG
        let stamp = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set("\(stamp) | \(value)", forKey: assistantBreadcrumbKey)
#else
        if value.contains("failure") || value.contains("success") {
            UserDefaults.standard.set(value, forKey: assistantBreadcrumbKey)
        }
#endif
    }

    var isResponding: Bool {
        viewModel.isResponding
    }

    var streamingMessageID: UUID? {
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
            let shellBottomInset = proxy.safeAreaInsets.bottom
            Group {
                switch launchState {
                case .ready:
                    if showAssistantChatShell {
                        assistantChatLayout(shellBottomInset: shellBottomInset)
                    } else {
                        assistantLaunchCheckingState
                    }
                case .checking, .installRequired:
                    assistantInstallRequiredState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.bgMain)
        .accessibilityIdentifier("assistant.root")
        .shellDynamicTypeReadable()
        .task {
            setAssistantBreadcrumb("view.task.begin")
            await refreshAssistantModelAvailability()
            refreshAssistantPlannerContext()
        }
        .onAppear {
            registerAssistantToolbar()
            syncAssistantToolbarScene()
            if showAssistantChatShell, !hasLoadedInitialMessages {
                scheduleInitialMessageLoad()
            }
        }
        .onChange(of: selectedRole) { _, _ in
            syncAssistantToolbarScene()
        }
        .onChange(of: collegePersistence.calendarDidChangeToken) { _, _ in
            refreshAssistantPlannerContext()
        }
        .onDisappear {
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
            viewModel.cancelActiveGeneration()
            persistMessagesImmediatelyFromState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshAssistantModelAvailability() }
        }
        .onChange(of: showAssistantChatShell) { _, show in
            guard show else { return }
            SubsystemMemoryEstimator.emitSubsystemWarningsIfNeeded()
            scheduleInitialMessageLoad()
            startAutoPromptRunIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeAssistantOpenWebMemory)) { _ in
            showWebMemoryLibrary = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeAssistantExportTranscript)) { _ in
            exportTranscript()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeAssistantClearThread)) { _ in
            messages.removeAll()
            hasLoadedInitialMessages = false
            loadMessagesIfNeeded()
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
                scheduleNextAutoPromptIfNeeded()
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
        shellBottomInset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    assistantOfflineBanner
                }
                Divider().opacity(0.45)
                composer(shellBottomInset: shellBottomInset)
            }
            .background(DesignSystem.Colors.bgMain)
        }
    }

    private var assistantOfflineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text("You're offline. On-device replies still work; web search and catalog fetch are unavailable.")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.warning.opacity(0.12))
        .accessibilityIdentifier("assistant.offlineBanner")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. On-device replies still work. Web search and catalog fetch are unavailable.")
    }

    @ViewBuilder
    private var assistantLaunchCheckingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.small)
            Text("Checking AI model status…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    @ViewBuilder
    private var assistantInstallRequiredState: some View {
        VStack(spacing: 18) {
            if launchState == .checking {
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

                Text(installRequiredGuidance)
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
                .disabled(isInstallingAssistantModel || launchState == .checking)
                .help("Install on-device Qwen JSON model")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var installRequiredGuidance: String {
        "Turn on Apple Intelligence in System Settings, or install the on-device JSON model below for offline use."
    }

    private func syncAssistantToolbarScene() {
        container.assistantScene.selectedRole = selectedRole
        container.assistantScene.applyInferenceAvailability(inferenceAvailability)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        AssistantStudentGuidePanel(
                            selectedRole: selectedRole,
                            localModelInstalled: showAssistantChatShell,
                            webSearchEnabled: webSearchEnabled
                        )
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if shouldShowTranscriptDayHeader(for: message, previousMessage: previous) {
                            transcriptDayHeader(message.timestamp)
                        }
                        messageBubble(message, previousMessage: previous)
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
                                Text(
                                    streamingMessageID == nil
                                        ? AssistantStepLabels.label(for: viewModel.activeAssistantToolName)
                                        : "Streaming..."
                                )
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
                .frame(maxWidth: AssistantChatChrome.transcriptColumnMaxWidth)
                .frame(maxWidth: .infinity)
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
                .accessibilityLabel("Attach file")
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
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("assistant.sendButton")
            }
        }
        .padding(.horizontal, AssistantChatChrome.composerHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, bottomSpacing)
    }


    func toolTraceSummary(from envelope: AssistantToolResultEnvelope) -> String {
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

    private func startAutoPromptRunIfNeeded() {
        guard AssistantUITestAutoPromptRunner.isEnabled,
              !autoPromptRunStarted,
              !autoPromptFinished else { return }
        autoPromptRunStarted = true
        autoPromptNextIndex = 0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            sendNextAutoPromptIfNeeded()
        }
    }

    private func scheduleNextAutoPromptIfNeeded() {
        guard AssistantUITestAutoPromptRunner.isEnabled,
              autoPromptRunStarted,
              !autoPromptFinished else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            sendNextAutoPromptIfNeeded()
        }
    }

    private func sendNextAutoPromptIfNeeded() {
        guard AssistantUITestAutoPromptRunner.isEnabled,
              autoPromptRunStarted,
              !autoPromptFinished,
              showAssistantChatShell,
              !isResponding else { return }

        let prompts = AssistantUITestAutoPromptRunner.prompts
        guard autoPromptNextIndex < prompts.count else {
            autoPromptFinished = true
            AssistantUITestAutoPromptRunner.writeLog(from: messages)
            logAssistant("Assistant auto-prompt run finished (\(prompts.count) prompts)")
            return
        }

        let prompt = prompts[autoPromptNextIndex]
        autoPromptNextIndex += 1
        draftText = prompt
        logAssistant("Assistant auto-prompt send \(autoPromptNextIndex)/\(prompts.count): \(prompt.prefix(80))")
        sendMessage()
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
        ProductAnalytics.track(.assistantMessageSent, properties: ["role": requestRole.rawValue])

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

    private func registerAssistantToolbar() {
        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = container.toolbarDispatcher.register(owner: .assistant) { action in
            guard case .assistant(let assistantAction) = action else { return }
            switch assistantAction {
            case .openWebMemory:
                showWebMemoryLibrary = true
            case .regenerateLastReply:
                regenerateLastAssistantTurn()
            case .exportTranscript:
                exportTranscript()
            case .clearThread:
                messages.removeAll()
                hasLoadedInitialMessages = false
                loadMessagesIfNeeded()
            }
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

    func setMessageFeedback(messageID: UUID, feedback: AssistantReplyFeedback?) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].feedback = feedback
        let message = messages[idx]
        let query = inferPromptForAssistantMessage(at: idx)
        let university = collegePersistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines)

        if feedback == .notHelpful {
            AssistantFeedbackGovernance.recordNotHelpful(
                query: query,
                role: message.role,
                universityName: university
            )
#if DEBUG
            let telemetry = AssistantTurnTelemetry.recentRecords(limit: 1).last
            ProductionEvalSampler.recordSample(
                prompt: query,
                intent: telemetry?.intent,
                routePath: telemetry?.path.rawValue ?? "unknown",
                flagged: true
            )
#endif
            AppToastHost.shared.show(
                AppToast(
                    title: "Feedback saved",
                    message: "I'll refresh that answer next time you ask.",
                    accessibilityIdentifier: "assistant.toast.feedbackSaved"
                ),
                autoDismissAfter: 4
            )
            return
        }

        guard feedback == .helpful else { return }
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        AssistantFeedbackGovernance.recordHelpful(
            query: query,
            reply: message.text,
            role: message.role,
            universityName: university,
            sources: message.sources
        )
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

    func acceptedWebAnswerCacheKey(query: String, role: AssistantAgentRole, universityName: String?) -> String {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let uni = (universityName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(role.rawValue.lowercased())|\(uni)|\(normalizedQuery)"
    }

    func copyMessageText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportTranscript() {
        struct ExportRow: Codable {
            let id: UUID
            let isUser: Bool
            let roleRawValue: String
            let text: String
            let timestamp: Date
            let sourceTrustLabels: [String]?
            let toolTraceTools: [String]?
        }
        let payload = messages.map { message in
            ExportRow(
                id: message.id,
                isUser: message.isUser,
                roleRawValue: message.role.rawValue,
                text: message.text,
                timestamp: message.timestamp,
                sourceTrustLabels: message.sources.isEmpty
                    ? nil
                    : Array(Set(message.sources.compactMap(\.trustTier).map { AssistantAcademicWebPolicy.userFacingLabel(for: $0) })),
                toolTraceTools: message.toolTrace.isEmpty ? nil : message.toolTrace.map(\.toolName)
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
        try? raw.write(to: url, atomically: true, encoding: String.Encoding.utf8)
    }

    func canEditMessage(_ message: AssistantMessage) -> Bool {
        guard message.isUser else { return false }
        guard canEditWhileIdle else { return false }
        guard message.text.range(of: #"^\d+ attachment\(s\)$"#, options: .regularExpression) == nil else { return false }
        return true
    }

    func beginUserMessageEdit(_ message: AssistantMessage) {
        guard canEditMessage(message) else { return }
        editingUserMessageID = message.id
        editingUserMessageDraft = message.text
    }

    func cancelUserMessageEdit() {
        editingUserMessageID = nil
        editingUserMessageDraft = ""
    }

    func commitUserMessageEdit(messageID: UUID) {
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



    @MainActor
    private func refreshAssistantModelAvailability() async {
        let availability: AssistantInferenceAvailability
        let ready: Bool
        if UITestLaunchFlags.forcesMainUI && UITestLaunchFlags.fakeAssistantModelForUITest {
            availability = .foundationModels
            ready = true
        } else {
            availability = await AssistantInferenceAvailability.current()
            ready = switch availability {
            case .foundationModels, .jsonWorkerFallback: true
            case .unavailable: false
            }
        }

        let jsonWorkerInstalled = ready ? await ModelManager.shared.isModelInstalled(.jsonWorker) : false

        // Yield before flipping launch state so SwiftUI is not mid-render in `.task`.
        await Task.yield()

        inferenceAvailability = availability
        syncAssistantToolbarScene()
        assistantInstallError = nil
        if ready {
            if jsonWorkerInstalled {
                UserDefaults.standard.set(true, forKey: assistantLocalLLMEnabledKey)
            }
            launchState = .ready
            await Task.yield()
            showAssistantChatShell = true
        } else {
            showAssistantChatShell = false
            launchState = .installRequired
        }
    }

    @MainActor
    private func markAssistantInstallComplete(jsonWorkerInstalled: Bool) async {
        if jsonWorkerInstalled {
            UserDefaults.standard.set(true, forKey: assistantLocalLLMEnabledKey)
        }
        isInstallingAssistantModel = false
        assistantInstallProgress = 1
        assistantInstallDetail = jsonWorkerInstalled ? "Installed JSON model" : "Install finished"
        assistantInstallError = nil
        launchState = .ready
        await Task.yield()
        showAssistantChatShell = true
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

                let jsonInstalled = await ModelManager.shared.isModelInstalled(.jsonWorker)
                await markAssistantInstallComplete(jsonWorkerInstalled: jsonInstalled)
            } catch {
                await MainActor.run {
                    isInstallingAssistantModel = false
                    assistantInstallError = "Install failed: \(error.localizedDescription)"
                }
                if await AssistantInferenceAvailability.isChatReady() {
                    await markAssistantInstallComplete(jsonWorkerInstalled: false)
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


    func makeAssistantPolicyContext(for prompt: String) -> AssistantPolicyContext {
        AssistantPolicyContext.from(
            metadata: collegePersistence.activeSchoolPolicyMetadata(),
            activeUniversityName: collegePersistence.getActiveUniversityName(),
            message: prompt
        )
    }

    func makeAssistantPolicyRAGContext(for prompt: String, serviceRole: AIAssistantService.Role, policyContext: AssistantPolicyContext) async -> String? {
        let financialPrompt = serviceRole == .financialAid
        let academicIntent = AssistantIntentSemantics.classify(message: prompt, role: .academicAdvisor)?.matchedIntent
        let academicPrompt = academicIntent.map {
            ["first_semester_plan", "next_semester_plan", "multi_semester_plan", "semester_plan", "degree_policy_lookup"].contains($0)
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

    func explicitWebSearchQuery(from prompt: String) -> String? {
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

    func plannerSnapshotForTurn() -> AssistantPlannerSnapshot {
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

    func makeAssistantContextSummary(from snapshot: AssistantPlannerSnapshot, userPrompt: String) async -> String {
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
        let programIdentity = AssistantProgramIdentityBuilder.build(persistence: collegePersistence)
        lines.append(AssistantProgramIdentityBuilder.promptBlock(for: programIdentity))
        if let disclaimer = AssistantProgramIdentityBuilder.disclaimerLine(for: programIdentity) {
            lines.append(disclaimer)
        }
        let classifiedIntent = AssistantIntentSemantics.classify(message: userPrompt, role: selectedRole == .academicAdvisor ? .academicAdvisor : .financialAid)?.matchedIntent
        let continuity = AssistantSessionContinuity.openingContextBlock()
        if !continuity.isEmpty {
            lines.append(continuity)
        }
        if classifiedIntent == "career_exploration" {
            lines.append(AssistantCareerReplyGuide.synthesisRules)
        }
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
    func makeRecentConversationSummary(currentPrompt: String) -> String {
        AssistantConversationSummaryBuilder.makeSummary(
            messages: messages,
            currentPrompt: currentPrompt,
            recentMessageCount: contextPackaging.recentMessageCount
        )
    }

    func makeToolContext(from result: AssistantToolResultEnvelope) -> String {
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

    func pendingAction(from call: AssistantToolCallEnvelope) -> AssistantPendingAction? {
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
        case "syncSyllabusDeadlinesToPlanner":
            let drafts = AssistantSyllabusDeadlineExtractor.drafts(from: collegePersistence)
            guard !drafts.isEmpty else { return nil }
            let encoded = (try? JSONEncoder().encode(drafts)).flatMap { String(data: $0, encoding: .utf8) }
            return AssistantPendingAction(
                kind: .syncSyllabusDeadlines,
                title: "Sync \(drafts.count) syllabus deadline(s)",
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
                webLearningSummary: "Creates planner tasks from linked syllabus due dates.",
                webLearningTags: encoded
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
        AssistantISO8601Parsing.date(from: raw)
    }

    private func normalizedAssistantTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func decodeSavedSources(json: String) -> [AssistantReplySource] {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return []
        }
        return rows.compactMap { row -> AssistantReplySource? in
            guard let title = row["title"], !title.isEmpty else { return nil }
            return AssistantReplySource(title: title, url: row["url"], kind: .webSearch)
        }
    }

    private func loadPersistedMessages() -> [AssistantMessage] {
        AssistantMessageStore.load(key: messageStoreKey)
    }

    private func persistMessages(_ items: [AssistantMessage]) {
        AssistantMessageStore.persist(items, key: messageStoreKey)
    }

    private func schedulePersistMessages(_ items: [AssistantMessage]) {
        persistGeneration += 1
        let generation = persistGeneration
        let snapshot = items
        persistWriteTask?.cancel()
        persistWriteTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == persistGeneration else { return }
                AssistantMessageStore.persist(snapshot, key: messageStoreKey)
            }
        }
    }
}
