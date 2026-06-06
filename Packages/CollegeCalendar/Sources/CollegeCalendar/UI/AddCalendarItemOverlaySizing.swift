import SwiftUI

public struct AddCalendarItemOverlayPreferredHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct AddTaskOverlayPreferredHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
