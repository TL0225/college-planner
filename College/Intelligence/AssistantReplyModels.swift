import Foundation

/// A link or reference shown under an assistant reply (web search, fetched page, etc.).
struct AssistantReplySource: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case webSearch
        case fetchedPage
    }

    let title: String
    let url: String?
    let kind: Kind
    let snippet: String?
    let toolName: String?
    let hopIndex: Int?
    let latencyMS: Int?

    init(
        title: String,
        url: String?,
        kind: Kind,
        snippet: String? = nil,
        toolName: String? = nil,
        hopIndex: Int? = nil,
        latencyMS: Int? = nil
    ) {
        self.title = title
        self.url = url
        self.kind = kind
        self.snippet = snippet
        self.toolName = toolName
        self.hopIndex = hopIndex
        self.latencyMS = latencyMS
    }
}

enum AssistantReplyFeedback: String, Codable, Sendable {
    case helpful
    case notHelpful
}

struct AssistantToolTraceEntry: Codable, Hashable, Sendable {
    let toolName: String
    let hopIndex: Int
    let latencyMS: Int
    let ok: Bool
    let summary: String
}
