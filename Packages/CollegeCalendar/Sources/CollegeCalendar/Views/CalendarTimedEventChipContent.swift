// CalendarTimedEventChipContent.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarTimedEventChipContent.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Week/day timed grid chip: title, time range, optional location, full-height leading accent.
public struct CalendarTimedEventChipContent: View {
    public let title: String
    public let start: Date
    public let end: Date
    public var location: String?
    public let accentColor: Color
    public var titleColor: Color = .primary
    public var secondaryColor: Color = .secondary
    public var showsLocationLine: Bool = true

    public init(
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        accentColor: Color,
        titleColor: Color = .primary,
        secondaryColor: Color = .secondary,
        showsLocationLine: Bool = true
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.accentColor = accentColor
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.showsLocationLine = showsLocationLine
    }

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

    public var body: some View {
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
