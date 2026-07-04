// BackgroundServiceManifest+Tier5.swift
// Feature: Core/Platform
// Purpose: Execution workers invoked by Tier 1/2 coordinators (appendix only).

import Foundation

enum BackgroundServiceManifestTier5 {
    static let jobBoardScrapers: [String] = [
        "WorkdayScraper", "USAJobsScraper", "RemoteOKScraper", "JobicyScraper",
        "YCombinatorScraper", "BuiltInScraper", "GreenhouseScraper", "LeverScraper",
        "ICIMSScraper", "OracleHCMScraper", "TalemetryScraper", "NYStateJobsScraper",
        "NYCCityJobsScraper", "JobBoardPublicHubScrapeEngine",
    ]

    static let catalogWorkers: [String] = [
        "UniversalCatalogScraper", "ModernCampusEngine", "CatalogPDFPipeline",
        "AcademicCalendarScrapeService", "AcademicCalendarEntryDiscoverer",
        "AcademicCalendarHubNavigator", "ICSSubscriptionUpsertService", "AcademicCalendarUpsertService",
    ]

    static let calendarProviders: [String] = [
        "GoogleCalendarProvider", "AppleCalendarProvider", "OutlookCalendarProvider",
        "iCloudCalendarProvider", "CalendarEventWritePipeline", "CalendarSyncMapDiskPersistence",
    ]
}
