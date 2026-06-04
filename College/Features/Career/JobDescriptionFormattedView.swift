// JobDescriptionFormattedView.swift
// Feature: Career
// Purpose: Career module — JobDescriptionFormattedView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Renders scraped plain-text job descriptions with paragraph breaks, headings, and bullets.
struct JobDescriptionFormattedView: View {
    let text: String

    var body: some View {
        let blocks = JobDescriptionFormatter.blocks(from: text)
        if blocks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: JobDescriptionFormatter.Block) -> some View {
        switch block {
        case .heading(let line):
            Text(line)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let line):
            Text(line)
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
                        Text(item)
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
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case bullets([String])
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
        guard line.count <= 80 else { return false }
        if line.hasSuffix(":") { return true }
        let letters = line.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let upper = letters.filter(\.isUppercase).count
        return Double(upper) / Double(letters.count) > 0.75
    }
}
