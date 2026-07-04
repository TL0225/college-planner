// WidgetRegistryBootstrapTests.swift
// M30-030 — Overview widget registry matches built-in inventory.

import XCTest
@testable import College

@MainActor
final class WidgetRegistryBootstrapTests: XCTestCase {
    func testBootstrapRegistersExpectedBuiltIns() {
        let registry = WidgetRegistry.shared
        let before = registry.allDescriptors.count
        registry.bootstrapBuiltIns()
        let ids = Set(registry.allDescriptors.map(\.id))
        XCTAssertGreaterThanOrEqual(registry.allDescriptors.count, before)

        let required = [
            "academics",
            "academic_calendar",
            "deadlines",
            "schedule",
            "documents",
            "events",
            "tasks",
            "career_pipeline",
            "career_followups",
            "career_summary",
        ]
        for id in required {
            XCTAssertTrue(ids.contains(id), "Missing widget descriptor \(id)")
        }
    }
}
