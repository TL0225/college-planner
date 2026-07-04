// JobBoardModels.swift
// Feature: Career
// Purpose: Career module — JobBoardCompany.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - List projection (Phase 6.3)

/// Lightweight list-row projection for job-board reads off the main actor.
struct JobBoardPostingListDTO: Identifiable, Equatable, Sendable {
    let id: UUID
    let persistentModelID: PersistentIdentifier
    let companySlug: String
    let externalPath: String?
    let externalId: String
    let title: String?
    let locationText: String?
    let locationsFilterText: String?
    let jobTypeText: String?
    let timeType: String?
    let postedAt: Date?
    let firstSeenAt: Date?
    let isActive: Bool
    let closedAt: Date?
    let deadlineAt: Date?
    let listingHash: String?
    let descriptionHash: String?
    let jobIdDisplayText: String?
    let jobDescriptionText: String?

    init(posting: JobBoardPosting) {
        id = posting.id
        persistentModelID = posting.persistentModelID
        companySlug = posting.companySlug
        externalPath = posting.externalPath
        externalId = posting.externalId
        title = posting.title
        locationText = posting.locationText
        locationsFilterText = posting.locationsFilterText
        jobTypeText = posting.jobTypeText
        timeType = posting.timeType
        postedAt = posting.postedAt
        firstSeenAt = posting.firstSeenAt
        isActive = posting.isActive
        closedAt = posting.closedAt
        deadlineAt = posting.deadlineAt
        listingHash = posting.listingHash
        descriptionHash = posting.descriptionHash
        jobIdDisplayText = posting.jobIdDisplayText
        jobDescriptionText = posting.jobDescriptionText
    }
}

// MARK: - Thresholds

/// Column widths for Career → Openings (company sidebar + job list + inspector).
enum JobBoardOpeningsLayout {
    /// Wide enough for company names without truncation.
    static let companySidebarWidth: CGFloat = 196
    static let companySidebarMaxWidth: CGFloat = 260
    static let jobListMinWidth: CGFloat = 300
    static let jobListIdealWidth: CGFloat = 380
    static let detailMinWidth: CGFloat = 360
    static let detailIdealWidth: CGFloat = 480
}

enum JobBoardThresholds {
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
    /// Minimum interval between full list-pagination scrapes (quick probes may run more often).
    static let fullListRescrapeInterval: TimeInterval = 24 * 3600
    /// Maximum hub listing pages per sync (public boards).
    static let maxListPagesPerSync = 20
    /// Maximum listings imported per sync (public boards).
    static let maxListingsPerSync = 500
}

enum JobBoardRefreshIntervalOption: Int, CaseIterable, Identifiable {
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

    static func fromStoredSeconds(_ seconds: Int) -> JobBoardRefreshIntervalOption {
        JobBoardRefreshIntervalOption(rawValue: seconds) ?? .twelveHours
    }
}

extension Notification.Name {
    static let jobBoardImportDidFinish = Notification.Name("workday.importDidFinish")
}

// MARK: - Platform

enum JobBoardPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case workday
    case greenhouse
    case lever
    case oracle
    case icims
    case talemetry
    case builtIn
    case jobicy
    case remoteOK
    case yCombinator
    case usajobs
    case nycCityJobs
    case nyStateJobs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workday: return "Workday"
        case .greenhouse: return "Greenhouse"
        case .lever: return "Lever"
        case .oracle: return "Oracle HCM"
        case .icims: return "iCIMS"
        case .talemetry: return "Talemetry / Jobvite"
        case .builtIn: return "BuiltIn"
        case .jobicy: return "Jobicy"
        case .remoteOK: return "RemoteOK"
        case .yCombinator: return "Y Combinator"
        case .usajobs: return "USAJobs"
        case .nycCityJobs: return "NYC City Jobs"
        case .nyStateJobs: return "NY State Jobs"
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
        case .builtIn: return "building"
        case .jobicy: return "globe.americas"
        case .remoteOK: return "house"
        case .yCombinator: return "y.circle"
        case .usajobs: return "flag.fill"
        case .nycCityJobs: return "building.columns.fill"
        case .nyStateJobs: return "map.fill"
        }
    }

    var usesHTMLScraping: Bool {
        switch self {
        case .icims, .talemetry, .builtIn, .jobicy, .remoteOK, .yCombinator, .nycCityJobs, .nyStateJobs:
            return true
        default:
            return false
        }
    }

    var isPublicHubBoard: Bool {
        switch self {
        case .builtIn, .jobicy, .remoteOK, .yCombinator: return true
        default: return false
        }
    }

    var isGovernmentBoard: Bool {
        switch self {
        case .usajobs, .nycCityJobs, .nyStateJobs: return true
        default: return false
        }
    }
}

// MARK: - Company config

struct JobBoardCompany: Codable, Sendable, Identifiable, Equatable, Hashable {
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

struct JobBoardSyncUIState: Equatable, Sendable {
    struct CompanyState: Equatable, Sendable, Identifiable {
        enum Status: Equatable, Sendable {
            case idle
            /// `progress` is 0...1 when total is known; nil means indeterminate.
            case scraping(progress: Double?)
            /// Scrape finished; persisting listings locally.
            case importing
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

    static let empty = JobBoardSyncUIState()
}

enum JobBoardURLValidation {
    static func normalizedApplyURLString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        return trimmed
    }
}
