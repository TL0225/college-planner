// CatalogVersion.swift
// Feature: Catalog
// Purpose: Catalog module — catalog edition identity (school + bulletin slice).
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogVersion: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let schoolID: String
    let label: String
    let sourceSignature: String
    let catoid: String?
    let courseLeafRootURLs: [String]?
    let effectiveFrom: Date?
    let effectiveTo: Date?

    enum Segment: Sendable, Equatable {
        case courseLeafOnboarding(CourseLeafCatalogSegmentDiscoverer.OnboardingCatalog)
        case courseLeafDiscovered(CourseLeafCatalogSegmentDiscoverer.DiscoveredSegment)
        case modernCampus(ModernCampusCatalogDescriptor)
        case manifestOnly
    }

    static func resolve(
        school: SchoolManifest,
        segment: Segment,
        referenceDate: Date = Date()
    ) -> CatalogVersion {
        let schoolID = school.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalogURL = (school.catalogURL ?? school.profileURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch segment {
        case .courseLeafOnboarding(let catalog):
            let catoid = catalog.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let roots = catalog.pathPrefixes
                .map { prefix in
                    let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return "" }
                    if trimmed.hasPrefix("http") { return trimmed }
                    let base = catalogURL.hasSuffix("/") ? String(catalogURL.dropLast()) : catalogURL
                    return base + (trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)")
                }
                .filter { !$0.isEmpty }
            let signature = sourceSignature(
                schoolID: schoolID,
                catalogURL: catalogURL,
                segmentKey: catoid,
                pathPrefixes: catalog.pathPrefixes
            )
            return CatalogVersion(
                id: versionID(schoolID: schoolID, segmentKey: catoid),
                schoolID: schoolID,
                label: catalog.displayName,
                sourceSignature: signature,
                catoid: catoid,
                courseLeafRootURLs: roots.isEmpty ? nil : roots,
                effectiveFrom: nil,
                effectiveTo: nil
            )

        case .courseLeafDiscovered(let segment):
            let catoid = segment.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = joinCatalogURL(catalogURL, pathPrefix: segment.pathPrefix)
            let signature = sourceSignature(
                schoolID: schoolID,
                catalogURL: catalogURL,
                segmentKey: catoid,
                pathPrefixes: [segment.pathPrefix]
            )
            return CatalogVersion(
                id: versionID(schoolID: schoolID, segmentKey: catoid),
                schoolID: schoolID,
                label: segment.displayName,
                sourceSignature: signature,
                catoid: catoid,
                courseLeafRootURLs: root.map { [$0] },
                effectiveFrom: nil,
                effectiveTo: nil
            )

        case .modernCampus(let descriptor):
            let catoid = descriptor.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            let signature = sourceSignature(
                schoolID: schoolID,
                catalogURL: catalogURL,
                segmentKey: catoid,
                pathPrefixes: []
            )
            return CatalogVersion(
                id: versionID(schoolID: schoolID, segmentKey: catoid),
                schoolID: schoolID,
                label: descriptor.title,
                sourceSignature: signature,
                catoid: catoid.isEmpty ? nil : catoid,
                courseLeafRootURLs: nil,
                effectiveFrom: nil,
                effectiveTo: nil
            )

        case .manifestOnly:
            let label = academicYearLabel(from: catalogURL, referenceDate: referenceDate)
            let signature = sourceSignature(
                schoolID: schoolID,
                catalogURL: catalogURL,
                segmentKey: "default",
                pathPrefixes: []
            )
            return CatalogVersion(
                id: versionID(schoolID: schoolID, segmentKey: "default"),
                schoolID: schoolID,
                label: label,
                sourceSignature: signature,
                catoid: nil,
                courseLeafRootURLs: catalogURL.isEmpty ? nil : [catalogURL],
                effectiveFrom: nil,
                effectiveTo: nil
            )
        }
    }

    private static func versionID(schoolID: String, segmentKey: String) -> String {
        let school = schoolID.trimmingCharacters(in: .whitespacesAndNewlines)
        let segment = segmentKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return school }
        return "\(school)_\(segment)"
    }

    private static func sourceSignature(
        schoolID: String,
        catalogURL: String,
        segmentKey: String,
        pathPrefixes: [String]
    ) -> String {
        let prefixBlob = pathPrefixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .sorted()
            .joined(separator: "|")
        return [schoolID, catalogURL, segmentKey, prefixBlob]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "::")
    }

    private static func joinCatalogURL(_ catalogURL: String, pathPrefix: String) -> String? {
        let base = catalogURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = pathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !prefix.isEmpty else { return nil }
        if prefix.hasPrefix("http") { return prefix }
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return normalizedBase + (prefix.hasPrefix("/") ? prefix : "/\(prefix)")
    }

    private static func academicYearLabel(from catalogURL: String, referenceDate: Date) -> String {
        let text = catalogURL.lowercased()
        if let match = text.range(of: #"(20\d{2})[-_](20\d{2})"#, options: .regularExpression) {
            let token = String(text[match]).replacingOccurrences(of: "_", with: "-")
            return token
        }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: referenceDate)
        let next = year + 1
        return "\(year)-\(next)"
    }
}
