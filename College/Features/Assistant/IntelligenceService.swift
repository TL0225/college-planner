// IntelligenceService.swift
// Feature: Assistant
// Purpose: Assistant module — ParsingStats.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os

/// Intelligence Service: Hybrid prerequisite parsing (Regex + LLM)
/// Strategy: Parse 80% with fast regex, use LLM only for complex cases
final class IntelligenceService {

    // MARK: - In-memory LLM dedup cache

    /// Lightweight process-local cache to avoid duplicate LLM inference for identical
    /// prerequisite prompts within a session.
    private static let prereqCacheMaxEntries = 256
    nonisolated(unsafe) private static var prereqRuleCache: [String: PrerequisiteRule] = [:]
    nonisolated(unsafe) private static var prereqCacheInsertionOrder: [String] = []
    nonisolated(unsafe) private static var prereqCacheLock = OSAllocatedUnfairLock()

    // MARK: - Precompiled regexes (performance)

    private static let singleCourseRegex: NSRegularExpression? = {
        // Match "DEPT 1234" or "DEPT1234" (case-insensitive).
        // 2-6 uppercase letters covers short codes (CS, EE) through long ones (ENGPHIL, THEARTS).
        // Captures: (1) dept letters, (2) number + optional letter suffix
        return try? NSRegularExpression(
            pattern: #"\b([A-Z]{2,6})\s*(\d{3,4}[A-Z]?)\b"#,
            options: [.caseInsensitive]
        )
    }()

    private static let minGradeRegex: NSRegularExpression? = {
        // Examples: "grade of B", "B or better", "minimum grade: C+"
        return try? NSRegularExpression(
            pattern: #"(?:grade of|grade:|minimum grade:?|with a)\s*([A-D][+-]?|[ABCDF])"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches ", and X" trailing conjunctions — compiled once, not per call.
    private static let commaAndRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: ",\\s+and\\s+", options: [.caseInsensitive])

    /// Matches bare " and " conjunctions (not preceded by comma) — compiled once.
    private static let bareAndRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "\\s+and\\s+", options: [.caseInsensitive])

    /// Precompiled regex for collapsing whitespace sequences to a single space.
    private static let whitespaceCollapseRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s+"#, options: [])
    }()
    
    // MARK: - LLM Model
    // Uses the same local MLXLLM pipeline as SyllabusAI (ModelManager + LocalLLMRunner).
    
    // MARK: - Statistics
    struct ParsingStats {
        var totalParsed: Int = 0
        var regexParsed: Int = 0
        var llmParsed: Int = 0
        var failed: Int = 0
        var needsManualReview: Int = 0
    }
    
    private(set) var stats = ParsingStats()
    
    // MARK: - Main Entry Point
    
    /// Parse prerequisite text using hybrid strategy
    /// - Returns: (rule, needsLLM) - If needsLLM is true, mark for background processing
    func parsePrerequisite(
        _ text: String,
        courseCode: String
    ) -> (rule: PrerequisiteRule?, needsLLM: Bool, confidence: ParsingConfidence) {
        
        guard !text.isEmpty else {
            return (nil, false, .none)
        }
        
        // Step 1: Try regex parsing (Fast Lane - 80% of cases)
        if let simpleRule = tryRegexParsing(text) {
            stats.regexParsed += 1
            stats.totalParsed += 1
            return (simpleRule, false, .high)
        }
        
        // Step 2: Mark as needs LLM processing (Slow Lane - 20% of cases)
        stats.totalParsed += 1
        return (nil, true, .needsLLM)
    }
    
    /// Background processing for complex prerequisites
    static func parseComplexPrerequisites(
        _ batch: [(text: String, courseCode: String, courseURI: URL)],
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [URL: PrerequisiteRule] {
        guard AppleSiliconPlatform.isSupported else { return [:] }

        let spec = ModelSpec.jsonWorker

        // Ensure model is installed, downloading it if necessary.
        let modelDirectory: URL
        do {
            modelDirectory = try await ModelManager.shared.ensureModelInstalled(spec) { prog in
                // Progress is already reported via ModelBootstrapService; no extra UI needed here.
            }
        } catch {
            // Download failed — leave these for manual review.
            return [:]
        }

        var results: [URL: PrerequisiteRule] = [:]
        results.reserveCapacity(batch.count)

        for (index, item) in batch.enumerated() {
            let cacheKey = makePrereqCacheKey(text: item.text, courseCode: item.courseCode)

            if let cachedRule = cachedPrerequisiteRule(forKey: cacheKey) {
                results[item.courseURI] = cachedRule
                progressCallback?(index + 1, batch.count)
                continue
            }

            do {
                if let rule = try await Self.parseSingleWithLLM(item.text, courseCode: item.courseCode, modelPath: modelDirectory) {
                    results[item.courseURI] = rule
                    cachePrerequisiteRule(rule, forKey: cacheKey)
                }
            } catch {
                // Best-effort; leave as pending/manual review.
            }

            progressCallback?(index + 1, batch.count)
        }

        return results
    }

    private static func makePrereqCacheKey(text: String, courseCode: String) -> String {
        let normalizedCourseCode = courseCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wsRange = NSRange(trimmed.startIndex..., in: trimmed)
        let collapsed = IntelligenceService.whitespaceCollapseRegex
            .stringByReplacingMatches(in: trimmed, range: wsRange, withTemplate: " ")
        let normalizedText = collapsed.lowercased()
        return "\(normalizedCourseCode)|\(normalizedText)"
    }

    private static func cachedPrerequisiteRule(forKey key: String) -> PrerequisiteRule? {
        prereqCacheLock.withLock {
            prereqRuleCache[key]
        }
    }

    private static func cachePrerequisiteRule(_ rule: PrerequisiteRule, forKey key: String) {
        prereqCacheLock.withLock {
            if prereqRuleCache[key] == nil {
                prereqCacheInsertionOrder.append(key)
            }
            prereqRuleCache[key] = rule

            while prereqRuleCache.count > prereqCacheMaxEntries,
                  let oldestKey = prereqCacheInsertionOrder.first {
                prereqCacheInsertionOrder.removeFirst()
                prereqRuleCache.removeValue(forKey: oldestKey)
            }
        }
    }
    
    // MARK: - Step 1: Regex Parsing (Fast Lane)
    
    private func tryRegexParsing(_ text: String) -> PrerequisiteRule? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Pattern 1: Single course (e.g. "MATH 1920", "Prerequisite: CS 1110")
        if let single = parseSingleCourse(lower) {
            return single
        }

        let hasAnd   = lower.contains(" and ")
        let hasOr    = lower.contains(" or ")
        let hasParen = lower.contains("(")
        let hasComma = lower.contains(",")

        // Mixed AND+OR without parentheses is ambiguous — send to LLM.
        if hasAnd && hasOr {
            return nil
        }

        // Pattern 2: Simple AND "CS 1110 and MATH 1920"
        if hasAnd && !hasParen {
            return parseSimpleAND(lower)
        }

        // Pattern 3: Comma list without "or" → AND ("CS 1110, MATH 1920")
        if hasComma && !hasOr && !hasAnd && !hasParen {
            return parseCommaAND(lower)
        }

        // Pattern 4: Simple OR "CS 1110 or CS 1112"
        // Both sides must resolve to course codes to avoid false-positives
        // (e.g. "Introduction to OR and Operations Research").
        if hasOr && !hasAnd && !hasParen {
            return parseSimpleOR(lower)
        }

        // Complex (parentheses, mixed logic, etc.) → fall to LLM.
        return nil
    }
    
    private func parseSingleCourse(_ text: String) -> PrerequisiteRule? {
        guard let regex = Self.singleCourseRegex else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        // If exactly one course code found, it's a simple prerequisite
        guard matches.count == 1,
              let match = matches.first,
              let deptRange = Range(match.range(at: 1), in: text),
              let numRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        
        let dept = String(text[deptRange]).uppercased()
        let number = String(text[numRange]).uppercased()
        let courseCode = "\(dept) \(number)"
        
        // Check for grade requirement
        let minGrade = extractMinGrade(from: text)
        
        return .course(CourseRequirement(courseCode: courseCode, minGrade: minGrade))
    }
    
    private func parseSimpleAND(_ text: String) -> PrerequisiteRule? {
        let parts = text.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2 else { return nil }

        var rules: [PrerequisiteRule] = []
        for part in parts {
            guard !part.isEmpty, let rule = parseSingleCourse(part) else {
                return nil // Complex token — needs LLM.
            }
            rules.append(rule)
        }
        guard rules.count >= 2 else { return nil }
        return .and(rules)
    }

    /// Parse a comma-separated list as an AND group: "CS 1110, MATH 1920, PHY 100".
    private func parseCommaAND(_ text: String) -> PrerequisiteRule? {
        // Collapse a trailing ", and X" / " and X" into a standard comma entry.
        // Uses statically compiled regexes (no per-call compilation overhead).
        var normalized = text
        if let re = Self.commaAndRegex {
            normalized = re.stringByReplacingMatches(
                in: normalized, range: NSRange(normalized.startIndex..., in: normalized), withTemplate: ", "
            )
        }
        if let re = Self.bareAndRegex {
            normalized = re.stringByReplacingMatches(
                in: normalized, range: NSRange(normalized.startIndex..., in: normalized), withTemplate: ", "
            )
        }
        let parts = normalized.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2 else { return nil }

        var rules: [PrerequisiteRule] = []
        for part in parts {
            guard !part.isEmpty, let rule = parseSingleCourse(part) else {
                return nil
            }
            rules.append(rule)
        }
        guard rules.count >= 2 else { return nil }
        return .and(rules)
    }
    
    private func parseSimpleOR(_ text: String) -> PrerequisiteRule? {
        let parts = text.components(separatedBy: " or ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2 else { return nil }

        var rules: [PrerequisiteRule] = []
        for part in parts {
            guard !part.isEmpty, let rule = parseSingleCourse(part) else {
                // A part that doesn't resolve to a course code means this is either
                // a non-course OR (false-positive from "Operations Research") or a
                // complex qualifier ("or equivalent"). Route to LLM.
                return nil
            }
            rules.append(rule)
        }
        // Require at least 2 actual course codes; a single match means "or" appeared
        // as prose rather than as a logic operator.
        guard rules.count >= 2 else { return nil }
        return .or(rules)
    }
    
    private func extractMinGrade(from text: String) -> String? {
                guard let regex = Self.minGradeRegex,
                            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let gradeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        return String(text[gradeRange]).uppercased()
    }
    
    // MARK: - Step 2: LLM Parsing (Slow Lane)
    
    private static func parseSingleWithLLM(_ text: String, courseCode: String, modelPath: URL) async throws -> PrerequisiteRule? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Dynamic token budget: scales with input length so simple inputs stay fast
        // and complex multi-clause strings get enough output room for the full tree.
        let maxTokens = PrerequisitePromptBuilder.recommendedMaxTokens(for: trimmed)

        // For Qwen 3 models: prepend /think for complex expressions so the model
        // reasons step-by-step before emitting JSON; use /no_think for simpler
        // cases to keep inference fast.
        let modeDirective = PrerequisitePromptBuilder.requiresThinkingMode(trimmed) ? "/think\n" : "/no_think\n"
        let basePrompt = PrerequisitePromptBuilder.makePrompt(text: trimmed, courseCode: courseCode)
        let prompt = modeDirective + basePrompt

        // Enforce a per-course inference timeout so a stalled model never blocks the batch.
        let raw: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await LocalLLMRunner.shared.generateJSON(
                    prompt: prompt,
                    modelPath: modelPath,
                    maxTokens: maxTokens
                )
            }
            group.addTask {
                // 30-second hard deadline per course.
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw IntelligenceError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        let jsonString = extractJSON(from: raw)

        // If the model returned truncated JSON (starts with `{` but missing the closing `}`),
        // retry once with a continuation prompt rather than silently discarding the result.
        let finalJSON: String
        if jsonString.hasPrefix("{") && !jsonString.hasSuffix("}") {
            let continuationPrompt = "/no_think\nComplete this JSON object by adding the missing closing braces. Output ONLY the completed JSON, nothing else.\nIncomplete JSON: \(jsonString)"
            let retryRaw: String? = try? await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await LocalLLMRunner.shared.generateJSON(
                        prompt: continuationPrompt,
                        modelPath: modelPath,
                        maxTokens: 256
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw IntelligenceError.timeout
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let retryJSON = retryRaw.map { extractJSON(from: $0) } ?? ""
            finalJSON = (retryJSON.hasPrefix("{") && retryJSON.hasSuffix("}")) ? retryJSON : jsonString
        } else {
            finalJSON = jsonString
        }

        guard !finalJSON.isEmpty,
              finalJSON == "null" || (finalJSON.hasPrefix("{") && finalJSON.hasSuffix("}")) else {
            throw IntelligenceError.invalidResponse
        }

        guard let jsonData = finalJSON.data(using: .utf8) else {
            throw IntelligenceError.invalidResponse
        }

        let rule = try JSONDecoder().decode(PrerequisiteRule?.self, from: jsonData)

        // Safety net: never emit empty AND/OR nodes.
        // .and([]) always passes validation; .or([]) always blocks — both are semantically wrong.
        if let r = rule, isEmptyRule(r) { return nil }
        return rule
    }

    /// Returns true when a rule has no leaf course codes (empty AND or OR node).
    private static func isEmptyRule(_ rule: PrerequisiteRule) -> Bool {
        switch rule {
        case .and(let rules): return rules.isEmpty
        case .or(let rules):  return rules.isEmpty
        case .course:         return false
        }
    }
    
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "null" { return "null" }

        // Find JSON object block (between first { and last }).
        if let startIndex = trimmed.firstIndex(of: "{"),
           let endIndex = trimmed.lastIndex(of: "}") {
            return String(trimmed[startIndex...endIndex])
        }

        // If the model returned something unexpected, still try to salvage a `null`.
        if trimmed.lowercased().contains("null") { return "null" }
        return trimmed
    }
    
    // MARK: - Confidence Levels
    
    enum ParsingConfidence {
        case none           // No prerequisite
        case high           // Regex parsed successfully
        case medium         // LLM parsed successfully
        case low            // LLM parsed but uncertain
        case needsLLM       // Queued for LLM processing
        case failed         // Parsing failed
        case needsManualReview  // Invalid course codes detected
    }
}

// MARK: - Errors

enum IntelligenceError: LocalizedError {
    case modelNotLoaded
    case invalidResponse
    case parsingFailed
    /// Inference exceeded the per-course deadline (30 s).
    case timeout

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "LLM model not loaded"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .parsingFailed:
            return "Failed to parse prerequisite"
        case .timeout:
            return "Prerequisite parsing timed out"
        }
    }
}
