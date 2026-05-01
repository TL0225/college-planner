import Foundation

/// Shared normalization for Modern Campus / Acalog catalog titles so onboarding pickers and Core Data `degreeLevel` stay aligned.
enum ModernCampusCatalogLabels {
    static func latestCatalogsPerNormalizedLabel(from descriptors: [ModernCampusCatalogDescriptor]) -> [ModernCampusCatalogDescriptor] {
        guard !descriptors.isEmpty else { return [] }

        var bestByLabel: [String: ModernCampusCatalogDescriptor] = [:]
        var labelOrder: [String] = []

        for descriptor in descriptors {
            let label = normalizedCatalogTypeLabel(from: descriptor.title, catoid: descriptor.catoid)
            if !labelOrder.contains(label) {
                labelOrder.append(label)
            }

            if let existing = bestByLabel[label] {
                if isPreferred(descriptor, over: existing) {
                    bestByLabel[label] = descriptor
                }
            } else {
                bestByLabel[label] = descriptor
            }
        }

        return labelOrder.compactMap { bestByLabel[$0] }
    }

    private static func isPreferred(_ lhs: ModernCampusCatalogDescriptor, over rhs: ModernCampusCatalogDescriptor) -> Bool {
        let lYear = yearRangeScore(from: lhs.title)
        let rYear = yearRangeScore(from: rhs.title)

        switch (lYear, rYear) {
        case let (.some((lEnd, lStart)), .some((rEnd, rStart))):
            if lEnd != rEnd { return lEnd > rEnd }
            if lStart != rStart { return lStart > rStart }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        let lCatoid = Int(lhs.catoid.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        let rCatoid = Int(rhs.catoid.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        if lCatoid != rCatoid { return lCatoid > rCatoid }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
    }

    private static func yearRangeScore(from rawTitle: String) -> (Int, Int)? {
        let text = rawTitle.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard let regex = try? NSRegularExpression(pattern: "((?:19|20)\\d{2})\\s*[-–]\\s*((?:19|20)\\d{2})") else {
            return nil
        }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        var best: (Int, Int)? = nil

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let startNS = (text as NSString).substring(with: match.range(at: 1))
            let endNS = (text as NSString).substring(with: match.range(at: 2))
            guard let start = Int(startNS), let end = Int(endNS) else { continue }
            if let current = best {
                if end > current.0 || (end == current.0 && start > current.1) {
                    best = (end, start)
                }
            } else {
                best = (end, start)
            }
        }

        return best
    }

    /// Strips academic year prefixes, trailing "Catalog", and normalizes whitespace.
    static func normalizedCatalogTypeLabel(from rawTitle: String, catoid: String) -> String {
        let trimmedCatoid = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        var label = rawTitle
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Some schools publish draft entries prefixed with WORKING.
        label = label.replacingOccurrences(of: "^working\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        label = label.replacingOccurrences(of: "^\\d{4}\\s*[-–]\\s*\\d{4}\\s*", with: "", options: .regularExpression)
        label = label.replacingOccurrences(of: "^\\d{4}\\s*[-–]\\s*\\d{4}\\s+", with: "", options: .regularExpression)
        label = label.replacingOccurrences(of: "\\b\\d{4}\\s*[-–]\\s*\\d{4}\\b", with: "", options: .regularExpression)
        label = label.replacingOccurrences(of: "\\s*catalog\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
        label = label.replacingOccurrences(of: "^the\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        label = label.trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = label.lowercased()
        if lower.contains("undergraduate") {
            return "Undergraduate"
        }
        if lower.contains("graduate") {
            return "Graduate"
        }
        if lower.contains("law") {
            return "Law School"
        }
        if lower.contains("dental") || lower.contains("sdm") {
            return "Dental School"
        }
        if lower.contains("medical") || lower.contains("jacobs") || lower.contains("jsmbs") {
            return "JSMBS Medical School"
        }

        if label.isEmpty {
            return "Catalog \(trimmedCatoid.isEmpty ? catoid : trimmedCatoid)"
        }

        return label
    }
}
