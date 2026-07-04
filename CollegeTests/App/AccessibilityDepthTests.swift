// AccessibilityDepthTests.swift
// Part 10 — preserved pages expose landmarks, Dynamic Type, and widget labels.

import XCTest

final class AccessibilityDepthTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testPreservedPagesExposeShellLandmarksAndDynamicType() throws {
        let expectations: [(path: String, markers: [String])] = [
            ("College/App/ContentView.swift", ["shell.mainContent", "shellDynamicTypeReadable"]),
            ("College/App/OnboardingRootView.swift", ["onboarding.step.", "shellDynamicTypeReadable"]),
            ("College/Features/Academics/AcademicsView.swift", ["academics.root", "shellDynamicTypeReadable"]),
            ("College/Features/Documents/DocumentsView.swift", ["documents.root", "shellDynamicTypeReadable"]),
            ("College/Features/Profile/ProfileView.swift", ["shellDynamicTypeReadable"]),
            ("College/Features/Assistant/AIAssistantView.swift", ["assistant.root", "assistant.sessionBadge"]),
            ("College/Features/Career/Workspace/CareerWorkspaceView.swift", ["career.workspace.root"]),
            ("College/Features/SyllabusAI/SyllabusReviewView.swift", ["syllabus.review.root"]),
            ("College/Features/Overview/WidgetKit/OverviewCard.swift", ["overviewWidgetSurface"]),
        ]

        for item in expectations {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(item.path), encoding: .utf8)
            for marker in item.markers {
                XCTAssertTrue(source.contains(marker), "Expected \(marker) in \(item.path)")
            }
        }
    }

    func testSheetDismissModifierSupportsKeyboardEscape() throws {
        let path = repoRoot.appendingPathComponent("College/Core/SheetDismissOnOutsideClick.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains("installEscapeMonitorIfNeeded"))
        XCTAssertTrue(source.contains("dismissOnOutsideClickForSheet"))
    }
}
