// CatalogVerificationSuite.swift
// Feature: Catalog
// Purpose: Deterministic, offline verification that every bundled school in
//          schools.json is correctly configured and maps to an implemented
//          scraper path. Produces a per-school coverage matrix report.
// Data: Reads the real bundled schools.json via SchoolManifestCatalog.bundled().
//
// This is the "configuration + coverage" half of the catalog verification suite.
// It always runs (no network). The end-to-end scrape proof lives in
// CatalogVerificationLiveSuiteTests (gated behind COLLEGE_RUN_LIVE_TESTS=1).

import XCTest
import Darwin
@testable import College

/// Canonical catalog parser families the app actually implements end-to-end.
enum CatalogParserFamily: String, CaseIterable {
    /// Modern Campus / Acalog HTML catalogs (UniversalCatalogScraper Acalog path).
    case modernCampus = "moderncampus"
    /// CourseLeaf bulletins (CourseLeafEngine / CourseLeaf parsers).
    case courseLeaf = "courseleaf"
    /// PDF-only bulletins (CatalogPDF ingest pipeline).
    case pdf = "pdf"
    /// School-specific custom scraper (not part of the generic verified paths).
    case custom = "custom"
    /// Banner self-service catalogs (declared but not generically implemented).
    case banner = "banner"
    /// Coursedog catalogs (declared support, parser lands in Wave 6).
    case coursedog = "coursedog"
    /// Unknown / unmapped.
    case unknown = "unknown"

    /// Families whose full scrape→parse→display path is proven by the live suite.
    static let liveVerifiable: Set<CatalogParserFamily> = [.modernCampus, .courseLeaf, .coursedog]

    static func from(declaredFormat: String) -> CatalogParserFamily {
        switch declaredFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "acalog", "moderncampus": return .modernCampus
        case "courseleaf": return .courseLeaf
        case "pdf": return .pdf
        case "custom": return .custom
        case "banner": return .banner
        case "coursedog": return .coursedog
        default: return .unknown
        }
    }
}

/// One school's verification record (shared by the offline and live suites).
struct SchoolVerificationRecord {
    let schoolID: String
    let name: String
    let declaredFormat: String
    let parserFamily: CatalogParserFamily
    let scraperBacked: Bool

    var checks: [(name: String, passed: Bool, detail: String)] = []

    // Populated by the live suite; left at -1 when not exercised.
    var programsFound: Int = -1
    var coursesFound: Int = -1
    var sampleRequirementsFound: Int = -1
    var sampleRequirementCourses: Int = -1
    var severity: String = "not-run"
    var liveError: String?
    /// Set when a failure is likely environmental (offline, WAF, marathon partial crawl).
    var environmentalSkip: Bool = false

    var failed: Bool { checks.contains { !$0.passed } && !environmentalSkip }

    mutating func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        checks.append((name: name, passed: passed, detail: detail))
    }
}

/// Ranks programs for live requirement probes (majors before minors).
enum CatalogVerificationSampleSelection {
    static func rankedCandidates(from programs: [ScrapedProgram], limit: Int = 6) -> [ScrapedProgram] {
        Array(
            programs
                .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { rank($0) > rank($1) }
                .prefix(limit)
        )
    }

    static func rank(_ program: ScrapedProgram) -> Int {
        var score = 0
        let name = program.name.lowercased()
        let type = program.type.lowercased()

        if type == "major" { score += 20 }
        if type == "minor" { score -= 12 }
        if name.contains("minor") { score -= 10 }
        if name.contains("certificate") { score -= 6 }
        if name.contains("b.s") || name.contains("b.a") || name.contains("bachelor") { score += 8 }
        if name.contains("m.s") || name.contains("master") { score += 4 }
        if name.contains("politics") || name.contains("policy") { score -= 4 }
        return score
    }
}

/// Renders a fixed-width coverage matrix that is attached to the test result and
/// printed to the failure message when something regresses.
enum CatalogVerificationReport {
    static func render(_ records: [SchoolVerificationRecord]) -> String {
        var lines: [String] = []
        lines.append("CATALOG VERIFICATION COVERAGE MATRIX")
        lines.append(String(repeating: "=", count: 92))
        lines.append(String(
            format: "%-26@  %-12@  %-14@  %-8@  %@",
            "SCHOOL" as NSString,
            "FORMAT" as NSString,
            "PARSER" as NSString,
            "BACKED" as NSString,
            "CONFIG" as NSString
        ))
        lines.append(String(repeating: "-", count: 92))
        for record in records.sorted(by: { $0.name < $1.name }) {
            let configStatus = record.failed ? "FAIL" : "OK"
            lines.append(String(
                format: "%-26@  %-12@  %-14@  %-8@  %@",
                String(record.name.prefix(26)) as NSString,
                record.declaredFormat as NSString,
                record.parserFamily.rawValue as NSString,
                (record.scraperBacked ? "yes" : "no") as NSString,
                configStatus as NSString
            ))
            for failedCheck in record.checks where !failedCheck.passed {
                lines.append("      ✗ \(failedCheck.name): \(failedCheck.detail)")
            }
            if record.programsFound >= 0 || record.liveError != nil {
                if record.environmentalSkip, let liveError = record.liveError {
                    lines.append("      ○ live (environmental): \(liveError)")
                } else if let liveError = record.liveError {
                    lines.append("      ⚠︎ live: \(liveError)")
                } else {
                    lines.append(String(
                        format: "      • live: programs=%d courses=%d sampleReqs=%d sampleReqCourses=%d severity=%@",
                        record.programsFound,
                        record.coursesFound,
                        record.sampleRequirementsFound,
                        record.sampleRequirementCourses,
                        record.severity as NSString
                    ))
                }
            }
        }
        lines.append(String(repeating: "=", count: 92))
        return lines.joined(separator: "\n")
    }

    static func renderSchoolProgress(_ record: SchoolVerificationRecord) -> String {
        var lines: [String] = []
        lines.append("school=\(record.schoolID) name=\(record.name)")
        lines.append("parser=\(record.parserFamily.rawValue) format=\(record.declaredFormat)")
        if record.environmentalSkip {
            lines.append("status=environmental severity=\(record.severity)")
            if let liveError = record.liveError {
                lines.append("detail=\(liveError)")
            }
        } else if record.failed {
            lines.append("status=fail severity=\(record.severity)")
            if let liveError = record.liveError {
                lines.append("error=\(liveError)")
            }
            for failedCheck in record.checks where !failedCheck.passed {
                lines.append("check_fail \(failedCheck.name): \(failedCheck.detail)")
            }
        } else if record.checks.isEmpty {
            lines.append("status=skipped severity=\(record.severity)")
        } else {
            lines.append(
                "status=pass programs=\(record.programsFound) courses=\(record.coursesFound) " +
                "sampleReqs=\(record.sampleRequirementsFound) sampleReqCourses=\(record.sampleRequirementCourses) " +
                "severity=\(record.severity)"
            )
        }
        for check in record.checks where check.passed {
            lines.append("check_ok \(check.name): \(check.detail)")
        }
        return lines.joined(separator: "\n")
    }

    static func attach(_ report: String, name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(string: report)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}

/// Unbuffered progress lines for long-running live catalog verification.
enum CatalogVerificationProgressLog {
    static func log(_ message: String) {
        let line = "[catalog-live] \(message)"
        print(line)
        fflush(stdout)
        fputs(line + "\n", stderr)
    }

    static func familyStarted(_ family: CatalogParserFamily, schoolCount: Int) {
        log("FAMILY_START \(family.rawValue) schools=\(schoolCount)")
    }

    static func schoolStarted(
        family: CatalogParserFamily,
        school: SchoolManifest,
        index: Int,
        total: Int
    ) {
        log("START \(index)/\(total) family=\(family.rawValue) school=\(school.id) name=\(school.name)")
    }

    static func schoolFinished(
        family: CatalogParserFamily,
        record: SchoolVerificationRecord,
        index: Int,
        total: Int,
        elapsed: TimeInterval,
        testCase: XCTestCase
    ) {
        let status: String
        if record.environmentalSkip {
            status = "ENV_SKIP"
        } else if record.failed {
            status = "FAIL"
        } else if record.checks.isEmpty {
            status = "SKIP"
        } else {
            status = "PASS"
        }

        let detail = CatalogVerificationReport.renderSchoolProgress(record)
        log(
            "DONE \(index)/\(total) family=\(family.rawValue) school=\(record.schoolID) " +
            "status=\(status) elapsed=\(Int(elapsed.rounded()))s"
        )
        log(detail)

        let attachment = XCTAttachment(string: detail)
        attachment.name = "live-progress-\(record.schoolID)"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    static func familyFinished(_ family: CatalogParserFamily, passed: Int, failed: Int, environmental: Int) {
        log(
            "FAMILY_DONE \(family.rawValue) passed=\(passed) failed=\(failed) environmental=\(environmental)"
        )
    }
}

/// Deterministic, offline verification of the bundled school catalog config.
@MainActor
final class CatalogVerificationSuiteTests: XCTestCase {

    private static let knownFormats: Set<String> = [
        "acalog", "moderncampus", "courseleaf", "banner", "custom", "pdf", "coursedog"
    ]

    /// Schools that are flagged scraper-backed but do NOT yet have a generic,
    /// live-verified parser path. New additions must be acknowledged here (with a
    /// reason) or the coverage-lock test will fail — preventing silent gaps.
    private static let knownCoverageExceptions: [String: String] = [:]

    private func buildBaselineRecords() -> [SchoolVerificationRecord] {
        SchoolManifestCatalog.bundled().map { school in
            SchoolVerificationRecord(
                schoolID: school.id,
                name: school.name,
                declaredFormat: school.catalogFormat.lowercased(),
                parserFamily: .from(declaredFormat: school.catalogFormat),
                scraperBacked: SchoolManifestSelection.isScraperBacked(school)
            )
        }
    }

    func testBundledCatalogIsNonEmptyAndUnique() {
        let schools = SchoolManifestCatalog.bundled()
        XCTAssertFalse(schools.isEmpty, "Bundled schools.json failed to load")

        let ids = schools.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate school ids in schools.json: \(ids)")

        let names = schools.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Duplicate school names in schools.json: \(names)")
    }

    func testEverySchoolManifestIsWellFormed() {
        let schools = SchoolManifestCatalog.bundled()
        var records = buildBaselineRecords()

        for (index, school) in schools.enumerated() {
            var record = records[index]

            record.check("id", !school.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, school.id)
            record.check("name", !school.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, school.name)
            record.check("profile_url", !school.profileURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let format = school.catalogFormat.lowercased()
            record.check(
                "known_format",
                Self.knownFormats.contains(format),
                "format='\(format)' not in \(Self.knownFormats.sorted())"
            )

            let catalogURL = (school.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            record.check("catalog_url_present", !catalogURL.isEmpty)

            if let url = URL(string: catalogURL), let scheme = url.scheme?.lowercased() {
                record.check(
                    "catalog_url_valid",
                    (scheme == "http" || scheme == "https") && url.host?.isEmpty == false,
                    catalogURL
                )
            } else {
                record.check("catalog_url_valid", false, "unparseable: \(catalogURL)")
            }

            records[index] = record
        }

        let report = CatalogVerificationReport.render(records)
        CatalogVerificationReport.attach(report, name: "manifest-wellformed", to: self)

        let failures = records.filter(\.failed)
        XCTAssertTrue(failures.isEmpty, "Malformed school manifests:\n\(report)")
    }

    /// Locks the bundled Modern Campus / Acalog school set exercised by the live suite.
    func testBundledModernCampusSchoolIDsAreLocked() {
        let modernCampus = SchoolManifestCatalog.bundled().filter {
            CatalogParserFamily.from(declaredFormat: $0.catalogFormat) == .modernCampus
        }
        XCTAssertEqual(modernCampus.count, 5)
        XCTAssertEqual(
            Set(modernCampus.map(\.id)),
            Set([
                "dakota_state_university",
                "ohio_university",
                "purdue_university",
                "stony_brook",
                "university_at_buffalo",
            ])
        )
    }

    /// Locks the bundled Coursedog school set exercised by the live suite.
    func testBundledCoursedogSchoolIDsAreLocked() {
        let coursedog = SchoolManifestCatalog.bundled().filter {
            CatalogParserFamily.from(declaredFormat: $0.catalogFormat) == .coursedog
        }
        XCTAssertEqual(coursedog.count, 2)
        XCTAssertEqual(
            Set(coursedog.map(\.id)),
            Set([
                "cuny_city_college",
                "rutgers_nb",
            ])
        )
    }

    /// Locks the coverage matrix: every scraper-backed school must map to a
    /// live-verifiable parser family, OR be explicitly acknowledged as an exception.
    func testScraperBackedSchoolsMapToVerifiedParserOrAcknowledgedException() {
        let records = buildBaselineRecords()
        let report = CatalogVerificationReport.render(records)
        CatalogVerificationReport.attach(report, name: "coverage-matrix", to: self)

        var unexpectedGaps: [String] = []
        var staleExceptions = Set(Self.knownCoverageExceptions.keys)

        for record in records where record.scraperBacked {
            let isVerifiable = CatalogParserFamily.liveVerifiable.contains(record.parserFamily)
            if isVerifiable {
                if Self.knownCoverageExceptions[record.schoolID] != nil {
                    XCTFail("\(record.schoolID) is now verifiable (\(record.parserFamily.rawValue)); remove it from knownCoverageExceptions.")
                }
                continue
            }
            // Not generically verifiable — must be an acknowledged exception.
            if Self.knownCoverageExceptions[record.schoolID] != nil {
                staleExceptions.remove(record.schoolID)
            } else {
                unexpectedGaps.append("\(record.schoolID) (format=\(record.declaredFormat), family=\(record.parserFamily.rawValue))")
            }
        }

        XCTAssertTrue(
            unexpectedGaps.isEmpty,
            "Scraper-backed schools without a verified parser path (implement a parser or add to knownCoverageExceptions):\n  - "
                + unexpectedGaps.joined(separator: "\n  - ")
                + "\n\n\(report)"
        )

        XCTAssertTrue(
            staleExceptions.isEmpty,
            "knownCoverageExceptions lists schools that are no longer scraper-backed/unverified (clean them up): \(staleExceptions.sorted())"
        )
    }

    /// Every parser family the bundled catalog relies on must be one this app
    /// recognizes (no `.unknown` families leaking from a typo'd catalog_format).
    func testNoUnknownParserFamilies() {
        let records = buildBaselineRecords()
        let unknowns = records.filter { $0.parserFamily == .unknown }
        XCTAssertTrue(
            unknowns.isEmpty,
            "Schools with unrecognized catalog_format: \(unknowns.map { "\($0.schoolID)=\($0.declaredFormat)" })"
        )
    }
}
