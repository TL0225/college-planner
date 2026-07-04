// JobDescriptionHighlightedView.swift
// Feature: Career
// Purpose: JD keyword heatmap using AttributedString highlighting.

import SwiftUI

struct JobDescriptionHighlightedView: View {
    let text: String
    let matchingSkills: [String]
    let missingKeywords: [String]

    @State private var renderBlocks: [JobDescriptionHighlightRenderer.RenderBlock] = []

    var body: some View {
        Group {
            if renderBlocks.isEmpty {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyView()
                } else {
                    ProgressView().controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(renderBlocks) { item in
                        blockView(item)
                    }
                }
            }
        }
        .task(id: taskKey) {
            let skills = matchingSkills
            let missing = missingKeywords
            let source = text
            let parsed = await Task.detached(priority: .userInitiated) {
                JobDescriptionHighlightRenderer.prepareRenderBlocks(
                    text: source,
                    matchingSkills: skills,
                    missingKeywords: missing
                )
            }.value
            guard !Task.isCancelled else { return }
            renderBlocks = parsed
        }
    }

    private var taskKey: String {
        "\(text.hashValue)|\(matchingSkills.joined(separator: ","))|\(missingKeywords.joined(separator: ","))"
    }

    @ViewBuilder
    private func blockView(_ item: JobDescriptionHighlightRenderer.RenderBlock) -> some View {
        switch item.block {
        case .heading:
            Text(item.attributed)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            Text(item.attributed)
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets:
            Text(item.attributed)
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum JobDescriptionHighlightRenderer {
    struct RenderBlock: Identifiable, Sendable {
        let id: Int
        let block: JobDescriptionFormatter.Block
        let attributed: AttributedString
    }

    static func prepareRenderBlocks(
        text: String,
        matchingSkills: [String],
        missingKeywords: [String]
    ) -> [RenderBlock] {
        let blocks = JobDescriptionFormatter.blocks(from: text)
        return blocks.enumerated().map { index, block in
            RenderBlock(
                id: index,
                block: block,
                attributed: highlighted(block: block, matchingSkills: matchingSkills, missingKeywords: missingKeywords)
            )
        }
    }

    private static func highlighted(
        block: JobDescriptionFormatter.Block,
        matchingSkills: [String],
        missingKeywords: [String]
    ) -> AttributedString {
        switch block {
        case .heading(let line), .paragraph(let line):
            return highlighted(line, matchingSkills: matchingSkills, missingKeywords: missingKeywords)
        case .bullets(let items):
            var lines: [String] = []
            for item in items {
                lines.append("• \(item)")
            }
            return highlighted(lines.joined(separator: "\n"), matchingSkills: matchingSkills, missingKeywords: missingKeywords)
        }
    }

    private static func highlighted(
        _ source: String,
        matchingSkills: [String],
        missingKeywords: [String]
    ) -> AttributedString {
        var attributed = JobDescriptionFormatter.attributedInline(source)
        let matchSet = Set(matchingSkills.map { $0.lowercased() })
        let missSet = Set(missingKeywords.map { $0.lowercased() })
        let tokens = source.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        for token in tokens where token.count > 3 {
            let lower = token.lowercased()
            guard let range = attributed.range(of: token, options: .caseInsensitive) else { continue }
            if matchSet.contains(lower) {
                attributed[range].backgroundColor = .green.opacity(0.25)
            } else if missSet.contains(lower) {
                attributed[range].backgroundColor = .red.opacity(0.22)
            } else if partialMatch(lower, in: matchSet) {
                attributed[range].backgroundColor = .orange.opacity(0.22)
            }
        }
        return attributed
    }

    private static func partialMatch(_ token: String, in matches: Set<String>) -> Bool {
        matches.contains { match in
            match.contains(token) || token.contains(match)
        }
    }
}
