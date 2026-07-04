// RoutingCorpusExportTests.swift
// Regenerate routing-corpus.json (sandbox export):
//   1. Remove .disabled on writeCalibratedCorpusToSourceTree (or use xcodebuild -only-testing below)
//   2. xcodebuild test -scheme College -destination 'platform=macOS' \
//        -only-testing:CollegeTests/RoutingCorpusExportTests
//   3. ./scripts/copy-assistant-fixture-exports.sh

import Foundation
import Testing
@testable import College

@Suite("Routing Corpus Export")
struct RoutingCorpusExportTests {
    @Test(.disabled("Run manually to regenerate routing-corpus.json"))
    func writeCalibratedCorpusToSourceTree() throws {
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("routing-corpus-calibrated.json")
        let calibrated = RoutingCorpusCalibrator.calibratedCases(from: RoutingCorpus.all)
        let data = try RoutingCorpusCalibrator.exportJSON(from: calibrated)
        try data.write(to: exportURL, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        #expect(!calibrated.isEmpty)
    }
}
