import Foundation

/// Extracts user-visible citations from tool result payloads.
enum AssistantToolSources {
    static func extract(
        from envelope: AssistantToolResultEnvelope,
        toolName: String? = nil,
        hopIndex: Int? = nil,
        latencyMS: Int? = nil
    ) -> [AssistantReplySource] {
        guard envelope.ok, let root = envelope.result else { return [] }
        let resolvedToolName = toolName ?? envelope.tool
        switch envelope.tool {
        case "searxWebSearch":
            return extractSearx(root, toolName: resolvedToolName, hopIndex: hopIndex, latencyMS: latencyMS)
        case "fetchWebPageReadable":
            return extractFetch(root, toolName: resolvedToolName, hopIndex: hopIndex, latencyMS: latencyMS)
        default:
            return extractPolicyEvidence(root, toolName: resolvedToolName, hopIndex: hopIndex, latencyMS: latencyMS)
        }
    }

    private static func extractSearx(
        _ root: [String: AssistantJSONValue],
        toolName: String?,
        hopIndex: Int?,
        latencyMS: Int?
    ) -> [AssistantReplySource] {
        guard let hitsValue = root["hits"], case .array(let rows) = hitsValue else { return [] }
        var out: [AssistantReplySource] = []
        out.reserveCapacity(min(rows.count, 12))
        for row in rows.prefix(12) {
            guard case .object(let obj) = row else { continue }
            let title = obj["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let urlStr = obj["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = obj["snippet"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !urlStr.isEmpty else { continue }
            let displayTitle = title.isEmpty ? urlStr : title
            let url = urlStr.isEmpty ? nil : urlStr
            out.append(
                AssistantReplySource(
                    title: displayTitle,
                    url: url,
                    kind: .webSearch,
                    snippet: snippet?.isEmpty == true ? nil : snippet,
                    toolName: toolName,
                    hopIndex: hopIndex,
                    latencyMS: latencyMS
                )
            )
        }
        return out
    }

    private static func extractFetch(
        _ root: [String: AssistantJSONValue],
        toolName: String?,
        hopIndex: Int?,
        latencyMS: Int?
    ) -> [AssistantReplySource] {
        let urlStr = root["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !urlStr.isEmpty else { return [] }
        let snippet = root["content"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            AssistantReplySource(
                title: "Fetched page",
                url: urlStr,
                kind: .fetchedPage,
                snippet: snippet.map { String($0.prefix(180)) },
                toolName: toolName,
                hopIndex: hopIndex,
                latencyMS: latencyMS
            )
        ]
    }

    private static func extractPolicyEvidence(
        _ root: [String: AssistantJSONValue],
        toolName: String?,
        hopIndex: Int?,
        latencyMS: Int?
    ) -> [AssistantReplySource] {
        guard let evidenceValue = root["policyEvidence"], case .array(let rows) = evidenceValue else { return [] }
        return rows.compactMap { row -> AssistantReplySource? in
            guard case .object(let obj) = row else { return nil }
            let title = obj["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = obj["sourceURL"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = obj["summary"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !url.isEmpty else { return nil }
            return AssistantReplySource(
                title: title.isEmpty ? url : title,
                url: url.isEmpty ? nil : url,
                kind: .webSearch,
                snippet: summary.map { String($0.prefix(180)) },
                toolName: toolName,
                hopIndex: hopIndex,
                latencyMS: latencyMS
            )
        }
    }

    /// Dedupes by URL (when present) then title.
    static func mergeUnique(_ a: [AssistantReplySource], _ b: [AssistantReplySource]) -> [AssistantReplySource] {
        var seen = Set<String>()
        var out: [AssistantReplySource] = []
        for block in [a, b] {
            for s in block {
                let key: String
                if let u = s.url, !u.isEmpty {
                    key = "u:\(u.lowercased())"
                } else {
                    key = "t:\(s.title.lowercased())"
                }
                if seen.insert(key).inserted {
                    out.append(s)
                }
            }
        }
        return out
    }
}
