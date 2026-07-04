import SwiftUI

public extension DesignSystem {
    /// Shared trailing-inspector column chrome (Calendar Event List, Academics stats, etc.).
    enum InspectorSidebar {
        public static func gradient(for colorScheme: ColorScheme) -> LinearGradient {
            let colors: [Color] = switch colorScheme {
            case .dark:
                [Color(hex: "1e293b"), Color(nsColor: .windowBackgroundColor)]
            default:
                [Color(hex: "E6F2FF"), .white]
            }
            return LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

public struct InspectorSidebarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        DesignSystem.InspectorSidebar.gradient(for: colorScheme)
            .ignoresSafeArea()
    }
}

public extension View {
    /// Applies the shared inspector-column gradient and optional leading divider.
    func inspectorSidebarBackground(showLeadingDivider: Bool = true) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { InspectorSidebarBackground() }
            .overlay(alignment: .leading) {
                if showLeadingDivider {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                }
            }
    }
}
