// AssistantAcademicWebPolicy.swift
// Feature: Assistant
// Purpose: Official-host registry and web source trust (Ship B/C).

import Foundation

enum AssistantSourceTrustTier: String, Codable, Sendable {
    case planner
    case catalog
    case officialWeb
    case webGeneral
    case modelKnowledge
}

enum AssistantAcademicWebPolicy {
    @MainActor
    static func officialHosts(
        persistence: CollegePersistence,
        programIdentity: AssistantProgramIdentityContext?
    ) -> Set<String> {
        var hosts = Set<String>()
        if let metadata = persistence.activeSchoolPolicyMetadata() {
            for raw in [metadata.catalogURL, metadata.registrarURL, metadata.officialWebsiteURL] {
                if let host = host(from: raw) { hosts.insert(host) }
            }
        }
        if let programURL = programIdentity?.programURL ?? persistence.resolveSelectedMajorProgramURL(),
           let host = host(from: programURL) {
            hosts.insert(host)
        }
        let jurisdiction = AssistantFinancialAidPolicy.resolveJurisdiction(
            metadata: persistence.activeSchoolPolicyMetadata()
        )
        hosts.formUnion(AssistantFinancialAidPolicy.policyHosts(for: jurisdiction))
        return hosts
    }

    static func trustTier(for source: AssistantReplySource, officialHosts: Set<String>) -> AssistantSourceTrustTier {
        switch source.toolName {
        case "getStudentLearningProfile", "explainRequirements", "getStudentProfile", "getProgramProgress":
            return .planner
        case "semanticCatalogSearch", "searchCatalogCourses":
            return .catalog
        default:
            break
        }
        if let url = source.url, let host = URL(string: url)?.host?.lowercased() {
            if officialHosts.contains(host) { return .officialWeb }
            return .webGeneral
        }
        return .webGeneral
    }

    static func userFacingLabel(for tier: AssistantSourceTrustTier) -> String {
        switch tier {
        case .planner, .catalog:
            return "Your data"
        case .officialWeb:
            return "Official source"
        case .webGeneral, .modelKnowledge:
            return "General web"
        }
    }

    static func filterForSynthesis(
        sources: [AssistantReplySource],
        intent: String?,
        officialHosts: Set<String>
    ) -> [AssistantReplySource] {
        guard intent == "degree_policy_lookup" else { return sources }
        return sources.filter { source in
            let tier = trustTier(for: source, officialHosts: officialHosts)
            return tier == .planner || tier == .catalog || tier == .officialWeb
        }
    }

    static func isOfficialHost(_ host: String, officialHosts: Set<String>) -> Bool {
        officialHosts.contains(host.lowercased())
    }

    static func reorderSearxHits<T>(_ hits: [T], url: (T) -> String, officialHosts: Set<String>) -> [T] {
        guard !officialHosts.isEmpty else { return hits }
        let preferred = hits.filter { hit in
            guard let h = URL(string: url(hit))?.host?.lowercased() else { return false }
            return officialHosts.contains(h)
        }
        if preferred.isEmpty { return hits }
        let remaining = hits.filter { hit in
            guard let h = URL(string: url(hit))?.host?.lowercased() else { return true }
            return !officialHosts.contains(h)
        }
        return preferred + remaining
    }

    private static func host(from urlString: String?) -> String? {
        guard let urlString,
              let host = URL(string: urlString)?.host?.lowercased(),
              !host.isEmpty else { return nil }
        return host
    }

    static func validatePolicyReply(
        sources: [AssistantReplySource],
        intent: String?
    ) -> Bool {
        guard intent == "degree_policy_lookup" else { return true }
        return sources.contains { src in
            switch src.trustTier {
            case .planner, .catalog, .officialWeb:
                return true
            default:
                return false
            }
        }
    }
}
