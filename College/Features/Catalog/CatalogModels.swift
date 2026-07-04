// CatalogModels.swift
// Feature: Catalog
// Purpose: Catalog module — SchoolManifest.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - School Manifest (schools.json)

struct SchoolManifest: Codable, Identifiable {
    let id: String
    let name: String
    let shortName: String?
    let unitID: String?
    let opeID: String?
    let profileURL: String
    let catalogURL: String?  // Direct URL to school's catalog website
    let academicCalendarURL: String?
    let timeZoneID: String?
    let countryCode: String?
    let stateCode: String?
    let officialWebsiteURL: String?
    let financialAidURL: String?
    let registrarURL: String?
    let stateAidAgencyURL: String?
    let catalogFormat: String // "acalog", "moderncampus", "courseleaf", "banner", "custom", "pdf"
    let lastUpdated: Date
    let coursesCount: Int
    let verified: Bool

    // MARK: Transfer Database (schema 1.4) — all optional / backward compatible.

    /// Whether an aggregator (e.g. ASSIST.org) covers this institution.
    let transferAggregatorSupported: Bool?
    /// Aggregator institution identifier (e.g. ASSIST institution id).
    let assistInstitutionID: String?
    /// Base URL for a TES (Transfer Evaluation System) public-view dataset/page.
    let tesPublicViewURL: String?
    /// Base URL for a Banner transfer-articulation dataset/page.
    let bannerArticulationBaseURL: String?
    /// Banner generation in use (8 or 9) when `bannerArticulationBaseURL` is set.
    let bannerGeneration: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case shortName = "short_name"
        case unitID = "unit_id"
        case opeID = "ope_id"
        case profileURL = "profile_url"
        case catalogURL = "catalog_url"
        case academicCalendarURL = "academic_calendar_url"
        case timeZoneID = "time_zone_id"
        case countryCode = "country_code"
        case stateCode = "state_code"
        case officialWebsiteURL = "official_website_url"
        case financialAidURL = "financial_aid_url"
        case registrarURL = "registrar_url"
        case stateAidAgencyURL = "state_aid_agency_url"
        case catalogFormat = "catalog_format"
        case lastUpdated = "last_updated"
        case coursesCount = "courses_count"
        case verified
        case transferAggregatorSupported = "transfer_aggregator_supported"
        case assistInstitutionID = "assist_institution_id"
        case tesPublicViewURL = "tes_public_view_url"
        case bannerArticulationBaseURL = "banner_articulation_base_url"
        case bannerGeneration = "banner_generation"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
        unitID = try c.decodeIfPresent(String.self, forKey: .unitID)
        opeID = try c.decodeIfPresent(String.self, forKey: .opeID)
        profileURL = (try? c.decode(String.self, forKey: .profileURL)) ?? ""
        catalogURL = try c.decodeIfPresent(String.self, forKey: .catalogURL)
        academicCalendarURL = try c.decodeIfPresent(String.self, forKey: .academicCalendarURL)
        timeZoneID = try c.decodeIfPresent(String.self, forKey: .timeZoneID)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        stateCode = try c.decodeIfPresent(String.self, forKey: .stateCode)
        officialWebsiteURL = try c.decodeIfPresent(String.self, forKey: .officialWebsiteURL)
        financialAidURL = try c.decodeIfPresent(String.self, forKey: .financialAidURL)
        registrarURL = try c.decodeIfPresent(String.self, forKey: .registrarURL)
        stateAidAgencyURL = try c.decodeIfPresent(String.self, forKey: .stateAidAgencyURL)
        catalogFormat = (try? c.decode(String.self, forKey: .catalogFormat)) ?? "custom"
        lastUpdated = (try? c.decode(Date.self, forKey: .lastUpdated)) ?? .distantPast
        coursesCount = (try? c.decode(Int.self, forKey: .coursesCount)) ?? 0
        verified = (try? c.decode(Bool.self, forKey: .verified)) ?? false
        transferAggregatorSupported = try c.decodeIfPresent(Bool.self, forKey: .transferAggregatorSupported)
        assistInstitutionID = try c.decodeIfPresent(String.self, forKey: .assistInstitutionID)
        tesPublicViewURL = try c.decodeIfPresent(String.self, forKey: .tesPublicViewURL)
        bannerArticulationBaseURL = try c.decodeIfPresent(String.self, forKey: .bannerArticulationBaseURL)
        bannerGeneration = try c.decodeIfPresent(Int.self, forKey: .bannerGeneration)
    }

    init(
        id: String,
        name: String,
        shortName: String? = nil,
        unitID: String? = nil,
        opeID: String? = nil,
        profileURL: String,
        catalogURL: String? = nil,
        academicCalendarURL: String? = nil,
        timeZoneID: String? = nil,
        countryCode: String? = nil,
        stateCode: String? = nil,
        officialWebsiteURL: String? = nil,
        financialAidURL: String? = nil,
        registrarURL: String? = nil,
        stateAidAgencyURL: String? = nil,
        catalogFormat: String,
        lastUpdated: Date,
        coursesCount: Int,
        verified: Bool,
        transferAggregatorSupported: Bool? = nil,
        assistInstitutionID: String? = nil,
        tesPublicViewURL: String? = nil,
        bannerArticulationBaseURL: String? = nil,
        bannerGeneration: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.unitID = unitID
        self.opeID = opeID
        self.profileURL = profileURL
        self.catalogURL = catalogURL
        self.academicCalendarURL = academicCalendarURL
        self.timeZoneID = timeZoneID
        self.countryCode = countryCode
        self.stateCode = stateCode
        self.officialWebsiteURL = officialWebsiteURL
        self.financialAidURL = financialAidURL
        self.registrarURL = registrarURL
        self.stateAidAgencyURL = stateAidAgencyURL
        self.catalogFormat = catalogFormat
        self.lastUpdated = lastUpdated
        self.coursesCount = coursesCount
        self.verified = verified
        self.transferAggregatorSupported = transferAggregatorSupported
        self.assistInstitutionID = assistInstitutionID
        self.tesPublicViewURL = tesPublicViewURL
        self.bannerArticulationBaseURL = bannerArticulationBaseURL
        self.bannerGeneration = bannerGeneration
    }
}

// MARK: - School Profile (rutgers_nb.json)

struct SchoolProfile: Codable {
    let schoolID: String
    let schoolName: String
    let unitID: String?
    let opeID: String?
    let catalogURL: String
    let countryCode: String?
    let stateCode: String?
    let officialWebsiteURL: String?
    let financialAidURL: String?
    let registrarURL: String?
    let stateAidAgencyURL: String?
    let version: String
    let lastUpdated: Date
    let courses: [CatalogCourse]
    let degreeRequirements: [DegreeRequirement]
    let policies: SchoolPolicies

    init(
        schoolID: String,
        schoolName: String,
        unitID: String? = nil,
        opeID: String? = nil,
        catalogURL: String,
        countryCode: String? = nil,
        stateCode: String? = nil,
        officialWebsiteURL: String? = nil,
        financialAidURL: String? = nil,
        registrarURL: String? = nil,
        stateAidAgencyURL: String? = nil,
        version: String,
        lastUpdated: Date,
        courses: [CatalogCourse],
        degreeRequirements: [DegreeRequirement],
        policies: SchoolPolicies
    ) {
        self.schoolID = schoolID
        self.schoolName = schoolName
        self.unitID = unitID
        self.opeID = opeID
        self.catalogURL = catalogURL
        self.countryCode = countryCode
        self.stateCode = stateCode
        self.officialWebsiteURL = officialWebsiteURL
        self.financialAidURL = financialAidURL
        self.registrarURL = registrarURL
        self.stateAidAgencyURL = stateAidAgencyURL
        self.version = version
        self.lastUpdated = lastUpdated
        self.courses = courses
        self.degreeRequirements = degreeRequirements
        self.policies = policies
    }
    
    enum CodingKeys: String, CodingKey {
        case schoolID = "school_id"
        case schoolName = "school_name"
        case unitID = "unit_id"
        case opeID = "ope_id"
        case catalogURL = "catalog_url"
        case countryCode = "country_code"
        case stateCode = "state_code"
        case officialWebsiteURL = "official_website_url"
        case financialAidURL = "financial_aid_url"
        case registrarURL = "registrar_url"
        case stateAidAgencyURL = "state_aid_agency_url"
        case version
        case lastUpdated = "last_updated"
        case courses
        case degreeRequirements = "degree_requirements"
        case policies
    }
}

struct SchoolPolicyMetadata: Codable, Sendable, Equatable {
    let schoolID: String?
    let unitID: String?
    let opeID: String?
    let schoolName: String
    let countryCode: String?
    let stateCode: String?
    let officialWebsiteURL: String?
    let catalogURL: String?
    let financialAidURL: String?
    let registrarURL: String?
    let stateAidAgencyURL: String?
    let sourceDescription: String
    let retrievedAtISO8601: String
    let confidence: Double
}

enum SchoolPolicyMetadataEnricher {
    static func metadata(profile: SchoolProfile, manifest: SchoolManifest? = nil) -> SchoolPolicyMetadata {
        let indexed = IPEDSInstitutionIndex.match(
            schoolID: firstNonEmpty(profile.schoolID, manifest?.id),
            unitID: firstNonEmpty(profile.unitID, manifest?.unitID),
            opeID: firstNonEmpty(profile.opeID, manifest?.opeID),
            schoolName: profile.schoolName
        )
        let catalogURL = firstNonEmpty(profile.catalogURL, manifest?.catalogURL)
        let officialURL = firstNonEmpty(profile.officialWebsiteURL, manifest?.officialWebsiteURL, indexed?.officialWebsiteURL, officialBaseURL(from: catalogURL))
        let country = firstNonEmpty(profile.countryCode, manifest?.countryCode, indexed?.countryCode, inferCountryCode(schoolName: profile.schoolName, url: officialURL ?? catalogURL))
        let state = firstNonEmpty(profile.stateCode, manifest?.stateCode, indexed?.stateCode, inferStateCode(schoolName: profile.schoolName, url: officialURL ?? catalogURL))
        let stateAgency = firstNonEmpty(profile.stateAidAgencyURL, manifest?.stateAidAgencyURL, state.flatMap { StateAidRegistry.agencyURL(for: $0) })
        let financialAidURL = firstNonEmpty(
            profile.financialAidURL,
            manifest?.financialAidURL,
            guessedURL(base: officialURL, path: "financial-aid"),
            guessedURL(base: officialURL, path: "financialaid")
        )
        let registrarURL = firstNonEmpty(
            profile.registrarURL,
            manifest?.registrarURL,
            guessedURL(base: officialURL, path: "registrar")
        )
        let confidence: Double = {
            var score = 0.35
            if profile.stateCode != nil || manifest?.stateCode != nil { score += 0.3 }
            if profile.financialAidURL != nil || manifest?.financialAidURL != nil { score += 0.2 }
            if officialURL != nil { score += 0.1 }
            return min(score, 0.95)
        }()
        return SchoolPolicyMetadata(
            schoolID: firstNonEmpty(profile.schoolID, manifest?.id, indexed?.schoolID),
            unitID: firstNonEmpty(profile.unitID, manifest?.unitID, indexed?.unitID),
            opeID: firstNonEmpty(profile.opeID, manifest?.opeID, indexed?.opeID),
            schoolName: profile.schoolName,
            countryCode: country,
            stateCode: state,
            officialWebsiteURL: officialURL,
            catalogURL: catalogURL,
            financialAidURL: financialAidURL,
            registrarURL: registrarURL,
            stateAidAgencyURL: stateAgency,
            sourceDescription: "school profile/manifest plus deterministic onboarding enrichment",
            retrievedAtISO8601: isoDate(Date()),
            confidence: confidence
        )
    }

    static func metadata(manifest: SchoolManifest) -> SchoolPolicyMetadata {
        let indexed = IPEDSInstitutionIndex.match(
            schoolID: manifest.id,
            unitID: manifest.unitID,
            opeID: manifest.opeID,
            schoolName: manifest.name
        )
        let officialURL = firstNonEmpty(manifest.officialWebsiteURL, indexed?.officialWebsiteURL, officialBaseURL(from: manifest.catalogURL))
        let country = firstNonEmpty(manifest.countryCode, indexed?.countryCode, inferCountryCode(schoolName: manifest.name, url: officialURL ?? manifest.catalogURL))
        let state = firstNonEmpty(manifest.stateCode, indexed?.stateCode, inferStateCode(schoolName: manifest.name, url: officialURL ?? manifest.catalogURL))
        return SchoolPolicyMetadata(
            schoolID: firstNonEmpty(manifest.id, indexed?.schoolID),
            unitID: firstNonEmpty(manifest.unitID, indexed?.unitID),
            opeID: firstNonEmpty(manifest.opeID, indexed?.opeID),
            schoolName: manifest.name,
            countryCode: country,
            stateCode: state,
            officialWebsiteURL: officialURL,
            catalogURL: manifest.catalogURL,
            financialAidURL: firstNonEmpty(manifest.financialAidURL, guessedURL(base: officialURL, path: "financial-aid"), guessedURL(base: officialURL, path: "financialaid")),
            registrarURL: firstNonEmpty(manifest.registrarURL, guessedURL(base: officialURL, path: "registrar")),
            stateAidAgencyURL: firstNonEmpty(manifest.stateAidAgencyURL, state.flatMap { StateAidRegistry.agencyURL(for: $0) }),
            sourceDescription: "school manifest plus deterministic onboarding enrichment",
            retrievedAtISO8601: isoDate(Date()),
            confidence: manifest.stateCode == nil ? 0.55 : 0.85
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func officialBaseURL(from urlString: String?) -> String? {
        guard let raw = firstNonEmpty(urlString), let url = URL(string: raw), let host = url.host?.lowercased() else { return nil }
        let components = host.split(separator: ".").map(String.init)
        let baseHost: String
        if components.count >= 3, components.suffix(2).joined(separator: ".") == "edu" {
            baseHost = components.suffix(2).joined(separator: ".")
        } else if components.count >= 2 {
            baseHost = components.suffix(2).joined(separator: ".")
        } else {
            baseHost = host
        }
        return "https://\(baseHost)/"
    }

    private static func guessedURL(base: String?, path: String) -> String? {
        guard let base, var components = URLComponents(string: base) else { return nil }
        components.path = "/" + path
        return components.url?.absoluteString
    }

    private static func inferCountryCode(schoolName: String, url: String?) -> String? {
        let normalized = schoolName.lowercased()
        if normalized.contains("canada") || normalized.contains("toronto") || normalized.contains("ontario") { return "CA" }
        if let host = URL(string: url ?? "")?.host?.lowercased(), host.hasSuffix(".edu") { return "US" }
        return normalized.isEmpty ? nil : "US"
    }

    private static func inferStateCode(schoolName: String, url: String?) -> String? {
        let normalized = schoolName.lowercased()
        for (needle, code) in stateNameHints where normalized.contains(needle) {
            return code
        }
        let host = URL(string: url ?? "")?.host?.lowercased() ?? ""
        for (needle, code) in domainHints where host.contains(needle) {
            return code
        }
        return nil
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private static let stateNameHints: [(String, String)] = [
        ("alabama", "AL"), ("alaska", "AK"), ("arizona", "AZ"), ("arkansas", "AR"), ("california", "CA"),
        ("colorado", "CO"), ("connecticut", "CT"), ("delaware", "DE"), ("florida", "FL"), ("georgia", "GA"),
        ("hawaii", "HI"), ("idaho", "ID"), ("illinois", "IL"), ("indiana", "IN"), ("iowa", "IA"),
        ("kansas", "KS"), ("kentucky", "KY"), ("louisiana", "LA"), ("maine", "ME"), ("maryland", "MD"),
        ("massachusetts", "MA"), ("michigan", "MI"), ("minnesota", "MN"), ("mississippi", "MS"), ("missouri", "MO"),
        ("montana", "MT"), ("nebraska", "NE"), ("nevada", "NV"), ("new hampshire", "NH"), ("new jersey", "NJ"),
        ("new mexico", "NM"), ("new york", "NY"), ("north carolina", "NC"), ("north dakota", "ND"), ("ohio", "OH"),
        ("oklahoma", "OK"), ("oregon", "OR"), ("pennsylvania", "PA"), ("rhode island", "RI"), ("south carolina", "SC"),
        ("south dakota", "SD"), ("tennessee", "TN"), ("texas", "TX"), ("utah", "UT"), ("vermont", "VT"),
        ("virginia", "VA"), ("washington", "WA"), ("west virginia", "WV"), ("wisconsin", "WI"), ("wyoming", "WY"),
        ("suny", "NY"), ("cuny", "NY"), ("cal state", "CA"), ("uc ", "CA"), ("university of california", "CA")
    ]

    private static let domainHints: [(String, String)] = [
        ("buffalo.edu", "NY"), ("suny.edu", "NY"), ("cuny.edu", "NY"),
        ("calstate.edu", "CA"), ("uc", "CA"), ("utexas.edu", "TX"), ("tamu.edu", "TX")
    ]
}

struct IPEDSInstitutionRecord: Codable, Sendable, Equatable {
    let schoolID: String
    let unitID: String
    let opeID: String
    let name: String
    let aliases: [String]
    let stateCode: String
    let countryCode: String
    let officialWebsiteURL: String
    let titleIVEligible: Bool
}

enum IPEDSInstitutionIndex {
    // Seed rows keep onboarding seamless until the bundled IPEDS SQLite/JSON asset is generated.
    static let bundledSeed: [IPEDSInstitutionRecord] = [
        .init(
            schoolID: "university_at_buffalo",
            unitID: "196088",
            opeID: "00283700",
            name: "University at Buffalo",
            aliases: ["state university of new york at buffalo", "suny buffalo", "ub"],
            stateCode: "NY",
            countryCode: "US",
            officialWebsiteURL: "https://www.buffalo.edu/",
            titleIVEligible: true
        ),
        .init(
            schoolID: "uc_berkeley",
            unitID: "110635",
            opeID: "00131200",
            name: "University of California Berkeley",
            aliases: ["uc berkeley", "berkeley"],
            stateCode: "CA",
            countryCode: "US",
            officialWebsiteURL: "https://www.berkeley.edu/",
            titleIVEligible: true
        ),
        .init(
            schoolID: "ut_austin",
            unitID: "228778",
            opeID: "00365800",
            name: "The University of Texas at Austin",
            aliases: ["university of texas at austin", "ut austin"],
            stateCode: "TX",
            countryCode: "US",
            officialWebsiteURL: "https://www.utexas.edu/",
            titleIVEligible: true
        )
    ]

    static func match(schoolID: String?, unitID: String?, opeID: String?, schoolName: String) -> IPEDSInstitutionRecord? {
        let normalizedID = normalize(schoolID)
        let normalizedUnit = normalize(unitID)
        let normalizedOPE = normalize(opeID)
        let normalizedName = normalize(schoolName)
        return bundledSeed.first { record in
            normalize(record.schoolID) == normalizedID ||
                normalize(record.unitID) == normalizedUnit ||
                normalize(record.opeID) == normalizedOPE ||
                normalize(record.name) == normalizedName ||
                record.aliases.contains { alias in normalizedName.contains(normalize(alias)) }
        }
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}

// MARK: - External catalog references (transfer / articulation; Tier 3 population)

nonisolated struct ExternalReference: Codable, Hashable, Sendable {
    let system: String
    let externalID: String
    let url: String?

    init(system: String, externalID: String, url: String? = nil) {
        self.system = system
        self.externalID = externalID
        self.url = url
    }
}

// MARK: - Catalog Course

nonisolated struct CatalogCourse: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let courseCode: String
    let title: String
    let description: String?
    let credits: Int
    let department: String?
    let prerequisites: PrerequisiteRule?
    let prerequisiteText: String? // Raw text for scraper output
    let corequisites: [String]?
    let typicallyOffered: [String]?
    let catalogCoid: String?
    let previewDetailURL: String?
    let externalReferences: [ExternalReference]

    enum CodingKeys: String, CodingKey {
        case id, courseCode = "course_code"
        case title, description, credits, department
        case prerequisites, prerequisiteText = "prerequisite_text", corequisites
        case typicallyOffered = "typically_offered"
        case catalogCoid
        case previewDetailURL
        case externalReferences = "external_references"
    }

    // Manual initializer for programmatic creation
    nonisolated init(
        id: UUID = UUID(),
        courseCode: String,
        title: String,
        description: String? = nil,
        credits: Int,
        department: String? = nil,
        prerequisites: PrerequisiteRule? = nil,
        prerequisiteText: String? = nil,
        corequisites: [String]? = nil,
        typicallyOffered: [String]? = nil,
        catalogCoid: String? = nil,
        previewDetailURL: String? = nil,
        externalReferences: [ExternalReference] = []
    ) {
        self.id = id
        self.courseCode = courseCode
        self.title = title
        self.description = description
        self.credits = credits
        self.department = department
        self.prerequisites = prerequisites
        self.prerequisiteText = prerequisiteText
        self.corequisites = corequisites
        self.typicallyOffered = typicallyOffered
        self.catalogCoid = catalogCoid
        self.previewDetailURL = previewDetailURL
        self.externalReferences = externalReferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        courseCode = try container.decode(String.self, forKey: .courseCode)
        title = try container.decode(String.self, forKey: .title)
        description = try? container.decode(String.self, forKey: .description)
        credits = try container.decode(Int.self, forKey: .credits)
        department = try? container.decode(String.self, forKey: .department)
        prerequisites = try? container.decode(PrerequisiteRule.self, forKey: .prerequisites)
        prerequisiteText = try? container.decode(String.self, forKey: .prerequisiteText)
        corequisites = try? container.decode([String].self, forKey: .corequisites)
        typicallyOffered = try? container.decode([String].self, forKey: .typicallyOffered)
        catalogCoid = try? container.decode(String.self, forKey: .catalogCoid)
        previewDetailURL = try? container.decode(String.self, forKey: .previewDetailURL)
        externalReferences = (try? container.decode([ExternalReference].self, forKey: .externalReferences)) ?? []
    }
}

// MARK: - Prerequisite Rules (Recursive Structure)

nonisolated enum PrerequisiteRule: Codable, Equatable, Hashable, Sendable {
    case course(CourseRequirement)
    case and([PrerequisiteRule])
    case or([PrerequisiteRule])
    
    enum CodingKeys: String, CodingKey {
        case type, course, rules
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type.lowercased() {
        case "course":
            let course = try container.decode(CourseRequirement.self, forKey: .course)
            self = .course(course)
        case "and":
            let rules = try container.decode([PrerequisiteRule].self, forKey: .rules)
            self = .and(rules)
        case "or":
            let rules = try container.decode([PrerequisiteRule].self, forKey: .rules)
            self = .or(rules)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown prerequisite type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .course(let requirement):
            try container.encode("course", forKey: .type)
            try container.encode(requirement, forKey: .course)
        case .and(let rules):
            try container.encode("and", forKey: .type)
            try container.encode(rules, forKey: .rules)
        case .or(let rules):
            try container.encode("or", forKey: .type)
            try container.encode(rules, forKey: .rules)
        }
    }
}

nonisolated struct CourseRequirement: Codable, Equatable, Hashable, Sendable {
    let courseCode: String
    let minGrade: String? // "B", "C+", etc.
    
    enum CodingKeys: String, CodingKey {
        case courseCode = "course_code"
        case minGrade = "min_grade"
    }
}

// MARK: - Degree Requirements

/// Detailed course information extracted from catalog
nonisolated struct CourseDetail: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let code: String // "CSE 113"
    let title: String? // "Foundations of Computer Science I"
    let credits: String? // "3" or "1-6"
    /// When set, courses sharing this key are catalog "or" alternatives (pick one).
    let alternativeGroupKey: String?

    init(code: String, title: String? = nil, credits: String? = nil, alternativeGroupKey: String? = nil) {
        self.id = UUID()
        self.code = code
        self.title = title
        self.credits = credits
        self.alternativeGroupKey = alternativeGroupKey
    }

    enum CodingKeys: String, CodingKey {
        case id, code, title, credits, alternativeGroupKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.code = try container.decode(String.self, forKey: .code)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.credits = try container.decodeIfPresent(String.self, forKey: .credits)
        self.alternativeGroupKey = try container.decodeIfPresent(String.self, forKey: .alternativeGroupKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(credits, forKey: .credits)
        try container.encodeIfPresent(alternativeGroupKey, forKey: .alternativeGroupKey)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(alternativeGroupKey)
    }

    static func == (lhs: CourseDetail, rhs: CourseDetail) -> Bool {
        lhs.code == rhs.code && lhs.alternativeGroupKey == rhs.alternativeGroupKey
    }
}

nonisolated enum RequirementPredicateType: String, Codable, Sendable {
    case all
    case any
    case course
}

/// Recursive logical predicate for richer requirement semantics.
/// This is optional and coexists with legacy flat fields for backward compatibility.
nonisolated struct RequirementPredicate: Codable, Hashable, Sendable {
    let type: RequirementPredicateType
    let course: CourseDetail?
    let children: [RequirementPredicate]?
    let selectCount: Int?

    init(
        type: RequirementPredicateType,
        course: CourseDetail? = nil,
        children: [RequirementPredicate]? = nil,
        selectCount: Int? = nil
    ) {
        self.type = type
        self.course = course
        self.children = children
        self.selectCount = selectCount
    }

    static func course(_ course: CourseDetail) -> RequirementPredicate {
        RequirementPredicate(type: .course, course: course)
    }

    static func all(_ children: [RequirementPredicate]) -> RequirementPredicate {
        RequirementPredicate(type: .all, children: children)
    }

    static func any(_ children: [RequirementPredicate], selectCount: Int? = nil) -> RequirementPredicate {
        RequirementPredicate(type: .any, children: children, selectCount: selectCount)
    }
}

nonisolated enum RequirementKind: String, Codable, Sendable, CaseIterable {
    case courseList
    case chooseOne
    case distributionBucket
    case ruleBucket
    case prose
}

nonisolated struct DegreeRequirement: Codable, Identifiable, Sendable {
    let id: UUID
    let degreeType: String // "Bachelor of Science"
    let major: String
    let category: String // "Core", "Electives", "General Education"
    let requiredCourses: [String]? // Legacy: course codes only
    let requiredCoursesDetailed: [CourseDetail]? // New: full course details
    let creditsRequired: Int
    let description: String?
    let selectFrom: [String]? // Legacy: course codes only
    let selectFromDetailed: [CourseDetail]? // New: full course details
    let selectCount: Int? // Number to select from selectFrom
    let requirementPredicate: RequirementPredicate? // Optional recursive semantics
    let requirementKind: RequirementKind?
    let parentCategory: String?
    let displayTitle: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case degreeType = "degree_type"
        case major, category
        case requiredCourses = "required_courses"
        case requiredCoursesDetailed = "required_courses_detailed"
        case creditsRequired = "credits_required"
        case description
        case selectFrom = "select_from"
        case selectFromDetailed = "select_from_detailed"
        case selectCount = "select_count"
        case requirementPredicate = "requirement_predicate"
        case requirementKind = "requirement_kind"
        case parentCategory = "parent_category"
        case displayTitle = "display_title"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        degreeType = try container.decode(String.self, forKey: .degreeType)
        major = try container.decode(String.self, forKey: .major)
        category = try container.decode(String.self, forKey: .category)
        requiredCourses = try? container.decode([String].self, forKey: .requiredCourses)
        requiredCoursesDetailed = try? container.decode([CourseDetail].self, forKey: .requiredCoursesDetailed)
        creditsRequired = try container.decode(Int.self, forKey: .creditsRequired)
        description = try? container.decode(String.self, forKey: .description)
        selectFrom = try? container.decode([String].self, forKey: .selectFrom)
        selectFromDetailed = try? container.decode([CourseDetail].self, forKey: .selectFromDetailed)
        selectCount = try? container.decode(Int.self, forKey: .selectCount)
        requirementPredicate = try? container.decode(RequirementPredicate.self, forKey: .requirementPredicate)
        requirementKind = try? container.decode(RequirementKind.self, forKey: .requirementKind)
        parentCategory = try? container.decode(String.self, forKey: .parentCategory)
        displayTitle = try? container.decode(String.self, forKey: .displayTitle)
    }
    
    // Manual initializer for programmatic creation
    init(
        id: UUID = UUID(),
        degreeType: String,
        major: String,
        category: String,
        requiredCourses: [String]? = nil,
        requiredCoursesDetailed: [CourseDetail]? = nil,
        creditsRequired: Int,
        description: String? = nil,
        selectFrom: [String]? = nil,
        selectFromDetailed: [CourseDetail]? = nil,
        selectCount: Int? = nil,
        requirementPredicate: RequirementPredicate? = nil,
        requirementKind: RequirementKind? = nil,
        parentCategory: String? = nil,
        displayTitle: String? = nil
    ) {
        self.id = id
        self.degreeType = degreeType
        self.major = major
        self.category = category
        self.requiredCourses = requiredCourses
        self.requiredCoursesDetailed = requiredCoursesDetailed
        self.creditsRequired = creditsRequired
        self.description = description
        self.selectFrom = selectFrom
        self.selectFromDetailed = selectFromDetailed
        self.selectCount = selectCount
        self.requirementPredicate = requirementPredicate
        self.requirementKind = requirementKind
        self.parentCategory = parentCategory
        self.displayTitle = displayTitle
    }

    /// Returns a copy with `major` and `degreeType` replaced.
    /// Used by the scraper to stamp the program name/degree onto parsed requirements,
    /// which are initially created with placeholder "Unknown" values.
    func stamping(major newMajor: String, degreeType newDegreeType: String) -> DegreeRequirement {
        DegreeRequirement(
            id: id,
            degreeType: newDegreeType,
            major: newMajor,
            category: category,
            requiredCourses: requiredCourses,
            requiredCoursesDetailed: requiredCoursesDetailed,
            creditsRequired: creditsRequired,
            description: description,
            selectFrom: selectFrom,
            selectFromDetailed: selectFromDetailed,
            selectCount: selectCount,
            requirementPredicate: requirementPredicate,
            requirementKind: requirementKind,
            parentCategory: parentCategory,
            displayTitle: displayTitle
        )
    }
}

// MARK: - School Policies

struct SchoolPolicies: Codable {
    let transferCreditLimit: Int?
    let minorTransferLimit: Int?
    let maxCreditsPerSemester: Int?
    let minCreditsForFullTime: Int?
    let gradeForCredit: String? // Minimum grade to receive credit (e.g., "D")
    let repeatCoursePolicy: String?
    
    enum CodingKeys: String, CodingKey {
        case transferCreditLimit = "transfer_credit_limit"
        case minorTransferLimit = "minor_transfer_limit"
        case maxCreditsPerSemester = "max_credits_per_semester"
        case minCreditsForFullTime = "min_credits_full_time"
        case gradeForCredit = "grade_for_credit"
        case repeatCoursePolicy = "repeat_course_policy"
    }
}

// MARK: - Policy Correction (for GitHub submission)

struct PolicyCorrection: Codable {
    let schoolID: String
    let policyName: String
    let currentValue: String
    let correctedValue: String
    let source: String?
    let submittedBy: String
    let submittedDate: Date
    
    enum CodingKeys: String, CodingKey {
        case schoolID = "school_id"
        case policyName = "policy_name"
        case currentValue = "current_value"
        case correctedValue = "corrected_value"
        case source
        case submittedBy = "submitted_by"
        case submittedDate = "submitted_date"
    }
}

// MARK: - Scraper Recipe

struct ScraperRecipe: Codable {
    let id: String
    let name: String
    let format: String // "acalog", "banner"
    let script: String // JavaScript code
    let selectors: [String: String]
    let version: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, format, script, selectors, version
    }
}
