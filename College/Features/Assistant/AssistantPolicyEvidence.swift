// AssistantPolicyEvidence.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantPolicyJurisdiction.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct AssistantPolicyJurisdiction: Codable, Sendable, Equatable {
    let key: String

    static let federalUS = AssistantPolicyJurisdiction(key: "US")
    static let newYork = AssistantPolicyJurisdiction(key: "US-NY")
    static let universityAtBuffalo = AssistantPolicyJurisdiction(key: "institution:university-at-buffalo")

    static func state(_ stateCode: String) -> AssistantPolicyJurisdiction {
        AssistantPolicyJurisdiction(key: "US-\(stateCode.uppercased())")
    }

    static func institution(_ id: String) -> AssistantPolicyJurisdiction {
        AssistantPolicyJurisdiction(key: "institution:\(id.lowercased())")
    }
}

enum AssistantPolicyTopic: String, Codable, Sendable, CaseIterable {
    case fafsa
    case pell
    case stateAid
    case enrollmentIntensity
    case sap
    case verification
    case schoolFinancialAid
    case academicCatalog
}

enum StateAidRegistry {
    struct StateAidProgram: Codable, Sendable, Equatable {
        let stateCode: String
        let label: String
        let agencyTitle: String
        let agencyURL: String
        let sourceHost: String
        let summary: String
    }

    static let programs: [StateAidProgram] = [
        .init(stateCode: "AL", label: "Alabama state aid", agencyTitle: "Alabama Commission on Higher Education", agencyURL: "https://ache.edu/", sourceHost: "ache.edu", summary: "Official Alabama higher-education agency source for state aid and program verification."),
        .init(stateCode: "AK", label: "Alaska state aid", agencyTitle: "Alaska Commission on Postsecondary Education", agencyURL: "https://acpe.alaska.gov/", sourceHost: "acpe.alaska.gov", summary: "Official Alaska postsecondary education source for state aid and program verification."),
        .init(stateCode: "AZ", label: "Arizona state aid", agencyTitle: "Arizona Board of Regents", agencyURL: "https://www.azregents.edu/", sourceHost: "azregents.edu", summary: "Official Arizona higher-education source for state aid and program verification."),
        .init(stateCode: "AR", label: "Arkansas state aid", agencyTitle: "Arkansas Division of Higher Education", agencyURL: "https://sams.adhe.edu/", sourceHost: "sams.adhe.edu", summary: "Official Arkansas state aid source for scholarships and grants."),
        .init(stateCode: "CA", label: "California state aid / Cal Grant", agencyTitle: "California Student Aid Commission", agencyURL: "https://www.csac.ca.gov/", sourceHost: "csac.ca.gov", summary: "Official California source for Cal Grant and state financial-aid program verification."),
        .init(stateCode: "CO", label: "Colorado state aid", agencyTitle: "Colorado Department of Higher Education", agencyURL: "https://cdhe.colorado.gov/", sourceHost: "cdhe.colorado.gov", summary: "Official Colorado higher-education source for state aid verification."),
        .init(stateCode: "CT", label: "Connecticut state aid", agencyTitle: "Connecticut Office of Higher Education", agencyURL: "https://www.ohe.ct.gov/", sourceHost: "ohe.ct.gov", summary: "Official Connecticut higher-education source for state aid verification."),
        .init(stateCode: "DE", label: "Delaware state aid", agencyTitle: "Delaware Higher Education Office", agencyURL: "https://www.doe.k12.de.us/domain/230", sourceHost: "doe.k12.de.us", summary: "Official Delaware source for scholarships and state aid verification."),
        .init(stateCode: "FL", label: "Florida state aid / Bright Futures", agencyTitle: "Florida Student Scholarship & Grant Programs", agencyURL: "https://www.floridastudentfinancialaidsg.org/", sourceHost: "floridastudentfinancialaidsg.org", summary: "Official Florida source for Bright Futures and state aid verification."),
        .init(stateCode: "GA", label: "Georgia state aid / HOPE", agencyTitle: "Georgia Student Finance Commission", agencyURL: "https://www.gafutures.org/", sourceHost: "gafutures.org", summary: "Official Georgia source for HOPE and state aid verification."),
        .init(stateCode: "HI", label: "Hawaii state aid", agencyTitle: "Hawaii P-20 Partnerships for Education", agencyURL: "https://collegeishawaii.com/", sourceHost: "collegeishawaii.com", summary: "Official Hawaii college affordability and aid resource."),
        .init(stateCode: "ID", label: "Idaho state aid", agencyTitle: "Idaho State Board of Education", agencyURL: "https://boardofed.idaho.gov/", sourceHost: "boardofed.idaho.gov", summary: "Official Idaho higher-education source for state aid verification."),
        .init(stateCode: "IL", label: "Illinois state aid / MAP", agencyTitle: "Illinois Student Assistance Commission", agencyURL: "https://www.isac.org/", sourceHost: "isac.org", summary: "Official Illinois source for MAP grants and state aid verification."),
        .init(stateCode: "IN", label: "Indiana state aid", agencyTitle: "Indiana Commission for Higher Education", agencyURL: "https://www.in.gov/che/", sourceHost: "in.gov", summary: "Official Indiana higher-education source for state aid verification."),
        .init(stateCode: "IA", label: "Iowa state aid", agencyTitle: "Iowa College Aid", agencyURL: "https://educate.iowa.gov/higher-ed/student-aid", sourceHost: "educate.iowa.gov", summary: "Official Iowa student aid source."),
        .init(stateCode: "KS", label: "Kansas state aid", agencyTitle: "Kansas Board of Regents", agencyURL: "https://www.kansasregents.org/students/student_financial_aid", sourceHost: "kansasregents.org", summary: "Official Kansas state financial-aid source."),
        .init(stateCode: "KY", label: "Kentucky state aid", agencyTitle: "Kentucky Higher Education Assistance Authority", agencyURL: "https://www.kheaa.com/", sourceHost: "kheaa.com", summary: "Official Kentucky source for state aid verification."),
        .init(stateCode: "LA", label: "Louisiana state aid / TOPS", agencyTitle: "Louisiana Office of Student Financial Assistance", agencyURL: "https://mylosfa.la.gov/", sourceHost: "mylosfa.la.gov", summary: "Official Louisiana source for TOPS and state aid verification."),
        .init(stateCode: "ME", label: "Maine state aid", agencyTitle: "Finance Authority of Maine", agencyURL: "https://www.famemaine.com/", sourceHost: "famemaine.com", summary: "Official Maine source for state aid verification."),
        .init(stateCode: "MD", label: "Maryland state aid", agencyTitle: "Maryland Higher Education Commission", agencyURL: "https://mhec.maryland.gov/", sourceHost: "mhec.maryland.gov", summary: "Official Maryland source for state aid verification."),
        .init(stateCode: "MA", label: "Massachusetts state aid", agencyTitle: "Massachusetts Office of Student Financial Assistance", agencyURL: "https://www.mass.edu/osfa/", sourceHost: "mass.edu", summary: "Official Massachusetts source for state aid verification."),
        .init(stateCode: "MI", label: "Michigan state aid", agencyTitle: "Michigan Student Aid", agencyURL: "https://www.michigan.gov/mistudentaid", sourceHost: "michigan.gov", summary: "Official Michigan source for state aid verification."),
        .init(stateCode: "MN", label: "Minnesota state aid", agencyTitle: "Minnesota Office of Higher Education", agencyURL: "https://www.ohe.state.mn.us/", sourceHost: "ohe.state.mn.us", summary: "Official Minnesota source for state aid verification."),
        .init(stateCode: "MS", label: "Mississippi state aid", agencyTitle: "Mississippi Office of Student Financial Aid", agencyURL: "https://www.msfinancialaid.org/", sourceHost: "msfinancialaid.org", summary: "Official Mississippi source for state aid verification."),
        .init(stateCode: "MO", label: "Missouri state aid", agencyTitle: "Missouri Department of Higher Education & Workforce Development", agencyURL: "https://dhewd.mo.gov/ppc/grants/", sourceHost: "dhewd.mo.gov", summary: "Official Missouri state aid source."),
        .init(stateCode: "MT", label: "Montana state aid", agencyTitle: "Montana University System", agencyURL: "https://mus.edu/", sourceHost: "mus.edu", summary: "Official Montana higher-education source for state aid verification."),
        .init(stateCode: "NE", label: "Nebraska state aid", agencyTitle: "Nebraska Coordinating Commission for Postsecondary Education", agencyURL: "https://ccpe.nebraska.gov/", sourceHost: "ccpe.nebraska.gov", summary: "Official Nebraska higher-education source for state aid verification."),
        .init(stateCode: "NV", label: "Nevada state aid", agencyTitle: "Nevada System of Higher Education", agencyURL: "https://nshe.nevada.edu/", sourceHost: "nshe.nevada.edu", summary: "Official Nevada higher-education source for state aid verification."),
        .init(stateCode: "NH", label: "New Hampshire state aid", agencyTitle: "New Hampshire College & University Council", agencyURL: "https://www.nhcuc.org/", sourceHost: "nhcuc.org", summary: "New Hampshire higher-education resource for aid verification."),
        .init(stateCode: "NJ", label: "New Jersey state aid / TAG", agencyTitle: "New Jersey Higher Education Student Assistance Authority", agencyURL: "https://www.hesaa.org/", sourceHost: "hesaa.org", summary: "Official New Jersey source for TAG and state aid verification."),
        .init(stateCode: "NM", label: "New Mexico state aid", agencyTitle: "New Mexico Higher Education Department", agencyURL: "https://hed.nm.gov/", sourceHost: "hed.nm.gov", summary: "Official New Mexico state aid source."),
        .init(stateCode: "NY", label: "New York state aid / TAP", agencyTitle: "NYS HESC Tuition Assistance Program", agencyURL: "https://www.hesc.ny.gov/pay-for-college/financial-aid/types-of-financial-aid/grants/tap/", sourceHost: "hesc.ny.gov", summary: "Official New York source for TAP and HESC aid verification."),
        .init(stateCode: "NC", label: "North Carolina state aid", agencyTitle: "North Carolina State Education Assistance Authority", agencyURL: "https://www.ncseaa.edu/", sourceHost: "ncseaa.edu", summary: "Official North Carolina source for state aid verification."),
        .init(stateCode: "ND", label: "North Dakota state aid", agencyTitle: "North Dakota University System", agencyURL: "https://ndus.edu/", sourceHost: "ndus.edu", summary: "Official North Dakota higher-education source for state aid verification."),
        .init(stateCode: "OH", label: "Ohio state aid", agencyTitle: "Ohio Department of Higher Education", agencyURL: "https://highered.ohio.gov/", sourceHost: "highered.ohio.gov", summary: "Official Ohio state aid source."),
        .init(stateCode: "OK", label: "Oklahoma state aid", agencyTitle: "Oklahoma State Regents for Higher Education", agencyURL: "https://www.okhighered.org/", sourceHost: "okhighered.org", summary: "Official Oklahoma state aid source."),
        .init(stateCode: "OR", label: "Oregon state aid", agencyTitle: "Oregon Higher Education Coordinating Commission", agencyURL: "https://oregonstudentaid.gov/", sourceHost: "oregonstudentaid.gov", summary: "Official Oregon student aid source."),
        .init(stateCode: "PA", label: "Pennsylvania state aid / PA State Grant", agencyTitle: "Pennsylvania Higher Education Assistance Agency", agencyURL: "https://www.pheaa.org/", sourceHost: "pheaa.org", summary: "Official Pennsylvania source for PA State Grant verification."),
        .init(stateCode: "RI", label: "Rhode Island state aid", agencyTitle: "Rhode Island Office of the Postsecondary Commissioner", agencyURL: "https://riopc.edu/", sourceHost: "riopc.edu", summary: "Official Rhode Island higher-education source for state aid verification."),
        .init(stateCode: "SC", label: "South Carolina state aid", agencyTitle: "South Carolina Commission on Higher Education", agencyURL: "https://www.che.sc.gov/", sourceHost: "che.sc.gov", summary: "Official South Carolina state aid source."),
        .init(stateCode: "SD", label: "South Dakota state aid", agencyTitle: "South Dakota Board of Regents", agencyURL: "https://www.sdbor.edu/", sourceHost: "sdbor.edu", summary: "Official South Dakota higher-education source for state aid verification."),
        .init(stateCode: "TN", label: "Tennessee state aid / HOPE", agencyTitle: "Tennessee Student Assistance Corporation", agencyURL: "https://www.tn.gov/collegepays.html", sourceHost: "tn.gov", summary: "Official Tennessee state aid source."),
        .init(stateCode: "TX", label: "Texas state aid", agencyTitle: "Texas Higher Education Coordinating Board", agencyURL: "https://www.highered.texas.gov/", sourceHost: "highered.texas.gov", summary: "Official Texas higher-education source for state aid verification."),
        .init(stateCode: "UT", label: "Utah state aid", agencyTitle: "Utah System of Higher Education", agencyURL: "https://ushe.edu/", sourceHost: "ushe.edu", summary: "Official Utah higher-education source for state aid verification."),
        .init(stateCode: "VT", label: "Vermont state aid", agencyTitle: "Vermont Student Assistance Corporation", agencyURL: "https://www.vsac.org/", sourceHost: "vsac.org", summary: "Official Vermont source for state aid verification."),
        .init(stateCode: "VA", label: "Virginia state aid", agencyTitle: "State Council of Higher Education for Virginia", agencyURL: "https://www.schev.edu/", sourceHost: "schev.edu", summary: "Official Virginia higher-education source for state aid verification."),
        .init(stateCode: "WA", label: "Washington state aid", agencyTitle: "Washington Student Achievement Council", agencyURL: "https://wsac.wa.gov/", sourceHost: "wsac.wa.gov", summary: "Official Washington source for state aid verification."),
        .init(stateCode: "WV", label: "West Virginia state aid", agencyTitle: "College for West Virginia", agencyURL: "https://www.cfwv.com/", sourceHost: "cfwv.com", summary: "Official West Virginia source for state aid verification."),
        .init(stateCode: "WI", label: "Wisconsin state aid", agencyTitle: "State of Wisconsin Higher Educational Aids Board", agencyURL: "https://heab.state.wi.us/", sourceHost: "heab.state.wi.us", summary: "Official Wisconsin source for state aid verification."),
        .init(stateCode: "WY", label: "Wyoming state aid", agencyTitle: "Wyoming Department of Education", agencyURL: "https://edu.wyoming.gov/", sourceHost: "edu.wyoming.gov", summary: "Official Wyoming education source for aid verification.")
    ]

    private static var byState: [String: StateAidProgram] {
        Dictionary(uniqueKeysWithValues: programs.map { ($0.stateCode, $0) })
    }

    static func program(for stateCode: String) -> StateAidProgram? {
        byState[stateCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    static func programLabel(for stateCode: String) -> String? {
        program(for: stateCode)?.label
    }

    static func agencyURL(for stateCode: String) -> String? {
        program(for: stateCode)?.agencyURL
    }

    static func hosts(for stateCode: String) -> Set<String> {
        guard let program = program(for: stateCode) else { return [] }
        return [program.sourceHost, "www.\(program.sourceHost)"]
    }

    static func stateCode(in text: String) -> String? {
        let normalized = text.lowercased()
        for program in programs {
            if normalized.contains(program.label.lowercased()) ||
                normalized.contains(program.agencyTitle.lowercased()) {
                return program.stateCode
            }
        }
        for program in programs where containsStandalone(program.stateCode.lowercased(), in: normalized) {
            return program.stateCode
        }
        for (name, code) in stateNames where normalized.contains(name) {
            return code
        }
        return nil
    }

    private static let stateNames: [(String, String)] = [
        ("alabama", "AL"), ("alaska", "AK"), ("arizona", "AZ"), ("arkansas", "AR"), ("california", "CA"),
        ("colorado", "CO"), ("connecticut", "CT"), ("delaware", "DE"), ("florida", "FL"), ("georgia", "GA"),
        ("hawaii", "HI"), ("idaho", "ID"), ("illinois", "IL"), ("indiana", "IN"), ("iowa", "IA"),
        ("kansas", "KS"), ("kentucky", "KY"), ("louisiana", "LA"), ("maine", "ME"), ("maryland", "MD"),
        ("massachusetts", "MA"), ("michigan", "MI"), ("minnesota", "MN"), ("mississippi", "MS"), ("missouri", "MO"),
        ("montana", "MT"), ("nebraska", "NE"), ("nevada", "NV"), ("new hampshire", "NH"), ("new jersey", "NJ"),
        ("new mexico", "NM"), ("new york", "NY"), ("north carolina", "NC"), ("north dakota", "ND"), ("ohio", "OH"),
        ("oklahoma", "OK"), ("oregon", "OR"), ("pennsylvania", "PA"), ("rhode island", "RI"), ("south carolina", "SC"),
        ("south dakota", "SD"), ("tennessee", "TN"), ("texas", "TX"), ("utah", "UT"), ("vermont", "VT"),
        ("virginia", "VA"), ("washington", "WA"), ("west virginia", "WV"), ("wisconsin", "WI"), ("wyoming", "WY")
    ]

    private static func containsStandalone(_ token: String, in text: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b", options: .regularExpression) != nil
    }
}

struct AssistantPolicyEvidence: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let jurisdiction: AssistantPolicyJurisdiction
    let topic: AssistantPolicyTopic
    let title: String
    let sourceURL: String
    let sourceHost: String
    let retrievalDateISO8601: String
    let effectiveLabel: String
    let summary: String
    let cautions: [String]
}

enum AssistantPolicyEvidenceStore {
    static let retrievalDateISO8601 = "2026-04-27"

    static let all: [AssistantPolicyEvidence] = [
        .init(
            id: "fsa-fafsa-application",
            jurisdiction: .federalUS,
            topic: .fafsa,
            title: "Federal Student Aid FAFSA Application",
            sourceURL: "https://studentaid.gov/h/apply-for-aid/fafsa",
            sourceHost: "studentaid.gov",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "Verify for the student's aid year",
            summary: "FAFSA is the federal application used to apply for federal student aid and is also used by many states and schools for their aid processes.",
            cautions: [
                "Official eligibility and award amounts come from Federal Student Aid and the school.",
                "Never collect or repeat FSA ID passwords, SSNs, or tax identifiers in chat."
            ]
        ),
        .init(
            id: "fsa-enrollment-intensity",
            jurisdiction: .federalUS,
            topic: .enrollmentIntensity,
            title: "Federal Student Aid Enrollment Intensity",
            sourceURL: "https://studentaid.gov/understand-aid/types/grants/pell",
            sourceHost: "studentaid.gov",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "Current Pell/aid-year rules can change",
            summary: "Federal aid eligibility and payment can depend on enrollment intensity, cost of attendance, SAI, program eligibility, and school packaging rules.",
            cautions: [
                "Do not promise award changes from credits alone.",
                "Treat 12 credits as a common full-time undergraduate planning benchmark unless the school policy says otherwise."
            ]
        ),
        .init(
            id: "fsa-sap",
            jurisdiction: .federalUS,
            topic: .sap,
            title: "Federal Student Aid Satisfactory Academic Progress",
            sourceURL: "https://studentaid.gov/understand-aid/eligibility/staying-eligible",
            sourceHost: "studentaid.gov",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "School policy applies",
            summary: "Students generally must make satisfactory academic progress, including pace/completion, GPA, and maximum timeframe standards set by the school.",
            cautions: [
                "The app can estimate completion-rate pace only when attempted and completed credits are available.",
                "The school's financial-aid office determines official SAP status and appeal options."
            ]
        ),
        .init(
            id: "fsa-verification",
            jurisdiction: .federalUS,
            topic: .verification,
            title: "Federal Student Aid FAFSA Verification",
            sourceURL: "https://studentaid.gov/apply-for-aid/fafsa/review-and-correct/verify-info",
            sourceHost: "studentaid.gov",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "Verify current document requests in the student portal",
            summary: "Verification means the school may ask for documents to confirm FAFSA information before finalizing aid.",
            cautions: [
                "Students should submit documents only through official school or Federal Student Aid channels.",
                "Do not upload full sensitive identifiers into the assistant."
            ]
        ),
        .init(
            id: "hesc-tap-eligibility",
            jurisdiction: .newYork,
            topic: .stateAid,
            title: "NYS HESC Tuition Assistance Program",
            sourceURL: "https://www.hesc.ny.gov/pay-for-college/financial-aid/types-of-financial-aid/grants/tap/",
            sourceHost: "hesc.ny.gov",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "Verify for the student's award year",
            summary: "TAP is New York State grant aid for eligible New York residents attending eligible New York schools and programs.",
            cautions: [
                "TAP approval depends on residency, program, enrollment, academic progress, income, and HESC rules.",
                "The assistant should screen factors, not declare approval."
            ]
        ),
        .init(
            id: "ub-financial-aid",
            jurisdiction: .universityAtBuffalo,
            topic: .schoolFinancialAid,
            title: "University at Buffalo Financial Aid",
            sourceURL: "https://financialaid.buffalo.edu/",
            sourceHost: "financialaid.buffalo.edu",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "School priority dates and packaging rules must be verified with UB",
            summary: "UB's financial-aid office is the official source for school packaging, verification, SAP status, aid deadlines, and account-specific aid questions.",
            cautions: [
                "Do not present app guidance as a UB financial-aid decision.",
                "Direct account-specific or appeal questions to UB financial aid."
            ]
        ),
        .init(
            id: "ub-catalog",
            jurisdiction: .universityAtBuffalo,
            topic: .academicCatalog,
            title: "University at Buffalo Undergraduate Catalog",
            sourceURL: "https://catalogs.buffalo.edu/",
            sourceHost: "catalogs.buffalo.edu",
            retrievalDateISO8601: retrievalDateISO8601,
            effectiveLabel: "Use the catalog year that applies to the student",
            summary: "UB catalog pages are the official source for program requirements, course descriptions, credits, and prerequisite language.",
            cautions: [
                "Course availability, placement, transfer/AP credit, and advisor exceptions must be confirmed before registration.",
                "The app's degree plan is not an official registrar audit."
            ]
        )
    ]

    static func evidence(
        for topics: Set<AssistantPolicyTopic>,
        jurisdiction: UniversityPolicyJurisdiction
    ) -> [AssistantPolicyEvidence] {
        let stored = all.filter { item in
            guard topics.contains(item.topic) else { return false }
            switch item.jurisdiction.key {
            case AssistantPolicyJurisdiction.federalUS.key:
                return jurisdiction.allowsFederalFAFSA
            case AssistantPolicyJurisdiction.newYork.key:
                return jurisdiction.normalizedStateCode == "NY" && jurisdiction.allowsFederalFAFSA
            case AssistantPolicyJurisdiction.universityAtBuffalo.key:
                return jurisdiction.isUniversityAtBuffalo
            default:
                if let state = jurisdiction.normalizedStateCode, item.jurisdiction.key == AssistantPolicyJurisdiction.state(state).key {
                    return true
                }
                if let schoolID = jurisdiction.schoolID, item.jurisdiction.key == AssistantPolicyJurisdiction.institution(schoolID).key {
                    return true
                }
                return false
            }
        }
        let dynamic = dynamicEvidence(for: topics, jurisdiction: jurisdiction)
        return schoolFirst(stored + dynamic)
    }

    static func hosts(for jurisdiction: UniversityPolicyJurisdiction) -> Set<String> {
        Set(evidence(for: Set(AssistantPolicyTopic.allCases), jurisdiction: jurisdiction).map(\.sourceHost))
    }

    private static func dynamicEvidence(
        for topics: Set<AssistantPolicyTopic>,
        jurisdiction: UniversityPolicyJurisdiction
    ) -> [AssistantPolicyEvidence] {
        var rows: [AssistantPolicyEvidence] = []
        if topics.contains(.schoolFinancialAid), let url = jurisdiction.financialAidURL, let host = URL(string: url)?.host?.lowercased() {
            rows.append(.init(
                id: "school-financial-aid-\(stableID(jurisdiction.universityName))",
                jurisdiction: jurisdiction.schoolID.map(AssistantPolicyJurisdiction.institution) ?? .institution(stableID(jurisdiction.universityName)),
                topic: .schoolFinancialAid,
                title: "\(jurisdiction.universityName.isEmpty ? "School" : jurisdiction.universityName) Financial Aid",
                sourceURL: url,
                sourceHost: host,
                retrievalDateISO8601: retrievalDateISO8601,
                effectiveLabel: "Verify school priority dates, packaging, verification, and SAP rules with this office",
                summary: "The selected school's financial-aid office is the primary source for account-specific aid, verification, SAP, deadlines, packaging, and appeal questions.",
                cautions: ["Use federal/state sources as extra resources; do not replace the school's official financial-aid policy."]
            ))
        }
        if topics.contains(.academicCatalog), let url = jurisdiction.catalogURL, let host = URL(string: url)?.host?.lowercased() {
            rows.append(.init(
                id: "school-catalog-\(stableID(jurisdiction.universityName))",
                jurisdiction: jurisdiction.schoolID.map(AssistantPolicyJurisdiction.institution) ?? .institution(stableID(jurisdiction.universityName)),
                topic: .academicCatalog,
                title: "\(jurisdiction.universityName.isEmpty ? "School" : jurisdiction.universityName) Catalog",
                sourceURL: url,
                sourceHost: host,
                retrievalDateISO8601: retrievalDateISO8601,
                effectiveLabel: "Use the catalog year that applies to the student",
                summary: "The selected school's catalog is the primary source for program requirements, course descriptions, credits, and prerequisites.",
                cautions: ["Registration eligibility and exceptions must be confirmed with the advisor or registrar."]
            ))
        }
        if topics.contains(.stateAid),
           let state = jurisdiction.normalizedStateCode,
           let program = StateAidRegistry.program(for: state) {
            rows.append(.init(
                id: "state-aid-\(state.lowercased())",
                jurisdiction: .state(state),
                topic: .stateAid,
                title: program.agencyTitle,
                sourceURL: jurisdiction.stateAidAgencyURL ?? program.agencyURL,
                sourceHost: program.sourceHost,
                retrievalDateISO8601: retrievalDateISO8601,
                effectiveLabel: "Use as an extra resource for state aid rules; verify school packaging with the school",
                summary: program.summary,
                cautions: ["State aid source is an extra resource; the school determines account-specific packaging and may set local deadlines."]
            ))
        }
        return rows
    }

    private static func schoolFirst(_ rows: [AssistantPolicyEvidence]) -> [AssistantPolicyEvidence] {
        let rank: (AssistantPolicyEvidence) -> Int = { item in
            if item.topic == .schoolFinancialAid || item.topic == .academicCatalog { return 0 }
            if item.jurisdiction.key.hasPrefix("US-") { return 2 }
            return 1
        }
        var seen = Set<String>()
        return rows
            .sorted { lhs, rhs in
                let l = rank(lhs)
                let r = rank(rhs)
                if l != r { return l < r }
                return lhs.title < rhs.title
            }
            .filter { item in
                let key: String
                if item.topic == .schoolFinancialAid || item.topic == .academicCatalog {
                    key = "\(item.topic.rawValue):\(item.title.lowercased())"
                } else {
                    key = item.sourceURL.isEmpty ? item.id : item.sourceURL
                }
                return seen.insert(key).inserted
            }
    }

    private static func stableID(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
