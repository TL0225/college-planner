// JobBoardPlatformDetector.swift
// Feature: Career
// Purpose: Career module — JobBoardPlatformDetector.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum JobBoardPlatformDetector {
    /// Fast URL-only detection (no network).
    static func detect(from urlString: String) -> JobBoardPlatform? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else { return nil }

        let path = url.path.lowercased()

        if host.contains("myworkdayjobs.com") { return .workday }
        if host.contains("greenhouse.io") { return .greenhouse }
        if host.contains("lever.co") { return .lever }
        if host.contains("oraclecloud.com"), path.contains("hcmui") || path.contains("candidateexperience") {
            return .oracle
        }
        if host.contains("icims.com") { return .icims }
        if host.contains("talemetry.com") || host.contains("jobvite.com") { return .talemetry }

        return nil
    }

    /// Fetches page HTML when URL alone is ambiguous (custom domains).
    static func probe(urlString: String) async -> JobBoardPlatform? {
        if let detected = detect(from: urlString) { return detected }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }

        do {
            let (data, _) = try await JobBoardHTTP.get(url: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            return detectInHTML(html)
        } catch {
            return nil
        }
    }

    static func detectInHTML(_ html: String) -> JobBoardPlatform? {
        let lower = html.lowercased()
        if lower.contains("myworkdayjobs.com") || lower.contains("wday/cxs/") { return .workday }
        if lower.contains("boards.greenhouse.io") || lower.contains("boards-api.greenhouse.io") { return .greenhouse }
        if lower.contains("jobs.lever.co") || lower.contains("api.lever.co") { return .lever }
        if lower.contains("oraclecloud.com") && (lower.contains("hcmui") || lower.contains("recruitingcejobrequisitions")) {
            return .oracle
        }
        if lower.contains("jibecdn.com")
            || lower.contains("data-jibe-search-version")
            || lower.contains("window._jibe")
            || lower.contains("\"/api/jobs\"")
            || lower.contains("icims.com")
            || lower.contains("icims_") {
            return .icims
        }
        if lower.contains("webpackjsonptalemetry_careersites")
            || lower.contains("apply.talemetry.com")
            || lower.contains("jobvite.com")
            || lower.contains("jobvite-") {
            return .talemetry
        }
        return nil
    }

    static func validationMessage(for urlString: String, platform: JobBoardPlatform) -> (message: String, ok: Bool) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("Enter a careers URL", false) }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            return ("Careers URLs must use HTTPS", false)
        }

        switch platform {
        case .workday:
            let normalized = WorkdayScraper.normalizeCareersURLString(trimmed)
            if let ctx = WorkdayScraper.deriveAPIContext(careersURLString: normalized) {
                return ("Workday API: \(ctx.apiBase.absoluteString)", true)
            }
            if URL(string: normalized)?.host?.lowercased().contains("myworkdayjobs.com") == true {
                return ("Workday URL — board name will be resolved when scraping", true)
            }
            return ("Not a recognized Workday board URL — use the main careers page URL", false)
        case .greenhouse:
            if GreenhouseScraper.boardToken(from: trimmed) != nil {
                return ("Greenhouse board detected", true)
            }
            return ("Use a boards.greenhouse.io URL or embed link", false)
        case .lever:
            if LeverScraper.companySlug(from: trimmed) != nil {
                return ("Lever board detected", true)
            }
            return ("Use a jobs.lever.co/{company} URL", false)
        case .oracle:
            if URL(string: trimmed)?.host?.lowercased().contains("oraclecloud.com") == true {
                return ("Oracle HCM — site number discovered on scrape", true)
            }
            return ("Use an oraclecloud.com Candidate Experience URL", false)
        case .icims:
            if URL(string: trimmed)?.host != nil {
                return ("iCIMS / Jibe — uses /api/jobs when available, else classic HTML", true)
            }
            return ("Enter a valid careers site URL", false)
        case .talemetry:
            if URL(string: trimmed)?.host != nil {
                return ("\(platform.displayName) — HTML scraping; results may vary", true)
            }
            return ("Enter a valid careers site URL", false)
        }
    }
}
