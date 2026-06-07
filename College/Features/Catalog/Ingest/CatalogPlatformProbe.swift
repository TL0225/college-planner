// CatalogPlatformProbe.swift
// Feature: Catalog
// Purpose: Warn when manifest catalog_format disagrees with URL/HTML sniff (Tier 2).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPlatformProbe {
    struct Result: Sendable, Equatable {
        let declaredFormat: String
        let sniffedFormat: String
        let mismatch: Bool
        let message: String
    }

    static func evaluate(manifest: SchoolManifest, catalogURL: String) -> Result {
        let declared = (manifest.catalogFormat ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sniffed = sniffFormat(catalogURL: catalogURL).lowercased()
        let mismatch = !declared.isEmpty && !sniffed.isEmpty && declared != sniffed && sniffed != "unknown"
        let message: String
        if mismatch {
            message = "Manifest declares '\(declared)' but catalog URL looks like '\(sniffed)'."
        } else {
            message = ""
        }
        return Result(
            declaredFormat: declared.isEmpty ? "unknown" : declared,
            sniffedFormat: sniffed,
            mismatch: mismatch,
            message: message
        )
    }

    static func enqueueMismatchWarningIfNeeded(manifest: SchoolManifest, catalogURL: String) {
        let probe = evaluate(manifest: manifest, catalogURL: catalogURL)
        guard probe.mismatch else { return }
        CatalogReviewQueue.enqueue(
            schoolID: manifest.id,
            reason: "catalog_platform_mismatch: \(probe.message)",
            severity: .warning
        )
    }

    private static func sniffFormat(catalogURL: String) -> String {
        let lower = catalogURL.lowercased()
        if lower.contains("bulletins.") || lower.contains("bulletin.") && lower.contains("courseleaf") {
            return "courseleaf"
        }
        if lower.contains("bulletins.") || lower.contains("bulletin.") {
            return "courseleaf"
        }
        if lower.contains("catalog.") || lower.contains("acalog") || lower.contains("content.php") {
            return "moderncampus"
        }
        if lower.hasSuffix(".pdf") {
            return "pdf"
        }
        return "unknown"
    }
}
