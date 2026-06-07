// ModernCampusIRPipeline.swift
// Feature: Catalog
// Purpose: Modern Campus ingest — HTML analyze → classify → profile extract (stub).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum ModernCampusIRPipeline {
    struct PageParseResult: Sendable {
        let courses: [CatalogCourse]
        let programs: [ScrapedProgram]
        let ir: CatalogDocumentIR
    }

    static func parsePage(
        html: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String
    ) -> PageParseResult {
        let (profileID, confidenceScore, analysis, versionID, host) = analyzePage(
            html: html,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: catalogVersionID
        )
        return finishParse(
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID,
            host: host,
            analysis: analysis,
            profileID: profileID,
            confidenceScore: confidenceScore
        )
    }

    static func parsePageAsync(
        html: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String
    ) async -> PageParseResult {
        let (profileID, confidenceScore, analysis, versionID, host) = analyzePage(
            html: html,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: catalogVersionID
        )
        let (resolvedID, resolvedConfidence) = await CatalogLayoutLLMClassifier.classifyModernCampus(
            domFeatures: analysis.domFeatures,
            host: host
        )
        return finishParse(
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID,
            host: host,
            analysis: analysis,
            profileID: resolvedID,
            confidenceScore: resolvedConfidence
        )
    }

    private static func analyzePage(
        html: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String
    ) -> (profileID: String, confidence: Double, analysis: ModernCampusDOMAnalysis, versionID: String, host: String?) {
        let versionID = catalogVersionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? schoolID
            : catalogVersionID
        let host = pageURL.host
        let analysis = CatalogModernCampusHTMLAnalyzer.analyze(
            html: html,
            sourceURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID
        )
        let (profileID, confidenceScore) = ModernCampusLayoutProfileID.classify(
            domFeatures: analysis.domFeatures,
            host: host
        )
        return (profileID, confidenceScore, analysis, versionID, host)
    }

    private static func finishParse(
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String,
        host: String?,
        analysis: ModernCampusDOMAnalysis,
        profileID: String,
        confidenceScore: Double
    ) -> PageParseResult {
        let confidence = CatalogExtractionConfidence(
            score: confidenceScore,
            reasons: [
                "layout:\(profileID)",
                "n2:\(analysis.domFeatures.n2LinksCount)",
                "programs:\(analysis.domFeatures.previewProgramLinkCount)"
            ]
        )
        let ir = CatalogModernCampusHTMLAnalyzer.buildIR(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            analysis: analysis,
            layoutProfileID: profileID,
            layoutConfidence: confidence
        )

        var profile = ModernCampusLayoutProfileID.resolve(profileID)
        let config = ModernCampusProfileConfig.forHost(host)
        var extracted = profile.extractEntities(from: ir, pageURL: pageURL, config: config)

        if extracted.programs.isEmpty, profile != .sidebarN2Links {
            profile = .sidebarN2Links
            extracted = profile.extractEntities(from: ir, pageURL: pageURL, config: config)
        }

        return PageParseResult(courses: extracted.courses, programs: extracted.programs, ir: ir)
    }
}
