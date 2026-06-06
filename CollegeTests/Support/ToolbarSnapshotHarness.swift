// ToolbarSnapshotHarness.swift
// Feature: App / Toolbar tests
// Purpose: PNG snapshot compare/record for ToolbarVisualTests.

import AppKit
import SwiftUI
import XCTest

enum ToolbarSnapshotHarness {
    static let snapshotDirectoryName = "__Snapshots__/ToolbarVisual"

    /// ImageRenderer output varies slightly between runs; allow small pixel drift.
    private static let maxMismatchRatio = 0.03

    static var recordMode: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-RECORD_SNAPSHOTS")
    }

    static func snapshotURL(named name: String, file: StaticString = #filePath) -> URL {
        let testFile = URL(fileURLWithPath: String(describing: file))
        let testsRoot = testFile
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // CollegeTests
        return testsRoot
            .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent("\(name).png")
    }

    @MainActor
    static func assertSnapshot<V: View>(
        named name: String,
        size: CGSize,
        colorScheme: ColorScheme? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        @ViewBuilder content: () -> V
    ) throws {
        var configured = AnyView(content())
        if let colorScheme {
            configured = AnyView(configured.environment(\.colorScheme, colorScheme))
        }

        let framed = configured.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: framed)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = true
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            XCTFail("Failed to render snapshot \(name)", file: file, line: line)
            return
        }

        let actualBitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = actualBitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode snapshot \(name)", file: file, line: line)
            return
        }

        let url = snapshotURL(named: name, file: file)
        if recordMode || !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url)
            return
        }

        let baselineData = try Data(contentsOf: url)
        guard let baselineBitmap = NSBitmapImageRep(data: baselineData) else {
            XCTFail("Failed to decode baseline \(name)", file: file, line: line)
            return
        }

        XCTAssertTrue(
            imagesMatch(baseline: baselineBitmap, actual: actualBitmap, maxMismatchRatio: maxMismatchRatio),
            "Snapshot drift for \(name) exceeds \(Int(maxMismatchRatio * 100))% pixels. Run scripts/record_toolbar_snapshots.sh if intentional.",
            file: file,
            line: line
        )
    }

    private static func imagesMatch(
        baseline: NSBitmapImageRep,
        actual: NSBitmapImageRep,
        maxMismatchRatio: Double
    ) -> Bool {
        guard baseline.pixelsWide == actual.pixelsWide,
              baseline.pixelsHigh == actual.pixelsHigh else {
            return false
        }

        let width = baseline.pixelsWide
        let height = baseline.pixelsHigh
        let totalPixels = width * height
        guard totalPixels > 0 else { return false }

        var mismatches = 0
        for y in 0..<height {
            for x in 0..<width {
                guard let baselineColor = baseline.colorAt(x: x, y: y),
                      let actualColor = actual.colorAt(x: x, y: y) else {
                    mismatches += 1
                    continue
                }

                let channelDelta = max(
                    abs(baselineColor.redComponent - actualColor.redComponent),
                    abs(baselineColor.greenComponent - actualColor.greenComponent),
                    abs(baselineColor.blueComponent - actualColor.blueComponent),
                    abs(baselineColor.alphaComponent - actualColor.alphaComponent)
                )

                if channelDelta > 0.02 {
                    mismatches += 1
                }
            }
        }

        return Double(mismatches) / Double(totalPixels) <= maxMismatchRatio
    }
}
