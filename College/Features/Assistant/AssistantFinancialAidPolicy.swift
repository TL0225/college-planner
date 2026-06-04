// AssistantFinancialAidPolicy.swift
// Feature: Assistant
// Purpose: Assistant module — UniversityPolicyJurisdiction.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct UniversityPolicyJurisdiction: Sendable, Equatable {
    let schoolID: String?
    let unitID: String?
    let opeID: String?
    let countryCode: String?
    let stateCode: String?
    let universityName: String
    let officialWebsiteURL: String?
    let catalogURL: String?
    let financialAidURL: String?
    let registrarURL: String?
    let stateAidAgencyURL: String?
    let evidenceSource: String

    init(
        schoolID: String? = nil,
        unitID: String? = nil,
        opeID: String? = nil,
        countryCode: String?,
        stateCode: String?,
        universityName: String,
        officialWebsiteURL: String? = nil,
        catalogURL: String? = nil,
        financialAidURL: String? = nil,
        registrarURL: String? = nil,
        stateAidAgencyURL: String? = nil,
        evidenceSource: String
    ) {
        self.schoolID = schoolID
        self.unitID = unitID
        self.opeID = opeID
        self.countryCode = countryCode
        self.stateCode = stateCode
        self.universityName = universityName
        self.officialWebsiteURL = officialWebsiteURL
        self.catalogURL = catalogURL
        self.financialAidURL = financialAidURL
        self.registrarURL = registrarURL
        self.stateAidAgencyURL = stateAidAgencyURL
        self.evidenceSource = evidenceSource
    }

    var allowsFederalFAFSA: Bool {
        normalizedCountry == "us" || normalizedCountry == "usa" || normalizedCountry == "united states"
    }

    var allowsStateAidRouting: Bool {
        allowsFederalFAFSA && stateCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var normalizedStateCode: String? {
        let trimmed = (stateCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    var isUniversityAtBuffalo: Bool {
        let normalized = universityName.lowercased()
        return normalized.contains("university at buffalo") ||
            normalized.contains("state university of new york at buffalo") ||
            normalized == "ub"
    }

    var policySummary: String {
        let suffix = evidenceSource.isEmpty ? "" : " [\(evidenceSource)]"
        if let state = normalizedStateCode, allowsFederalFAFSA {
            let stateProgram = StateAidRegistry.programLabel(for: state) ?? "\(state) state aid"
            return "Federal(US FAFSA/FSA) + \(stateProgram)\(suffix)"
        }
        if allowsFederalFAFSA {
            return "Federal(US FAFSA/FSA)\(suffix)"
        }
        return "Non-US/unknown (no FAFSA/state-aid-first policy routing)\(suffix)"
    }

    private var normalizedCountry: String {
        (countryCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}

enum AssistantFinancialAidPolicy {
    private struct KnownSchoolMetadata {
        let aliases: [String]
        let countryCode: String
        let stateCode: String?
        let officialWebsiteURL: String?
        let catalogURL: String?
        let financialAidURL: String?
        let registrarURL: String?
        let evidenceSource: String
    }

    private static let knownSchools: [KnownSchoolMetadata] = [
        .init(
            aliases: [
                "university at buffalo",
                "state university of new york at buffalo",
                "suny buffalo",
                "ub"
            ],
            countryCode: "US",
            stateCode: "NY",
            officialWebsiteURL: "https://www.buffalo.edu/",
            catalogURL: "https://catalogs.buffalo.edu/",
            financialAidURL: "https://financialaid.buffalo.edu/",
            registrarURL: "https://registrar.buffalo.edu/",
            evidenceSource: "AssistantPolicyEvidenceStore.universityAtBuffalo"
        )
    ]

    static func resolveJurisdiction(metadata: SchoolPolicyMetadata?) -> UniversityPolicyJurisdiction {
        guard let metadata else { return resolveJurisdiction(activeUniversityName: nil) }
        return UniversityPolicyJurisdiction(
            schoolID: metadata.schoolID,
            unitID: metadata.unitID,
            opeID: metadata.opeID,
            countryCode: metadata.countryCode,
            stateCode: metadata.stateCode,
            universityName: metadata.schoolName,
            officialWebsiteURL: metadata.officialWebsiteURL,
            catalogURL: metadata.catalogURL,
            financialAidURL: metadata.financialAidURL,
            registrarURL: metadata.registrarURL,
            stateAidAgencyURL: metadata.stateAidAgencyURL,
            evidenceSource: metadata.sourceDescription
        )
    }

    // Conservative defaults: only infer US/state when a strong match exists.
    static func resolveJurisdiction(activeUniversityName: String?) -> UniversityPolicyJurisdiction {
        let name = (activeUniversityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name.lowercased()
        if let known = knownSchools.first(where: { school in
            school.aliases.contains { alias in
                normalized == alias || normalized.contains(alias)
            }
        }) {
            return UniversityPolicyJurisdiction(
                schoolID: nil,
                unitID: nil,
                opeID: nil,
                countryCode: known.countryCode,
                stateCode: known.stateCode,
                universityName: name,
                officialWebsiteURL: known.officialWebsiteURL,
                catalogURL: known.catalogURL,
                financialAidURL: known.financialAidURL,
                registrarURL: known.registrarURL,
                stateAidAgencyURL: known.stateCode.flatMap { StateAidRegistry.agencyURL(for: $0) },
                evidenceSource: known.evidenceSource
            )
        }

        let isLikelyUS = !name.isEmpty && !containsNonUSMarker(normalized)
        let inferredState = inferStateCode(from: normalized)

        return UniversityPolicyJurisdiction(
            schoolID: nil,
            unitID: nil,
            opeID: nil,
            countryCode: isLikelyUS ? "US" : nil,
            stateCode: inferredState,
            universityName: name,
            officialWebsiteURL: nil,
            catalogURL: nil,
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: inferredState.flatMap { StateAidRegistry.agencyURL(for: $0) },
            evidenceSource: isLikelyUS ? "name heuristic" : "unknown"
        )
    }

    static func policyHosts(for jurisdiction: UniversityPolicyJurisdiction) -> Set<String> {
        var hosts = AssistantPolicyEvidenceStore.hosts(for: jurisdiction)
        if jurisdiction.allowsFederalFAFSA {
            hosts.formUnion([
                "studentaid.gov",
                "www.studentaid.gov",
                "fafsa.gov",
                "fsapartners.ed.gov",
                "ed.gov",
                "www.ed.gov"
            ])
        }
        if let host = host(from: jurisdiction.financialAidURL) {
            hosts.insert(host)
        }
        if let host = host(from: jurisdiction.catalogURL) {
            hosts.insert(host)
        }
        if let state = jurisdiction.normalizedStateCode {
            hosts.formUnion(StateAidRegistry.hosts(for: state))
        }
        return hosts
    }

    private static func inferStateCode(from normalizedName: String) -> String? {
        let hints: [(String, String)] = [
            ("new york", "NY"), ("suny", "NY"), ("cuny", "NY"),
            ("california", "CA"), ("cal state", "CA"), ("university of california", "CA"),
            ("texas", "TX"), ("pennsylvania", "PA"), ("florida", "FL"), ("georgia", "GA"),
            ("illinois", "IL"), ("ohio", "OH"), ("michigan", "MI"), ("north carolina", "NC"),
            ("virginia", "VA"), ("washington", "WA"), ("new jersey", "NJ"), ("massachusetts", "MA")
        ]
        return hints.first { normalizedName.contains($0.0) }?.1
    }

    private static func host(from urlString: String?) -> String? {
        guard let urlString, let host = URL(string: urlString)?.host?.lowercased() else { return nil }
        return host
    }

    private static func containsNonUSMarker(_ normalizedName: String) -> Bool {
        let markers = [
            "canada", "toronto", "ontario", "uk", "united kingdom", "england",
            "australia", "singapore", "india", "germany", "france", "ireland"
        ]
        return markers.contains { normalizedName.contains($0) }
    }
}
