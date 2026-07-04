// ATSFingerprintStore.swift
// Feature: Career / Job Board
// Purpose: Central ATS hostname and HTML fingerprint detection.

import Foundation

enum ATSFingerprintStore {
    static func detect(from urlString: String) -> JobBoardPlatform? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else { return nil }

        let path = url.path.lowercased()

        for (platform, hosts) in hostPatterns {
            if hosts.contains(where: { host.contains($0) }) {
                if platform == .oracle {
                    if path.contains("hcmui") || path.contains("candidateexperience") { return .oracle }
                    continue
                }
                return platform
            }
        }
        return nil
    }

    static func detectInHTML(_ html: String) -> JobBoardPlatform? {
        let lower = html.lowercased()
        for marker in htmlMarkers {
            if marker.patterns.contains(where: { lower.contains($0) }) {
                return marker.platform
            }
        }
        return nil
    }

    private static let hostPatterns: [(JobBoardPlatform, [String])] = [
        (.workday, ["myworkdayjobs.com"]),
        (.greenhouse, ["greenhouse.io"]),
        (.lever, ["lever.co", "jobs.lever.co"]),
        (.oracle, ["oraclecloud.com"]),
        (.icims, ["icims.com"]),
        (.talemetry, ["talemetry.com", "jobvite.com"]),
        (.builtIn, ["builtin.com"]),
        (.jobicy, ["jobicy.com"]),
        (.remoteOK, ["remoteok.com"]),
        (.yCombinator, ["ycombinator.com"]),
        (.usajobs, ["usajobs.gov"]),
        (.nycCityJobs, ["cityjobs.nyc.gov"]),
        (.nyStateJobs, ["statejobs.ny.gov"]),
    ]

    private struct HTMLMarker {
        let platform: JobBoardPlatform
        let patterns: [String]
    }

    private static let htmlMarkers: [HTMLMarker] = [
        HTMLMarker(platform: .workday, patterns: ["myworkdayjobs.com", "wday/cxs/"]),
        HTMLMarker(platform: .greenhouse, patterns: ["boards.greenhouse.io", "boards-api.greenhouse.io"]),
        HTMLMarker(platform: .lever, patterns: ["jobs.lever.co", "api.lever.co"]),
        HTMLMarker(platform: .oracle, patterns: ["oraclecloud.com", "recruitingcejobrequisitions", "hcmui"]),
        HTMLMarker(platform: .icims, patterns: ["jibecdn.com", "data-jibe-search-version", "window._jibe", "\"/api/jobs\"", "icims.com", "icims_"]),
        HTMLMarker(platform: .talemetry, patterns: ["webpackjsonptalemetry_careersites", "apply.talemetry.com", "jobvite.com", "jobvite-"]),
        HTMLMarker(platform: .builtIn, patterns: ["builtin.com/job/", "data-builtin-job"]),
        HTMLMarker(platform: .jobicy, patterns: ["jobicy.com/jobs", "jobicy"]),
        HTMLMarker(platform: .remoteOK, patterns: ["remoteok.com/remote-jobs", "remoteok"]),
        HTMLMarker(platform: .yCombinator, patterns: ["ycombinator.com/jobs", "workatastartup.com"]),
        HTMLMarker(platform: .usajobs, patterns: ["usajobs.gov", "data.usajobs.gov"]),
        HTMLMarker(platform: .nycCityJobs, patterns: ["cityjobs.nyc.gov/job/"]),
        HTMLMarker(platform: .nyStateJobs, patterns: ["statejobs.ny.gov/public/vacancy"]),
    ]
}
