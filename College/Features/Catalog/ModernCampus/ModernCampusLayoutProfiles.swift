// ModernCampusLayoutProfiles.swift
// Feature: Catalog
// Purpose: Modern Campus layout profiles — feature-based IR entity extraction.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ModernCampusDOMFeatures: Sendable, Equatable {
    var n2LinksCount: Int = 0
    var blockN2TableCount: Int = 0
    var previewProgramLinkCount: Int = 0
    var contentHeadingCount: Int = 0
    var entityPageLinkCount: Int = 0
}

struct ModernCampusProfileConfig: Sendable, Equatable {
    /// UB-style catalogs list programs under entity pages (`preview_entity`) before `preview_program`.
    let prefersEntityPageProgramDiscovery: Bool

    static let `default` = ModernCampusProfileConfig(prefersEntityPageProgramDiscovery: false)

    static func forHost(_ host: String?) -> ModernCampusProfileConfig {
        if ModernCampusHostProfiles.resolve(host: host)?.prefersEntityPageProgramDiscovery == true {
            return ModernCampusProfileConfig(prefersEntityPageProgramDiscovery: true)
        }
        return .default
    }
}

enum ModernCampusLayoutProfileID: String, Sendable, CaseIterable {
    case sidebarN2Links = "sidebarN2Links"
    case blockN2Table = "blockN2Table"
    case entityPreviewProgram = "entityPreviewProgram"

    static func resolve(_ raw: String) -> ModernCampusLayoutProfileID {
        ModernCampusLayoutProfileID(rawValue: raw) ?? .sidebarN2Links
    }

    static func classify(domFeatures: ModernCampusDOMFeatures, host: String?) -> (profileID: String, confidence: Double) {
        let config = ModernCampusProfileConfig.forHost(host)
        let entityScore = Double(domFeatures.entityPageLinkCount) * 5.0
            + (config.prefersEntityPageProgramDiscovery ? 4.0 : 0.0)
        let sidebarScore = Double(domFeatures.n2LinksCount) * 2.0 + Double(domFeatures.blockN2TableCount)
        let tableScore = Double(domFeatures.blockN2TableCount) * 4.0 + Double(domFeatures.n2LinksCount)
        let programScore = Double(domFeatures.previewProgramLinkCount) * 3.0

        let candidates: [(ModernCampusLayoutProfileID, Double)] = [
            (.entityPreviewProgram, entityScore + programScore),
            (.blockN2Table, tableScore),
            (.sidebarN2Links, sidebarScore + programScore * 0.5)
        ]
        let best = candidates.max(by: { $0.1 < $1.1 }) ?? (.sidebarN2Links, sidebarScore)
        let total = candidates.map(\.1).reduce(0, +)
        let rawConfidence = total > 0 ? best.1 / total : 0.25
        return (best.0.rawValue, min(max(rawConfidence, 0.2), 1.0))
    }

    func extractEntities(
        from ir: CatalogDocumentIR,
        pageURL: URL,
        config: ModernCampusProfileConfig
    ) -> (courses: [CatalogCourse], programs: [ScrapedProgram]) {
        let courses = ModernCampusIRCourseExtractor.courses(from: ir)
        switch self {
        case .sidebarN2Links, .blockN2Table:
            let programLinks = ir.nodes.filter { $0.kind == .programBlock || ($0.kind == .linkList && ($0.sourceURL ?? "").contains("preview_program")) }
            let programs = programLinks.compactMap { node -> ScrapedProgram? in
                guard let url = node.sourceURL, url.contains("preview_program") else { return nil }
                let name = (node.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return ScrapedProgram(name: name, type: "Program", url: url)
            }
            return (courses: courses, programs: programs)
        case .entityPreviewProgram:
            if config.prefersEntityPageProgramDiscovery {
                // Entity-page program discovery may still use UniversalCatalogScraper when IR program count is low.
            }
            let programLinks = ir.nodes.filter { $0.elementSignature == "a.preview_program" || $0.kind == .programBlock }
            let programs = programLinks.compactMap { node -> ScrapedProgram? in
                guard let url = node.sourceURL, url.contains("preview_program") else { return nil }
                let name = (node.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return ScrapedProgram(name: name, type: "Program", url: url)
            }
            return (courses: courses, programs: programs)
        }
    }
}
