// CalendarTimedEventChipContent.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarTimedEventChipContent.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Week/day timed grid chip: title, time range, optional location, full-height leading accent.
struct CalendarTimedEventChipContent: View {
    let title: String
    let start: Date
    let end: Date
    var location: String?
    let accentColor: Color
    var titleColor: Color = .primary
    var secondaryColor: Color = .secondary
    var showsLocationLine: Bool = true

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var trimmedLocation: String? {
        guard let location else { return nil }
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var timeRangeText: String {
        "\(Self.timeFormatter.string(from: start)) – \(Self.timeFormatter.string(from: end))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(timeRangeText)
                    .font(DesignSystem.Fonts.main(size: 9, weight: .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if showsLocationLine, let trimmedLocation {
                    Text(trimmedLocation)
                        .font(DesignSystem.Fonts.main(size: 9, weight: .regular))
                        .foregroundStyle(secondaryColor.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
