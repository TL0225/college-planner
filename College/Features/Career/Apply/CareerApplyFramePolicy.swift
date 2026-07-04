// CareerApplyFramePolicy.swift
// Feature: Career / Apply
// Purpose: Origin allowlist for trusted iframe injection (iCIMS / nested apply frames).

import Foundation

enum CareerApplyFramePolicy {
    static let trustedSuffixes = [
        "myworkdayjobs.com",
        "icims.com",
        "greenhouse.io",
        "lever.co",
        "oraclecloud.com",
        "talemetry.com",
        "jobvite.com",
        "jibecdn.com",
    ]

    static func isTrusted(origin: String, applyURL: URL) -> Bool {
        guard let host = URL(string: origin)?.host?.lowercased()
            ?? (origin.contains("://") ? nil : origin.lowercased()) else {
            return false
        }
        if let applyHost = applyURL.host?.lowercased(), host == applyHost || host.hasSuffix(".\(applyHost)") {
            return true
        }
        return trustedSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func allowedOrigins(for applyURL: URL) -> Set<String> {
        var origins: Set<String> = []
        if let host = applyURL.host {
            origins.insert(host.lowercased())
        }
        for suffix in trustedSuffixes {
            origins.insert(suffix)
        }
        return origins
    }
}
