// DiagnosticsEnvironment.swift
// Feature: Debug
// Purpose: Build and device manifest for diagnostic exports.

import Foundation
import Darwin

struct DiagnosticsEnvironmentManifest: Codable, Sendable, Equatable {
    struct BuildInfo: Codable, Sendable, Equatable {
        let version: String
        let build: String
        let gitCommit: String
        let buildDate: String
    }

    struct DeviceProfile: Codable, Sendable, Equatable {
        let macModel: String
        let ramGB: Double
        let storageFreeGB: Double
        let cpuDescription: String
    }

    let build: BuildInfo
    let device: DeviceProfile
    let capturedAtISO8601: String
}

enum DiagnosticsEnvironment {
    static func capture(now: Date = Date()) -> DiagnosticsEnvironmentManifest {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let gitCommit = bundle.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? "unknown"

        let formatter = ISO8601DateFormatter()
        let buildDate = formatter.string(from: now)

        let report = AppleSiliconPlatform.report
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let storageFreeGB = freeStorageGB() ?? 0

        return DiagnosticsEnvironmentManifest(
            build: .init(version: version, build: build, gitCommit: gitCommit, buildDate: buildDate),
            device: .init(
                macModel: sysctlString("hw.model") ?? report.deviceName,
                ramGB: (ramGB * 10).rounded() / 10,
                storageFreeGB: (storageFreeGB * 10).rounded() / 10,
                cpuDescription: sysctlString("machdep.cpu.brand_string") ?? report.deviceName
            ),
            capturedAtISO8601: buildDate
        )
    }

    static func writeJSON(to url: URL) throws {
        let manifest = capture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func freeStorageGB() -> Double? {
        guard let url = DiagnosticsArtifacts.applicationSupportBase() else { return nil }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Double(bytes) / 1_073_741_824.0
    }
}
