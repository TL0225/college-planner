// CatalogPDFSampleHarnessTests.swift
// Feature: Catalog
// Purpose: Ad-hoc end-to-end harness for running the catalog PDF scraper against a real PDF.
// Data: Read-only extraction; does NOT persist to the app database.

import XCTest
@testable import College

/// Runs the catalog PDF extraction pipeline against an arbitrary local PDF and prints a report.
///
/// This calls `CatalogPDFPipeline.run` directly, which performs extraction/classification only.
/// It never calls `runPDFCatalogSync` or any persistence, so the app database is untouched.
///
/// Usage:
///   PDF_CATALOG_SAMPLE=/absolute/path/to/catalog.pdf \
///   PDF_CATALOG_SAMPLE_SCHOOL=fordham_university \
///   xcodebuild test -scheme College -destination 'platform=macOS' \
///     -only-testing:CollegeTests/CatalogPDFSampleHarnessTests
///
/// `PDF_CATALOG_SAMPLE_SCHOOL` is optional (defaults to a generic profile).
final class CatalogPDFSampleHarnessTests: XCTestCase {
    func testRunSamplePDF_printsReport_withoutPersisting() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PDF_CATALOG_SAMPLE"], !path.isEmpty else {
            throw XCTSkip("Set PDF_CATALOG_SAMPLE=/absolute/path/to/catalog.pdf to run this harness.")
        }

        let pdfURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            return XCTFail("No PDF found at \(pdfURL.path)")
        }

        let schoolID = env["PDF_CATALOG_SAMPLE_SCHOOL"] ?? "sample_school"

        // OCR is expensive (Vision per page). Default OFF for born-digital catalogs.
        // Set PDF_CATALOG_SAMPLE_OCR=1 to exercise the OCR fallback path.
        let ocrFallback = (env["PDF_CATALOG_SAMPLE_OCR"].map { $0 == "1" || $0.lowercased() == "true" }) ?? false

        print("[harness] starting extraction (ocrFallback=\(ocrFallback)) for \(pdfURL.lastPathComponent)")
        let start = Date()
        let output = try await CatalogPDFPipeline.run(
            pdfURL: pdfURL,
            options: CatalogPDFPipeline.Options(
                schoolID: schoolID,
                includeCourses: true,
                includePolicies: true,
                ocrFallback: ocrFallback
            ),
            onPageProgress: { completed, total in
                if completed == total || completed % 100 == 0 {
                    print("[harness] parsing page \(completed)/\(total)")
                }
            }
        )
        let elapsed = Date().timeIntervalSince(start)

        let diag = output.classificationDiagnostics
        let avgConfidence = diag.averageAcceptedProgramConfidence.map { String(format: "%.3f", $0) } ?? "n/a"

        var report = """

        ===== Catalog PDF Scrape Report =====
        School ID:            \(schoolID)
        File:                 \(pdfURL.lastPathComponent)
        Runtime:              \(String(format: "%.1f", elapsed))s
        OCR enabled:          \(ocrFallback)
        -------------------------------------
        Pages:                \(output.healthReport.pageCount)
        Outline entries:      \(output.healthReport.outlineEntryCount)
        Low-text-density:     \(output.healthReport.lowTextDensityPages)
        OCR pages used:       \(output.ocrPagesUsed)
        Layout note:          \(output.healthReport.layoutNote ?? "none")
        -------------------------------------
        Sections detected:    \(output.foundation.sections.count)
        \(output.foundation.sections.map { "  - \($0.kind.rawValue) [pages \($0.startPage)-\($0.endPage)] conf=\(String(format: "%.2f", $0.confidence))" }.joined(separator: "\n"))
        -------------------------------------
        Total blocks:         \(diag.totalBlocks)
        Blocks by type:       \(diag.blocksByType)
        Program candidates:   \(diag.programCandidates)
        Program accepted:     \(diag.programAccepted)
        Program rejected:     \(diag.programRejected)
        Avg program conf:     \(avgConfidence)
        -------------------------------------
        Programs extracted:   \(output.programs.count)
        Courses extracted:    \(output.courses.count)
        Courses w/ desc:      \(output.courses.filter { ($0.description?.isEmpty == false) }.count)
        Courses w/ prereqs:   \(output.courses.filter { ($0.prerequisiteText?.isEmpty == false) }.count)
        Requirements:         \(output.requirements.count)
        Policy rows:          \(output.policyRows.count)
        Document IR nodes:    \(output.documentIR?.nodes.count ?? 0)
        """

        if let courseDiag = output.courseExtractionDiagnostics {
            report += """
            
            -------------------------------------
            Detected grammar:     \(courseDiag.detection?.grammar.identifier ?? "n/a")
            Detection confidence: \(courseDiag.detection.map { String(format: "%.3f", $0.confidence) } ?? "n/a")
            Adaptive parser used: \(courseDiag.usedAdaptiveParser)
            Legacy fallback used: \(courseDiag.usedLegacyFallback)
            Low confidence:       \(courseDiag.lowConfidence)
            Credit rate:          \(courseDiag.coursesWithCredits)/\(output.courses.count)
            Description rate:     \(courseDiag.coursesWithDescriptions)/\(output.courses.count)
            Failed headers:       \(courseDiag.failedHeaderCount)
            Top failures:         \(courseDiag.topFailureReasons.joined(separator: ", "))
            """
        }

        report += """
        =====================================
        """

        report += "\n\n[harness] Sample programs (up to 40):\n"
        for program in output.programs.prefix(40) {
            let degree = program.degreeType ?? "—"
            report += "  • \(program.name)  [\(program.type) / \(degree)]\n"
        }

        report += "\n[harness] Sample courses (up to 40):\n"
        for course in output.courses.prefix(40) {
            report += "  • \(course.courseCode)  \(course.title)  (\(course.credits) cr)\n"
            if let desc = course.description, !desc.isEmpty {
                report += "      desc: \(desc.prefix(120))\n"
            }
            if let prereq = course.prerequisiteText, !prereq.isEmpty {
                report += "      prereq: \(prereq.prefix(100))\n"
            }
        }

        let coursesWithoutDescriptions = output.courses.filter {
            ($0.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !coursesWithoutDescriptions.isEmpty {
            report += "\n[harness] Courses without descriptions (up to 40):\n"
            for course in coursesWithoutDescriptions.prefix(40) {
                report += "  • \(course.courseCode)  \(course.title)  (\(course.credits) cr)\n"
            }
        }

        report += "\n[harness] Sample requirements (up to 20):\n"
        for requirement in output.requirements.prefix(20) {
            let requiredCount = requirement.requiredCoursesDetailed?.count ?? 0
            let selectCount = requirement.selectFromDetailed?.count ?? 0
            let pickText = requirement.selectCount.map { ", pick \($0)" } ?? ""
            let courseCountText = selectCount > 0
                ? "\(selectCount) selectable\(pickText)"
                : "\(requiredCount) required"
            report += "  • [\(requirement.major)] \(requirement.category) — \(courseCountText), \(requirement.creditsRequired) cr\n"
        }

        if !diag.sampleRejections.isEmpty {
            report += "\n[harness] Sample rejections (up to 12):\n"
            for rejection in diag.sampleRejections.prefix(12) {
                report += "  ✗ \(rejection)\n"
            }
        }

        print(report)

        // xcodebuild routes test stdout into the .xcresult bundle, not the console log.
        // Write the report to a file so it can be inspected directly. The host app may be
        // sandboxed, so prefer the sandbox-writable temporary directory.
        if let reportPath = env["PDF_CATALOG_SAMPLE_REPORT"] {
            try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        }
        let sandboxReportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog_harness_report.txt")
        try? report.write(to: sandboxReportURL, atomically: true, encoding: .utf8)

        // Basic sanity assertions (do not fail on extraction yield, which varies by catalog).
        XCTAssertGreaterThan(output.healthReport.pageCount, 0, "Expected a non-empty PDF")
        for requirement in output.requirements {
            XCTAssertFalse(
                requirement.major.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Requirement rows must be attributed to a real program (no fabricated major)"
            )
        }
        for program in output.programs {
            XCTAssertNil(program.department, "Department inference should be disabled in this pass: \(program.name)")
            XCTAssertFalse(
                CatalogPDFProgramRejectLexicon.hasStrongNegative(program.name),
                "Policy-like text leaked into a program name: \(program.name)"
            )
        }
    }

    /// Runs all committed corpus PDFs and writes harness reports under `docs/pdf-baselines/`.
    func testHarnessAllCorpusPDFs_writesReports() async throws {
        struct HarnessFixture {
            let id: String
            let schoolID: String
            let pdfBasename: String
            let maxRuntimeSeconds: Double
        }

        let fixtures: [HarnessFixture] = [
            HarnessFixture(id: "fordham", schoolID: "fordham_university", pdfBasename: "fordham-bulletin.pdf", maxRuntimeSeconds: 90),
            HarnessFixture(id: "cmu_undergrad", schoolID: "carnegie_mellon_university", pdfBasename: "cmu-undergrad.pdf", maxRuntimeSeconds: 55),
            HarnessFixture(id: "brooklyn_undergrad", schoolID: "brooklyn_college", pdfBasename: "brooklyn-undergrad.pdf", maxRuntimeSeconds: 25),
            HarnessFixture(id: "brooklyn_grad", schoolID: "brooklyn_college", pdfBasename: "brooklyn-grad.pdf", maxRuntimeSeconds: 15),
        ]

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        var ranAny = false
        for fixture in fixtures {
            let pdfURL = repoRoot.appendingPathComponent("docs/pdf-baselines/\(fixture.pdfBasename)")
            guard FileManager.default.fileExists(atPath: pdfURL.path) else { continue }
            ranAny = true

            let start = Date()
            let output = try await CatalogPDFPipeline.run(
                pdfURL: pdfURL,
                options: CatalogPDFPipeline.Options(
                    schoolID: fixture.schoolID,
                    includeCourses: true,
                    includePolicies: false,
                    ocrFallback: false
                )
            )
            let elapsed = Date().timeIntervalSince(start)

            let reportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(fixture.id)-harness-report.txt")
            let repoReportURL = repoRoot.appendingPathComponent("docs/pdf-baselines/\(fixture.id)-harness-report.txt")
            let report = buildHarnessReport(
                output: output,
                schoolID: fixture.schoolID,
                pdfURL: pdfURL,
                elapsed: elapsed
            )
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            try? report.write(to: repoReportURL, atomically: true, encoding: .utf8)
            print("[harness] wrote \(reportURL.path)")

            XCTAssertGreaterThan(output.courses.count, 100, fixture.id)
            XCTAssertLessThanOrEqual(elapsed, fixture.maxRuntimeSeconds * 1.5, fixture.id)
            if let courseDiag = output.courseExtractionDiagnostics {
                XCTAssertTrue(courseDiag.usedAdaptiveParser, fixture.id)
                XCTAssertFalse(courseDiag.usedLegacyFallback, fixture.id)
            }
        }

        if !ranAny {
            throw XCTSkip("No corpus PDFs found under docs/pdf-baselines/")
        }
    }

    /// Dumps the FULL scraper output (every course code/title/credits/desc flag and
    /// every program) per corpus PDF to the sandbox tmp dir, for offline reconciliation
    /// against an independent ground-truth enumeration.
    func testAuditDumpsFullScraperOutput() async throws {
        struct AuditFixture { let id: String; let schoolID: String; let pdfBasename: String }
        let fixtures: [AuditFixture] = [
            AuditFixture(id: "fordham", schoolID: "fordham_university", pdfBasename: "fordham-bulletin.pdf"),
            AuditFixture(id: "cmu_undergrad", schoolID: "carnegie_mellon_university", pdfBasename: "cmu-undergrad.pdf"),
            AuditFixture(id: "brooklyn_undergrad", schoolID: "brooklyn_college", pdfBasename: "brooklyn-undergrad.pdf"),
            AuditFixture(id: "brooklyn_grad", schoolID: "brooklyn_college", pdfBasename: "brooklyn-grad.pdf"),
        ]

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        var ranAny = false
        for fixture in fixtures {
            let pdfURL = repoRoot.appendingPathComponent("docs/pdf-baselines/\(fixture.pdfBasename)")
            guard FileManager.default.fileExists(atPath: pdfURL.path) else { continue }
            ranAny = true

            let output = try await CatalogPDFPipeline.run(
                pdfURL: pdfURL,
                options: CatalogPDFPipeline.Options(
                    schoolID: fixture.schoolID,
                    includeCourses: true,
                    includePolicies: false,
                    ocrFallback: false
                )
            )

            var courseLines: [String] = []
            for course in output.courses.sorted(by: { $0.courseCode < $1.courseCode }) {
                let hasDesc = (course.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
                courseLines.append("\(course.courseCode)\t\(course.credits)\t\(hasDesc)\t\(course.title)")
            }
            let coursesURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fixture.id)-courses.tsv")
            try courseLines.joined(separator: "\n").write(to: coursesURL, atomically: true, encoding: .utf8)

            var programLines: [String] = []
            for program in output.programs.sorted(by: { $0.name < $1.name }) {
                programLines.append("\(program.type)\t\(program.degreeType ?? "")\t\(program.department ?? "")\t\(program.name)")
            }
            let programsURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fixture.id)-programs.tsv")
            try programLines.joined(separator: "\n").write(to: programsURL, atomically: true, encoding: .utf8)

            var deptLines: [String] = []
            for dept in output.departments.sorted(by: { $0.name < $1.name }) {
                deptLines.append("\(dept.name)\t\(dept.code ?? "")")
            }
            let deptsURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fixture.id)-departments.tsv")
            try deptLines.joined(separator: "\n").write(to: deptsURL, atomically: true, encoding: .utf8)

            var reqLines: [String] = []
            for req in output.requirements {
                let courseCount = (req.requiredCoursesDetailed?.count ?? req.requiredCourses?.count ?? 0)
                    + (req.selectFromDetailed?.count ?? req.selectFrom?.count ?? 0)
                reqLines.append("\(req.major)\t\(req.degreeType)\t\(req.category)\t\(req.creditsRequired)\t\(courseCount)")
            }
            let reqsURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fixture.id)-requirements.tsv")
            try reqLines.joined(separator: "\n").write(to: reqsURL, atomically: true, encoding: .utf8)
            let reqMajors = Set(output.requirements.map { $0.major.lowercased() })
            let majorNames = Set(output.programs.filter { $0.type == "Major" }.map { $0.name.lowercased() })
            let minorNames = Set(output.programs.filter { $0.type == "Minor" }.map { $0.name.lowercased() })
            let majorsCovered = majorNames.intersection(reqMajors).count
            let minorsCovered = minorNames.intersection(reqMajors).count
            let proseGroups = output.requirements.filter { $0.requirementKind == .prose }.count
            print("[audit-req] \(fixture.id): requirements=\(output.requirements.count) "
                  + "programsWithRequirements=\(reqMajors.count) prose=\(proseGroups) "
                  + "majorsCovered=\(majorsCovered)/\(majorNames.count) minorsCovered=\(minorsCovered)/\(minorNames.count)")

            let majors = output.programs.filter { $0.type == "Major" }.count
            let minors = output.programs.filter { $0.type == "Minor" }.count
            let grad = output.programs.filter { $0.type == "Graduate Program" }.count
            let conc = output.programs.filter { $0.type == "Concentration" }.count
            let withDept = output.programs.filter { ($0.department?.isEmpty == false) }.count
            print("[audit] \(fixture.id): courses=\(output.courses.count) programs=\(output.programs.count) "
                  + "(major=\(majors) minor=\(minors) grad=\(grad) conc=\(conc) withDept=\(withDept)) "
                  + "departments=\(output.departments.count) subjectMap=\(output.departmentSubjectMap.count)")
        }

        if !ranAny { throw XCTSkip("No corpus PDFs found under docs/pdf-baselines/") }
    }

    private func buildHarnessReport(
        output: CatalogPDFIngestOutput,
        schoolID: String,
        pdfURL: URL,
        elapsed: TimeInterval
    ) -> String {
        let diag = output.classificationDiagnostics
        let avgConfidence = diag.averageAcceptedProgramConfidence.map { String(format: "%.3f", $0) } ?? "n/a"
        var report = """

        ===== Catalog PDF Scrape Report =====
        School ID:            \(schoolID)
        File:                 \(pdfURL.lastPathComponent)
        Runtime:              \(String(format: "%.1f", elapsed))s
        OCR enabled:          false
        -------------------------------------
        Pages:                \(output.healthReport.pageCount)
        Outline entries:      \(output.healthReport.outlineEntryCount)
        Low-text-density:     \(output.healthReport.lowTextDensityPages)
        OCR pages used:       \(output.ocrPagesUsed)
        Layout note:          \(output.healthReport.layoutNote ?? "none")
        -------------------------------------
        Sections detected:    \(output.foundation.sections.count)
        \(output.foundation.sections.map { "  - \($0.kind.rawValue) [pages \($0.startPage)-\($0.endPage)] conf=\(String(format: "%.2f", $0.confidence))" }.joined(separator: "\n"))
        -------------------------------------
        Total blocks:         \(diag.totalBlocks)
        Blocks by type:       \(diag.blocksByType)
        Program candidates:   \(diag.programCandidates)
        Program accepted:     \(diag.programAccepted)
        Program rejected:     \(diag.programRejected)
        Avg program conf:     \(avgConfidence)
        -------------------------------------
        Programs extracted:   \(output.programs.count)
        Courses extracted:    \(output.courses.count)
        Courses w/ desc:      \(output.courses.filter { ($0.description?.isEmpty == false) }.count)
        Courses w/ prereqs:   \(output.courses.filter { ($0.prerequisiteText?.isEmpty == false) }.count)
        Requirements:         \(output.requirements.count)
        Policy rows:          \(output.policyRows.count)
        Document IR nodes:    \(output.documentIR?.nodes.count ?? 0)
        """

        if let courseDiag = output.courseExtractionDiagnostics {
            report += """

            -------------------------------------
            Detected grammar:     \(courseDiag.detection?.grammar.identifier ?? "n/a")
            Detection confidence: \(courseDiag.detection.map { String(format: "%.3f", $0.confidence) } ?? "n/a")
            Adaptive parser used: \(courseDiag.usedAdaptiveParser)
            Legacy fallback used: \(courseDiag.usedLegacyFallback)
            Low confidence:       \(courseDiag.lowConfidence)
            Credit rate:          \(courseDiag.coursesWithCredits)/\(output.courses.count)
            Description rate:     \(courseDiag.coursesWithDescriptions)/\(output.courses.count)
            Failed headers:       \(courseDiag.failedHeaderCount)
            Top failures:         \(courseDiag.topFailureReasons.joined(separator: ", "))
            """
        }

        var programsByType: [String: Int] = [:]
        for program in output.programs {
            programsByType[program.type, default: 0] += 1
        }
        let typeSummary = programsByType.keys.sorted()
            .map { "\($0)=\(programsByType[$0] ?? 0)" }
            .joined(separator: " ")
        report += "\n-------------------------------------\n"
        report += "Programs by type:     \(typeSummary)\n"

        let majors = output.programs.filter { $0.type == "Major" }
        let minors = output.programs.filter { $0.type == "Minor" }
        report += "\nSample majors (up to 15):\n"
        for program in majors.prefix(15) {
            report += "  • \(program.name)  [\(program.degreeType ?? "—")]\n"
        }
        report += "\nSample minors (up to 15):\n"
        for program in minors.prefix(15) {
            report += "  • \(program.name)\n"
        }

        report += "\n=====================================\n"
        return report
    }
}
