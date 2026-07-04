// EvalCorpusExportTests.swift
// Regenerate eval substring rules:
//   1. Remove .disabled on writeCalibratedEvalCorpora
//   2. xcodebuild test -scheme College -destination 'platform=macOS' \
//        -only-testing:CollegeTests/EvalCorpusExportTests
//   3. ./scripts/copy-assistant-fixture-exports.sh

import Foundation
import Testing
@testable import College

@Suite("Eval Corpus Export")
struct EvalCorpusExportTests {
    @Test(.disabled("Run manually to regenerate eval substring rules"))
    func writeCalibratedEvalCorpora() async throws {
        let exportDir = FileManager.default.temporaryDirectory
        let singleURL = exportDir.appendingPathComponent("eval-corpus-calibrated.json")
        let multiURL = exportDir.appendingPathComponent("multi-turn-eval-corpus-calibrated.json")

        let single = try await calibratedCases(EvalCorpus.singleTurn, multiTurn: false)
        let multi = try await calibratedCases(EvalCorpus.multiTurn, multiTurn: true)

        try write(cases: single, to: singleURL)
        try write(cases: multi, to: multiURL)
        #expect(FileManager.default.fileExists(atPath: singleURL.path))
        #expect(FileManager.default.fileExists(atPath: multiURL.path))
    }

    private func calibratedCases(_ cases: [EvalCase], multiTurn: Bool) async throws -> [EvalCase] {
        var output: [EvalCase] = []
        for evalCase in cases {
            if multiTurn, let turns = evalCase.turns, !turns.isEmpty {
                var history: [String] = []
                var finalReply = ""
                for turn in turns {
                    history.append("User: \(turn.user)")
                    finalReply = await EvalQualityCalibrator.previewReply(
                        for: turn.user,
                        recentConversation: history.joined(separator: "\n")
                    )
                    history.append("Assistant: \(finalReply)")
                }
                let quality = EvalQualityCalibrator.calibratedRules(
                    reply: finalReply,
                    existing: evalCase.quality,
                    isFinalTurn: true
                )
                output.append(EvalCase(id: evalCase.id, prompt: nil, turns: evalCase.turns, quality: quality))
            } else if let prompt = evalCase.prompt {
                let reply = await EvalQualityCalibrator.previewReply(for: prompt)
                let quality = EvalQualityCalibrator.calibratedRules(
                    reply: reply,
                    existing: evalCase.quality,
                    isFinalTurn: false
                )
                output.append(EvalCase(id: evalCase.id, prompt: prompt, turns: nil, quality: quality))
            }
        }
        return output
    }

    private func write(cases: [EvalCase], to url: URL) throws {
        struct Payload: Encodable {
            let version: Int
            let cases: [EvalCase]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Payload(version: 1, cases: cases)).write(to: url, options: .atomic)
    }
}
