import SwiftUI

public enum CalendarOverlayPresentationStyle {
    case anchoredPanel
    case fullScreenOverlay
}

@MainActor
public protocol CalendarOverlayBuilding: AnyObject {
    func addCalendarItemOverlay(
        isPresented: Binding<Bool>,
        semesterID: UUID?,
        initialTitle: String?,
        initialStart: Date?,
        initialEnd: Date?,
        eventID: UUID?,
        style: CalendarOverlayPresentationStyle
    ) -> AnyView
}

@MainActor
public enum CalendarOverlayAccess {
    public static weak var builder: (any CalendarOverlayBuilding)?
}
