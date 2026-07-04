// CareerResumeIngestProgressStore.swift
// Feature: Career / Resumes
// Purpose: Live resume ingest stage + fraction for inspector UI.

import Combine
import Foundation

struct CareerResumeIngestProgress: Equatable, Sendable {
    let stageLabel: String
    let fraction: Double

    static let extracting = CareerResumeIngestProgress(stageLabel: "Reading file text…", fraction: 0.15)
    static let compliance = CareerResumeIngestProgress(stageLabel: "Checking parser quality…", fraction: 0.35)
    static let structuring = CareerResumeIngestProgress(stageLabel: "Organizing sections with on-device AI…", fraction: 0.65)
    static let enriching = CareerResumeIngestProgress(stageLabel: "Detecting skills and target role…", fraction: 0.85)
    static let saving = CareerResumeIngestProgress(stageLabel: "Saving parsed resume…", fraction: 0.95)
}

@MainActor
final class CareerResumeIngestProgressStore: ObservableObject {
    static let shared = CareerResumeIngestProgressStore()

    @Published private(set) var progressByDocumentID: [UUID: CareerResumeIngestProgress] = [:]

    private init() {}

    func setProgress(_ progress: CareerResumeIngestProgress, for documentID: UUID) {
        progressByDocumentID[documentID] = progress
        let title = resumeTitle(for: documentID)
        BackgroundActivityReporter.running(
            id: BackgroundActivityCenter.resumeActivityID(documentID: documentID),
            domain: .careerResume,
            title: title,
            detail: progress.stageLabel,
            fraction: progress.fraction,
            indeterminate: false
        )
    }

    func clearProgress(for documentID: UUID) {
        progressByDocumentID.removeValue(forKey: documentID)
    }

    private func resumeTitle(for documentID: UUID) -> String {
        guard let doc = try? CollegePersistence.shared.vaultRepository.fetchDocument(id: documentID) else {
            return String(localized: "resume.background.parsing", defaultValue: "Parsing resume…")
        }
        let raw = doc.customDisplayName ?? doc.fileName
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "resume.background.parsing", defaultValue: "Parsing resume…")
            : trimmed
    }

    func progress(for documentID: UUID) -> CareerResumeIngestProgress? {
        progressByDocumentID[documentID]
    }
}

enum CareerResumeIngestTimeouts {
    static let structuredParseSeconds: TimeInterval = 120
}

private enum CareerResumeIngestTimeoutRace<T: Sendable>: Sendable {
    case value(T)
    case timedOut
}

func withCareerResumeIngestTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    return await withTaskGroup(of: CareerResumeIngestTimeoutRace<T>.self) { group in
        group.addTask {
            .value(await operation())
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return .timedOut
        }

        while let next = await group.next() {
            switch next {
            case .value(let value):
                group.cancelAll()
                return value
            case .timedOut:
                continue
            }
        }
        return nil
    }
}
