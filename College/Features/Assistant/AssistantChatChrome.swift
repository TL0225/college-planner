// AssistantChatChrome.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantReplyFormattedText.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI

// MARK: - Reply markdown + formatted text (was AssistantReplyFormattedText.swift)

enum AssistantReplyMarkdown {
    /// Strip pathological length; keep model output bounded before AttributedString parsing.
    static func boundedPlainInput(_ raw: String, maxChars: Int = 40_000) -> String {
        guard raw.count > maxChars else { return raw }
        return String(raw.prefix(maxChars))
    }

    /// Replace `[1]`, `[2]` with Markdown links when the source has an https URL (best-effort, on-device).
    static func expandNumericCitations(_ text: String, sources: [AssistantReplySource]) -> String {
        guard !sources.isEmpty else { return text }
        var out = text
        for i in sources.indices {
            let marker = "[\(i + 1)]"
            guard out.contains(marker) else { continue }
            let src = sources[i]
            guard let urlStr = src.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let u = URL(string: urlStr),
                  u.scheme == "http" || u.scheme == "https"
            else { continue }
            let title = src.title
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            out = out.replacingOccurrences(
                of: marker,
                with: "[\(title)](\(urlStr))"
            )
        }
        return out
    }

    /// Turns bare https URLs in prose into Markdown links (skips ones already inside `(...)` or after `]`).
    static func linkifyBareHTTPSInMarkdown(_ text: String) -> String {
        let pattern = #"(^|[\s>])(https?://[^\s\[\]()<>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }
        var out = ""
        var cursor = text.startIndex
        for m in matches {
            guard let full = Range(m.range, in: text),
                  let prefixRange = Range(m.range(at: 1), in: text),
                  let urlRange = Range(m.range(at: 2), in: text) else { continue }
            out.append(contentsOf: text[cursor..<full.lowerBound])
            out.append(contentsOf: text[prefixRange])
            let url = String(text[urlRange])
            let trimmedUrl = url.trimmingCharacters(in: CharacterSet(charactersIn: ".,);:"))
            let trailing = String(url.dropFirst(trimmedUrl.count))
            out.append("[\(trimmedUrl)](\(trimmedUrl))")
            out.append(trailing)
            cursor = full.upperBound
        }
        out.append(contentsOf: text[cursor...])
        return String(out)
    }
}

/// Assistant reply body: Markdown when supported; plain `Text` while streaming.
struct AssistantReplyFormattedText: View {
    let text: String
    let sources: [AssistantReplySource]
    /// When true, skip Markdown (partial streaming tokens).
    let renderPlainTextOnly: Bool

    var body: some View {
        Group {
            if renderPlainTextOnly {
                Text(text)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .textSelection(.enabled)
            } else {
                let merged = AssistantReplyMarkdown.linkifyBareHTTPSInMarkdown(
                    AssistantReplyMarkdown.expandNumericCitations(
                        AssistantReplyMarkdown.boundedPlainInput(text),
                        sources: sources
                    )
                )
                if let attributed = try? AttributedString(
                    markdown: merged,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .full,
                        failurePolicy: .returnPartiallyParsedIfPossible
                    )
                ) {
                    Text(attributed)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .textSelection(.enabled)
                } else {
                    Text(text)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Planner bars (was AssistantPlannerProgressBars.swift)

/// Compact, deterministic progress rows from live local store (no LLM-drawn charts).
struct AssistantPlannerProgressBars: View {
    @ObservedObject private var collegePersistence: CollegePersistence

    private struct Row: Identifiable {
        let id: String
        let title: String
        let completed: Double
        let required: Double
    }

    private var rows: [Row] {
        let majors = collegePersistence.resolvedMajorNames()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return majors.prefix(3).map { name in
            let p = collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: name)
            return Row(
                id: name,
                title: name,
                completed: p.completed,
                required: max(p.required, 1)
            )
        }
    }

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Planner progress (from your data)")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                ForEach(rows) { row in
                    let frac = min(1, max(0, row.completed / row.required))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.title)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textMain)
                            Spacer(minLength: 8)
                            Text("\(Int(row.completed.rounded())) / \(Int(row.required.rounded())) cr")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                        ProgressView(value: frac)
                            .tint(DesignSystem.Colors.primary)
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Rolling dialog summary (was AssistantRollingDialogSummary.swift)

/// Bounded on-device “long thread” recall injected into planner context (see `AssistantContextBudget` / assistant pipeline memory plan).
enum AssistantRollingDialogSummary {
    private static let storageKey = "assistant.dialog.rollingSummary.v1"
    private static let maxChars = 1_200

    static func summaryBlockForPrompt() -> String? {
        let s = UserDefaults.standard.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    /// Append a normalized exchange after a completed assistant turn.
    static func appendExchange(userPrompt: String, assistantReply: String) {
        let u = String(userPrompt.prefix(420)).replacingOccurrences(of: "\n", with: " ")
        let a = String(assistantReply.prefix(520)).replacingOccurrences(of: "\n", with: " ")
        guard !u.isEmpty, !a.isEmpty else { return }
        let line = "- Q: \(u)\n  A: \(a)\n"
        var cur = UserDefaults.standard.string(forKey: storageKey) ?? ""
        if cur.isEmpty {
            cur = "Rolling conversation highlights (local):\n" + line
        } else {
            cur += line
        }
        if cur.count > maxChars {
            cur = String(cur.suffix(maxChars))
        }
        UserDefaults.standard.set(cur, forKey: storageKey)
    }
}
