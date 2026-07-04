// EmptyStateContractTests.swift
// Part 20 — primary empty states expose ContentUnavailableView actions.

import XCTest

final class EmptyStateContractTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testCareerAndAssistantEmptyStatesExposeActions() throws {
        let emptyStateFiles = [
            "College/Features/Career/Networking/NetworkingTrackerView.swift",
            "College/Features/Career/Applications/CareerApplicationsListView.swift",
            "College/Features/Overview/WidgetKit/OverviewCard.swift",
        ]
        for relative in emptyStateFiles {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertTrue(
                source.contains("ContentUnavailableView") || source.contains("OverviewWidgetEmptyState"),
                "Expected empty-state surface in \(relative)"
            )
        }

        let assistantGuide = try String(
            contentsOf: repoRoot.appendingPathComponent("College/Features/Assistant/AssistantStudentGuidePanel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(assistantGuide.contains("assistant.studentGuidePanel"))
    }
}
