// CourseLeafProgramURLParser.swift
// Feature: Catalog
// Purpose: Catalog module — CourseLeafProgramURLParser.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Derives program ownership and catalog matching hints from CourseLeaf bulletin URLs.
enum CourseLeafProgramURLParser {
    private static let programPathMarkers: Set<String> = [
        "programs", "program", "major", "minor", "degree", "mba", "doctoral"
    ]

    /// Top-level bulletin segments (NYU, etc.) — not a college/school name.
    private static let catalogLevelSlugs: Set<String> = [
        "undergraduate", "graduate", "courses"
    ]

    /// Known NYU school path slugs → bulletin display names (from bulletins.nyu.edu nav labels).
    private static let nyuCollegeDisplayNames: [String: String] = [
        "abu-dhabi": "NYU Abu Dhabi",
        "arts": "Tisch School of the Arts",
        "arts-science": "College of Arts and Science",
        "business": "Leonard N. Stern School of Business",
        "culture-education-human-development": "Steinhardt School of Culture, Education, and Human Development",
        "dentistry": "College of Dentistry",
        "engineering": "Tandon School of Engineering",
        "gallatin": "Gallatin School of Individualized Study",
        "global-public-health": "School of Global Public Health",
        "individualized-study": "Individualized Study",
        "law": "School of Law",
        "liberal-studies": "Liberal Studies",
        "medicine-grossman": "Grossman School of Medicine",
        "medicine-long-island": "NYU Long Island School of Medicine",
        "medicine": "Grossman School of Medicine",
        "nursing": "Rory Meyers College of Nursing",
        "professional-studies": "School of Professional Studies",
        "public-service": "Robert F. Wagner Graduate School of Public Service",
        "shanghai": "NYU Shanghai",
        "social-work": "Silver School of Social Work",
        "steinhardt": "Steinhardt School of Culture, Education, and Human Development",
        "stern": "Leonard N. Stern School of Business",
        "tandon": "Tandon School of Engineering"
    ]

    /// Collapse legacy slug/humanized labels onto one department bucket per college.
    private static let nyuCollegeCanonicalKeys: [String: String] = [
        "arts science": "college of arts and science",
        "business": "leonard n stern school of business",
        "culture education human development": "steinhardt school of culture education and human development",
        "engineering": "tandon school of engineering",
        "stern": "leonard n stern school of business",
        "steinhardt": "steinhardt school of culture education and human development",
        "tandon": "tandon school of engineering"
    ]

    /// Titles scraped from program index/listing pages — not selectable degrees.
    static func isJunkProgramTitle(_ title: String) -> Bool {
        let normalized = title
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty { return true }
        if normalized == "programs" || normalized == "program" { return true }
        if normalized.hasSuffix(" programs") && normalized.count <= 24 { return true }
        return false
    }

    /// Human-readable college/school and department labels from a program page path.
    static func ownership(from pageURL: URL) -> (department: String?, college: String?) {
        let parts = pageURL.path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return (nil, nil) }

        guard let markerIndex = parts.firstIndex(where: { programPathMarkers.contains($0.lowercased()) }) else {
            // Fordham-style: /undergraduate/accounting/major/
            if parts.count >= 2 {
                let department = humanizeSlug(parts[parts.count - 1])
                let college = humanizeSlug(parts[0])
                return (department, college)
            }
            return (nil, nil)
        }

        guard markerIndex > 0 else { return (nil, nil) }

        // NYU-style: /undergraduate/{school}/programs/{program}/ — school slug is the college.
        let marker = parts[markerIndex].lowercased()
        if markerIndex >= 2,
           catalogLevelSlugs.contains(parts[0].lowercased()),
           marker == "programs" || marker == "program" {
            let schoolSlug = parts[markerIndex - 1]
            let collegeName = displayCollegeName(slug: schoolSlug, pageURL: pageURL)
            return (collegeName, collegeName)
        }

        let departmentSlug = parts[markerIndex - 1]
        let department = humanizeSlug(departmentSlug)
        let collegeSlug = markerIndex >= 2 ? parts[markerIndex - 2] : parts[0]
        let college = humanizeSlug(collegeSlug)
        return (department, college)
    }

    /// Bulletin college/school label for a URL path slug.
    static func displayCollegeName(slug: String, pageURL: URL) -> String {
        let normalizedSlug = slug
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedSlug.isEmpty { return humanizeSlug(slug) }

        let host = (pageURL.host ?? "").lowercased()
        if host.contains("nyu.edu") {
            if let mapped = nyuCollegeDisplayNames[normalizedSlug] {
                return mapped
            }
        }

        return humanizeSlug(slug)
    }

    /// Stable key for deduplicating NYU college labels (slug, humanized, or full title).
    static func canonicalCollegeKey(for label: String) -> String {
        let normalized = label
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty { return "" }
        if let mapped = nyuCollegeCanonicalKeys[normalized] {
            return mapped
        }
        return normalized
    }

    /// Re-derive college ownership from a bulletin program URL when possible.
    static func ownershipFromProgramURL(_ urlString: String?) -> (department: String?, college: String?)? {
        let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let pageURL = URL(string: trimmed) else { return nil }
        let host = (pageURL.host ?? "").lowercased()
        guard host.contains("nyu.edu") else { return nil }
        let ownership = ownership(from: pageURL)
        guard ownership.college != nil || ownership.department != nil else { return nil }
        return ownership
    }

    /// Degree token from a trailing parenthetical in the page title, e.g. "(BA)".
    static func degreeTypeFromTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "("), let close = trimmed.lastIndex(of: ")"), open < close else {
            return nil
        }
        let token = trimmed[trimmed.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 12 else { return nil }
        if let canonical = DegreeTypeNormalizer.normalize(token) {
            return canonical.storageToken
        }
        return token.uppercased()
    }

    static func humanizeSlug(_ slug: String) -> String {
        slug
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { part in
                let s = String(part)
                guard !s.isEmpty else { return "" }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
