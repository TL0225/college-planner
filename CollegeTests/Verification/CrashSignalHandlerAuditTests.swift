// CrashSignalHandlerAuditTests.swift
// Snow Leopard V&V: signal handler uses async-signal-safe C APIs only (CO-F3, CP6).

import XCTest

final class CrashSignalHandlerAuditTests: XCTestCase {
    func testCrashSignalHandlerSourceUsesOnlyAsyncSignalSafeCalls() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("College/Debug/CrashSignalHandler.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        let handlerStart = source.range(of: "private let crash_signal_handler")!
        let handlerBody = String(source[handlerStart.lowerBound...])

        XCTAssertTrue(handlerBody.contains("open("))
        XCTAssertTrue(handlerBody.contains("write("))
        XCTAssertTrue(handlerBody.contains("close("))
        XCTAssertFalse(handlerBody.contains("print("))
        XCTAssertFalse(handlerBody.contains("NSLog("))
        XCTAssertFalse(handlerBody.contains("fatalError("))
    }
}
