// JobBoardSyncStatusPresentation.swift
// Feature: Career / Job Board
// Purpose: User-facing sync status copy for openings UI.

import Foundation

enum JobBoardSyncStatusPresentation {
    static func sidebarSubtitle(for status: JobBoardSyncUIState.CompanyState.Status?) -> String {
        switch status {
        case .idle:
            return "Not synced"
        case .scraping(let progress):
            if let progress {
                return "Syncing \(Int((progress * 100).rounded()))%"
            }
            return "Syncing…"
        case .importing:
            return "Saving listings…"
        case .ok(let count, _):
            return count == 1 ? "1 job" : "\(count) jobs"
        case .error(let err, _):
            return shortError(err)
        case .none:
            return "Not synced"
        }
    }

    static func bannerTitle(for status: JobBoardSyncUIState.CompanyState.Status) -> String {
        switch status {
        case .idle:
            return "This company hasn't been synced yet"
        case .scraping(let progress):
            if let progress, progress >= 0.99 {
                return "Finishing sync…"
            }
            return "Syncing openings"
        case .importing:
            return "Saving openings"
        case .ok(let count, let at):
            if count == 0 {
                return "Sync completed with no active openings"
            }
            return "Last synced \(at.formatted(.relative(presentation: .named)))"
        case .error:
            return "Couldn't sync this company's board"
        }
    }

    static func bannerMessage(
        for status: JobBoardSyncUIState.CompanyState.Status,
        companyName: String
    ) -> String {
        switch status {
        case .idle:
            return "Tap refresh to pull the latest roles from \(companyName). If this keeps failing, the careers site may have changed or be temporarily unavailable."
        case .scraping:
            return "College is fetching job listings from \(companyName). This usually takes a few seconds."
        case .importing:
            return "Download complete — saving listings locally so you can browse and filter them."
        case .ok(let count, _):
            if count == 0 {
                return "The board responded, but there are no active openings right now. Try again later or confirm the careers URL is correct."
            }
            return "Showing \(count) active opening\(count == 1 ? "" : "s") from \(companyName)."
        case .error(let err, let at):
            return """
            \(fullError(err))

            Last attempt \(at.formatted(.relative(presentation: .named))). This is usually an issue with the employer's careers site — not College.
            """
        }
    }

    static func bannerIsError(for status: JobBoardSyncUIState.CompanyState.Status) -> Bool {
        if case .error = status { return true }
        return false
    }

    static func bannerShowsAction(for status: JobBoardSyncUIState.CompanyState.Status) -> Bool {
        switch status {
        case .idle, .error, .ok(0, _):
            return true
        default:
            return false
        }
    }

    private static func shortError(_ error: WorkdayScraperError) -> String {
        switch error {
        case .requiresAuth:
            return "Sign-in required"
        case .badURL:
            return "Bad careers URL"
        case .httpError(404):
            return "Board not found"
        case .rateLimited:
            return "Rate limited"
        case .network:
            return "Network issue"
        default:
            return "Sync failed"
        }
    }

    private static func fullError(_ error: WorkdayScraperError) -> String {
        error.userFacingExplanation
    }
}

private extension WorkdayScraperError {
    var userFacingExplanation: String {
        switch self {
        case .badURL:
            return "The careers page URL doesn't look like a supported job board. Open the company picker and verify the link."
        case .httpError(let code):
            if code == 404 {
                return "The employer's careers board wasn't found (HTTP 404). The site may have moved or the board URL may be wrong."
            }
            if code == 403 || code == 401 {
                return "The careers site blocked automated access (HTTP \(code)). You may need to browse openings on their website directly."
            }
            return "The careers site returned HTTP \(code). Their server may be down or blocking requests."
        case .requiresAuth:
            return "This careers board appears to require sign-in. College can only sync public job listings."
        case .decodingFailed(let detail):
            if detail.localizedCaseInsensitiveContains("empty json")
                || detail.localizedCaseInsensitiveContains("unexpected response") {
                return "The careers site returned an unexpected response. Their Workday board may be misconfigured or temporarily broken."
            }
            return "The careers site returned data College couldn't read: \(detail)"
        case .rateLimited:
            return "The careers site rate-limited requests or blocked automated access (common on BuiltIn). Wait a few minutes and try again, or pick a different board."
        case .network(let detail):
            return "College couldn't reach the careers site: \(detail)"
        }
    }
}
