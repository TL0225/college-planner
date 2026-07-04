// AIAssistantViewModels.swift
// Feature: Assistant
// Purpose: Shared assistant message/composer types (Phase 6 decomposition).

import SwiftUI
import AppKit

enum AssistantTargetReference {
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

struct AssistantMessage: Identifiable, Hashable {
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

struct AssistantTurnResult: Sendable {
    let text: String
    let sources: [AssistantReplySource]
    let toolTrace: [AssistantToolTraceEntry]

    init(text: String, sources: [AssistantReplySource], toolTrace: [AssistantToolTraceEntry] = []) {
        self.text = text
        self.sources = sources
        self.toolTrace = toolTrace
    }
}

struct PersistedAssistantMessage: Codable {
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

struct AssistantPendingAction: Identifiable {
    enum Kind {
        case createTask
        case createEvent
        case editTask
        case editEvent
        case deleteTask
        case deleteEvent
        case saveWebLearning
        case syncSyllabusDeadlines
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

struct AssistantComposerTextField: NSViewRepresentable {
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
        field.setAccessibilityLabel("Assistant message composer")
        field.setAccessibilityRole(.textField)
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
