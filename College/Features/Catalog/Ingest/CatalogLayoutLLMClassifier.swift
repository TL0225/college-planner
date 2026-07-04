// CatalogLayoutLLMClassifier.swift
// Feature: Catalog
// Purpose: LLM fallback for ambiguous layout profile classification (Tier 2, last resort).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogLayoutLLMClassifier {
    private static let ambiguousConfidenceThreshold = 0.55
    private static let scoreMarginThreshold = 0.08

    struct CourseLeafScorecard: Sendable {
        let profileID: String
        let confidence: Double
        let scores: [(CourseLeafLayoutProfileID, Double)]
    }

    struct ModernCampusScorecard: Sendable {
        let profileID: String
        let confidence: Double
        let scores: [(ModernCampusLayoutProfileID, Double)]
    }

    static func classifyCourseLeaf(domFeatures: CatalogDOMFeatures) async -> (profileID: String, confidence: Double) {
        let scorecard = courseLeafScorecard(domFeatures: domFeatures)
        guard CatalogPlatformFlags.layoutLLMEnabled,
              shouldUseLLM(scorecard.confidence, scores: scorecard.scores.map(\.1)),
              let resolved = await resolveCourseLeafWithLLM(domFeatures: domFeatures, scorecard: scorecard) else {
            return (scorecard.profileID, scorecard.confidence)
        }
        return resolved
    }

    static func classifyModernCampus(
        domFeatures: ModernCampusDOMFeatures,
        host: String?
    ) async -> (profileID: String, confidence: Double) {
        let scorecard = modernCampusScorecard(domFeatures: domFeatures, host: host)
        guard CatalogPlatformFlags.layoutLLMEnabled,
              shouldUseLLM(scorecard.confidence, scores: scorecard.scores.map(\.1)),
              let resolved = await resolveModernCampusWithLLM(domFeatures: domFeatures, host: host, scorecard: scorecard) else {
            return (scorecard.profileID, scorecard.confidence)
        }
        return resolved
    }

    static func shouldUseLLM(_ confidence: Double, scores: [Double]) -> Bool {
        if confidence < ambiguousConfidenceThreshold { return true }
        let sorted = scores.sorted(by: >)
        guard sorted.count >= 2 else { return false }
        return (sorted[0] - sorted[1]) < scoreMarginThreshold
    }

    static func courseLeafScorecard(domFeatures: CatalogDOMFeatures) -> CourseLeafScorecard {
        let (profileID, confidence) = CourseLeafLayoutClassifier.classify(domFeatures: domFeatures)
        let scores: [(CourseLeafLayoutProfileID, Double)] = [
            (.profileA, scoreCourseLeaf(domFeatures, profile: .profileA)),
            (.profileB, scoreCourseLeaf(domFeatures, profile: .profileB)),
            (.profileC, scoreCourseLeaf(domFeatures, profile: .profileC)),
            (.profileDefault, scoreCourseLeaf(domFeatures, profile: .profileDefault))
        ]
        return CourseLeafScorecard(profileID: profileID, confidence: confidence, scores: scores)
    }

    static func modernCampusScorecard(domFeatures: ModernCampusDOMFeatures, host: String?) -> ModernCampusScorecard {
        let (profileID, confidence) = ModernCampusLayoutProfileID.classify(domFeatures: domFeatures, host: host)
        let config = ModernCampusProfileConfig.forHost(host)
        let entityScore = Double(domFeatures.entityPageLinkCount) * 5.0
            + (config.prefersEntityPageProgramDiscovery ? 4.0 : 0.0)
        let sidebarScore = Double(domFeatures.n2LinksCount) * 2.0 + Double(domFeatures.blockN2TableCount)
        let tableScore = Double(domFeatures.blockN2TableCount) * 4.0 + Double(domFeatures.n2LinksCount)
        let programScore = Double(domFeatures.previewProgramLinkCount) * 3.0
        let scores: [(ModernCampusLayoutProfileID, Double)] = [
            (.entityPreviewProgram, entityScore + programScore),
            (.blockN2Table, tableScore),
            (.sidebarN2Links, sidebarScore + programScore * 0.5)
        ]
        return ModernCampusScorecard(profileID: profileID, confidence: confidence, scores: scores)
    }

    private static func scoreCourseLeaf(_ features: CatalogDOMFeatures, profile: CourseLeafLayoutProfileID) -> Double {
        switch profile {
        case .profileA:
            return Double(features.detailCodeCount) * 4.0 + Double(features.detailTitleCount) * 1.5
        case .profileB:
            return Double(features.courseblocktitleCount) * 4.0 + Double(features.divCourseblockCount)
        case .profileC:
            return Double(features.dlCourseblockCount) * 6.0
        case .profileDefault:
            return Double(features.divCourseblockCount + features.dlCourseblockCount + features.scCourselistCount)
        }
    }

    private static func resolveCourseLeafWithLLM(
        domFeatures: CatalogDOMFeatures,
        scorecard: CourseLeafScorecard
    ) async -> (profileID: String, confidence: Double)? {
        guard AppleSiliconPlatform.isMLXCompatible else { return nil }
        let spec = ModelSpec.jsonWorker
        guard let modelPath = try? await ModelManager.shared.ensureModelInstalled(spec, progress: { _ in }) else {
            return nil
        }
        let prompt = """
/no_think
Classify this CourseLeaf catalog page layout. Return ONLY JSON:
{"profileID":"profileA|profileB|profileC|profileDefault","confidence":0.0}

DOM features: detailCode=\(domFeatures.detailCodeCount), courseblocktitle=\(domFeatures.courseblocktitleCount), divCourseblock=\(domFeatures.divCourseblockCount), dlCourseblock=\(domFeatures.dlCourseblockCount), sc_courselist=\(domFeatures.scCourselistCount)
Deterministic guess: \(scorecard.profileID) @ \(String(format: "%.2f", scorecard.confidence))
"""
        return await parseProfileResponse(
            prompt: prompt,
            modelPath: modelPath,
            allowed: Set(CourseLeafLayoutProfileID.allCases.map(\.rawValue))
        )
    }

    private static func resolveModernCampusWithLLM(
        domFeatures: ModernCampusDOMFeatures,
        host: String?,
        scorecard: ModernCampusScorecard
    ) async -> (profileID: String, confidence: Double)? {
        guard AppleSiliconPlatform.isMLXCompatible else { return nil }
        let spec = ModelSpec.jsonWorker
        guard let modelPath = try? await ModelManager.shared.ensureModelInstalled(spec, progress: { _ in }) else {
            return nil
        }
        let prompt = """
/no_think
Classify this Modern Campus catalog page layout. Return ONLY JSON:
{"profileID":"sidebarN2Links|blockN2Table|entityPreviewProgram","confidence":0.0}

Host: \(host ?? "unknown")
DOM features: n2=\(domFeatures.n2LinksCount), blockN2=\(domFeatures.blockN2TableCount), previewProgram=\(domFeatures.previewProgramLinkCount), entityPage=\(domFeatures.entityPageLinkCount)
Deterministic guess: \(scorecard.profileID) @ \(String(format: "%.2f", scorecard.confidence))
"""
        return await parseProfileResponse(
            prompt: prompt,
            modelPath: modelPath,
            allowed: Set(ModernCampusLayoutProfileID.allCases.map(\.rawValue))
        )
    }

    private static func parseProfileResponse(
        prompt: String,
        modelPath: URL,
        allowed: Set<String>
    ) async -> (profileID: String, confidence: Double)? {
        do {
            let raw = try await LocalLLMRunner.shared.generateJSON(prompt: prompt, modelPath: modelPath, maxTokens: 96)
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let profileID = json["profileID"] as? String,
                  allowed.contains(profileID) else {
                return nil
            }
            let confidence = (json["confidence"] as? Double) ?? (json["confidence"] as? NSNumber)?.doubleValue ?? 0.65
            return (profileID, min(max(confidence, 0.2), 1.0))
        } catch {
            return nil
        }
    }
}
