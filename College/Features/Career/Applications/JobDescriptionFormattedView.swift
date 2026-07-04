// JobDescriptionFormattedView.swift
// Feature: Career
// Purpose: Career module — JobDescriptionFormattedView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Renders scraped plain-text job descriptions with paragraph breaks, headings, and bullets.
struct JobDescriptionFormattedView: View {
    let text: String

    @State private var blocks: [JobDescriptionFormatter.Block] = []

    var body: some View {
        Group {
            if blocks.isEmpty {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyView()
                } else {
                    ProgressView().controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
            }
        }
        .task(id: text) {
            let parsed = await JobDescriptionFormatter.blocksOffMain(from: text)
            guard !Task.isCancelled else { return }
            blocks = parsed
        }
    }

    @ViewBuilder
    private func blockView(_ block: JobDescriptionFormatter.Block) -> some View {
        switch block {
        case .heading(let line):
            Text(JobDescriptionFormatter.attributedInline(line))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let line):
            Text(JobDescriptionFormatter.attributedInline(line))
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Text(JobDescriptionFormatter.attributedInline(item))
                            .font(.body)
                            .foregroundStyle(DesignSystem.Colors.textMain)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

enum JobDescriptionFormatter {
    enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph(String)
        case bullets([String])
    }

    static func blocksOffMain(from raw: String) async -> [Block] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            blocks(from: raw)
        }.value
    }

    static func blocks(from raw: String) -> [Block] {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [Block] = []
        var bulletBuffer: [String] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            if !joined.isEmpty { result.append(.paragraph(joined)) }
            paragraphBuffer.removeAll()
        }

        func flushBullets() {
            guard !bulletBuffer.isEmpty else { return }
            result.append(.bullets(bulletBuffer))
            bulletBuffer.removeAll()
        }

        for line in lines {
            if line.isEmpty {
                flushBullets()
                flushParagraph()
                continue
            }

            if let bullet = bulletItem(from: line) {
                flushParagraph()
                bulletBuffer.append(bullet)
                continue
            }

            flushBullets()

            if isHeading(line) {
                flushParagraph()
                result.append(.heading(line))
            } else {
                paragraphBuffer.append(line)
            }
        }

        flushBullets()
        flushParagraph()
        return result
    }

    private static func bulletItem(from line: String) -> String? {
        let patterns = [
            #"^[\u2022\u00b7•\-–—\*]\s+"#,
            #"^\d+[\.\)]\s+"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                let item = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return item.isEmpty ? nil : item
            }
        }
        return nil
    }

    private static func isHeading(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.count <= 80 else { return false }
        if stripped.hasSuffix(":") { return true }
        let letters = stripped.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let upper = letters.filter(\.isUppercase).count
        return Double(upper) / Double(letters.count) > 0.75
    }

    /// Inline Markdown (**bold**, _italic_, `code`) for consistent job-body typography.
    static func attributedInline(_ raw: String) -> AttributedString {
        AssistantMessageFormatting.attributedInline(raw)
    }
}
