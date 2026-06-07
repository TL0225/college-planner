// UniversalCatalogScraperIRConsumer.swift
// Feature: Catalog
// Purpose: Build CatalogDocumentIR from CatalogGraph + UniversalCatalogScraper hierarchy pages.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum UniversalCatalogScraperIRConsumer {
    static func buildDocumentIR(
        graph: CatalogGraph,
        schoolID: String,
        catalogVersionID: String,
        layoutProfileID: String = "universal-scraper",
        catoid: String? = nil,
        maxPages: Int = 48
    ) async -> CatalogDocumentIR? {
        guard CatalogPlatformFlags.documentIREnabled else { return nil }
        let filteredURLs: [String]
        if let catoid, !catoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filteredURLs = graph.extractablePageURLs.filter { url in
                url.contains("catoid=\(catoid)") || url.contains("catoid%3D\(catoid)")
            }
        } else {
            filteredURLs = graph.extractablePageURLs
        }
        let urls = Array(filteredURLs.prefix(max(1, maxPages)))
        guard !urls.isEmpty else { return nil }

        var nodes: [CatalogDocumentNode] = []
        let ingestRunID = UUID()
        for urlString in urls {
            guard let pageURL = URL(string: urlString) else { continue }
            do {
                let html = try await ModernCampusEngine.fetchHTMLPublic(urlString)
                let analysis = CatalogModernCampusHTMLAnalyzer.analyze(
                    html: html,
                    sourceURL: pageURL,
                    schoolID: schoolID,
                    catalogVersionID: catalogVersionID
                )
                nodes.append(contentsOf: analysis.nodes)
            } catch {
                continue
            }
        }
        guard !nodes.isEmpty else { return nil }
        return CatalogDocumentIR.build(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            engine: "moderncampus",
            layoutProfileID: layoutProfileID,
            nodes: nodes,
            layoutConfidence: CatalogExtractionConfidence(
                score: 0.7,
                reasons: ["universal_scraper_ir", "pages:\(urls.count)", "nodes:\(nodes.count)"]
            ),
            ingestRunID: ingestRunID
        )
    }

    static func mergeNodes(_ incoming: [CatalogDocumentNode], into existing: inout [CatalogDocumentNode]) {
        var signatures = Set(existing.map { $0.elementSignature ?? $0.id.uuidString })
        for node in incoming {
            let sig = node.elementSignature ?? node.id.uuidString
            guard !signatures.contains(sig) else { continue }
            signatures.insert(sig)
            existing.append(node)
        }
    }

    static func buildDocumentIR(
        schoolID: String,
        catalogVersionID: String,
        nodes: [CatalogDocumentNode],
        layoutProfileID: String = "universal-scraper"
    ) -> CatalogDocumentIR? {
        guard CatalogPlatformFlags.documentIREnabled, !nodes.isEmpty else { return nil }
        return CatalogDocumentIR.build(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            engine: "moderncampus",
            layoutProfileID: layoutProfileID,
            nodes: nodes,
            layoutConfidence: CatalogExtractionConfidence(
                score: 0.72,
                reasons: ["universal_scraper_stream", "nodes:\(nodes.count)"]
            )
        )
    }
}
