// CourseLeafIRPipeline.swift
// Feature: Catalog
// Purpose: CourseLeaf ingest — DOM analyze → classify → profile extract → programs.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CourseLeafIRPipeline {
    typealias PageParseResult = CourseLeafEngine.PageParseResult

    static func provenance(
        pageURL: URL,
        layoutProfileID: String,
        documentNodeID: UUID,
        catalogVersionID: String,
        ingestRunID: UUID
    ) -> CatalogProvenance {
        CatalogProvenance(
            sourceURL: pageURL.absoluteString,
            layoutProfileID: layoutProfileID,
            documentNodeID: documentNodeID,
            catalogVersionID: catalogVersionID,
            ingestRunID: ingestRunID
        )
    }

    static func parsePage(
        xml: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String,
        parseRequirements: Bool
    ) -> PageParseResult {
        let versionID = catalogVersionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? schoolID
            : catalogVersionID

        guard xml.contains("<courseleaf") else {
            return PageParseResult(courses: [], programs: [], layoutProfileID: nil, layoutConfidence: 0)
        }

        let analysis = CatalogCourseLeafDOMAnalyzer.analyze(
            xml: xml,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID
        )
        let (profileID, confidenceScore) = CourseLeafLayoutClassifier.classify(domFeatures: analysis.domFeatures)
        return finishParse(
            xml: xml,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID,
            parseRequirements: parseRequirements,
            analysis: analysis,
            classifiedProfileID: profileID,
            confidenceScore: confidenceScore
        )
    }

    static func parsePageAsync(
        xml: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String,
        parseRequirements: Bool
    ) async -> PageParseResult {
        let versionID = catalogVersionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? schoolID
            : catalogVersionID

        guard xml.contains("<courseleaf") else {
            return PageParseResult(courses: [], programs: [], layoutProfileID: nil, layoutConfidence: 0)
        }

        let analysis = CatalogCourseLeafDOMAnalyzer.analyze(
            xml: xml,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID
        )
        let (profileID, confidenceScore) = await CatalogLayoutLLMClassifier.classifyCourseLeaf(domFeatures: analysis.domFeatures)
        return finishParse(
            xml: xml,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: versionID,
            parseRequirements: parseRequirements,
            analysis: analysis,
            classifiedProfileID: profileID,
            confidenceScore: confidenceScore
        )
    }

    private static func finishParse(
        xml: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String,
        parseRequirements: Bool,
        analysis: CatalogCourseLeafDOMAnalysis,
        classifiedProfileID: String,
        confidenceScore: Double
    ) -> PageParseResult {
        let classifiedProfile = CourseLeafLayoutProfileID.resolve(classifiedProfileID)
        let routingConfig = CatalogLayoutProfileRegistry.legacyCrawlConfig(forSchoolID: schoolID)
        let profile = CatalogLayoutProfileRegistry.resolvedProfileID(
            forSchoolID: schoolID,
            classifiedProfile: classifiedProfile
        )
        let config = CourseLeafProfileConfig.config(for: profile)
        let confidence = CatalogExtractionConfidence(
            score: confidenceScore,
            reasons: [
                "layout:\(classifiedProfileID)",
                CatalogPlatformFlags.layoutLLMEnabled ? "llm:optional" : "deterministic",
                "detailCode:\(analysis.domFeatures.detailCodeCount)",
                "dl:\(analysis.domFeatures.dlCourseblockCount)"
            ]
        )
        let ir = CatalogCourseLeafDOMAnalyzer.buildIR(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            analysis: analysis,
            layoutProfileID: profile.rawValue,
            layoutConfidence: confidence
        )

        var courses: [CatalogCourse] = []
        if shouldParseCourses(pageURL: pageURL, config: routingConfig) {
            var activeProfile = profile
            var extracted = activeProfile.extractEntities(from: ir, pageURL: pageURL, config: config, xml: xml)
            if extracted.courses.isEmpty, activeProfile != .profileDefault {
                activeProfile = .profileDefault
                let fallbackConfig = CourseLeafProfileConfig.config(for: activeProfile)
                extracted = activeProfile.extractEntities(from: ir, pageURL: pageURL, config: fallbackConfig, xml: xml)
            }
            courses = extracted.courses
        }

        let programs: [ScrapedProgram]
        if shouldParsePrograms(pageURL: pageURL, config: routingConfig) {
            programs = CourseLeafEngine.parseProgramsForTests(
                from: xml,
                pageURL: pageURL,
                profileConfig: routingConfig,
                schoolID: schoolID,
                parseRequirements: parseRequirements
            )
        } else {
            programs = []
        }

        return PageParseResult(
            courses: courses,
            programs: programs,
            layoutProfileID: profile.rawValue,
            layoutConfidence: confidence.score
        )
    }

    private static func shouldParseCourses(pageURL: URL, config: CourseLeafProfileConfig) -> Bool {
        let path = pageURL.path.lowercased()
        return config.coursePagePathHints.contains(where: { path.contains($0) })
    }

    private static func shouldParsePrograms(pageURL: URL, config: CourseLeafProfileConfig) -> Bool {
        let path = pageURL.path.lowercased()
        return config.programPagePathHints.contains(where: { path.contains($0) })
    }
}
