// VaultSourceFileMaterializerTests.swift
// Feature: Core
// Purpose: External file materialization from local and cloud-hosted paths.

import XCTest
@testable import College

final class VaultSourceFileMaterializerTests: XCTestCase {
    func testMaterializedData_readsLocalPDF() async throws {
        let source = try ResumePDFTestFixtures.materializeSamplePDF()
        defer { try? FileManager.default.removeItem(at: source) }

        let data = try await VaultSourceFileMaterializer.materializedDataAsync(from: source)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
    }

    func testMaterializedTempURL_preservesFilenameExtension() async throws {
        let source = try ResumePDFTestFixtures.materializeSamplePDF()
        defer { try? FileManager.default.removeItem(at: source) }

        let tempURL = try await VaultSourceFileMaterializer.materializedTempURL(
            from: source,
            preferredFileName: "resume.pdf"
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertEqual(tempURL.pathExtension.lowercased(), "pdf")
        let data = try Data(contentsOf: tempURL)
        XCTAssertGreaterThan(data.count, 1_000)
    }
}
