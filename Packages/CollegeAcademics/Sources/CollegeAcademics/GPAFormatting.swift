// GPAFormatting.swift
// Feature: Academics
// Purpose: Academics module — GPAFormatting.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Shared 4.0-scale GPA display (three decimal places; denominator always 4.000).
public enum GPAFormatting {
    public static let scaleMaximum: Double = 4.0

    public static var scaleDenominatorText: String { formatValue(scaleMaximum) }

    public static let missingNumeratorText = "—"

    public static func formatValue(_ gpa: Double) -> String {
        let clamped = min(max(gpa, 0), scaleMaximum)
        return String(format: "%.3f", clamped)
    }

    /// `3.500 / 4.000`, or `— / 4.000` when GPA is unknown.
    public static func fractionText(gpa: Double?) -> String {
        let numerator = gpa.map(formatValue) ?? missingNumeratorText
        return "\(numerator) / \(scaleDenominatorText)"
    }

    /// Numerator only (`3.500` or `—`).
    public static func numeratorText(gpa: Double?) -> String {
        guard let gpa else { return missingNumeratorText }
        return formatValue(gpa)
    }

    /// Localized label prefix for profile cards, e.g. `GPA 3.500 / 4.000`.
    public static func labeledFractionText(gpa: Double?) -> String {
        String(
            format: String(
                localized: "academic.gpa.fraction_label_fmt",
                defaultValue: "GPA %@"
            ),
            fractionText(gpa: gpa)
        )
    }
}
