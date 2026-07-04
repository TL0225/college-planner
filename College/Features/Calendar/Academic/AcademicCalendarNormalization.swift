// AcademicCalendarNormalization.swift
// Feature: Calendar
// Purpose: Shared text normalization for academic calendar link matching.

import Foundation

enum AcademicCalendarNormalization {
  private static let boilerplatePrefixes = [
    "school of ", "college of ", "department of ", "faculty of ", "the ",
  ]

  private static let professionalSchoolAliases: [String: [String]] = [
    "law": ["law", "legal"],
    "medicine": ["medicine", "medical", "md", "health sciences"],
    "business": ["business", "mba", "commerce", "management"],
    "engineering": ["engineering", "eng"],
    "nursing": ["nursing", "nurse"],
    "education": ["education", "teaching"],
    "arts": ["arts", "fine arts"],
    "science": ["science", "sciences"],
  ]

  /// Diacritic-insensitive, punctuation-stripped, lowercased token for calendar matching.
  static func calendarNormalize(_ raw: String) -> String {
    let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let replaced = folded
      .replacingOccurrences(of: "&", with: " and ")
      .replacingOccurrences(of: "'", with: "")
    let stripped = replaced.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
      .map { String($0) }
      .joined()
    return stripped
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  static func slugKey(from displayName: String) -> String {
    let normalized = calendarNormalize(displayName)
    let slug = normalized
      .replacingOccurrences(of: " ", with: "_")
      .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    return slug.isEmpty ? AcademicCalendarConfig.universityWideKey : slug
  }

  static func matchTokens(from rawLabels: [String]) -> [String] {
    var tokens = Set<String>()
    for raw in rawLabels {
      let normalized = calendarNormalize(raw)
      guard !normalized.isEmpty else { continue }
      tokens.insert(normalized)

      var stripped = normalized
      for prefix in boilerplatePrefixes {
        if stripped.hasPrefix(prefix) {
          stripped = String(stripped.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
      }
      if !stripped.isEmpty, stripped != normalized {
        tokens.insert(stripped)
      }

      for word in stripped.split(separator: " ") where word.count >= 4 {
        tokens.insert(String(word))
      }

      for (_, aliases) in professionalSchoolAliases {
        if aliases.contains(where: { normalized.contains($0) }) {
          aliases.forEach { tokens.insert($0) }
        }
      }
    }
    return tokens.sorted()
  }
}
