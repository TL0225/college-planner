// AcademicCalendarLinkResolver.swift
// Feature: Calendar
// Purpose: Score hub/sub-calendar candidates using catalog-derived program profile.

import Foundation

struct AcademicCalendarLinkResolverRanking: Sendable, Equatable {
  var url: String
  var label: String
  var score: Int
}

enum AcademicCalendarLinkResolver {
  static let autoFollowThreshold = 2
  static let autoFollowMargin = 2

  static func rank(
    candidates: [AcademicCalendarSubCalendarCandidate],
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved?
  ) -> [AcademicCalendarLinkResolverRanking] {
    candidates
      .map { candidate in
        AcademicCalendarLinkResolverRanking(
          url: candidate.url,
          label: candidate.label,
          score: score(
            label: candidate.label,
            url: candidate.url,
            profile: profile,
            termScope: termScope
          )
        )
      }
      .sorted { $0.score > $1.score }
  }

  static func bestMatch(
    candidates: [AcademicCalendarSubCalendarCandidate],
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved? = nil
  ) -> String? {
    if hasCompetingAudienceCandidates(candidates) {
      guard let degreeLevel = profile?.degreeLevel,
            !degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
    }
    let ranked = rank(candidates: candidates, profile: profile, termScope: termScope)
    guard let best = ranked.first else { return candidates.first?.url }
    guard best.score > 0 else { return candidates.first?.url }

    if ranked.count > 1 {
      let second = ranked[1]
      if best.score == second.score {
        if areEquivalentCandidates(best, second) {
          return best.url
        }
        guard let degreeLevel = profile?.degreeLevel,
              !degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return nil
        }
        return tieBreakURL(from: ranked.map {
          AcademicCalendarSubCalendarCandidate(label: $0.label, url: $0.url)
        }, degreeLevel: degreeLevel)
      }
    }
    return best.url
  }

  static func confidenceMargin(
    candidates: [AcademicCalendarSubCalendarCandidate],
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved?
  ) -> Int {
    let ranked = rank(candidates: candidates, profile: profile, termScope: termScope)
    guard ranked.count >= 2 else { return ranked.first?.score ?? 0 }
    return (ranked[0].score) - (ranked[1].score)
  }

  static func shouldAutoFollow(
    candidates: [AcademicCalendarSubCalendarCandidate],
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved?
  ) -> Bool {
    guard let termScope else { return false }
    if hasCompetingAudienceCandidates(candidates) {
      guard let degreeLevel = profile?.degreeLevel,
            !degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
      }
    }
    let ranked = rank(candidates: candidates, profile: profile, termScope: termScope)
    guard let best = ranked.first else { return false }
    guard best.score >= autoFollowThreshold else { return false }
    if ranked.count > 1 {
      let margin = best.score - ranked[1].score
      if margin < autoFollowMargin {
        if areEquivalentCandidates(best, ranked[1]) { return true }
        return false
      }
    }
    return true
  }

  static func areEquivalentCandidates(_ lhs: AcademicCalendarLinkResolverRanking, _ rhs: AcademicCalendarLinkResolverRanking) -> Bool {
    let lhsPrefix = AcademicCalendarNormalization.calendarNormalize(lhs.label)
    let rhsPrefix = AcademicCalendarNormalization.calendarNormalize(rhs.label)
    if lhsPrefix == rhsPrefix { return true }
    if let lhsURL = URL(string: lhs.url), let rhsURL = URL(string: rhs.url) {
      if lhsURL.path == rhsURL.path { return true }
    }
    return false
  }

  private static func tieBreakURL(
    from ranked: [AcademicCalendarSubCalendarCandidate],
    degreeLevel: String
  ) -> String? {
    let preferGraduate = !DegreeConfiguration.isUndergraduate(degreeLevel)
    let preferredToken = preferGraduate ? "graduate" : "undergrad"
    return ranked.first(where: { candidate in
      let haystack = "\(candidate.label) \(candidate.url)".lowercased()
      return haystack.contains(preferredToken)
    })?.url
  }

  private static func score(
    label: String,
    url: String,
    profile: AcademicCalendarProgramProfile?,
    termScope: AcademicCalendarTermScope.Resolved?
  ) -> Int {
    let lower = "\(label) \(url)".lowercased()
    var total = 0

    if let termScope {
      if lower.contains(termScope.term.lowercased()) { total += 2 }
      if lower.contains(String(termScope.year)) { total += 2 }
      if termScope.term.lowercased().contains("summer"), lower.contains("summer") { total += 1 }
      if termScope.term.lowercased().contains("winter"), lower.contains("winter") { total += 1 }
      if !termScope.term.lowercased().contains("summer"), lower.contains("summer") { total -= 3 }
      if !termScope.term.lowercased().contains("winter"), lower.contains("winter") { total -= 3 }
    }

    if let profile {
      for token in profile.matchTokens {
        let normalized = AcademicCalendarNormalization.calendarNormalize(token)
        guard normalized.count >= 3 else { continue }
        if lower.contains(normalized) {
          total += profile.owningCollege?.localizedCaseInsensitiveContains(token) == true ? 3 : 2
        }
      }
      total += audienceAlignmentScore(label: label, url: url, profile: profile)
      total += professionalSchoolScore(lower: lower, profile: profile)
    }

    if lower.contains("current") || lower.contains("active") {
      total += 1
    }
    return total
  }

  private static func audienceAlignmentScore(label: String, url: String, profile: AcademicCalendarProgramProfile) -> Int {
    guard let degreeLevel = profile.degreeLevel,
          !degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return 0
    }
    let haystack = "\(label) \(url)".lowercased()
    let undergradAudience = haystack.contains("undergrad")
    let graduateAudience = haystack.contains("graduate") || haystack.contains("_grad-")

    if DegreeConfiguration.isUndergraduate(degreeLevel) {
      if undergradAudience && !graduateAudience { return 4 }
      if graduateAudience && !undergradAudience { return -4 }
    } else {
      if graduateAudience && !undergradAudience { return 4 }
      if undergradAudience && !graduateAudience { return -4 }
    }
    return 0
  }

  private static func professionalSchoolScore(lower: String, profile: AcademicCalendarProgramProfile) -> Int {
    let college = profile.owningCollege?.lowercased() ?? ""
    let keywords: [(String, [String])] = [
      ("law", ["law", "legal"]),
      ("business", ["business", "gabelli", "stern", "commerce"]),
      ("medicine", ["medicine", "medical", "health"]),
      ("engineering", ["engineering", "eng"]),
      ("nursing", ["nursing"]),
    ]
    for (domain, tokens) in keywords {
      if college.contains(domain) || profile.matchTokens.contains(where: { $0.contains(domain) }) {
        if tokens.contains(where: { lower.contains($0) }) { return 3 }
      }
    }
    return 0
  }

  private static func hasCompetingAudienceCandidates(_ candidates: [AcademicCalendarSubCalendarCandidate]) -> Bool {
    var hasUndergrad = false
    var hasGraduate = false
    for candidate in candidates {
      let haystack = "\(candidate.label) \(candidate.url)".lowercased()
      if haystack.contains("undergrad") { hasUndergrad = true }
      if haystack.contains("graduate") || haystack.contains("_grad-") { hasGraduate = true }
    }
    return hasUndergrad && hasGraduate
  }
}

// Backward-compatible shim for callers not yet migrated.
enum AcademicCalendarHubSuggestion {
  static func bestMatch(
    candidates: [AcademicCalendarSubCalendarCandidate],
    collegeName: String?,
    degreeLevel: String?,
    termScope: AcademicCalendarTermScope.Resolved? = nil
  ) -> String? {
    let tokens = collegeName.map { AcademicCalendarNormalization.matchTokens(from: [$0]) } ?? []
    let profile = AcademicCalendarProgramProfile(
      degreeLevel: degreeLevel,
      levelScope: degreeLevel.map { DegreeConfiguration.isUndergraduate($0) ? AcademicCalendarLevelScope.undergrad : .grad } ?? .all,
      programLabel: collegeName,
      owningCollege: collegeName,
      owningDepartment: nil,
      owningSchool: nil,
      matchTokens: tokens,
      isDegraded: true,
      departmentKey: AcademicCalendarConfig.universityWideKey,
      departmentDisplayName: collegeName ?? "University Term Dates"
    )
    return AcademicCalendarLinkResolver.bestMatch(candidates: candidates, profile: profile, termScope: termScope)
  }

  static func shouldAutoFollow(
    candidates: [AcademicCalendarSubCalendarCandidate],
    collegeName: String?,
    degreeLevel: String?,
    termScope: AcademicCalendarTermScope.Resolved?
  ) -> Bool {
    let tokens = collegeName.map { AcademicCalendarNormalization.matchTokens(from: [$0]) } ?? []
    let profile = AcademicCalendarProgramProfile(
      degreeLevel: degreeLevel,
      levelScope: degreeLevel.map { DegreeConfiguration.isUndergraduate($0) ? AcademicCalendarLevelScope.undergrad : .grad } ?? .all,
      programLabel: collegeName,
      owningCollege: collegeName,
      owningDepartment: nil,
      owningSchool: nil,
      matchTokens: tokens,
      isDegraded: true,
      departmentKey: AcademicCalendarConfig.universityWideKey,
      departmentDisplayName: collegeName ?? "University Term Dates"
    )
    return AcademicCalendarLinkResolver.shouldAutoFollow(candidates: candidates, profile: profile, termScope: termScope)
  }
}
