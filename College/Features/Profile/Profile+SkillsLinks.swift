// Profile+SkillsLinks.swift
// Feature: Profile
// Purpose: Decode/encode profile skills and links JSON fields.

import Foundation

extension Profile {
    var skillsList: [String] {
        get { Self.decodeStringArray(from: skillsJSON) }
        set { skillsJSON = Self.encodeStringArray(newValue) }
    }

    var linksList: [String] {
        get { Self.decodeStringArray(from: linksJSON) }
        set { linksJSON = Self.encodeStringArray(newValue) }
    }

    private static func decodeStringArray(from json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    private static func encodeStringArray(_ values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty,
              let data = try? JSONEncoder().encode(cleaned),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }
}
