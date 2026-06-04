// WorkdayJobBoardModels.swift
// Feature: Career
// Purpose: Career module — WorkdayCompanyConfigEntry.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Thresholds

/// Column widths for Career → Openings (`HSplitView`).
enum WorkdayOpeningsLayout {
    /// Wide enough for company names without truncation.
    static let companySidebarWidth: CGFloat = 196
    static let companySidebarMaxWidth: CGFloat = 260
    static let jobListMinWidth: CGFloat = 300
    static let jobListIdealWidth: CGFloat = 380
    static let detailMinWidth: CGFloat = 360
    static let detailIdealWidth: CGFloat = 480
}

enum WorkdayJobBoardThresholds {
    /// “New” badge when `now - firstSeenAt` is within this interval.
    static let newPostingMaxAge: TimeInterval = 48 * 3600
    /// Sync status chip warns when last successful sync is older than this.
    static let staleSyncInterval: TimeInterval = 24 * 3600
    /// Minimum time between manual refresh-all triggers.
    static let minScrapeCooldown: TimeInterval = 30
    /// Reuse cached job detail when younger than this (force refresh ignores).
    static let detailCacheTTL: TimeInterval = 48 * 3600
    /// Default background refresh interval (12 hours).
    static let defaultRefreshInterval: TimeInterval = 12 * 3600
}

enum WorkdayRefreshIntervalOption: Int, CaseIterable, Identifiable {
    case manual = 0
    case oneHour = 3600
    case threeHours = 10_800
    case sixHours = 21_600
    case twelveHours = 43_200
    case twentyFourHours = 86_400

    var id: Int { rawValue }

    var storageSeconds: Int { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual only"
        case .oneHour: return "Every hour"
        case .threeHours: return "Every 3 hours"
        case .sixHours: return "Every 6 hours"
        case .twelveHours: return "Every 12 hours"
        case .twentyFourHours: return "Every 24 hours"
        }
    }

    static func fromStoredSeconds(_ seconds: Int) -> WorkdayRefreshIntervalOption {
        WorkdayRefreshIntervalOption(rawValue: seconds) ?? .twelveHours
    }
}

extension Notification.Name {
    static let workdayImportDidFinish = Notification.Name("workday.importDidFinish")
}

// MARK: - Platform

enum JobBoardPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case workday
    case greenhouse
    case lever
    case oracle
    case icims
    case talemetry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workday: return "Workday"
        case .greenhouse: return "Greenhouse"
        case .lever: return "Lever"
        case .oracle: return "Oracle HCM"
        case .icims: return "iCIMS"
        case .talemetry: return "Talemetry / Jobvite"
        }
    }

    var icon: String {
        switch self {
        case .workday: return "building.2"
        case .greenhouse: return "leaf"
        case .lever: return "link"
        case .oracle: return "cloud"
        case .icims: return "person.text.rectangle"
        case .talemetry: return "globe"
        }
    }

    var usesHTMLScraping: Bool {
        switch self {
        case .icims, .talemetry: return true
        default: return false
        }
    }
}

// MARK: - Company config

struct WorkdayCompanyConfigEntry: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var slug: String
    var displayName: String
    var careersURL: String
    var enabled: Bool = true
    var platform: JobBoardPlatform = .workday

    var normalizedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, displayName, careersURL, enabled, platform
    }

    init(
        id: UUID = UUID(),
        slug: String,
        displayName: String,
        careersURL: String,
        enabled: Bool = true,
        platform: JobBoardPlatform = .workday
    ) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
        self.careersURL = careersURL
        self.enabled = enabled
        self.platform = platform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        slug = try c.decode(String.self, forKey: .slug)
        displayName = try c.decode(String.self, forKey: .displayName)
        careersURL = try c.decode(String.self, forKey: .careersURL)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        platform = try c.decodeIfPresent(JobBoardPlatform.self, forKey: .platform) ?? .workday
    }
}

// MARK: - Sync UI state (drives company cards + settings chips)

struct WorkdaySyncUIState: Equatable, Sendable {
    struct CompanyState: Equatable, Sendable, Identifiable {
        enum Status: Equatable, Sendable {
            case idle
            /// `progress` is 0...1 when total is known; nil means indeterminate.
            case scraping(progress: Double?)
            case ok(jobCount: Int, at: Date)
            case error(WorkdayScraperError, at: Date)
        }

        var slug: String
        var displayName: String
        var status: Status

        var id: String { slug }
    }

    var companies: [CompanyState] = []
    var lastSuccessfulSyncAt: Date?
    var isAnyScrapeInFlight: Bool = false

    static let empty = WorkdaySyncUIState()
}

enum WorkdayURLValidation {
    static func normalizedApplyURLString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        return trimmed
    }
}
