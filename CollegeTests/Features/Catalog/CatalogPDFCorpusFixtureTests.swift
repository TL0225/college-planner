// CatalogPDFCorpusFixtureTests.swift
// Feature: Catalog
// Purpose: Corpus-driven regression tests against real bulletin PDFs.

import Foundation
import XCTest
@testable import College

final class CatalogPDFCorpusFixtureTests: XCTestCase {
    private struct GoldProgram: Decodable {
        let name: String
        let requirementCategories: [String]
    }

    private struct GoldFixture: Decodable {
        let id: String
        let programs: [GoldProgram]
    }

    private struct GoldManifest: Decodable {
        let fixtures: [GoldFixture]
    }

    private struct GoldenCourse: Decodable {
        let code: String
        let titleContains: String
        let credits: Int
        let requiresDescription: Bool
    }

    private struct Fixture: Decodable {
        let id: String
        let schoolID: String
        let pdfBasename: String
        let pdfSearchPaths: [String]
        let expectedHeaderCodeShape: String
        let expectedMetadataGrammar: String
        let expectedCourseCount: Int?
        let expectedCoursesWithCredits: Int?
        let expectedCoursesWithDescriptions: Int?
        let minCourseCount: Int
        let minDescriptionFraction: Double
        let minCreditFraction: Double
        let maxRuntimeSeconds: Double
        let goldenCourses: [GoldenCourse]
        let expectedPrograms: Int?
        let expectedMajors: Int?
        let expectedMinors: Int?
        let expectedGraduatePrograms: Int?
        let expectedDepartments: Int?
        let expectedProgramsWithDepartment: Int?
        let minPrograms: Int?
        let minMajors: Int?
        let minMinors: Int?
        let minGraduatePrograms: Int?
        let minRequirementGroups: Int?
        let minProgramsWithRequirements: Int?
    }

    private struct Manifest: Decodable {
        let fixtures: [Fixture]
    }

    private struct BenchmarkRow {
        let fixtureID: String
        let courses: Int
        let coursesDelta: Int?
        let programs: Int
        let programsDelta: Int?
        let requirements: Int
        let requirementsDelta: Int?
        let requirementPrecision: Double?
        let requirementRecall: Double?
        let requirementF1: Double?

        func tsvLine() -> String {
            var parts: [String] = []
            parts.reserveCapacity(10)
            parts.append(fixtureID)
            parts.append(String(courses))
            parts.append(coursesDelta.map(String.init) ?? "na")
            parts.append(String(programs))
            parts.append(programsDelta.map(String.init) ?? "na")
            parts.append(String(requirements))
            parts.append(requirementsDelta.map(String.init) ?? "na")
            parts.append(requirementPrecision.map { String(format: "%.4f", $0) } ?? "na")
            parts.append(requirementRecall.map { String(format: "%.4f", $0) } ?? "na")
            parts.append(requirementF1.map { String(format: "%.4f", $0) } ?? "na")
            return parts.joined(separator: "\t")
        }
    }

    func testCorpusFixturesAgainstRealBulletinPDFs() async throws {
        let manifest = try loadManifest()
        let gold = try loadGoldManifest()
        writeBaselineManifest(manifest)
        var ranAny = false
        var benchmarkRows: [BenchmarkRow] = []

        for fixture in manifest.fixtures {
            let row = try await runFixture(fixture, ranAny: &ranAny, gold: gold)
            if let row {
                benchmarkRows.append(row)
            }
        }

        if !ranAny {
            throw XCTSkip("No corpus PDFs found locally. Place bulletins under docs/pdf-baselines/ or ~/Downloads/.")
        }
        writeBenchmark(rows: benchmarkRows)
    }

    func testCorpusFordham() async throws {
        try await runSingleFixture(id: "fordham")
    }

    func testCorpusCMUUndergrad() async throws {
        try await runSingleFixture(id: "cmu_undergrad")
    }

    func testCorpusBrooklynUndergrad() async throws {
        try await runSingleFixture(id: "brooklyn_undergrad")
    }

    func testCorpusBrooklynGrad() async throws {
        try await runSingleFixture(id: "brooklyn_grad")
    }

    private func runSingleFixture(id: String) async throws {
        let manifest = try loadManifest()
        guard let fixture = manifest.fixtures.first(where: { $0.id == id }) else {
            return XCTFail("Missing fixture \(id)")
        }
        let gold = try loadGoldManifest()
        var ranAny = false
        _ = try await runFixture(fixture, ranAny: &ranAny, gold: gold)
        if !ranAny {
            throw XCTSkip("PDF not found for \(id)")
        }
    }

    private func runFixture(
        _ fixture: Fixture,
        ranAny: inout Bool,
        gold: GoldManifest?
    ) async throws -> BenchmarkRow? {
        guard let pdfURL = resolvePDF(for: fixture) else {
            return nil
        }
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

        let courseDiag = try XCTUnwrap(output.courseExtractionDiagnostics, fixture.id)
        let detection = try XCTUnwrap(courseDiag.detection, fixture.id)

        appendCorpusDiagnostic(
            """
            \(fixture.id): courses=\(output.courses.count) credits=\(courseDiag.coursesWithCredits) descriptions=\(courseDiag.coursesWithDescriptions) grammar=\(detection.grammar.identifier) confidence=\(String(format: "%.3f", detection.confidence)) adaptive=\(courseDiag.usedAdaptiveParser) fallback=\(courseDiag.usedLegacyFallback) runtime=\(String(format: "%.1f", elapsed))s sections=\(output.foundation.sections.map { "\($0.kind.rawValue):\($0.startPage)-\($0.endPage)" }.joined(separator: ","))
            """
        )

        XCTAssertEqual(
            detection.grammar.header.codeShape.rawValue,
            fixture.expectedHeaderCodeShape,
            "\(fixture.id) header grammar"
        )
        XCTAssertEqual(
            detection.grammar.metadata.rawValue,
            fixture.expectedMetadataGrammar,
            "\(fixture.id) metadata grammar"
        )
        XCTAssertGreaterThanOrEqual(
            output.courses.count,
            fixture.minCourseCount,
            "\(fixture.id) expected >= \(fixture.minCourseCount) courses, got \(output.courses.count)"
        )
        if let expectedCourseCount = fixture.expectedCourseCount {
            XCTAssertEqual(output.courses.count, expectedCourseCount, "\(fixture.id) exact course count")
        }
        XCTAssertTrue(courseDiag.usedAdaptiveParser, "\(fixture.id) should use adaptive parser")
        XCTAssertFalse(courseDiag.usedLegacyFallback, "\(fixture.id) should not fall back")

        let total = max(output.courses.count, 1)
        let creditFraction = Double(courseDiag.coursesWithCredits) / Double(total)
        let descriptionFraction = Double(courseDiag.coursesWithDescriptions) / Double(total)
        if let expectedCredits = fixture.expectedCoursesWithCredits {
            XCTAssertEqual(courseDiag.coursesWithCredits, expectedCredits, "\(fixture.id) exact credits count")
        }
        if let expectedDescriptions = fixture.expectedCoursesWithDescriptions {
            XCTAssertEqual(courseDiag.coursesWithDescriptions, expectedDescriptions, "\(fixture.id) exact descriptions count")
        }
        XCTAssertGreaterThanOrEqual(creditFraction, fixture.minCreditFraction, fixture.id)
        XCTAssertGreaterThanOrEqual(descriptionFraction, fixture.minDescriptionFraction, fixture.id)

        for sample in fixture.goldenCourses {
            let course = try XCTUnwrap(
                output.courses.first { $0.courseCode.caseInsensitiveCompare(sample.code) == .orderedSame },
                "\(fixture.id) missing \(sample.code)"
            )
            XCTAssertTrue(
                course.title.localizedCaseInsensitiveContains(sample.titleContains),
                "\(fixture.id) \(sample.code) title got '\(course.title)'"
            )
            XCTAssertEqual(course.credits, sample.credits, "\(fixture.id) \(sample.code) credits")
            if sample.requiresDescription {
                XCTAssertFalse((course.description ?? "").isEmpty, "\(fixture.id) \(sample.code) description")
            }
        }

        XCTAssertLessThanOrEqual(
            elapsed,
            fixture.maxRuntimeSeconds * 1.5,
            "\(fixture.id) runtime \(elapsed)s exceeded perf ceiling"
        )

        try validatePrograms(fixture, output: output)
        let reqMetrics = validateRequirements(fixture, output: output, goldFixture: gold?.fixtures.first(where: { $0.id == fixture.id }))

        return BenchmarkRow(
            fixtureID: fixture.id,
            courses: output.courses.count,
            coursesDelta: fixture.expectedCourseCount.map { output.courses.count - $0 },
            programs: output.programs.count,
            programsDelta: fixture.expectedPrograms.map { output.programs.count - $0 },
            requirements: output.requirements.count,
            requirementsDelta: fixture.minRequirementGroups.map { output.requirements.count - $0 },
            requirementPrecision: reqMetrics?.precision,
            requirementRecall: reqMetrics?.recall,
            requirementF1: reqMetrics?.f1
        )
    }

    /// Validates degree-requirement coverage: every catalog must attach requirement
    /// groups to a floor number of distinct programs (majors/minors), guarding against
    /// regressions in the program-heading-anchored requirement extraction.
    private func validateRequirements(
        _ fixture: Fixture,
        output: CatalogPDFIngestOutput,
        goldFixture: GoldFixture?
    ) -> (precision: Double, recall: Double, f1: Double)? {
        let distinctProgramsWithReqs = Set(
            output.requirements.map { $0.major.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        ).count
        let proseGroups = output.requirements.filter { $0.requirementKind == .prose }.count

        appendCorpusDiagnostic(
            "\(fixture.id): requirements=\(output.requirements.count) programsWithRequirements=\(distinctProgramsWithReqs) prose=\(proseGroups)"
        )

        if let minGroups = fixture.minRequirementGroups {
            XCTAssertGreaterThanOrEqual(
                output.requirements.count, minGroups,
                "\(fixture.id) expected >= \(minGroups) requirement groups, got \(output.requirements.count)"
            )
        }
        if let minPrograms = fixture.minProgramsWithRequirements {
            XCTAssertGreaterThanOrEqual(
                distinctProgramsWithReqs, minPrograms,
                "\(fixture.id) expected >= \(minPrograms) programs with requirements, got \(distinctProgramsWithReqs)"
            )
        }

        // Every requirement must be attributable to a named program and be non-empty
        // (either resolved courses or preserved prose), so we never persist orphan rows.
        for req in output.requirements {
            XCTAssertFalse(
                req.major.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(fixture.id) requirement with empty program: category '\(req.category)'"
            )
            let courseCount = (req.requiredCoursesDetailed?.count ?? req.requiredCourses?.count ?? 0)
                + (req.selectFromDetailed?.count ?? req.selectFrom?.count ?? 0)
            let hasProse = (req.description?.isEmpty == false)
            XCTAssertTrue(
                courseCount > 0 || hasProse,
                "\(fixture.id) empty requirement group for '\(req.major)' / '\(req.category)'"
            )
        }

        guard let goldFixture else { return nil }
        var expectedKeyBuffer: [String] = []
        expectedKeyBuffer.reserveCapacity(goldFixture.programs.count * 4)
        for program in goldFixture.programs {
            let normalizedProgram = normalize(program.name)
            for category in program.requirementCategories {
                expectedKeyBuffer.append("\(normalizedProgram)||\(normalize(category))")
            }
        }
        let expectedKeys = Set(expectedKeyBuffer)
        guard !expectedKeys.isEmpty else { return nil }

        let extractedKeys = Set(
            output.requirements.map { req in
                "\(normalize(req.major))||\(normalize(req.category))"
            }
        )
        let correct = expectedKeys.intersection(extractedKeys).count
        let precision = extractedKeys.isEmpty ? 0 : Double(correct) / Double(extractedKeys.count)
        let recall = Double(correct) / Double(expectedKeys.count)
        let f1Denominator = precision + recall
        let f1 = f1Denominator > 0 ? (2 * precision * recall / f1Denominator) : 0
        appendCorpusDiagnostic(
            "\(fixture.id): req_precision=\(String(format: "%.4f", precision)) req_recall=\(String(format: "%.4f", recall)) req_f1=\(String(format: "%.4f", f1)) expectedKeys=\(expectedKeys.count) extractedKeys=\(extractedKeys.count)"
        )
        return (precision, recall, f1)
    }

    /// Validates the Programs / Majors / Minors category against ground-truth
    /// floors and enforces a school-agnostic "no fabricated/garbage names" rule.
    private func validatePrograms(_ fixture: Fixture, output: CatalogPDFIngestOutput) throws {
        let majors = output.programs.filter { $0.type == "Major" }
        let minors = output.programs.filter { $0.type == "Minor" }
        let graduate = output.programs.filter { $0.type == "Graduate Program" }

        appendCorpusDiagnostic(
            "\(fixture.id): programs=\(output.programs.count) majors=\(majors.count) minors=\(minors.count) graduate=\(graduate.count)"
        )

        if let minPrograms = fixture.minPrograms {
            XCTAssertGreaterThanOrEqual(
                output.programs.count, minPrograms,
                "\(fixture.id) expected >= \(minPrograms) programs, got \(output.programs.count)"
            )
        }
        if let expectedPrograms = fixture.expectedPrograms {
            XCTAssertEqual(output.programs.count, expectedPrograms, "\(fixture.id) exact programs count")
        }
        if let expectedMajors = fixture.expectedMajors {
            XCTAssertEqual(majors.count, expectedMajors, "\(fixture.id) exact majors count")
        }
        if let expectedMinors = fixture.expectedMinors {
            XCTAssertEqual(minors.count, expectedMinors, "\(fixture.id) exact minors count")
        }
        if let expectedGraduate = fixture.expectedGraduatePrograms {
            XCTAssertEqual(graduate.count, expectedGraduate, "\(fixture.id) exact graduate programs count")
        }
        if let minMajors = fixture.minMajors {
            XCTAssertGreaterThanOrEqual(majors.count, minMajors, "\(fixture.id) majors")
        }
        if let minMinors = fixture.minMinors {
            XCTAssertGreaterThanOrEqual(minors.count, minMinors, "\(fixture.id) minors")
        }
        if let minGraduate = fixture.minGraduatePrograms {
            XCTAssertGreaterThanOrEqual(graduate.count, minGraduate, "\(fixture.id) graduate programs")
        }
        if let expectedDepartments = fixture.expectedDepartments {
            XCTAssertEqual(output.departments.count, expectedDepartments, "\(fixture.id) exact departments count")
        }
        if let expectedWithDept = fixture.expectedProgramsWithDepartment {
            let withDept = output.programs.filter { ($0.department?.isEmpty == false) }.count
            XCTAssertEqual(withDept, expectedWithDept, "\(fixture.id) exact programs-with-department count")
        }

        // No fabricated/structural-noise program names may leak into output.
        for program in output.programs {
            let name = program.name
            XCTAssertNil(
                name.range(of: #"\b\d{4}\b"#, options: .regularExpression),
                "\(fixture.id) program name contains a 4-digit year: '\(name)'"
            )
            XCTAssertNil(
                name.split(separator: " ").first(where: { $0.count > 28 }),
                "\(fixture.id) run-together/concatenated program name: '\(name)'"
            )
            let lower = name.lowercased()
            XCTAssertFalse(
                lower.hasPrefix("college of ") || lower.hasPrefix("school of ") || lower.hasPrefix("department of "),
                "\(fixture.id) academic-unit banner leaked as program: '\(name)'"
            )
            XCTAssertFalse(
                CatalogPDFProgramRejectLexicon.hasStrongNegative(name),
                "\(fixture.id) policy-like text leaked into program: '\(name)'"
            )
        }
    }

    private func loadManifest() throws -> Manifest {
        let bundle = Bundle(for: CatalogPDFCorpusFixtureTests.self)
        let url = bundle.url(
            forResource: "golden_samples",
            withExtension: "json",
            subdirectory: "Fixtures/CatalogPDF"
        ) ?? bundle.url(forResource: "golden_samples", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/CatalogPDF/golden_samples.json")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func loadGoldManifest() throws -> GoldManifest? {
        let bundle = Bundle(for: CatalogPDFCorpusFixtureTests.self)
        let resolvedURL = bundle.url(
            forResource: "catalog_gold_standard",
            withExtension: "json",
            subdirectory: "Fixtures/CatalogPDF"
        ) ?? bundle.url(forResource: "catalog_gold_standard", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/CatalogPDF/catalog_gold_standard.json")
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return nil }
        let data = try Data(contentsOf: resolvedURL)
        return try JSONDecoder().decode(GoldManifest.self, from: data)
    }

    private func resolvePDF(for fixture: Fixture) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let repoRoot = repoRootURL() {
            for path in fixture.pdfSearchPaths where !path.hasPrefix("/") && !path.hasPrefix("~/") {
                candidates.append(repoRoot.appendingPathComponent(path))
            }
        }

        candidates.append(contentsOf: fixture.pdfSearchPaths.map { raw in
            if raw.hasPrefix("~/") {
                return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
            }
            if raw.hasPrefix("/") {
                return URL(fileURLWithPath: raw)
            }
            return URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(raw)
        })

        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    private func appendCorpusDiagnostic(_ line: String) {
        guard let root = repoRootURL() else { return }
        let url = root.appendingPathComponent("docs/pdf-baselines/corpus-last-run.txt")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeBenchmark(rows: [BenchmarkRow]) {
        guard !rows.isEmpty, let root = repoRootURL() else { return }
        let url = root.appendingPathComponent("docs/pdf-baselines/corpus-benchmark-last-run.tsv")
        var lines: [String] = [
            "fixtureID\tcourses\tcoursesDelta\tprograms\tprogramsDelta\trequirements\trequirementsDelta\treqPrecision\treqRecall\treqF1"
        ]
        lines.append(contentsOf: rows.map { $0.tsvLine() })
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeBaselineManifest(_ manifest: Manifest) {
        guard let root = repoRootURL() else { return }
        let url = root.appendingPathComponent("docs/pdf-baselines/corpus-baseline.tsv")
        var lines: [String] = [
            "fixtureID\texpectedCourses\texpectedPrograms\tminRequirementGroups\tminProgramsWithRequirements"
        ]
        for fixture in manifest.fixtures {
            var row: [String] = []
            row.reserveCapacity(5)
            row.append(fixture.id)
            row.append(fixture.expectedCourseCount.map(String.init) ?? "na")
            row.append(fixture.expectedPrograms.map(String.init) ?? "na")
            row.append(fixture.minRequirementGroups.map(String.init) ?? "na")
            row.append(fixture.minProgramsWithRequirements.map(String.init) ?? "na")
            lines.append(row.joined(separator: "\t"))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func repoRootURL() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("College.xcodeproj").path) ? url : nil
    }
}
