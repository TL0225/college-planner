import Foundation

extension ProfileEntity {

    // MARK: - JSON helpers for majors / minors lists

    /// Decode a JSON-encoded array of strings stored in a CoreData String field.
    static func decodeMajors(_ json: String?) -> [String] {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    /// Encode an array of strings to a JSON string for storage in CoreData.
    static func encodeMajors(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(list),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
