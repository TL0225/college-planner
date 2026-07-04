// ShareExtensionEntitlementsTests.swift
// M30-075 — share extension sandbox / app-group parity.

import Foundation
import Testing

@Suite("Share Extension Entitlements")
struct ShareExtensionEntitlementsTests {
    private let appGroup = "group.com.timothy.college"

    @Test("Main app entitlements declare career share app group")
    func mainAppEntitlements() throws {
        let url = repoRoot().appendingPathComponent("College/College.entitlements")
        let plist = try loadPlist(url)
        let groups = plist["com.apple.security.application-groups"] as? [String]
        #expect(groups?.contains(appGroup) == true)
    }

    @Test("Share extension entitlements declare career share app group")
    func shareExtensionEntitlements() throws {
        let url = repoRoot().appendingPathComponent("CollegeShareExtension/CollegeShareExtension.entitlements")
        let plist = try loadPlist(url)
        let groups = plist["com.apple.security.application-groups"] as? [String]
        #expect(groups?.contains(appGroup) == true)
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = object as? [String: Any] else {
            Issue.record("Expected dictionary plist at \(url.path)")
            return [:]
        }
        return dict
    }
}
