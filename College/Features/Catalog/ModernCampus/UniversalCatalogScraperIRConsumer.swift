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
        maxPages: Int = 48,
        programsIndexOnly: Bool = false,
        politeness: CatalogFetchPoliteness = .interactiveBackground,
        pageFetchCache: ModernCampusPageFetchCache? = nil
    ) async -> CatalogDocumentIR? {
        guard CatalogPlatformFlags.documentIREnabled else { return nil }
        let filteredURLs: [String]
        if let catoid, !catoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedCatoid = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            filteredURLs = graph.nodes
                .filter { node in
                    let matchesCatoid = node.url.contains("catoid=\(trimmedCatoid)")
                        || node.url.contains("catoid%3D\(trimmedCatoid)")
                    guard matchesCatoid else { return false }
                    if programsIndexOnly {
                        return node.kind == .programListing || node.kind == .programDetail
                    }
                    return [.programDetail, .courseListing, .courseDetail, .programListing].contains(node.kind)
                }
                .map(\.url)
                .sorted()
        } else {
            filteredURLs = graph.extractablePageURLs
        }
        let candidateURLs = filteredURLs
        let urls = Array(candidateURLs.prefix(max(1, maxPages)))
        guard !urls.isEmpty else { return nil }

        var nodes: [CatalogDocumentNode] = []
        let ingestRunID = UUID()
        for urlString in urls {
            guard let pageURL = URL(string: urlString) else { continue }
            do {
                let html: String
                if let pageFetchCache {
                    html = try await pageFetchCache.fetchHTML(urlString, politeness: politeness)
                } else {
                    html = try await ModernCampusEngine.fetchHTMLPublic(urlString, politeness: politeness)
                }
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
        var signatures = Set(existing.map { canonicalNodeSignature($0) })
        for node in incoming {
            let sig = canonicalNodeSignature(node)
            guard !signatures.contains(sig) else { continue }
            signatures.insert(sig)
            existing.append(node)
        }
    }

    private static func canonicalNodeSignature(_ node: CatalogDocumentNode) -> String {
        let url = (node.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (node.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let signature = (node.elementSignature ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(node.kind.rawValue)|\(signature)|\(url)|\(text)"
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
