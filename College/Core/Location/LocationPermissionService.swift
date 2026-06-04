// LocationPermissionService.swift
// Feature: Core
// Purpose: Core module — LocationPermissionService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationPermissionService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case notDetermined
        case denied
        case authorized
        case restricted
    }

    @Published private(set) var status: Status = .notDetermined
    @Published private(set) var lastLocation: CLLocation? = nil

    private let manager: CLLocationManager

    override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refreshStatus()
    }

    func refreshStatus() {
        let auth = manager.authorizationStatus
        switch auth {
        case .notDetermined:
            status = .notDetermined
        case .restricted:
            status = .restricted
        case .denied:
            status = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            status = .authorized
        @unknown default:
            status = .notDetermined
        }
    }

    func requestWhenInUseAuthorizationIfNeeded() {
        refreshStatus()
        guard status == .notDetermined else {
            if status == .authorized {
                requestOneShotLocation()
            }
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func requestOneShotLocation() {
        refreshStatus()
        guard status == .authorized else { return }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshStatus()
            if self.status == .authorized {
                self.requestOneShotLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignore transient failures; UI will show unavailable.
    }
}
