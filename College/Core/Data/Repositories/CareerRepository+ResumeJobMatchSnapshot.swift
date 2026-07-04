// CareerRepository+ResumeJobMatchSnapshot.swift
// Feature: Core/Data
// Purpose: Append-only score snapshots for resume version diffing.

import Foundation
import SwiftData

extension CareerRepository {
    func appendResumeJobMatchSnapshot(matchID: UUID, overallScore: Int) throws {
        let snapshot = CareerResumeJobMatchSnapshot(
            matchID: matchID,
            overallScore: min(100, max(0, overallScore))
        )
        context.insert(snapshot)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func fetchResumeJobMatchSnapshots(matchID: UUID, limit: Int = 10) throws -> [CareerResumeJobMatchSnapshot] {
        var descriptor = FetchDescriptor<CareerResumeJobMatchSnapshot>(
            predicate: #Predicate { snap in snap.matchID == matchID },
            sortBy: [SortDescriptor(\.scoredAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func scoreDeltaSincePrevious(matchID: UUID, currentScore: Int) throws -> Int? {
        let snapshots = try fetchResumeJobMatchSnapshots(matchID: matchID, limit: 2)
        guard snapshots.count >= 2 else { return nil }
        return currentScore - snapshots[1].overallScore
    }
}
