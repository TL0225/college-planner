// ModernCampusCatalogDiscovery.swift
// Feature: Catalog
// Purpose: Single catalog-discovery path for ingest, onboarding, graph build, and verification.

import Foundation

/// Shared Modern Campus / Acalog catalog list resolution.
enum ModernCampusCatalogDiscovery {
    /// Resolves the catalog editions to scrape (latest per label, archived rows excluded).
    ///
    /// Callers must pass the output of ``ModernCampusEngine/normalizeCatalogEntryPointForCaller(_:)``.
    static func resolveCatalogsForIngest(
        normalizedBaseURL: String,
        catoidHint: String?
    ) async throws -> [ModernCampusCatalogDescriptor] {
        let discovered = try await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedBaseURL)
        if !discovered.isEmpty {
            return discovered
        }

        let trimmedHint = catoidHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedHint.isEmpty {
            return [ModernCampusCatalogDescriptor(catoid: trimmedHint, title: "Catalog")]
        }

        let current = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedBaseURL)
        return [ModernCampusCatalogDescriptor(catoid: current, title: "Catalog")]
    }

    /// Best-effort resolver for UI paths that should fall back to a hinted `catoid` when list discovery fails.
    static func resolveCatalogsForIngestLenient(
        normalizedBaseURL: String,
        catoidHint: String?
    ) async -> [ModernCampusCatalogDescriptor] {
        if let resolved = try? await resolveCatalogsForIngest(
            normalizedBaseURL: normalizedBaseURL,
            catoidHint: catoidHint
        ), !resolved.isEmpty {
            return resolved
        }

        let trimmedHint = catoidHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedHint.isEmpty {
            return [ModernCampusCatalogDescriptor(catoid: trimmedHint, title: "Catalog")]
        }
        return []
    }

    /// Merges program rows across catalog editions using the same dedup key as catalog sync.
    static func mergeProgramsAcrossCatalogs(
        _ programsByCatalog: [(catoid: String, programs: [ScrapedProgram])]
    ) -> [ScrapedProgram] {
        var merged: [String: ScrapedProgram] = [:]
        merged.reserveCapacity(programsByCatalog.reduce(0) { $0 + $1.programs.count })

        for bucket in programsByCatalog {
            let catoid = bucket.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            for program in bucket.programs {
                let normalizedURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
                let dedupStem = normalizedURL.isEmpty
                    ? program.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    : normalizedURL
                let dedupKey = "\(catoid)|\(dedupStem)"
                merged[dedupKey] = program
            }
        }

        return Array(merged.values)
    }
}
