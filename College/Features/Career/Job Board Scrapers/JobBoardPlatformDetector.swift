// JobBoardPlatformDetector.swift
// Feature: Career / Job Board Scrapers
// Purpose: Detect job-board platform from careers URL.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum JobBoardPlatformDetector {
    /// Fast URL-only detection (no network).
    static func detect(from urlString: String) -> JobBoardPlatform? {
        ATSFingerprintStore.detect(from: urlString)
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
        ATSFingerprintStore.detectInHTML(html)
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
        case .builtIn:
            guard let url = URL(string: trimmed) else {
                return ("Enter a valid BuiltIn jobs URL", false)
            }
            if !JobBoardRobotsPolicy.isAllowedBuiltInHubURL(url) {
                if url.query?.lowercased().contains("search=") == true {
                    return ("BuiltIn search URLs are blocked by robots.txt — use https://builtin.com/jobs and filter in College", false)
                }
                return ("This BuiltIn URL is not allowed (regional hub, apply path, or search). Use https://builtin.com/jobs", false)
            }
            if url.path.lowercased().contains("/jobs/remote") || url.path.lowercased().contains("/jobs/dev") {
                return ("Category URLs are optional — All jobs already includes these roles. Use https://builtin.com/jobs unless you want a smaller sync.", true)
            }
            return ("BuiltIn hub — paginated HTML sync (up to \(JobBoardThresholds.maxListPagesPerSync) pages)", true)
        case .jobicy:
            guard let url = URL(string: trimmed), url.host?.lowercased().contains("jobicy.com") == true else {
                return ("Use a jobicy.com remote-jobs hub URL", false)
            }
            return ("Jobicy remote jobs hub", true)
        case .remoteOK:
            guard URL(string: trimmed)?.host?.lowercased().contains("remoteok.com") == true else {
                return ("Use https://remoteok.com as the hub URL", false)
            }
            return ("RemoteOK hub — HTML sync with 1s crawl delay", true)
        case .yCombinator:
            guard let url = URL(string: trimmed), url.host?.lowercased().contains("ycombinator.com") == true else {
                return ("Use https://www.ycombinator.com/jobs", false)
            }
            return ("Y Combinator jobs board", true)
        case .usajobs:
            guard URL(string: trimmed)?.host?.lowercased().contains("usajobs.gov") == true else {
                return ("Use https://www.usajobs.gov/Search/Results", false)
            }
            if JobBoardUSAJobsCredentials.isConfigured {
                return ("USAJobs Search API — credentials configured", true)
            }
            return ("USAJobs — enter your API key and email below", false)
        case .nycCityJobs:
            guard let url = URL(string: trimmed), url.host?.lowercased().contains("cityjobs.nyc.gov") == true else {
                return ("Use https://cityjobs.nyc.gov/jobs", false)
            }
            if url.path.lowercased().hasPrefix("/jobs") {
                return ("NYC City Jobs listing board", true)
            }
            return ("Use the /jobs listing URL (not filtered search)", false)
        case .nyStateJobs:
            guard URL(string: trimmed)?.host?.lowercased().contains("statejobs.ny.gov") == true else {
                return ("Use https://statejobs.ny.gov/public/vacancyTable.cfm", false)
            }
            return ("NY State civil service vacancy table", true)
        }
    }
}
