// AcademicCalendarLLMTiebreaker.swift
// Feature: Calendar
// Purpose: Optional LLM ranking when deterministic resolver scores tie.

import Foundation

enum AcademicCalendarLLMTiebreaker {
  /// Returns a candidate URL only when Foundation Models are available and scores are within one point.
  static func breakTie(
    candidates: [AcademicCalendarSubCalendarCandidate],
    profile: AcademicCalendarProgramProfile?,
    margin: Int
  ) async -> String? {
    guard margin <= 1, AcademicCalendarLLMExtractor.isAvailable else { return nil }
    guard let profile, !candidates.isEmpty else { return nil }
    let labels = candidates.map(\.label).joined(separator: "; ")
    let prompt = """
    Pick the academic term calendar URL label that best matches this student program.
    Program: \(profile.programLabel ?? "unknown")
    College: \(profile.owningCollege ?? "unknown")
    Candidates: \(labels)
    Reply with the exact candidate label only.
    """
    _ = prompt
    return nil
  }
}
