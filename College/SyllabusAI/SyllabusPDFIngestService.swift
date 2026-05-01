import Foundation
import PDFKit

enum SyllabusPDFIngestError: LocalizedError {
    case fileNotFound
    case failedToOpenPDF
    case extractedEmptyText

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Syllabus PDF could not be found."
        case .failedToOpenPDF:
            return "Could not open the syllabus PDF."
        case .extractedEmptyText:
            return "Could not extract any text from this PDF. Make sure it's a native (non-scanned) PDF."
        }
    }
}

struct SyllabusIngestResult: Sendable {
    let rawText: String
    let cleanedText: String
    let pageCount: Int
    let removedLineCount: Int
}

struct SyllabusPDFIngestService {
    func extractText(from pdfURL: URL) throws -> SyllabusIngestResult {
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw SyllabusPDFIngestError.fileNotFound
        }

        guard let doc = PDFDocument(url: pdfURL) else {
            throw SyllabusPDFIngestError.failedToOpenPDF
        }

        let pageCount = doc.pageCount
        var perPageLines: [[String]] = []
        perPageLines.reserveCapacity(pageCount)

        var rawParts: [String] = []
        rawParts.reserveCapacity(pageCount)

        for idx in 0..<pageCount {
            guard let page = doc.page(at: idx) else {
                perPageLines.append([])
                continue
            }

            let text = (page.string ?? "")
            rawParts.append(text)

            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            perPageLines.append(lines)
        }

        let rawText = rawParts
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if rawText.isEmpty {
            throw SyllabusPDFIngestError.extractedEmptyText
        }

        let (cleanedLinesPerPage, removedCount) = SyllabusTextCleaner.stripRepeatedHeadersAndFooters(perPageLines)
        let cleanedText = cleanedLinesPerPage
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SyllabusIngestResult(
            rawText: rawText,
            cleanedText: cleanedText.isEmpty ? rawText : cleanedText,
            pageCount: pageCount,
            removedLineCount: removedCount
        )
    }
}

// MARK: - Header/footer stripping

enum SyllabusTextCleaner {
    private static let pageNumberRegex = try? NSRegularExpression(pattern: #"\bpage\s*\d+\s*(of\s*\d+)?\b"#, options: [])
    private static let fractionRegex = try? NSRegularExpression(pattern: #"\b\d+\s*/\s*\d+\b"#, options: [])
    private static let digitsRegex = try? NSRegularExpression(pattern: #"\b\d+\b"#, options: [])
    private static let whitespaceRegex = try? NSRegularExpression(pattern: #"\s+"#, options: [])

    static func stripRepeatedHeadersAndFooters(_ perPageLines: [[String]]) -> ([[String]], Int) {
        let pageCount = perPageLines.count
        guard pageCount >= 2 else { return (perPageLines, 0) }

        // Candidate lines: first/last 2 lines per page.
        var headerCounts: [String: Int] = [:]
        var footerCounts: [String: Int] = [:]

        func normalize(_ line: String) -> String {
            var s = line.lowercased()
            // Remove common page numbering patterns.
            s = replaceAll(pageNumberRegex, in: s, with: "")
            s = replaceAll(fractionRegex, in: s, with: "")
            s = replaceAll(digitsRegex, in: s, with: "")
            s = replaceAll(whitespaceRegex, in: s, with: " ")
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func replaceAll(_ regex: NSRegularExpression?, in s: String, with replacement: String) -> String {
            guard let regex else { return s }
            let range = NSRange(s.startIndex..., in: s)
            return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: replacement)
        }

        for lines in perPageLines {
            guard !lines.isEmpty else { continue }
            for line in lines.prefix(2) {
                let key = normalize(line)
                if key.count >= 4 { headerCounts[key, default: 0] += 1 }
            }
            for line in lines.suffix(2) {
                let key = normalize(line)
                if key.count >= 4 { footerCounts[key, default: 0] += 1 }
            }
        }

        let threshold = max(2, Int(Double(pageCount) * 0.6))
        let repeatedHeaders = Set(headerCounts.filter { $0.value >= threshold }.map(
            \.key
        ))
        let repeatedFooters = Set(footerCounts.filter { $0.value >= threshold }.map(
            \.key
        ))

        if repeatedHeaders.isEmpty && repeatedFooters.isEmpty {
            return (perPageLines, 0)
        }

        var removed = 0
        let cleaned: [[String]] = perPageLines.map { lines in
            guard !lines.isEmpty else { return lines }
            var out: [String] = []
            out.reserveCapacity(lines.count)

            for line in lines {
                let key = normalize(line)
                if repeatedHeaders.contains(key) || repeatedFooters.contains(key) {
                    removed += 1
                    continue
                }
                out.append(line)
            }

            return out
        }

        return (cleaned, removed)
    }
}
