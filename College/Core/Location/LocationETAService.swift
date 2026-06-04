// LocationETAService.swift
// Feature: Core
// Purpose: Core module — LocationETAService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CoreLocation
import MapKit

@MainActor
enum LocationETAService {
    static func resolveCoordinate(query: String) async -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            let search = MKLocalSearch(request: request)
            search.start { response, _ in
                guard let item = response?.mapItems.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: item.location.coordinate)
            }
        }
    }

    static func calculateETASeconds(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async -> TimeInterval? {
        await withCheckedContinuation { continuation in
            let request = MKDirections.Request()
            let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            request.source = MKMapItem(location: originLocation, address: nil)
            request.destination = MKMapItem(location: destinationLocation, address: nil)
            request.transportType = transportType

            let directions = MKDirections(request: request)
            directions.calculateETA { response, _ in
                continuation.resume(returning: response?.expectedTravelTime)
            }
        }
    }
}
