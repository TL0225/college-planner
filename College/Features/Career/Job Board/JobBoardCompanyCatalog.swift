// JobBoardCompanyCatalog.swift
// Feature: Career / Job Board
// Purpose: Curated employer catalog for the company picker sheet.

import Foundation

struct JobBoardCompanyCatalogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let careersURL: String
    let platform: JobBoardPlatform
    let keywords: [String]

    init(
        displayName: String,
        careersURL: String,
        platform: JobBoardPlatform,
        keywords: [String] = []
    ) {
        self.id = Self.slugify(displayName)
        self.displayName = displayName
        self.careersURL = careersURL
        self.platform = platform
        self.keywords = keywords
    }

    private static func slugify(_ displayName: String) -> String {
        let lowered = displayName.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func asCompany() -> JobBoardCompany {
        JobBoardCompany(
            slug: id,
            displayName: displayName,
            careersURL: careersURL,
            enabled: true,
            platform: platform
        )
    }
}

enum JobBoardCompanyCatalog {
    static let entries: [JobBoardCompanyCatalogEntry] = [
        // Workday
        JobBoardCompanyCatalogEntry(
            displayName: "NVIDIA",
            careersURL: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Nike",
            careersURL: "https://nike.wd1.myworkdayjobs.com/nikeinc",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Target",
            careersURL: "https://target.wd5.myworkdayjobs.com/targetcareers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Walmart",
            careersURL: "https://walmart.wd5.myworkdayjobs.com/WalmartExternal",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Cisco",
            careersURL: "https://cisco.wd1.myworkdayjobs.com/External",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Adobe",
            careersURL: "https://adobe.wd5.myworkdayjobs.com/external_experienced",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Salesforce",
            careersURL: "https://salesforce.wd12.myworkdayjobs.com/External",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Deloitte",
            careersURL: "https://deloitte.wd5.myworkdayjobs.com/en-US/ExternalCareers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "PwC",
            careersURL: "https://pwc.wd3.myworkdayjobs.com/Global_Experienced_Careers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Boeing",
            careersURL: "https://boeing.wd1.myworkdayjobs.com/EXTERNAL_CAREERS",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Disney",
            careersURL: "https://disney.wd5.myworkdayjobs.com/disneycareers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Starbucks",
            careersURL: "https://starbucks.wd1.myworkdayjobs.com/External",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Mastercard",
            careersURL: "https://mastercard.wd1.myworkdayjobs.com/CorporateCareers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Visa",
            careersURL: "https://visa.wd5.myworkdayjobs.com/VisaCareers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Pfizer",
            careersURL: "https://pfizer.wd1.myworkdayjobs.com/PfizerCareers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Insmed",
            careersURL: "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Capital One",
            careersURL: "https://capitalone.wd12.myworkdayjobs.com/Capital_One",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Intuit",
            careersURL: "https://intuit.wd1.myworkdayjobs.com/External",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "ServiceNow",
            careersURL: "https://servicenow.wd1.myworkdayjobs.com/careers",
            platform: .workday
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Workday",
            careersURL: "https://workday.wd5.myworkdayjobs.com/Workday",
            platform: .workday
        ),

        // Greenhouse
        JobBoardCompanyCatalogEntry(
            displayName: "Stripe",
            careersURL: "https://boards.greenhouse.io/stripe",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Airbnb",
            careersURL: "https://boards.greenhouse.io/airbnb",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Coinbase",
            careersURL: "https://boards.greenhouse.io/coinbase",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Dropbox",
            careersURL: "https://boards.greenhouse.io/dropbox",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Discord",
            careersURL: "https://boards.greenhouse.io/discord",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Figma",
            careersURL: "https://boards.greenhouse.io/figma",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Notion",
            careersURL: "https://boards.greenhouse.io/notion",
            platform: .greenhouse
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Robinhood",
            careersURL: "https://boards.greenhouse.io/robinhood",
            platform: .greenhouse
        ),

        // Lever
        JobBoardCompanyCatalogEntry(
            displayName: "Palantir",
            careersURL: "https://jobs.lever.co/palantir",
            platform: .lever
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Uber",
            careersURL: "https://jobs.lever.co/uber",
            platform: .lever
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Spotify",
            careersURL: "https://jobs.lever.co/spotify",
            platform: .lever
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Netflix",
            careersURL: "https://jobs.lever.co/netflix",
            platform: .lever
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "BuiltIn",
            careersURL: "https://builtin.com/jobs",
            platform: .builtIn,
            keywords: ["public", "hub", "startup", "tech"]
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Jobicy · Remote",
            careersURL: "https://jobicy.com/remote-jobs",
            platform: .jobicy,
            keywords: ["remote", "public", "hub"]
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "RemoteOK",
            careersURL: "https://remoteok.com",
            platform: .remoteOK,
            keywords: ["remote", "public"]
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "Y Combinator · Jobs",
            careersURL: "https://www.ycombinator.com/jobs",
            platform: .yCombinator,
            keywords: ["startup", "yc", "public"]
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "USAJobs · Federal",
            careersURL: "https://www.usajobs.gov/Search/Results",
            platform: .usajobs,
            keywords: ["federal", "government", "public"]
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "NYC · City Jobs",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs,
            keywords: ["nyc", "new york city", "government", "public"]
        ),
        JobBoardCompanyCatalogEntry(
            displayName: "NY State · Jobs",
            careersURL: "https://statejobs.ny.gov/public/vacancyTable.cfm",
            platform: .nyStateJobs,
            keywords: ["new york", "state", "government", "public"]
        ),
    ]

    static func search(_ query: String, excludingTracked trackedSlugs: Set<String> = []) -> [JobBoardCompanyCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return entries
        }

        let lowered = trimmed.lowercased()
        let tokens = lowered.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return entries.filter { entry in
            let haystack = ([entry.displayName, entry.id] + entry.keywords).joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
        .sorted { lhs, rhs in
            let lhsTracked = trackedSlugs.contains(lhs.id)
            let rhsTracked = trackedSlugs.contains(rhs.id)
            if lhsTracked != rhsTracked { return !lhsTracked }
            let lhsPrefix = lhs.displayName.lowercased().hasPrefix(lowered)
            let rhsPrefix = rhs.displayName.lowercased().hasPrefix(lowered)
            if lhsPrefix != rhsPrefix { return lhsPrefix }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }
}
