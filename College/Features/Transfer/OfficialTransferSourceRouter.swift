// OfficialTransferSourceRouter.swift
// Feature: Transfer
// Purpose: Transfer Database — aggregator-first routing across official source engines.
// Data: Derives route order + engine instances from school manifest capabilities.

import Foundation

/// What official transfer routes are available for a given target institution.
struct TransferSourceAvailability: Hashable, Sendable {
    var aggregatorSupported: Bool
    var assistBaseURL: URL?
    var tesPublicViewURL: URL?
    var bannerArticulationBaseURL: URL?
    var bannerGeneration: Int?

    static let none = TransferSourceAvailability(
        aggregatorSupported: false,
        assistBaseURL: nil,
        tesPublicViewURL: nil,
        bannerArticulationBaseURL: nil,
        bannerGeneration: nil
    )

    /// Builds availability from a target-school manifest. Aggregator support defaults on for
    /// California public institutions where ASSIST.org is authoritative.
    static func from(manifest: SchoolManifest?) -> TransferSourceAvailability {
        guard let manifest else { return .none }
        let aggregator = manifest.transferAggregatorSupported
            ?? (manifest.stateCode?.uppercased() == "CA")
        return TransferSourceAvailability(
            aggregatorSupported: aggregator,
            assistBaseURL: nil,
            tesPublicViewURL: manifest.tesPublicViewURL.flatMap(URL.init(string:)),
            bannerArticulationBaseURL: manifest.bannerArticulationBaseURL.flatMap(URL.init(string:)),
            bannerGeneration: manifest.bannerGeneration
        )
    }
}

/// Picks and orders official source engines, always preferring the aggregator first.
enum OfficialTransferSourceRouter {
    /// Aggregator-first route ordering. The aggregator (ASSIST) is the most authoritative and
    /// cheapest to query, so it leads; institution-specific systems backfill what it misses.
    static func orderedRoutes(for availability: TransferSourceAvailability) -> [TransferOfficialRouteKind] {
        var routes: [TransferOfficialRouteKind] = []
        if availability.aggregatorSupported {
            routes.append(.aggregator)
        }
        if availability.tesPublicViewURL != nil {
            routes.append(.tesPublicView)
        }
        if availability.bannerArticulationBaseURL != nil {
            switch availability.bannerGeneration {
            case 8: routes.append(.banner8Articulation)
            case 9: routes.append(.banner9SSB)
            default: routes.append(.banner9SSB)
            }
        }
        // Always attempt the aggregator even when the manifest is silent — it gracefully
        // degrades (fixture sample or 404) and keeps the feature demonstrable.
        if routes.isEmpty {
            routes.append(.aggregator)
        }
        return routes
    }

    /// Instantiates engines in route order for a refresh pass.
    static func engines(
        for availability: TransferSourceAvailability,
        session: URLSession = .shared
    ) -> [any TransferSourceEngine] {
        orderedRoutes(for: availability).map { route in
            engine(for: route, availability: availability, session: session)
        }
    }

    static func engine(
        for route: TransferOfficialRouteKind,
        availability: TransferSourceAvailability,
        session: URLSession = .shared
    ) -> any TransferSourceEngine {
        switch route {
        case .aggregator:
            return ASSISTOrgEngine(session: session)
        case .tesPublicView:
            return TESPublicViewEngine(liveBaseURL: availability.tesPublicViewURL, session: session)
        case .banner8Articulation:
            return Banner8ArticulationEngine(liveBaseURL: availability.bannerArticulationBaseURL, session: session)
        case .banner9SSB:
            return Banner9SSBEngine(liveBaseURL: availability.bannerArticulationBaseURL, session: session)
        }
    }
}
