import Foundation
import MapKit

enum TravelTransport: String, Codable, CaseIterable {
    case driving
    case walking
    case transit

    var title: String {
        switch self {
        case .driving: return "Driving"
        case .walking: return "Walking"
        case .transit: return "Transit"
        }
    }

    var directionsType: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        }
    }

    var symbolName: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        }
    }
}

struct TravelTimeSettings: Codable, Equatable {
    var enabled: Bool
    var transport: TravelTransport
    var minutes: Int?
    var resolvedLocation: ResolvedLocation?
}

enum TravelTimeStore {
    private static let overridePrefix = "College.TravelTimeOverride.v1."
    private static let lastTransportKey = "College.TravelTimeLastTransportType.v1"

    static func loadLastTransport() -> TravelTransport {
        if let raw = UserDefaults.standard.string(forKey: lastTransportKey),
           let transport = TravelTransport(rawValue: raw) {
            return transport
        }
        return .driving
    }

    static func saveLastTransport(_ transport: TravelTransport) {
        UserDefaults.standard.set(transport.rawValue, forKey: lastTransportKey)
    }

    static func loadOverride(eventID: UUID) -> TravelTimeSettings? {
        let key = overridePrefix + eventID.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TravelTimeSettings.self, from: data)
    }

    static func saveOverride(_ settings: TravelTimeSettings, eventID: UUID) {
        let key = overridePrefix + eventID.uuidString
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clearOverride(eventID: UUID) {
        let key = overridePrefix + eventID.uuidString
        UserDefaults.standard.removeObject(forKey: key)
    }
}
