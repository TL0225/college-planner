// CareerRepository+ApplyPreferences.swift
// Feature: Core/Data
// Purpose: Fetch and upsert Career Apply Profile preferences.

import Foundation
import SwiftData

extension CareerRepository {
    func fetchApplicationPreferences() throws -> CareerApplicationPreferences? {
        var descriptor = FetchDescriptor<CareerApplicationPreferences>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func ensureApplicationPreferences() throws -> CareerApplicationPreferences {
        if let existing = try fetchApplicationPreferences() {
            return existing
        }
        let prefs = CareerApplicationPreferences()
        context.insert(prefs)
        try context.save()
        return prefs
    }

    func saveApplicationPreferences(_ prefs: CareerApplicationPreferences) throws {
        prefs.updatedAt = Date()
        try context.save()
    }
}
