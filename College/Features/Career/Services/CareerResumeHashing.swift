// CareerResumeHashing.swift
// Feature: Career
// Purpose: SHA-256 hashing of normalized resume plain text for cache invalidation.

import CryptoKit
import Foundation

enum CareerResumeHashing {
    /// SHA-256 hex digest of normalized plain text (not raw PDF bytes).
    static func hash(normalizedPlainText: String) -> String {
        let normalized = normalize(normalizedPlainText)
        let data = Data(normalized.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(jobDescriptionPlain: String) -> String {
        hash(normalizedPlainText: jobDescriptionPlain)
    }

    /// Combined JD + requirements hash for match-cache invalidation.
    /// Description-only postings keep the legacy single-field hash for compatibility.
    static func hashJobPostingContent(descriptionPlain: String?, requirementsPlain: String?) -> String {
        let desc = normalize(descriptionPlain ?? "")
        let req = normalize(requirementsPlain ?? "")
        if !desc.isEmpty, !req.isEmpty {
            return hash(normalizedPlainText: "\(desc)\n---\n\(req)")
        }
        if !desc.isEmpty { return hash(normalizedPlainText: desc) }
        if !req.isEmpty { return hash(normalizedPlainText: req) }
        return hash(normalizedPlainText: "")
    }

    static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
