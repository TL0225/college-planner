// DocumentClassifierService.swift
// Feature: Core
// Purpose: Core module — ClassificationResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import PDFKit

// MARK: - DocumentType

/// The semantic category of an academic document.
enum DocumentType: String, CaseIterable {
    case syllabus   = "syllabus"
    case notes      = "notes"
    case assignment = "assignment"
    case exam       = "exam"
    case project    = "project"
    case lab        = "lab"
    case reading    = "reading"
    case other      = "other"

    /// Human-readable label suitable for UI display.
    var displayName: String {
        switch self {
        case .syllabus:   return "Syllabus"
        case .notes:      return "Notes"
        case .assignment: return "Assignment"
        case .exam:       return "Exam / Quiz"
        case .project:    return "Project"
        case .lab:        return "Lab"
        case .reading:    return "Reading"
        case .other:      return "Document"
        }
    }
}

// MARK: - DocumentClassifierService

/// Classifies academic documents by filename patterns, keyword heuristics,
/// and (when available) local LLM inference via `LocalLLMRunner`.
actor DocumentClassifierService {

    // MARK: - Singleton

    static let shared = DocumentClassifierService()

    // MARK: - Public Types

    public struct ClassificationResult {
        /// Detected course code, e.g. `"CSE191"`.
        let courseCode: String?
        /// Semantic document category.
        let documentType: DocumentType
        /// Cleaned-up, human-friendly suggested filename (no extension).
        let suggestedName: String
        /// Academic week number if detectable, otherwise `nil`.
        let weekNumber: Int?
        /// Confidence score in the range 0 – 1.
        let confidence: Float
    }

    // MARK: - Private Constants

    /// Recognized department prefixes for course-code detection.
    private static let coursePrefixes = [
        "CSE", "MTH", "PHY", "BIO", "ENG", "CHE", "MAT", "CSC",
        "MUS", "ART", "PSY", "SOC", "ECO", "HIS", "POL", "ANT",
        "GEO", "STA", "MBA", "LAW", "NUR", "CIS", "MIS"
    ]

    private static let courseCodePattern: NSRegularExpression = {
        let prefixes = coursePrefixes.joined(separator: "|")
        return try! NSRegularExpression(pattern: "\\b(\(prefixes))\\s*(\\d{3,4}[A-Z]?)\\b", options: [.caseInsensitive])
    }()

    private static let weekPattern: NSRegularExpression =
        try! NSRegularExpression(pattern: "\\bweek\\s*(\\d{1,2})\\b", options: [.caseInsensitive])

    private static let llmTimeoutSeconds: UInt64 = 3_000_000_000 // 3 s in nanoseconds

    // MARK: - Init

    private init() {}

    // MARK: - Public Classification

    /// Classify `fileURL` using a three-tier strategy:
    /// 1. Fast regex match on the filename.
    /// 2. Keyword heuristics on the filename.
    /// 3. LLM inference on the first 500 chars of PDF text (with 3-second timeout).
    /// Falls back to the regex result if the LLM fails or times out.
    func classify(fileURL: URL) async -> ClassificationResult {
        let filename = fileURL.deletingPathExtension().lastPathComponent

        // --- Tier 1 & 2: Fast path from filename ---
        let fastResult = classifyFromFilename(filename)

        // --- Tier 3: LLM path (PDF only) ---
        guard fileURL.pathExtension.lowercased() == "pdf",
              let pdfText = extractPDFText(from: fileURL, maxChars: 500),
              !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fastResult
        }

        guard let llmResult = await classifyWithLLM(pdfText: pdfText, filename: filename) else {
            return fastResult
        }

        // Merge LLM result, preferring regex course code when LLM returns nil.
        return ClassificationResult(
            courseCode:   llmResult.courseCode ?? fastResult.courseCode,
            documentType: llmResult.documentType,
            suggestedName: llmResult.suggestedName,
            weekNumber:   llmResult.weekNumber ?? fastResult.weekNumber,
            confidence:   0.9
        )
    }

    // MARK: - Week Number Extraction

    /// Extract the first week number found in `text`, e.g. "Week 3" → 3.
    func extractWeekNumber(from text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.weekPattern.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let numRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[numRange])
    }

    // MARK: - Private: Filename Classification

    private func classifyFromFilename(_ filename: String) -> ClassificationResult {
        let lower = filename.lowercased()

        // --- Course code detection ---
        let courseCode = extractCourseCode(from: filename)

        // --- Document type via keywords ---
        let docType = detectDocumentType(from: lower)

        // --- Week number ---
        let weekNumber = extractWeekNumber(from: lower)

        // --- Suggested name: title-case the filename, replacing separators ---
        let suggestedName = suggestName(from: filename, courseCode: courseCode, docType: docType)

        let confidence: Float = courseCode != nil ? 0.6 : 0.3

        return ClassificationResult(
            courseCode:   courseCode,
            documentType: docType,
            suggestedName: suggestedName,
            weekNumber:   weekNumber,
            confidence:   confidence
        )
    }

    // MARK: - Private: Helpers

    /// Extract the first recognized course code from `text` (case-insensitive).
    private func extractCourseCode(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.courseCodePattern.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let prefixRange = Range(match.range(at: 1), in: text),
              let numRange    = Range(match.range(at: 2), in: text)
        else { return nil }
        return (text[prefixRange] + text[numRange]).uppercased()
    }

    /// Detect document type from lowercased filename text via keyword matching.
    private func detectDocumentType(from lower: String) -> DocumentType {
        if lower.contains("syllabus")                                   { return .syllabus   }
        if lower.contains("hw")    || lower.contains("homework")
            || lower.contains("assignment") || lower.contains("pset")  { return .assignment }
        if lower.contains("exam")  || lower.contains("midterm")
            || lower.contains("final") || lower.contains("quiz")       { return .exam       }
        if lower.contains("notes") || lower.contains("lecture")
            || lower.contains("lec")                                    { return .notes      }
        if lower.contains("lab")                                        { return .lab        }
        if lower.contains("project") || lower.contains("proj")         { return .project    }
        if lower.contains("reading") || lower.contains("chapter")
            || lower.contains("chap")                                   { return .reading    }
        return .other
    }

    /// Build a clean human-readable suggested name from the raw filename.
    private func suggestName(from filename: String, courseCode: String?, docType: DocumentType) -> String {
        // Replace underscores and dashes with spaces, then title-case.
        var clean = filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)

        // Collapse multiple spaces.
        while clean.contains("  ") {
            clean = clean.replacingOccurrences(of: "  ", with: " ")
        }

        // Title-case each word.
        clean = clean.split(separator: " ")
            .map { word -> String in
                let w = String(word)
                // Preserve all-uppercase abbreviations/course codes.
                if w == w.uppercased() && w.count <= 8 { return w }
                return w.prefix(1).uppercased() + w.dropFirst().lowercased()
            }
            .joined(separator: " ")

        return clean.isEmpty ? docType.displayName : clean
    }

    // MARK: - Private: PDF Text Extraction

    private func extractPDFText(from url: URL, maxChars: Int) -> String? {
        guard let doc = PDFDocument(url: url),
              let text = doc.string,
              !text.isEmpty
        else { return nil }
        return String(text.prefix(maxChars))
    }

    // MARK: - Private: LLM Classification

    /// Internal struct for LLM parse results.
    private struct LLMResult {
        let courseCode:   String?
        let documentType: DocumentType
        let suggestedName: String
        let weekNumber:   Int?
    }

    /// Ask the LLM to classify the document, enforcing a 3-second timeout.
    /// Returns `nil` if the LLM is unavailable, fails, or times out.
    private func classifyWithLLM(pdfText: String, filename: String) async -> LLMResult? {
        let prompt = """
        Classify this academic document. Return JSON only, no explanation:
        {"courseCode":"<code or null>","type":"<syllabus|notes|assignment|exam|project|lab|reading|other>","suggestedName":"<clean name without extension>","weekNumber":<number or null>}
        Document text: \(pdfText)
        """

        // Race the LLM call against a 3-second timeout using a task group.
        return await withTaskGroup(of: LLMResult?.self) { group in
            // LLM task
            group.addTask {
                do {
                    guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker) else {
                        return nil
                    }
                    let response = try await LocalLLMRunner.shared.generateJSON(
                        prompt: "/no_think\n" + prompt,
                        modelPath: modelPath,
                        maxTokens: 200
                    )
                    return self.parseLLMResponse(response)
                } catch {
                    print("[DocumentClassifierService] LLM error: \(error)")
                    return nil
                }
            }

            // Timeout sentinel task
            group.addTask {
                try? await Task.sleep(nanoseconds: FSWatchdogService_LLMTimeout.nanoseconds)
                return nil
            }

            // Return whichever finishes first, cancel the other.
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    /// Parse the JSON string returned by the LLM into an `LLMResult`.
    nonisolated private func parseLLMResponse(_ response: String) -> LLMResult? {
        // Extract the first JSON object from the response string.
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd   = response.lastIndex(of: "}")
        else { return nil }

        let jsonSubstring = response[jsonStart...jsonEnd]
        guard let data = jsonSubstring.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let courseCode    = obj["courseCode"]    as? String
        let typeRaw       = obj["type"]          as? String ?? "other"
        let suggestedName = obj["suggestedName"] as? String ?? ""
        let weekNumber    = obj["weekNumber"]    as? Int

        let docType = DocumentType(rawValue: typeRaw) ?? .other

        guard !suggestedName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        return LLMResult(
            courseCode:   (courseCode == "null" || courseCode?.isEmpty == true) ? nil : courseCode,
            documentType: docType,
            suggestedName: suggestedName,
            weekNumber:   weekNumber
        )
    }
}

// MARK: - Timeout Constant Namespace

/// Shared constant so FSWatchdogService.swift doesn't need to redeclare it.
private enum FSWatchdogService_LLMTimeout {
    static let nanoseconds: UInt64 = 3_000_000_000
}
