// TransferSceneState.swift
// Feature: Transfer
// Purpose: Transfer Database — observable scene state for the Transfer Database page.
// Owner: TransferDatabaseView (College/Features/Transfer)

import Foundation
import Observation

/// Window-scoped, observable state for the Transfer Database feature.
@Observable
@MainActor
final class TransferSceneState {
    var sourceSchoolName: String = ""
    var targetSchool: TransferTargetSchool?
    var mode: TransferSourceMode = .fixture

    var refreshStatus: TransferOfficialRefreshStatus = .idle
    var routesAttempted: [TransferOfficialRouteKind] = []
    var lastRefreshedAt: Date?
    var lastErrorMessage: String?

    var results: [TransferCourseResult] = []
    var impactRows: [TransferRequirementsImpactRow] = []

    init() {}

    var isRefreshing: Bool { refreshStatus == .running }

    var projectedTransferCredits: Int {
        TransferRequirementsImpactBuilder.projectedCredits(impactRows)
    }

    var toolbarProjection: ToolbarProjection {
        ToolbarProjection(
            mode: mode,
            isRefreshing: isRefreshing,
            resultCount: results.count,
            hasTarget: targetSchool != nil
        )
    }

    struct ToolbarProjection: Equatable, Sendable {
        var mode: TransferSourceMode
        var isRefreshing: Bool
        var resultCount: Int
        var hasTarget: Bool
    }

    func clearResults() {
        results = []
        impactRows = []
        lastErrorMessage = nil
        refreshStatus = .idle
        routesAttempted = []
    }
}
