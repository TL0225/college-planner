// ToolbarDispatcher.swift
// Feature: App / Toolbar
// Purpose: Window-scoped scoped toolbar action dispatch (ADR 002).

import Foundation
import Observation

@MainActor
struct ToolbarHandlerToken {
    fileprivate let owner: ToolbarHandlerOwner
    fileprivate weak var dispatcher: ToolbarDispatcher?

    func invalidate() {
        dispatcher?.removeHandler(for: owner)
    }
}

@Observable
@MainActor
final class ToolbarDispatcher {
    private var handlers: [ToolbarHandlerOwner: (ToolbarAction) -> Void] = [:]
    private let telemetry: ToolbarTelemetrySink

    #if DEBUG
    private(set) var dispatchCount: Int = 0
    private(set) var lastDispatchLatencyMicroseconds: UInt64 = 0
    #endif

    init(telemetry: ToolbarTelemetrySink = DebugToolbarTelemetry()) {
        self.telemetry = telemetry
    }

    @discardableResult
    func register(
        owner: ToolbarHandlerOwner,
        handler: @escaping (ToolbarAction) -> Void
    ) -> ToolbarHandlerToken {
        handlers[owner] = handler
        return ToolbarHandlerToken(owner: owner, dispatcher: self)
    }

    func dispatch(_ action: ToolbarAction) {
        #if DEBUG
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let end = DispatchTime.now().uptimeNanoseconds
            lastDispatchLatencyMicroseconds = (end - start) / 1_000
            dispatchCount += 1
        }
        #endif

        telemetry.track(action: action, owner: owner(for: action))
        guard let owner = owner(for: action), let handler = handlers[owner] else { return }
        handler(action)
    }

    fileprivate func removeHandler(for owner: ToolbarHandlerOwner) {
        handlers.removeValue(forKey: owner)
    }

    #if DEBUG
    var activeHandlerCount: Int { handlers.count }
    #endif

    private func owner(for action: ToolbarAction) -> ToolbarHandlerOwner? {
        switch action {
        case .calendar: return .calendar
        case .academics: return .academics
        case .web: return .webPortal(nil)
        case .career: return .career
        }
    }
}
