// ModelMergeCoalescer.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ModelMergeCoalescer.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Debounces `ModelContext.save()` during high-volume local store ingest (Phase 7b).
@MainActor
enum ModelMergeCoalescer {
    private static var pendingContextIDs = Set<ObjectIdentifier>()
    private static var pendingContexts: [ObjectIdentifier: ModelContext] = [:]
    private static var flushTask: Task<Void, Never>?

    static func scheduleSave(_ context: ModelContext) {
        let id = ObjectIdentifier(context)
        pendingContextIDs.insert(id)
        pendingContexts[id] = context
        flushTask?.cancel()
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            flushNow()
        }
    }

    static func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        let ids = pendingContextIDs
        pendingContextIDs.removeAll(keepingCapacity: true)
        for id in ids {
            guard let context = pendingContexts.removeValue(forKey: id) else { continue }
            _ = try? saveIfNeeded(context)
        }
    }

    @discardableResult
    static func saveIfNeeded(_ context: ModelContext) throws -> Bool {
        guard context.hasChanges else { return false }
        try context.save()
        return true
    }
}