// ProfileRepository+FocusBlocks.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+FocusBlocks.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    func fetchFocusBlocks() throws -> [FocusBlockRecord] {
        var descriptor = FetchDescriptor<FocusBlockRecord>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        descriptor.fetchLimit = 200
        return try context.fetch(descriptor)
    }

    func replaceFocusBlocks(_ blocks: [FocusBlock]) throws {
        let existing = try fetchFocusBlocks()
        for row in existing {
            context.delete(row)
        }
        for block in blocks {
            let weekdaysData = try JSONEncoder().encode(block.weekdays)
            let weekdaysJSON = String(data: weekdaysData, encoding: .utf8) ?? "[]"
            context.insert(
                FocusBlockRecord(
                    id: block.id,
                    title: block.title,
                    startHour: block.startHour,
                    endHour: block.endHour,
                    weekdaysJSON: weekdaysJSON
                )
            )
        }
        try context.save()
    }
}

extension FocusBlockRecord {
    func toFocusBlock() -> FocusBlock? {
        guard let data = weekdaysJSON.data(using: .utf8),
              let weekdays = try? JSONDecoder().decode([Int].self, from: data)
        else { return nil }
        return FocusBlock(
            id: id,
            title: title,
            startHour: startHour,
            endHour: endHour,
            weekdays: weekdays
        )
    }
}