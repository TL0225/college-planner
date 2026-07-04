// RateMyProfessorService.swift
// Feature: Courses
// Purpose: Best-effort RateMyProfessors enrichment for known course instructors.

import Foundation

enum RateMyProfessorLookupResult: Equatable, Sendable {
    case match(RateMyProfessorMatch)
    case notFound
    case unavailable
}

struct RateMyProfessorMatch: Codable, Equatable, Sendable {
    let teacherID: String
    let legacyID: Int
    let firstName: String
    let lastName: String
    let department: String
    let averageRating: Double
    let averageDifficulty: Double
    let ratingCount: Int
    let wouldTakeAgainPercent: Double?

    var displayName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var profileURL: URL? {
        URL(string: "https://www.ratemyprofessors.com/professor/\(legacyID)")
    }
}

struct RateMyProfessorTeacherCandidate: Decodable, Equatable, Sendable {
    let id: String
    let legacyId: Int?
    let firstName: String?
    let lastName: String?
    let department: String?
    let avgRating: Double?
    let avgDifficulty: Double?
    let numRatings: Int?
    let wouldTakeAgainPercent: Double?
}

struct RateMyProfessorSchoolCandidate: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let city: String?
    let state: String?
}

enum RateMyProfessorMatcher {
    static let minimumRatingCount = 3

    static func selectSchool(
        from candidates: [RateMyProfessorSchoolCandidate],
        universityName: String,
        universityShortName: String?
    ) -> RateMyProfessorSchoolCandidate? {
        let acceptedNames = [universityName, universityShortName ?? ""]
            .map(normalizeSchoolName)
            .filter { !$0.isEmpty }
        guard !acceptedNames.isEmpty else { return nil }

        let exactMatches = candidates.filter { candidate in
            acceptedNames.contains(normalizeSchoolName(candidate.name))
        }

        return exactMatches.count == 1 ? exactMatches[0] : nil
    }

    static func selectTeacher(
        from candidates: [RateMyProfessorTeacherCandidate],
        professorName: String,
        courseCode: String?
    ) -> RateMyProfessorLookupResult {
        guard let parsedName = parseProfessorName(professorName) else {
            return .notFound
        }

        let nameMatches = candidates.compactMap { candidate -> RateMyProfessorTeacherCandidate? in
            guard
                let candidateLastName = candidate.lastName,
                normalizePersonToken(candidateLastName) == parsedName.lastName,
                firstNameMatches(stored: parsedName.firstName, candidate: candidate.firstName),
                (candidate.numRatings ?? 0) >= minimumRatingCount,
                candidate.legacyId != nil,
                candidate.avgRating != nil,
                candidate.avgDifficulty != nil
            else {
                return nil
            }
            return candidate
        }

        if nameMatches.count == 1 {
            return buildMatch(from: nameMatches[0])
        }

        if nameMatches.count > 1,
           let courseCode,
           let departmentMatch = uniqueDepartmentMatch(in: nameMatches, courseCode: courseCode) {
            return buildMatch(from: departmentMatch)
        }

        return .notFound
    }

    private static func buildMatch(from candidate: RateMyProfessorTeacherCandidate) -> RateMyProfessorLookupResult {
        guard
            let legacyID = candidate.legacyId,
            let averageRating = candidate.avgRating,
            let averageDifficulty = candidate.avgDifficulty,
            let ratingCount = candidate.numRatings,
            ratingCount >= minimumRatingCount
        else {
            return .notFound
        }

        return .match(
            RateMyProfessorMatch(
                teacherID: candidate.id,
                legacyID: legacyID,
                firstName: candidate.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                lastName: candidate.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                department: candidate.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                averageRating: averageRating,
                averageDifficulty: averageDifficulty,
                ratingCount: ratingCount,
                wouldTakeAgainPercent: candidate.wouldTakeAgainPercent
            )
        )
    }

    private static func uniqueDepartmentMatch(
        in candidates: [RateMyProfessorTeacherCandidate],
        courseCode: String
    ) -> RateMyProfessorTeacherCandidate? {
        let prefix = coursePrefix(from: courseCode)
        guard let prefix else { return nil }

        let scored = candidates.map { candidate in
            (candidate, departmentScore(candidate.department ?? "", coursePrefix: prefix))
        }
        let relevant = scored.filter { $0.1 > 0 }.map(\.0)
        return relevant.count == 1 ? relevant[0] : nil
    }

    private static func departmentScore(_ department: String, coursePrefix: String) -> Int {
        let normalizedDepartment = normalizeSearchText(department)
        guard !normalizedDepartment.isEmpty else { return 0 }

        let prefixKeywords: [String: [String]] = [
            "INFA": ["information", "cyber", "security", "network", "technology"],
            "CSIA": ["cyber", "security", "information"],
            "CMIT": ["computer", "information", "technology", "network"],
            "CS": ["computer", "science"],
            "CSC": ["computer", "science"],
            "CSEC": ["cyber", "security"],
            "DATA": ["data", "analytics", "statistics"],
            "MATH": ["math", "mathematics"],
            "STAT": ["statistics", "math"],
            "BUS": ["business", "management"],
            "MBA": ["business", "management"],
        ]

        let keywords = prefixKeywords[coursePrefix] ?? [coursePrefix.lowercased()]
        return keywords.reduce(0) { score, keyword in
            normalizedDepartment.contains(keyword) ? score + 1 : score
        }
    }

    private static func firstNameMatches(stored: ParsedProfessorName.FirstName, candidate: String?) -> Bool {
        guard let normalizedCandidate = candidate.map(normalizePersonToken), !normalizedCandidate.isEmpty else {
            return false
        }

        switch stored {
        case .full(let value):
            return value == normalizedCandidate
        case .initial(let initial):
            return normalizedCandidate.first == initial
        }
    }

    private struct ParsedProfessorName {
        enum FirstName {
            case full(String)
            case initial(Character)
        }

        let firstName: FirstName
        let lastName: String
    }

    private static func parseProfessorName(_ rawName: String) -> ParsedProfessorName? {
        var name = normalizeDisplayName(rawName)
        guard !name.isEmpty else { return nil }

        if name.contains(",") {
            let parts = name
                .split(separator: ",", maxSplits: 1)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 {
                name = "\(parts[1]) \(parts[0])"
            }
        }

        var tokens = name
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        while let first = tokens.first, isTitle(first) {
            tokens.removeFirst()
        }
        while let last = tokens.last, isSuffix(last) {
            tokens.removeLast()
        }

        guard tokens.count >= 2 else { return nil }

        let firstToken = normalizePersonToken(tokens[0])
        let lastToken = normalizePersonToken(tokens[tokens.count - 1])
        guard !firstToken.isEmpty, !lastToken.isEmpty else { return nil }

        let firstName: ParsedProfessorName.FirstName
        if firstToken.count == 1, let initial = firstToken.first {
            firstName = .initial(initial)
        } else {
            firstName = .full(firstToken)
        }

        return ParsedProfessorName(firstName: firstName, lastName: lastToken)
    }

    private static func normalizeDisplayName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[.]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePersonToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z]"#, with: "", options: .regularExpression)
    }

    private static func normalizeSchoolName(_ value: String) -> String {
        normalizeSearchText(value)
            .replacingOccurrences(of: #"\b(the|at)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTitle(_ value: String) -> Bool {
        let token = normalizePersonToken(value)
        return ["dr", "prof", "professor", "mr", "mrs", "ms", "miss"].contains(token)
    }

    private static func isSuffix(_ value: String) -> Bool {
        let token = normalizePersonToken(value)
        return ["jr", "sr", "ii", "iii", "iv", "phd", "edd", "md"].contains(token)
    }

    private static func coursePrefix(from courseCode: String) -> String? {
        let prefix = courseCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isLetter }
            .uppercased()
        return prefix.isEmpty ? nil : prefix
    }
}

final class RateMyProfessorCache: @unchecked Sendable {
    static let shared = RateMyProfessorCache()

    private struct CachedEntry: Codable {
        let status: String
        let match: RateMyProfessorMatch?
        let expiresAt: Date
    }

    private let defaults: UserDefaults
    private let keyPrefix = "rmp.lookup.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cachedResult(for key: String, now: Date = .now) -> RateMyProfessorLookupResult? {
        guard
            let data = defaults.data(forKey: storageKey(for: key)),
            let entry = try? JSONDecoder().decode(CachedEntry.self, from: data)
        else {
            return nil
        }

        guard entry.expiresAt > now else {
            defaults.removeObject(forKey: storageKey(for: key))
            return nil
        }

        switch entry.status {
        case "match":
            if let match = entry.match { return .match(match) }
            return nil
        case "notFound":
            return .notFound
        default:
            return nil
        }
    }

    func store(_ result: RateMyProfessorLookupResult, for key: String, now: Date = .now) {
        let entry: CachedEntry?
        switch result {
        case .match(let match):
            entry = CachedEntry(status: "match", match: match, expiresAt: now.addingTimeInterval(14 * 24 * 60 * 60))
        case .notFound:
            entry = CachedEntry(status: "notFound", match: nil, expiresAt: now.addingTimeInterval(24 * 60 * 60))
        case .unavailable:
            entry = nil
        }

        guard let entry, let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: storageKey(for: key))
    }

    private func storageKey(for key: String) -> String {
        keyPrefix + key
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
    }
}

final class RateMyProfessorService: @unchecked Sendable {
    static let shared = RateMyProfessorService()

    private let session: URLSession
    private let cache: RateMyProfessorCache
    private let endpoint = URL(string: "https://www.ratemyprofessors.com/graphql")!

    init(
        session: URLSession = URLSession(configuration: .ephemeral),
        cache: RateMyProfessorCache = .shared
    ) {
        self.session = session
        self.cache = cache
    }

    func lookup(
        professorName: String,
        universityName: String,
        universityShortName: String?,
        courseCode: String
    ) async -> RateMyProfessorLookupResult {
        let professorName = professorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let universityName = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let universityShortName = universityShortName?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !professorName.isEmpty, !universityName.isEmpty else {
            return .notFound
        }

        let cacheKey = [universityName, universityShortName ?? "", professorName, courseCode]
            .joined(separator: "|")
        if let cached = cache.cachedResult(for: cacheKey) {
            return cached
        }

        do {
            let schools = try await searchSchools(query: universityName)
            guard let school = RateMyProfessorMatcher.selectSchool(
                from: schools,
                universityName: universityName,
                universityShortName: universityShortName
            ) else {
                cache.store(.notFound, for: cacheKey)
                return .notFound
            }

            let teachers = try await searchTeachers(professorName: professorName, schoolID: school.id)
            let result = RateMyProfessorMatcher.selectTeacher(
                from: teachers,
                professorName: professorName,
                courseCode: courseCode
            )
            cache.store(result, for: cacheKey)
            return result
        } catch {
            return .unavailable
        }
    }

    private func searchSchools(query: String) async throws -> [RateMyProfessorSchoolCandidate] {
        let graphQL = """
        query NewSearchSchoolsQuery($query: String!) {
          newSearch {
            schools(query: { text: $query }, first: 5) {
              edges {
                node {
                  id
                  name
                  city
                  state
                }
              }
            }
          }
        }
        """
        let response: SchoolSearchResponse = try await postGraphQL(
            query: graphQL,
            variables: ["query": query]
        )
        return response.data?.newSearch.schools.edges.map(\.node) ?? []
    }

    private func searchTeachers(professorName: String, schoolID: String) async throws -> [RateMyProfessorTeacherCandidate] {
        let graphQL = """
        query NewSearchTeachersQuery($query: TeacherSearchQuery!) {
          newSearch {
            teachers(query: $query, first: 10) {
              edges {
                node {
                  id
                  legacyId
                  firstName
                  lastName
                  department
                  avgRating
                  avgDifficulty
                  numRatings
                  wouldTakeAgainPercent
                }
              }
            }
          }
        }
        """
        let response: TeacherSearchResponse = try await postGraphQL(
            query: graphQL,
            variables: [
                "query": [
                    "text": professorName,
                    "schoolID": schoolID,
                    "fallback": true,
                ] as [String: Any]
            ]
        )
        return response.data?.newSearch.teachers.edges.map(\.node) ?? []
    }

    private func postGraphQL<Response: Decodable>(
        query: String,
        variables: [String: Any]
    ) async throws -> Response {
        let body = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables,
        ])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.ratemyprofessors.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded
    }
}

private struct SchoolSearchResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let newSearch: NewSearch
    }

    struct NewSearch: Decodable {
        let schools: EdgeList
    }

    struct EdgeList: Decodable {
        let edges: [Edge]
    }

    struct Edge: Decodable {
        let node: RateMyProfessorSchoolCandidate
    }
}

private struct TeacherSearchResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let newSearch: NewSearch
    }

    struct NewSearch: Decodable {
        let teachers: EdgeList
    }

    struct EdgeList: Decodable {
        let edges: [Edge]
    }

    struct Edge: Decodable {
        let node: RateMyProfessorTeacherCandidate
    }
}
