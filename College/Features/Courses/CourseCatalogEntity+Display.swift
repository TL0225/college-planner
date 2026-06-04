// CourseCatalogEntity+Display.swift
// Feature: Courses
// Purpose: Courses module — CourseCatalogEntity+Display.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Display helpers for catalog course rows (local store `CourseCatalog`).
extension CourseCatalog {
    var draggableCourseCode: String {
        courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var creditsDisplayText: String {
        let base = Int(credits)
        return base > 0 ? String(base) : ""
    }

    var creditsValue: Double { Double(credits) }
}
