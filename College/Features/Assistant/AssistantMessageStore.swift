// AssistantMessageStore.swift
// UserDefaults persistence for assistant transcript (testable).

import Foundation

enum AssistantMessageStore {
    static let defaultKey = "assistant.messages.v1"
    static let maxPersistedMessages = 120

    static func persist(_ items: [AssistantMessage], key: String = defaultKey) {
        let capped = Array(items.suffix(maxPersistedMessages))
        let payload = capped.map(persisted(from:))
        guard let data = try? JSONEncoder().encode(payload),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func load(key: String = defaultKey) -> [AssistantMessage] {
        guard var raw = UserDefaults.standard.string(forKey: key) else {
            return []
        }
        if let sanitized = ModelMigrationService.sanitizeAssistantMessagesJSON(raw), sanitized != raw {
            raw = sanitized
            UserDefaults.standard.set(sanitized, forKey: key)
        }
        guard let data = raw.data(using: .utf8),
              let persisted = try? JSONDecoder().decode([PersistedAssistantMessage].self, from: data) else {
            return []
        }
        return persisted.compactMap(restored(from:))
    }

    private static func persisted(from message: AssistantMessage) -> PersistedAssistantMessage {
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

    private static func restored(from item: PersistedAssistantMessage) -> AssistantMessage? {
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
