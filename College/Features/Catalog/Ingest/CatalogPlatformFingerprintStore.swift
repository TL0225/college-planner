// CatalogPlatformFingerprintStore.swift
// Feature: Catalog
// Purpose: Score HTML/URL evidence to derive catalog platform (not hostname heuristics alone).

import Foundation

enum CatalogDetectedPlatform: String, Sendable, Codable, CaseIterable {
    case moderncampus
    case courseleaf
    case coursedog
    case pdf
    case banner
    case custom
    case unknown

    /// Normalized manifest `catalog_format` string.
    var manifestFormat: String {
        switch self {
        case .moderncampus: return "acalog"
        case .courseleaf: return "courseleaf"
        case .coursedog: return "coursedog"
        case .pdf: return "pdf"
        case .banner: return "banner"
        case .custom: return "custom"
        case .unknown: return "unknown"
        }
    }

    static func from(manifestFormat: String) -> CatalogDetectedPlatform {
        switch manifestFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "acalog", "moderncampus": return .moderncampus
        case "courseleaf": return .courseleaf
        case "coursedog": return .coursedog
        case "pdf": return .pdf
        case "banner": return .banner
        case "custom": return .custom
        default: return .unknown
        }
    }
}

struct CatalogPlatformScoreResult: Sendable, Equatable {
    let platform: CatalogDetectedPlatform
    let score: Double
    let evidence: [String]
}

enum CatalogPlatformFingerprintStore {
    private struct HTMLMarker {
        let platform: CatalogDetectedPlatform
        let patterns: [String]
        let weight: Double
    }

    private static let htmlMarkers: [HTMLMarker] = [
        HTMLMarker(platform: .moderncampus, patterns: ["catalog_list.php", "catoid=", "#acalog-content", "preview_program.php", "content.php?catoid=", "hidecatalogdata("], weight: 1.0),
        HTMLMarker(platform: .moderncampus, patterns: ["modern campus"], weight: 0.5),
        HTMLMarker(platform: .courseleaf, patterns: ["courseleaf.css", "courseleaf.js", "sc_courselist", "sc_plangrid"], weight: 1.0),
        HTMLMarker(platform: .coursedog, patterns: ["coursedog"], weight: 0.35),
        HTMLMarker(platform: .custom, patterns: ["wp-json", "/wp-content/"], weight: 1.0),
        HTMLMarker(platform: .banner, patterns: ["banner.selfservice", "ssb/"], weight: 1.0),
    ]

    /// Fast URL-only sniff (weak signal, +0.5 when agreeing with HTML).
    static func sniffURL(_ catalogURL: String) -> CatalogDetectedPlatform {
        let lower = catalogURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasSuffix(".pdf") || lower.contains(".pdf?") { return .pdf }
        if lower.contains("bulletins.") || lower.contains("bulletin.") { return .courseleaf }
        if lower.contains("catalog_list.php") || lower.contains("catoid=") { return .moderncampus }
        if lower.contains("catalog.") || lower.contains("acalog") { return .moderncampus }
        return .unknown
    }

    static func scoreHTML(_ html: String, baseURL: URL?, urlSniff: CatalogDetectedPlatform) -> [CatalogPlatformScoreResult] {
        let lower = html.lowercased()
        var totals: [CatalogDetectedPlatform: (score: Double, evidence: [String])] = [:]

        for marker in htmlMarkers {
            var hits = 0
            for pattern in marker.patterns {
                if lower.contains(pattern) {
                    hits += 1
                    totals[marker.platform, default: (0, [])].evidence.append("html:\(pattern)")
                }
            }
            if hits > 0 {
                let bonus = marker.platform == .coursedog ? min(1.0, Double(hits) * marker.weight) : marker.weight
                let existing = totals[marker.platform, default: (0, [])]
                totals[marker.platform] = (existing.score + bonus, existing.evidence)
            }
        }

        if urlSniff != .unknown {
            let existing = totals[urlSniff, default: (0, [])]
            totals[urlSniff] = (existing.score + 0.5, existing.evidence + ["url_sniff:\(urlSniff.manifestFormat)"])
        }

        // Disambiguation: WordPress blocks CourseLeaf when wp-json present.
        if totals[.custom]?.score ?? 0 >= 1.0 {
            totals[.courseleaf] = nil
        }

        // Coursedog density beats catalog.* hostname — require 3+ coursedog hits for strong signal.
        let coursedogCount = lower.components(separatedBy: "coursedog").count - 1
        if coursedogCount >= 3, totals[.moderncampus] != nil {
            totals[.moderncampus] = nil
            let existing = totals[.coursedog, default: (0, [])]
            totals[.coursedog] = (max(existing.score, 2.0), existing.evidence + ["coursedog_density:\(coursedogCount)"])
        }

        return totals
            .map { CatalogPlatformScoreResult(platform: $0.key, score: $0.value.score, evidence: $0.value.evidence) }
            .sorted { $0.score > $1.score }
    }

    static func decide(from scores: [CatalogPlatformScoreResult]) -> (winner: CatalogDetectedPlatform, confidence: Double, margin: Double)? {
        guard let top = scores.first, top.score > 0 else { return nil }
        let runnerUp = scores.dropFirst().first?.score ?? 0
        let margin = top.score - runnerUp
        return (top.platform, top.score, margin)
    }

    static func shouldAutoOverride(
        declared: CatalogDetectedPlatform,
        detected: CatalogDetectedPlatform,
        confidence: Double,
        margin: Double
    ) -> Bool {
        guard detected != .unknown, declared != detected else { return false }
        guard confidence >= 2.0, margin >= 1.0 else { return false }
        return true
    }
}
