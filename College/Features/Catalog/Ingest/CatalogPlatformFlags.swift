// CatalogPlatformFlags.swift
// Feature: Catalog
// Purpose: UserDefaults feature flags for catalog platform rollout.
// Data: CollegePersistence / repositories when applicable.
//
// CLI / defaults (macOS):
//   defaults write Timothy.College catalog.documentIR.enabled -bool true
//   defaults write Timothy.College catalog.modernCampusIR.enabled -bool true
//   defaults write Timothy.College catalog.ingest.gate.enabled -bool true
//   defaults write Timothy.College catalog.layoutLLM.enabled -bool true
//   defaults write Timothy.College catalog.entityLLM.enabled -bool true
//   defaults write Timothy.College catalog.scraper.fullSummary.enabled -bool true
//
// Flag matrix:
//   documentIR OFF, modernCampusIR OFF → UniversalCatalogScraper + legacy CourseLeaf crawl
//   documentIR ON,  modernCampusIR OFF → CourseLeaf graph crawl; MC still uses UniversalCatalogScraper
//   documentIR ON,  modernCampusIR ON  → MC graph + ModernCampusIRPipeline; CL graph crawl
//   modernCampusIR explicit OFF        → MC UniversalCatalogScraper even if documentIR is ON
//   ingestGate OFF                     → skip CatalogIngestGate (not recommended)

import Foundation

enum CatalogPlatformFlags {
    private static let documentIRKey = "catalog.documentIR.enabled"
    private static let modernCampusIRKey = "catalog.modernCampusIR.enabled"
    private static let ingestGateKey = "catalog.ingest.gate.enabled"
    private static let layoutLLMKey = "catalog.layoutLLM.enabled"
    private static let entityLLMKey = "catalog.entityLLM.enabled"
    private static let universalScraperFullSummaryKey = "catalog.scraper.fullSummary.enabled"

    /// When true, Document IR pipelines run for supported engines (CourseLeaf + Modern Campus when `modernCampusIREnabled`).
    /// Default **true** when the key is unset (post–golden-parity rollout); set explicitly to opt out.
    static var documentIREnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: documentIRKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: documentIRKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: documentIRKey) }
    }

    /// When true (and document IR on), Modern Campus sync crawls `CatalogGraph` via `ModernCampusIRPipeline`.
    /// Unset mirrors `documentIREnabled`.
    static var modernCampusIREnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: modernCampusIRKey) != nil {
                return UserDefaults.standard.bool(forKey: modernCampusIRKey)
            }
            return documentIREnabled
        }
        set { UserDefaults.standard.set(newValue, forKey: modernCampusIRKey) }
    }

    /// When true, run structural invariants + sanity + recovery before persisting ingest results.
    static var ingestGateEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: ingestGateKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: ingestGateKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: ingestGateKey) }
    }

    /// When true, invoke local LLM for layout profile classification only when deterministic confidence is ambiguous.
    static var layoutLLMEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: layoutLLMKey) }
        set { UserDefaults.standard.set(newValue, forKey: layoutLLMKey) }
    }

    /// When true, Settings review tooling may invoke local LLM entity validation (dev/review only).
    static var entityLLMEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: entityLLMKey) }
        set { UserDefaults.standard.set(newValue, forKey: entityLLMKey) }
    }

    /// When true, UniversalCatalogScraper emits the full program/school debug dump (DEBUG builds default on).
    static var universalScraperFullSummaryEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: universalScraperFullSummaryKey)
        #endif
    }
}
