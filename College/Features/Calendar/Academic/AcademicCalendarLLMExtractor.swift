// AcademicCalendarLLMExtractor.swift
// Feature: Calendar
// Purpose: LLM-assisted extraction of academic calendar events to JSON.

import Foundation

enum AcademicCalendarLLMExtractor {
    static var isAvailable: Bool {
        CareerFoundationModelsJSONService.isAvailable() || AppleSiliconPlatform.isMLXCompatible
    }

    static func extract(
        content: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) async -> [AcademicCalendarParsedEvent] {
        let chunks = chunkText(content, maxCharacters: 12_000)
        var all: [AcademicCalendarParsedEvent] = []
        for chunk in chunks {
            let prompt = buildPrompt(chunk: chunk, config: config)
            guard let raw = await generateJSON(prompt: prompt) else { continue }
            let sanitized = JSONSanitizer.extractJSONPayload(from: raw) ?? raw
            let parsed = AcademicCalendarEventParser.parseJSONArray(sanitized, config: config, subCalendarURL: subCalendarURL)
            all.append(contentsOf: parsed)
        }
        let filtered = AcademicCalendarEventParser.filterByImportedScopes(all, scopes: config.importedScopes)
        return AcademicCalendarEventParser.mergeNearDuplicates(filtered)
    }

    private static func buildPrompt(chunk: String, config: AcademicCalendarConfig) -> String {
        """
Return ONLY a JSON array of academic calendar events from the page excerpt.
Each item: {"title":"","startDate":"YYYY-MM-DD","endDate":"YYYY-MM-DD","allDay":true,"status":"confirmed|tentative|cancelled","term":"Fall|Spring|Summer|Winter|unknown","year":2025,"level":"undergrad|grad|all","confidence":0.0}
Rules:
- Use one-line titles without embedded dates.
- Infer missing years from nearest term header.
- Ranges become startDate/endDate spanning days.
- Split multiple events in one row.
- Ignore finals time grids and navigation text.
- Bound to current and next academic year only.
- School timezone: \(config.timeZoneID)
- Audience level preference: \(config.levelScope.rawValue)

Page excerpt:
\(chunk)
"""
    }

    private static func generateJSON(prompt: String) async -> String? {
        if let fm = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt) {
            return fm
        }
        guard AppleSiliconPlatform.isMLXCompatible else { return nil }
        let spec = ModelSpec.jsonWorker
        guard let modelPath = try? await ModelManager.shared.ensureModelInstalled(spec, progress: { _ in }) else {
            return nil
        }
        return try? await LocalLLMRunner.shared.generateJSON(prompt: prompt, modelPath: modelPath, maxTokens: 1400)
    }

    private static func chunkText(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }
}
