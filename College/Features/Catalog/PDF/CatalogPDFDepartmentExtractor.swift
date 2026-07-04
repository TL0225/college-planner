// CatalogPDFDepartmentExtractor.swift
// Feature: Catalog
// Purpose: Generic, school-agnostic extraction of academic departments and the
//          department<->course / department<->program relationships from a
//          catalog PDF's structural signals (running headers, "Department of X"
//          headings, and course-code-prefix grouping).

import Foundation

/// A department recognized from a catalog PDF, with the page span it occupies and
/// the course-code subject prefixes that belong to it.
struct CatalogPDFDepartment: Sendable, Hashable {
    let name: String
    /// Representative subject prefix (e.g. `ACCT`, `15`) when one dominates the span.
    let code: String?
    let startPage: Int
    let endPage: Int
    let subjectPrefixes: [String]
}

/// Lookups derived from department recognition: page -> department and
/// subject-prefix -> department, used to attach departments to programs/courses.
struct CatalogPDFDepartmentIndex: Sendable {
    let departments: [CatalogPDFDepartment]
    let departmentNameByPage: [Int: String]
    let departmentNameBySubject: [String: String]

    func departmentName(forPage page: Int) -> String? { departmentNameByPage[page] }
    func departmentName(forSubject subject: String) -> String? {
        departmentNameBySubject[subject.uppercased()]
    }

    static let empty = CatalogPDFDepartmentIndex(
        departments: [],
        departmentNameByPage: [:],
        departmentNameBySubject: [:]
    )
}

enum CatalogPDFDepartmentExtractor {
    // Brooklyn-style running header: "Accounting 82 Programs and Courses of Instruction".
    private static let runningHeaderRegex = try? NSRegularExpression(
        pattern: #"^(.{3,55}?)\s+\d{1,4}\s+Programs and Courses of Instruction$"#
    )
    // "Department of Biomedical Engineering" / "... Courses".
    private static let departmentOfRegex = try? NSRegularExpression(
        pattern: #"^Department of ([A-Z][A-Za-z ,&'/-]{2,50}?)(?:\s+Courses)?$"#
    )
    // "Computational Biology Department".
    private static let xDepartmentRegex = try? NSRegularExpression(
        pattern: #"^([A-Z][A-Za-z ,&'/-]{2,50}) Department$"#
    )
    // Subject section header carrying its course-code prefix, e.g.
    // "986 Accounting (Graduate) (ACGB)" or "Biology (BISC)". The trailing code
    // is the authoritative subject prefix for that department.
    private static let subjectHeaderRegex = try? NSRegularExpression(
        pattern: #"^(?:\d{1,4}\s+)?([A-Z][A-Za-z ,&/'.()-]{2,55}?)\s+\(([A-Z]{2,6})\)$"#
    )
    // Course headers used to learn subject prefixes per page.
    private static let alphaCourseRegex = try? NSRegularExpression(
        pattern: #"^([A-Z]{2,6})\s+\d{3,4}[A-Z]?\b"#
    )
    private static let numCourseRegex = try? NSRegularExpression(
        pattern: #"^(\d{2})-\d{3}\b"#
    )

    static func build(from lines: [CatalogPDFLine]) -> CatalogPDFDepartmentIndex {
        guard !lines.isEmpty else { return .empty }
        let pageCount = (lines.map { $0.pageIndex }.max() ?? 0) + 1

        // 0) Set of all course-code subject prefixes anywhere in the document. A
        //    `Name (CODE)` header is only treated as a department when CODE actually
        //    labels courses, which filters out non-academic codes (aid, fees, etc.).
        var allCourseSubjects = Set<String>()
        for line in lines { if let s = subjectPrefix(in: line.text) { allCourseSubjects.insert(s) } }

        // 1) Collect department-name anchors per page from heading signals.
        //    `Name (CODE)` subject headers also give an authoritative code->name map.
        var anchorsByPage: [Int: String] = [:]
        var explicitSubjectName: [String: String] = [:]
        var explicitSubjectPage: [String: Int] = [:]
        for line in lines {
            if let header = recognizeSubjectHeader(line.text), allCourseSubjects.contains(header.code) {
                if anchorsByPage[line.pageIndex] == nil { anchorsByPage[line.pageIndex] = header.name }
                if explicitSubjectName[header.code] == nil { explicitSubjectName[header.code] = header.name }
                explicitSubjectPage[header.name] = min(explicitSubjectPage[header.name] ?? line.pageIndex, line.pageIndex)
            }
            guard anchorsByPage[line.pageIndex] == nil else { continue }
            if let name = recognizeDepartmentName(line.text) {
                anchorsByPage[line.pageIndex] = name
            }
        }

        // 2) Assign every page to the most recent department anchor (forward fill),
        //    so a department "owns" its pages until the next department begins.
        var departmentNameByPage: [Int: String] = [:]
        var current: String?
        for page in 0..<pageCount {
            if let anchor = anchorsByPage[page] { current = anchor }
            if let current { departmentNameByPage[page] = current }
        }

        // 3) Learn subject prefix -> department by majority vote over course headers.
        var subjectVotes: [String: [String: Int]] = [:]
        for line in lines {
            guard let subject = subjectPrefix(in: line.text) else { continue }
            guard let dept = departmentNameByPage[line.pageIndex] else { continue }
            subjectVotes[subject, default: [:]][dept, default: 0] += 1
        }
        var departmentNameBySubject: [String: String] = [:]
        var subjectsByDept: [String: Set<String>] = [:]
        for (subject, votes) in subjectVotes {
            guard let winner = votes.max(by: { $0.value < $1.value })?.key else { continue }
            departmentNameBySubject[subject] = winner
            subjectsByDept[winner, default: []].insert(subject)
        }
        // `Name (CODE)` headers are authoritative and also cover subjects whose course
        // headers never coincided with a page anchor (e.g. Fordham, which labels its
        // subject sections only via these headers).
        for (subject, name) in explicitSubjectName {
            departmentNameBySubject[subject] = name
            subjectsByDept[name, default: []].insert(subject)
        }

        // 4) Build department spans (first..last page the name owns).
        var firstPage: [String: Int] = [:]
        var lastPage: [String: Int] = [:]
        for page in 0..<pageCount {
            guard let dept = departmentNameByPage[page] else { continue }
            if firstPage[dept] == nil { firstPage[dept] = page }
            lastPage[dept] = page
        }

        var departments: [CatalogPDFDepartment] = []
        let departmentNames = Set(firstPage.keys).union(subjectsByDept.keys)
        for name in departmentNames {
            let fallbackPage = explicitSubjectPage[name] ?? 0
            let prefixes = subjectsByDept[name].map { $0.sorted() } ?? []
            departments.append(
                CatalogPDFDepartment(
                    name: name,
                    code: dominantPrefix(prefixes, votes: subjectVotes, dept: name),
                    startPage: firstPage[name] ?? fallbackPage,
                    endPage: lastPage[name] ?? (firstPage[name] ?? fallbackPage),
                    subjectPrefixes: prefixes
                )
            )
        }
        departments.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return CatalogPDFDepartmentIndex(
            departments: departments,
            departmentNameByPage: departmentNameByPage,
            departmentNameBySubject: departmentNameBySubject
        )
    }

    // MARK: - Recognition

    /// Returns a cleaned department name when a line is a recognizable department
    /// heading (running header, "Department of X", or "X Department"); else nil.
    static func recognizeDepartmentName(_ rawLine: String) -> String? {
        let line = rawLine
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count <= 90 else { return nil }

        if let name = firstGroup(runningHeaderRegex, in: line),
           isPlausibleDepartmentName(name) {
            return cleanName(name)
        }
        if let name = firstGroup(departmentOfRegex, in: line),
           isPlausibleDepartmentName(name) {
            return cleanName(name)
        }
        if let name = firstGroup(xDepartmentRegex, in: line),
           isPlausibleDepartmentName(name),
           !name.lowercased().hasPrefix("education") {
            return cleanName(name)
        }
        return nil
    }

    /// Recognizes a `Name (CODE)` subject section header, returning the cleaned
    /// department name and its course-code prefix.
    static func recognizeSubjectHeader(_ rawLine: String) -> (name: String, code: String)? {
        let line = rawLine
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count <= 80,
              let regex = subjectHeaderRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 3,
              let nameRange = Range(match.range(at: 1), in: line),
              let codeRange = Range(match.range(at: 2), in: line) else { return nil }
        let name = cleanName(String(line[nameRange]))
        let code = String(line[codeRange]).uppercased()
        guard isPlausibleDepartmentName(name) else { return nil }
        return (name, code)
    }

    private static func subjectPrefix(in line: String) -> String? {
        if let g = firstGroup(alphaCourseRegex, in: line) { return g.uppercased() }
        if let g = firstGroup(numCourseRegex, in: line) { return g }
        return nil
    }

    private static func dominantPrefix(
        _ prefixes: [String],
        votes: [String: [String: Int]],
        dept: String
    ) -> String? {
        prefixes.max { lhs, rhs in
            (votes[lhs]?[dept] ?? 0) < (votes[rhs]?[dept] ?? 0)
        }
    }

    private static func cleanName(_ name: String) -> String {
        name
            .replacingOccurrences(of: #"\s+Courses$"#, with: "", options: .regularExpression)
            // Drop a trailing level qualifier, e.g. "Accounting (Graduate)" -> "Accounting",
            // so undergraduate/graduate subject variants collapse to one department.
            .replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
    }

    /// Rejects prose and structural noise so only true department names survive.
    static func isPlausibleDepartmentName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3, name.count <= 55 else { return false }
        guard let first = name.first, first.isUppercase || first.isLetter else { return false }
        // Must start with a capital letter.
        guard name.first?.isUppercase == true else { return false }
        // Sentence-like prose markers never appear in a department heading.
        if name.range(of: #"[.!?]"#, options: .regularExpression) != nil { return false }
        // All-caps multi-word banners ("BACHELOR OF COMPUTER SCIENCE AND ARTS").
        let letters = name.filter { $0.isLetter }
        if !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }), name.split(separator: " ").count >= 2 {
            return false
        }
        // Non-academic codes that look like subjects but aren't departments.
        let lowerName = name.lowercased()
        let nonDepartment = ["aid", "scholarship", "fellowship", "grant", "loan", "tuition", "fee",
                             "deposit", "progress", "elective", "satisfactory", "probation", "dean's list"]
        if nonDepartment.contains(where: { lowerName.contains($0) }) { return false }
        let lower = " \(name.lowercased()) "
        let proseTokens = [" is ", " are ", " by ", " the ", " of the ", " for ", " with ", " and the ",
                           " offering ", " program ", " programs ", " requirements", " seminar ", " about "]
        if proseTokens.contains(where: { lower.contains($0) }) {
            // "Health and Nutrition Sciences" contains " and " legitimately; allow a
            // single connective but reject multi-clause prose.
            let words = name.split(separator: " ")
            if words.count > 6 { return false }
        }
        // Reject lines that are mostly lowercase (prose), require title-case-ish.
        let wordList = name.split(separator: " ")
        let titleCased = wordList.filter { $0.first?.isUppercase == true || $0.allSatisfy { !$0.isLetter } }
        if Double(titleCased.count) / Double(max(1, wordList.count)) < 0.6 { return false }
        return true
    }

    private static func firstGroup(_ regex: NSRegularExpression?, in line: String) -> String? {
        guard let regex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
