// AcademicCalendarLinkValidator.swift
// Feature: Calendar
// Purpose: Validate discovered calendar URLs before persisting.

import Foundation

enum AcademicCalendarLinkValidationFailure: String, Sendable, Equatable {
  case unreachable
  case notCalendarContent
  case insufficientEvents
  case audienceMismatch
  case unstableContent
}

enum AcademicCalendarLinkValidationResult: Sendable, Equatable {
  case passed(eventCount: Int, dateMentions: Int)
  case rejected(AcademicCalendarLinkValidationFailure, detail: String)

  var isPassed: Bool {
    if case .passed = self { return true }
    return false
  }
}

enum AcademicCalendarLinkValidator {
  static func validate(
    urlString: String,
    config: AcademicCalendarConfig,
    profile: AcademicCalendarProgramProfile?,
    fetcher: any AcademicCalendarFetching = LiveAcademicCalendarFetcher()
  ) async -> AcademicCalendarLinkValidationResult {
    do {
      let fetch = try await fetcher.fetch(urlString: urlString, etag: nil)
      guard fetch.statusCode == 200 || fetch.statusCode == 0,
            !fetch.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .rejected(.unreachable, detail: "HTTP \(fetch.statusCode)")
      }

      guard let baseURL = URL(string: urlString) else {
        return .rejected(.unreachable, detail: "Invalid URL")
      }

      let classification = AcademicCalendarPageClassifier.classify(
        content: fetch.content,
        baseURL: baseURL,
        forcedMode: config.forcedMode
      )

      switch classification.kind {
      case .hasICSFeed, .indexHub, .calendar:
        break
      }

      if let profile, audienceMismatch(content: fetch.content, profile: profile) {
        return .rejected(.audienceMismatch, detail: "Page audience does not match program level")
      }

      let dateMentions = estimateDateMentions(fetch.content)
      let parsed = AcademicCalendarDeterministicParser.parse(
        content: fetch.content,
        config: config,
        subCalendarURL: urlString
      )
      let scoped = AcademicCalendarEventParser.filterByImportedScopes(parsed, scopes: config.importedScopes)
      let threshold = dynamicEventThreshold(for: config.importedScopes.first)

      if scoped.count >= threshold {
        return .passed(eventCount: scoped.count, dateMentions: dateMentions)
      }

      if parsed.count >= threshold {
        return .passed(eventCount: parsed.count, dateMentions: dateMentions)
      }

      if dateMentions >= threshold * 2 {
        return .passed(eventCount: max(scoped.count, parsed.count), dateMentions: dateMentions)
      }

      if hasUpcomingTermBlock(in: parsed, config: config, threshold: threshold) {
        return .passed(eventCount: parsed.count, dateMentions: dateMentions)
      }

      return .rejected(
        .insufficientEvents,
        detail: "Found \(scoped.count) scoped events; need at least \(threshold)"
      )
    } catch {
      return .rejected(.unreachable, detail: error.localizedDescription)
    }
  }

  static func dynamicEventThreshold(for scope: AcademicCalendarImportedScope?) -> Int {
    guard let scope else { return 3 }
    let term = scope.term.lowercased()
    if term.contains("winter") || term.contains("summer") { return 2 }
    return 4
  }

  private static func audienceMismatch(content: String, profile: AcademicCalendarProgramProfile) -> Bool {
    guard let degreeLevel = profile.degreeLevel,
          !degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    let lower = content.lowercased()
    let undergradOnly = lower.contains("undergraduate only") || lower.contains("undergraduates only")
    let gradOnly = lower.contains("graduate students only") || lower.contains("graduate only")
    if DegreeConfiguration.isUndergraduate(degreeLevel) {
      return gradOnly && !undergradOnly
    }
    return undergradOnly && !gradOnly
  }

  private static func hasUpcomingTermBlock(
    in events: [AcademicCalendarParsedEvent],
    config: AcademicCalendarConfig,
    threshold: Int
  ) -> Bool {
    let horizon = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    let upcoming = events.filter { $0.startDate <= horizon }
    let grouped = Dictionary(grouping: upcoming, by: \.scopeKey)
    return grouped.values.contains { $0.count >= threshold }
  }

  private static func estimateDateMentions(_ content: String) -> Int {
    let pattern = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}(?:,?\s+\d{4})?"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
    return regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
  }
}
