// NetworkConnectivityMonitor.swift
// Feature: Core / Services
// Purpose: Lightweight online/offline signal for degraded UI (M30-077).

import Foundation
import Network

@MainActor
@Observable
final class NetworkConnectivityMonitor {
    static let shared = NetworkConnectivityMonitor()

    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "college.network.monitor", qos: .utility)
    private var started = false

    private init() {}

    func startIfNeeded() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
        isOnline = monitor.currentPath.status == .satisfied
    }

    func stop() {
        guard started else { return }
        monitor.cancel()
        started = false
    }
}
