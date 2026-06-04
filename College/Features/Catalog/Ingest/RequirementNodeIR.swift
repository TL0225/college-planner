// RequirementNodeIR.swift
// Feature: Catalog
// Purpose: Catalog module — Node.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Deterministic requirement intermediate representation (Phase 2) used before LLM enrichment.
enum RequirementNodeIR {
    static let descriptionPrefix = "requirementIR:"

    enum NodeKind: String, Codable, Sendable {
        case all
        case any
        case course
        case credits
        case text
    }

    struct Node: Codable, Sendable, Equatable, Identifiable {
        let id: UUID
        let kind: NodeKind
        let courseCode: String?
        let credits: Int?
        let label: String?
        let children: [Node]

        init(
            id: UUID = UUID(),
            kind: NodeKind,
            courseCode: String? = nil,
            credits: Int? = nil,
            label: String? = nil,
            children: [Node] = []
        ) {
            self.id = id
            self.kind = kind
            self.courseCode = courseCode
            self.credits = credits
            self.label = label
            self.children = children
        }

        static func course(_ code: String) -> Node {
            Node(kind: .course, courseCode: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }

        static func all(_ children: [Node]) -> Node {
            Node(kind: .all, children: children)
        }

        static func any(_ children: [Node], label: String? = nil) -> Node {
            Node(kind: .any, label: label, children: children)
        }

        static func credits(_ value: Int, label: String? = nil) -> Node {
            Node(kind: .credits, credits: value, label: label)
        }
    }

    /// Maps a flat list of course codes into a deterministic `all` node graph.
    static func graphFromRequiredCourseCodes(_ codes: [String]) -> Node {
        let normalized = codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        if normalized.isEmpty {
            return Node(kind: .text, label: "No structured requirements")
        }
        return .all(normalized.map { .course($0) })
    }

    /// Serializes IR to stable JSON for persistence/comparison.
    static func encodeJSON(_ node: Node) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(node) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encodeForDescription(_ node: Node) -> String? {
        guard let json = encodeJSON(node) else { return nil }
        return descriptionPrefix + json
    }

    static func decodeFromDescription(_ description: String?) -> Node? {
        guard let description else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(descriptionPrefix) else { return nil }
        let json = String(trimmed.dropFirst(descriptionPrefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Node.self, from: data)
    }

    static func collectCourseCodes(from node: Node) -> [String] {
        var out: [String] = []
        func walk(_ n: Node) {
            if n.kind == .course, let code = n.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
                out.append(code.uppercased())
            }
            for child in n.children { walk(child) }
        }
        walk(node)
        return out
    }
}
