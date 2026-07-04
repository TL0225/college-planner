// AcademicCalendarHubNavigator.swift
// Feature: Calendar
// Purpose: Multi-hop hub navigation with cycle detection and depth limits.

import Foundation

enum AcademicCalendarHubNavigationOutcome: Sendable, Equatable {
  case resolved(url: String, hops: Int, classification: AcademicCalendarPageKind)
  case needsUserChoice(candidates: [AcademicCalendarSubCalendarCandidate], hops: Int)
  case timedOut(lastURL: String, hops: Int)
  case failed(reason: String, hops: Int)
}

actor AcademicCalendarHubNavigator {
  private var visitedURLs: Set<String> = []
  private let maxDepth = 3
  private let fetcher: any AcademicCalendarFetching

  init(fetcher: any AcademicCalendarFetching = LiveAcademicCalendarFetcher()) {
    self.fetcher = fetcher
  }

  func navigate(
    from startURL: String,
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved?,
    deadline: Date
  ) async -> AcademicCalendarHubNavigationOutcome {
    visitedURLs.removeAll()
    return await walk(
      urlString: startURL,
      profile: profile,
      termScope: termScope,
      depth: 0,
      deadline: deadline
    )
  }

  private func walk(
    urlString: String,
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved?,
    depth: Int,
    deadline: Date
  ) async -> AcademicCalendarHubNavigationOutcome {
    if Date() > deadline {
      return .timedOut(lastURL: urlString, hops: depth)
    }
    guard depth < maxDepth else {
      return .failed(reason: "Maximum hub depth reached", hops: depth)
    }

    let normalized = normalizeURL(urlString)
    if visitedURLs.contains(normalized) {
      return .failed(reason: "Hub navigation cycle detected", hops: depth)
    }
    visitedURLs.insert(normalized)

    do {
      let fetch = try await fetcher.fetch(urlString: urlString, etag: nil)
      guard !fetch.content.isEmpty else {
        return .failed(reason: "Empty page content", hops: depth)
      }
      guard let baseURL = URL(string: urlString) else {
        return .failed(reason: "Invalid URL", hops: depth)
      }

      let classification = AcademicCalendarPageClassifier.classify(
        content: fetch.content,
        baseURL: baseURL,
        forcedMode: nil
      )

      switch classification.kind {
      case .hasICSFeed, .calendar:
        return .resolved(url: urlString, hops: depth, classification: classification.kind)
      case .indexHub:
        let candidates = classification.subCalendars
        guard !candidates.isEmpty else {
          return .failed(reason: "Hub page has no sub-calendars", hops: depth)
        }

        if let deepest = deepestCalendarURL(from: candidates, termScope: termScope),
           deepest != urlString,
           !visitedURLs.contains(normalizeURL(deepest)) {
          return await walk(
            urlString: deepest,
            profile: profile,
            termScope: termScope,
            depth: depth + 1,
            deadline: deadline
          )
        }

        if AcademicCalendarLinkResolver.shouldAutoFollow(
          candidates: candidates,
          profile: profile,
          termScope: termScope
        ), let autoURL = AcademicCalendarLinkResolver.bestMatch(
          candidates: candidates,
          profile: profile,
          termScope: termScope
        ) {
          return await walk(
            urlString: autoURL,
            profile: profile,
            termScope: termScope,
            depth: depth + 1,
            deadline: deadline
          )
        }

        return .needsUserChoice(candidates: candidates, hops: depth)
      }
    } catch {
      return .failed(reason: error.localizedDescription, hops: depth)
    }
  }

  private func deepestCalendarURL(
    from candidates: [AcademicCalendarSubCalendarCandidate],
    termScope: AcademicCalendarTermScope.Resolved?
  ) -> String? {
    let scopeTerm = termScope?.term.lowercased() ?? ""
    let calendarLinks = candidates.filter { candidate in
      let haystack = "\(candidate.label) \(candidate.url)".lowercased()
      guard haystack.contains("/calendar") || candidate.label.localizedCaseInsensitiveContains("calendar") else {
        return false
      }
      if haystack.contains("/calendars/index") || haystack.hasSuffix("/calendars/") {
        return false
      }
      if !scopeTerm.isEmpty, haystack.contains(scopeTerm) {
        return true
      }
      return haystack.contains("_calendar-") || haystack.contains("-calendar-")
    }
    return calendarLinks.max(by: { lhs, rhs in
      lhs.url.count < rhs.url.count
    })?.url
  }

  private func normalizeURL(_ urlString: String) -> String {
    guard let url = URL(string: urlString),
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return urlString.lowercased()
    }
    components.fragment = nil
    return (components.url?.absoluteString ?? urlString).lowercased()
  }
}
