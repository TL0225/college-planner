// SyllabusAnalysisViewModel.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — DraftSyllabusEvent.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import Combine
import os
import CryptoKit

@MainActor
final class SyllabusAnalysisViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case extracting
        case downloadingModel(progress: Double, detail: String)
        case analyzing
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var extractedPreview: String = ""
    @Published var syllabusData: SyllabusData = .init()

    @Published var draftEvents: [DraftSyllabusEvent] = []

    /// True while the background LLM pass is running after the heuristic result
    /// has already been shown.
    @Published var isRefiningSilently: Bool = false
    /// Set to true once the LLM successfully refines the heuristic result.
    @Published var wasRefinedByLLM: Bool = false

    struct DraftSyllabusEvent: Identifiable, Hashable {
        var id: UUID
        var title: String
        var kind: SyllabusEvent.Kind
        var startDate: Date
        var endDate: Date
        var allDay: Bool
        var notes: String?
        var location: String?
        var include: Bool

        init(id: UUID = UUID(), title: String, kind: SyllabusEvent.Kind, startDate: Date, endDate: Date, allDay: Bool, notes: String?, location: String? = nil, include: Bool = true) {
            self.id = id
            self.title = title
            self.kind = kind
            self.startDate = startDate
            self.endDate = endDate
            self.allDay = allDay
            self.notes = notes
            self.location = location
            self.include = include
        }
    }

    /// IDs of events whose times were set by `applySection`; used to target live location updates.
    private(set) var sectionAppliedIDs: Set<UUID> = []

    private let ingestService = SyllabusPDFIngestService()
    /// Stored so the previous LLM refinement Task can be cancelled if analyzeSyllabus() is called again.
    private var refinementTask: Task<Void, Never>?
#if DEBUG
    private let perfLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "Perf.Syllabus")
#endif

    func setFailed(_ message: String) {
        phase = .failed(message)
    }

    func analyzeSyllabus(
        pdfURL: URL,
        courseCode: String,
        courseName: String,
        semesterText: String?,
        calendar: Calendar,
        timeZone: TimeZone
    ) async {
        // Signal first use so the model pre-warm runs on subsequent cold launches.
        UserDefaults.standard.set(true, forKey: "syllabusAI.hasBeenUsed")
#if DEBUG
        let analyzeID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "SyllabusAnalyze", signpostID: analyzeID)
        defer { os_signpost(.end, log: perfLog, name: "SyllabusAnalyze", signpostID: analyzeID) }
#endif
        phase = .extracting

        let ingest: SyllabusIngestResult
        do {
#if DEBUG
            let extractID = OSSignpostID(log: perfLog)
            os_signpost(.begin, log: perfLog, name: "SyllabusExtract", signpostID: extractID)
            defer { os_signpost(.end, log: perfLog, name: "SyllabusExtract", signpostID: extractID) }
#endif
            ingest = try await Task.detached(priority: .userInitiated) {
                try SyllabusPDFIngestService().extractText(from: pdfURL)
            }.value
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        extractedPreview = String(ingest.cleanedText.prefix(2000))

        // --- Compute content hash for caching ---
        let contentHash: String = {
            let bytes = Array(ingest.cleanedText.utf8)
            let digest = SHA256.hash(data: Data(bytes))
            return digest.map { String(format: "%02x", $0) }.joined()
        }()

        // --- Cache hit: apply cached result and skip all model work ---
        if let cached = Self.cachedResult(for: contentHash) {
            applyDecoded(cached, calendar: calendar, timeZone: timeZone, sourceText: ingest.cleanedText, semesterText: semesterText)
            // Refresh per-course key so future quick-cache hits stay warm.
            Self.persistResult(cached, hash: contentHash, courseCode: courseCode)
            phase = .ready
            return
        }

        // --- Heuristic pass: give the user results immediately (<200 ms) ---
        let heuristicResult = SyllabusHeuristicExtractor.extract(from: ingest.cleanedText)
        applyDecoded(heuristicResult.syllabus, calendar: calendar, timeZone: timeZone, sourceText: ingest.cleanedText, semesterText: semesterText)
        phase = .ready

        // --- Background LLM refinement ---
        isRefiningSilently = true
        wasRefinedByLLM = false

        let prompt = SyllabusPromptBuilder.makePrompt(
            courseCode: courseCode,
            courseName: courseName,
            semesterText: semesterText,
            syllabusText: ingest.cleanedText
        )
        let spec = ModelSpec.jsonWorker
        LLMOnDemandPrewarm.prewarmJsonWorkerIfInstalled()
        let capturedCalendar = calendar
        let capturedTimeZone = timeZone
        let capturedSemesterText = semesterText
        let capturedSourceText = ingest.cleanedText

        // Cancel any in-flight refinement before starting a new one.
        refinementTask?.cancel()
        refinementTask = Task { [weak self] in
            guard let self else { return }

            // Download model if needed (shows downloadingModel phase on main actor).
            let modelPath: URL
            do {
                modelPath = try await ModelManager.shared.ensureModelInstalled(spec) { prog in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRefiningSilently else { return }
                        self.phase = .downloadingModel(
                            progress: prog.fractionCompleted,
                            detail: "Downloading \(spec.displayName) (\(prog.completedFiles)/\(prog.totalFiles))"
                        )
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isRefiningSilently = false
                }
                return
            }

            await MainActor.run { [weak self] in
                guard let self, self.isRefiningSilently else { return }
                self.phase = .analyzing
            }

            // Run LLM inference with 90-second timeout.
            do {
#if DEBUG
                let llmID = OSSignpostID(log: self.perfLog)
                os_signpost(.begin, log: self.perfLog, name: "SyllabusLLM", signpostID: llmID)
#endif
                let rawOutput = try await Self.runWithTimeout(seconds: 90) {
                    try await LocalLLMRunner.shared.generateJSON(prompt: prompt, modelPath: modelPath)
                }
#if DEBUG
                os_signpost(.end, log: self.perfLog, name: "SyllabusLLM", signpostID: llmID)
#endif
                let json = JSONSanitizer.extractJSONPayload(from: rawOutput) ?? rawOutput
                guard let data = json.data(using: .utf8) else {
                    await MainActor.run { [weak self] in
                        self?.isRefiningSilently = false
                        self?.phase = .ready
                    }
                    return
                }
                let decoded = try JSONDecoder().decode(SyllabusData.self, from: data)

                // Persist LLM result (best quality) to cache.
                Self.persistResult(decoded, hash: contentHash, courseCode: courseCode)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.applyDecoded(decoded, calendar: capturedCalendar, timeZone: capturedTimeZone, sourceText: capturedSourceText, semesterText: capturedSemesterText)
                    self.wasRefinedByLLM = true
                    self.isRefiningSilently = false
                    self.phase = .ready
                }
            } catch {
                // LLM failed — user already has the heuristic result; silently ignore.
                // Persist the heuristic result so future opens are instant.
                Self.persistResult(heuristicResult.syllabus, hash: contentHash, courseCode: courseCode)
                await MainActor.run { [weak self] in
                    self?.isRefiningSilently = false
                    self?.phase = .ready
                }
            }
        }
    }

    private func applyDecoded(_ decoded: SyllabusData, calendar: Calendar, timeZone: TimeZone, sourceText: String?, semesterText: String?) {
        let normalized = SyllabusPostProcessor.normalize(decoded, sourceText: sourceText, semesterText: semesterText)
        syllabusData = normalized
        let raw = normalized.events.compactMap { ev -> DraftSyllabusEvent? in
            do {
                guard let date = ev.date, !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let parsed = try SyllabusDateParser.parseEventDate(date: date, time: ev.time, calendar: calendar, timeZone: timeZone)
                return DraftSyllabusEvent(
                    id: ev.id,
                    title: ev.title,
                    kind: ev.kind,
                    startDate: parsed.start,
                    endDate: parsed.end,
                    allDay: parsed.allDay,
                    notes: ev.notes,
                    include: true
                )
            } catch {
                return nil
            }
        }
        draftEvents = Self.mergeSameDay(raw, calendar: calendar)
    }

    /// Applies a user-selected section's meeting time to all all-day week-schedule events.
    /// Events that already carry explicit times are left unchanged.
    func applySection(_ section: SyllabusSection, manualLocation: String? = nil) {
        guard let startStr = section.startTime, let endStr = section.endTime else { return }

        let parts = { (hhmm: String) -> (Int, Int)? in
            let comps = hhmm.split(separator: ":")
            guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
            return (h, m)
        }

        guard let (sh, sm) = parts(startStr), let (eh, em) = parts(endStr) else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.autoupdatingCurrent

        let effectiveDays: Set<SyllabusWeekday>? = section.meetingDays.map { Set($0) }

        for i in draftEvents.indices {
            guard draftEvents[i].allDay else { continue }

            // Only retime events whose day matches the section's meeting days (if known).
            if let days = effectiveDays, !days.isEmpty {
                let weekday = cal.component(.weekday, from: draftEvents[i].startDate)
                guard days.contains(where: { $0.calendarWeekday == weekday }) else { continue }
            }

            let baseDay = cal.startOfDay(for: draftEvents[i].startDate)
            guard let newStart = cal.date(bySettingHour: sh, minute: sm, second: 0, of: baseDay),
                  let newEnd   = cal.date(bySettingHour: eh, minute: em, second: 0, of: baseDay)
            else { continue }

            draftEvents[i].startDate = newStart
            draftEvents[i].endDate   = newEnd > newStart ? newEnd : cal.date(byAdding: .hour, value: 1, to: newStart) ?? newEnd
            draftEvents[i].allDay    = false
            sectionAppliedIDs.insert(draftEvents[i].id)
        }
    }

    /// Live-updates the location on every event that was timed by `applySection`.
    func updateSectionLocation(_ location: String?) {
        let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = loc.flatMap { $0.isEmpty ? nil : $0 }
        for i in draftEvents.indices where sectionAppliedIDs.contains(draftEvents[i].id) {
            draftEvents[i].location = effective
        }
    }

    /// Reverts all events whose time was applied via `applySection` back to all-day.
    /// Call this when the user deselects their section.
    func clearSectionTimes() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.autoupdatingCurrent

        for i in draftEvents.indices {
            guard sectionAppliedIDs.contains(draftEvents[i].id) else { continue }
            // Reset to midnight-span all-day and clear location.
            let baseDay = cal.startOfDay(for: draftEvents[i].startDate)
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: baseDay) else { continue }
            draftEvents[i].startDate = baseDay
            draftEvents[i].endDate   = endOfDay
            draftEvents[i].allDay    = true
            draftEvents[i].location  = nil
        }
        sectionAppliedIDs.removeAll()
    }

    /// Merges events that fall on the same calendar date into a single event.
    /// The highest-priority kind (exam > midterm > quiz > … > other) becomes the
    /// primary event. All notes are joined with " • " so no content is lost.
    private static func mergeSameDay(_ events: [DraftSyllabusEvent], calendar: Calendar) -> [DraftSyllabusEvent] {
        func kindWeight(_ k: SyllabusEvent.Kind) -> Int {
            switch k {
            case .final:        return 0
            case .midterm:      return 1
            case .exam:         return 2
            case .quiz:         return 3
            case .homework:     return 4
            case .assignment:   return 5
            case .project:      return 6
            case .lab:          return 7
            case .presentation: return 8
            case .reading:      return 9
            case .discussion:   return 10
            case .other:        return 11
            @unknown default:   return 12
            }
        }

        // Group by calendar day (local start-of-day).
        var byDay: [Date: [DraftSyllabusEvent]] = [:]
        for ev in events {
            let day = calendar.startOfDay(for: ev.startDate)
            byDay[day, default: []].append(ev)
        }

        let isWeekTitle: (String) -> Bool = {
            $0.range(of: #"^Week \d+$"#, options: .regularExpression) != nil
        }

        return byDay.keys.sorted().flatMap { day -> [DraftSyllabusEvent] in
            let group = byDay[day]!
            guard group.count > 1 else { return group }

            // Pick primary: best kind, then prefer "Week N" title for tie-breaking.
            let sortedGroup = group.sorted {
                let wa = kindWeight($0.kind), wb = kindWeight($1.kind)
                if wa != wb { return wa < wb }
                // Same kind: prefer "Week N" events as the container title.
                return isWeekTitle($0.title) && !isWeekTitle($1.title)
            }
            var primary = sortedGroup[0]

            // Collect note fragments in chronological order (preserving topic info).
            let fragments = group
                .sorted { $0.startDate < $1.startDate }
                .compactMap { ev -> String? in
                    if isWeekTitle(ev.title) {
                        // For "Week N" events the topic lives in notes.
                        return ev.notes
                    }
                    // For milestones, surface the title (plus notes if different).
                    if let n = ev.notes, !n.isEmpty, n != ev.title {
                        return "\(ev.title): \(n)"
                    }
                    return ev.title
                }
                .filter { !$0.isEmpty }

            // Remove duplicates while preserving order.
            var seen = Set<String>()
            let deduped = fragments.filter { seen.insert($0).inserted }
            primary.notes = deduped.isEmpty ? primary.notes : deduped.joined(separator: " • ")

            // If primary is all-day but another event has a specific time, adopt it.
            if primary.allDay, let timed = group.first(where: { !$0.allDay }) {
                primary.startDate = timed.startDate
                primary.endDate   = timed.endDate
                primary.allDay    = false
            }

            return [primary]
        }
    }

    // MARK: - Cache helpers

    /// Returns `~/Library/Application Support/<bundleID>/SyllabusCache/`, creating it if needed.
    private static func cacheDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
                            .appendingPathComponent("SyllabusCache", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir
    }

    private static func cachedResult(for hash: String) -> SyllabusData? {
        guard let dir = cacheDirectory() else { return nil }
        let file = dir.appendingPathComponent("\(hash).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SyllabusData.self, from: data)
    }

    private static func persistResult(_ data: SyllabusData, hash: String, courseCode: String? = nil) {
        guard let dir = cacheDirectory() else { return }
        let file = dir.appendingPathComponent("\(hash).json")
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: file, options: .atomic)
        // Also store hash per-course so reopening skips PDF re-extraction.
        if let courseCode {
            let key = courseHashKey(for: courseCode)
            UserDefaults.standard.set(hash, forKey: key)
        }
    }

    private static func courseHashKey(for courseCode: String) -> String {
        let safe = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }.joined()
        return "SyllabusLastHash_\(safe)"
    }

    /// Immediately restores results from the per-course cache if available.
    /// Returns `true` if successful — call site should skip full analysis.
    func tryApplyCachedForCourse(
        courseCode: String,
        semesterText: String?,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Bool {
        let key = Self.courseHashKey(for: courseCode)
        guard let hash = UserDefaults.standard.string(forKey: key),
              let cached = Self.cachedResult(for: hash) else { return false }
        applyDecoded(cached, calendar: calendar, timeZone: timeZone, sourceText: nil, semesterText: semesterText)
        phase = .ready
        return true
    }

    private nonisolated static func runWithTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw LocalLLMRunnerError.unavailable("Local model timed out while analyzing the syllabus.")
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}
