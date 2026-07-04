// PDFCatalogIngestMainActorIsolationTests.swift
// H1 gate: PDF pipeline work must not run on the main thread.

import XCTest
@testable import College

final class PDFCatalogIngestMainActorIsolationTests: XCTestCase {
    func testPDFCatalogIngestAdapterDocumentsDetachedExecution() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("College/Core/Services/CatalogBackgroundSyncRunner.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        let adapterStart = source.range(of: "enum PDFCatalogIngestAdapter")!
        let adapterBody = String(source[adapterStart.lowerBound...])

        XCTAssertTrue(
            adapterBody.contains("Task.detached"),
            "PDFCatalogIngestAdapter must detach CatalogPDFPipeline.run from MainActor"
        )
    }
}
