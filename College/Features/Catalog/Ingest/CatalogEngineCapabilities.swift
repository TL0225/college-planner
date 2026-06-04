// CatalogEngineCapabilities.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogEngineCapabilities.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// High-level ingest engine identifier used by shared capability policy.
enum CatalogIngestEngine: String, Codable, Sendable, CaseIterable {
    case modernCampus = "moderncampus"
    case courseLeaf = "courseleaf"
    case pdf
    case profile
    case unknown

    init(manifestFormat: String?) {
        let normalized = (manifestFormat ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "acalog", "moderncampus":
            self = .modernCampus
        case "courseleaf":
            self = .courseLeaf
        case "pdf":
            self = .pdf
        case "profile":
            self = .profile
        default:
            self = .unknown
        }
    }
}

/// Shared, engine-agnostic capability contract.
///
/// This model is intentionally independent from per-engine internals so each
/// engine can provide an adapter without leaking transport/parser details.
struct CatalogEngineCapabilities: Sendable, Codable, Equatable {
    let engine: CatalogIngestEngine
    let supportsCourses: Bool
    let supportsPrograms: Bool
    let supportsRequirements: Bool
    let supportsCatalogYear: Bool
    let supportsDiffing: Bool
    let supportsHistoricalSnapshots: Bool
}

protocol CatalogEngineCapabilityProvider: Sendable {
    func capabilities(for engine: CatalogIngestEngine) -> CatalogEngineCapabilities
}

struct CatalogEngineCapabilityDefaults: CatalogEngineCapabilityProvider {
    static let shared = CatalogEngineCapabilityDefaults()

    func capabilities(for engine: CatalogIngestEngine) -> CatalogEngineCapabilities {
        switch engine {
        case .modernCampus:
            return CatalogEngineCapabilities(
                engine: engine,
                supportsCourses: true,
                supportsPrograms: true,
                supportsRequirements: true,
                supportsCatalogYear: true,
                supportsDiffing: true,
                supportsHistoricalSnapshots: true
            )
        case .courseLeaf:
            return CatalogEngineCapabilities(
                engine: engine,
                supportsCourses: true,
                supportsPrograms: true,
                supportsRequirements: true,
                supportsCatalogYear: true,
                supportsDiffing: true,
                supportsHistoricalSnapshots: true
            )
        case .pdf:
            return CatalogEngineCapabilities(
                engine: engine,
                supportsCourses: true,
                supportsPrograms: true,
                supportsRequirements: true,
                supportsCatalogYear: true,
                supportsDiffing: false,
                supportsHistoricalSnapshots: true
            )
        case .profile:
            return CatalogEngineCapabilities(
                engine: engine,
                supportsCourses: true,
                supportsPrograms: true,
                supportsRequirements: true,
                supportsCatalogYear: false,
                supportsDiffing: false,
                supportsHistoricalSnapshots: false
            )
        case .unknown:
            return CatalogEngineCapabilities(
                engine: engine,
                supportsCourses: false,
                supportsPrograms: false,
                supportsRequirements: false,
                supportsCatalogYear: false,
                supportsDiffing: false,
                supportsHistoricalSnapshots: false
            )
        }
    }
}

extension CollegePersistence.CatalogCapability {
    /// Adapts persisted readiness into a normalized engine capability view.
    func asSharedCapabilities(
        engine: CatalogIngestEngine,
        provider: CatalogEngineCapabilityProvider = CatalogEngineCapabilityDefaults.shared
    ) -> CatalogEngineCapabilities {
        let declared = provider.capabilities(for: engine)
        return CatalogEngineCapabilities(
            engine: declared.engine,
            supportsCourses: declared.supportsCourses && coursesReady,
            supportsPrograms: declared.supportsPrograms && programsReady,
            supportsRequirements: declared.supportsRequirements && requirementsReady,
            supportsCatalogYear: declared.supportsCatalogYear,
            supportsDiffing: declared.supportsDiffing,
            supportsHistoricalSnapshots: declared.supportsHistoricalSnapshots && fullArchiveReady
        )
    }
}
