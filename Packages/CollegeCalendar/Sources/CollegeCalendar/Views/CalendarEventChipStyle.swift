// CalendarEventChipStyle.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarStoredEventChipLabel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

@MainActor
enum CalendarEventChipStyle {
    static func kindDefaultColor(for type: CalendarEventKind) -> Color {
        switch type {
        case .deadline: return .red
        case .lecture, .classEvent: return .accentColor
        case .lab: return .purple
        case .extracurricular, .club: return .green
        case .management: return .orange
        case .computerScience: return .blue
        case .personal: return .indigo
        }
    }

    static func resolveBaseColor(
        event: CalEvent,
        entity: CalendarStoredEvent?,
        calendarManager: CalendarIntegrationManager
    ) -> Color {
        let kindDefault = kindDefaultColor(for: event.type)
        if let entity {
            return CalendarEventDisplayColorResolver.resolve(
                for: entity,
                sourceCalendarColor: calendarManager.sourceCalendarColor(for: entity),
                kindDefault: kindDefault
            )
        }
        return CalendarEventDisplayColorResolver.resolve(
            customColorHex: event.customColorHex,
            legacyEventID: event.calendarEventID,
            sourceCalendarColor: nil,
            kindDefault: kindDefault
        )
    }

    static func chipCornerRadius(
        event: CalEvent,
        entity: CalendarStoredEvent?,
        cellRadius: CGFloat = 8
    ) -> CGFloat {
        if let entity {
            return CalendarTenantKind.resolve(for: entity).resolvedCornerRadius(cellRadius: cellRadius)
        }
        return CalendarTenantKind.personal.resolvedCornerRadius(cellRadius: cellRadius)
    }

    static func textColor(event: CalEvent, baseColor: Color, entity: CalendarStoredEvent?, calendarManager: CalendarIntegrationManager) -> Color {
        if event.customColorHex != nil {
            return baseColor.opacity(0.9)
        }
        if let entity, calendarManager.sourceCalendarColor(for: entity) != nil {
            return baseColor.opacity(0.9)
        }
        switch event.type {
        case .deadline: return .red.opacity(0.8)
        case .lecture, .classEvent: return .accentColor.opacity(0.8)
        case .lab: return .purple.opacity(0.8)
        case .extracurricular, .club: return .green.opacity(0.8)
        default: return .primary
        }
    }
}

/// Shared leading accent + type icons + title row used by `EventPill` and `TimeEventBlock`.
struct CalendarStoredEventChipLabel: View {
    let event: CalEvent
    let baseColor: Color
    let textColor: Color
    var titleFontSize: CGFloat = 9
    var showsTypeIcons: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(baseColor)
                .frame(width: 3)

            if showsTypeIcons {
                if event.isImportant {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 8))
                } else if event.type == .lecture || event.type == .classEvent {
                    Image(systemName: "book.fill")
                        .font(DesignSystem.Fonts.main(size: 8))
                } else if event.type == .lab {
                    Image(systemName: "flask.fill")
                        .font(DesignSystem.Fonts.main(size: 8))
                }
            }

            Text(event.title)
                .font(DesignSystem.Fonts.main(size: titleFontSize, weight: event.isImportant ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(textColor)
    }
}
