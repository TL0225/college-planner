// AcademicCalendarEntryDiscoverer.swift
// Feature: Calendar
// Purpose: Discover academic calendar entry URLs from registrar landing pages.

import Foundation

actor AcademicCalendarEntryDiscoverer {
  private let maxCandidates = 50
  private let maxProbeFetches = 3
  private let fetcher: any AcademicCalendarFetching

  init(fetcher: any AcademicCalendarFetching = LiveAcademicCalendarFetcher()) {
    self.fetcher = fetcher
  }

  func discover(
    manifest: SchoolManifest?,
    policyMetadata: SchoolPolicyMetadata?,
    universityName: String
  ) async -> AcademicCalendarDiscoveredEntry? {
    if let manifestURL = manifest?.academicCalendarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
       !manifestURL.isEmpty {
      return AcademicCalendarDiscoveredEntry(
        url: manifestURL,
        source: .manifest,
        confidence: 1.0,
        evidence: ["Bundled manifest academic_calendar_url"]
      )
    }

    let registrarCandidates = registrarLandingURLs(manifest: manifest, policyMetadata: policyMetadata, universityName: universityName)
    for landing in registrarCandidates {
      if let discovered = await discoverOnRegistrarLanding(landing) {
        return discovered
      }
    }
    return nil
  }

  private func registrarLandingURLs(
    manifest: SchoolManifest?,
    policyMetadata: SchoolPolicyMetadata?,
    universityName: String
  ) -> [String] {
    var urls: [String] = []
    if let registrar = policyMetadata?.registrarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !registrar.isEmpty {
      urls.append(registrar)
    }
    if let official = policyMetadata?.officialWebsiteURL?.trimmingCharacters(in: .whitespacesAndNewlines), !official.isEmpty {
      urls.append(official.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/registrar")
    }
    if let official = manifest?.officialWebsiteURL?.trimmingCharacters(in: .whitespacesAndNewlines), !official.isEmpty {
      urls.append(official.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/registrar")
    }
    _ = universityName
    return Array(Set(urls))
  }

  private func discoverOnRegistrarLanding(_ landingURL: String) async -> AcademicCalendarDiscoveredEntry? {
    do {
      let fetch = try await fetcher.fetch(urlString: landingURL, etag: nil)
      guard !fetch.content.isEmpty, let baseURL = URL(string: landingURL) else { return nil }

      var candidates = AcademicCalendarPageClassifier.extractSubCalendars(content: fetch.content, baseURL: baseURL)
      candidates = Array(candidates.prefix(maxCandidates))
      candidates = candidates.filter(isHighSignalCandidate)

      let scored = candidates.map { candidate -> (AcademicCalendarSubCalendarCandidate, Int) in
        (candidate, scoreRegistrarCandidate(candidate))
      }.sorted { $0.1 > $1.1 }

      let top = Array(scored.prefix(maxProbeFetches))
      for (candidate, score) in top where score >= 0 {
        guard let probeBase = URL(string: candidate.url, relativeTo: URL(string: landingURL)) ?? URL(string: candidate.url) else { continue }
        let resolvedURL = probeBase.absoluteString
        let probe = try await fetcher.fetch(urlString: resolvedURL, etag: nil)
        guard !probe.content.isEmpty else { continue }
        let classification = AcademicCalendarPageClassifier.classify(
          content: probe.content,
          baseURL: probeBase,
          forcedMode: nil
        )
        if classification.kind != .calendar && classification.kind != .indexHub && classification.kind != .hasICSFeed {
          continue
        }
        return AcademicCalendarDiscoveredEntry(
          url: resolvedURL,
          source: .registrar,
          confidence: min(1.0, Double(score) / 10.0),
          evidence: ["Registrar landing: \(landingURL)", "Candidate: \(candidate.label)"]
        )
      }
    } catch {
      return nil
    }
    return nil
  }

  private func isHighSignalCandidate(_ candidate: AcademicCalendarSubCalendarCandidate) -> Bool {
    let haystack = "\(candidate.label) \(candidate.url)".lowercased()
    let include = ["calendar", "academic", "dates", "registrar", "term"]
    let exclude = ["financial-aid", "financial_aid", "/news", "/search", "facebook.com", "twitter.com", "instagram.com"]
    guard include.contains(where: { haystack.contains($0) }) else { return false }
    return !exclude.contains(where: { haystack.contains($0) })
  }

  private func scoreRegistrarCandidate(_ candidate: AcademicCalendarSubCalendarCandidate) -> Int {
    let haystack = "\(candidate.label) \(candidate.url)".lowercased()
    var score = 0
    if haystack.contains("academic calendar") { score += 4 }
    if haystack.contains("calendar") { score += 2 }
    if haystack.contains("registrar") { score += 2 }
    if haystack.contains("term dates") || haystack.contains("important dates") { score += 2 }
    if haystack.contains("financial") || haystack.contains("news") { score -= 5 }
    return score
  }
}
