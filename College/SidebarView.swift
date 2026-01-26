import SwiftUI

struct SidebarView: View {
    @Binding var activePage: AppPage
    @Namespace private var selectionNamespace
    
    var body: some View {
        VStack(spacing: 20) {
            // Logo area
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 10, x: 0, y: 0)
                
                Image(systemName: "square.grid.2x2")
                    .foregroundColor(.white)
                    .font(DesignSystem.Fonts.main(size: 24))
            }
            .padding(.top, 24)
            .padding(.bottom, 10)
            
            // Navigation Links
            VStack(spacing: 16) {
                SidebarButton(page: .degree, activePage: $activePage, color: DesignSystem.Colors.primary, selectionNamespace: selectionNamespace)
                SidebarButton(page: .calendar, activePage: $activePage, color: DesignSystem.Colors.primary, selectionNamespace: selectionNamespace)
                SidebarButton(page: .whatIf, activePage: $activePage, color: DesignSystem.Colors.secondary, selectionNamespace: selectionNamespace)
                SidebarButton(page: .flowChart, activePage: $activePage, color: DesignSystem.Colors.accent, selectionNamespace: selectionNamespace)
                SidebarButton(page: .resources, activePage: $activePage, color: DesignSystem.Colors.warning, selectionNamespace: selectionNamespace)
                SidebarButton(page: .profile, activePage: $activePage, color: DesignSystem.Colors.info, selectionNamespace: selectionNamespace)
                SidebarButton(page: .settings, activePage: $activePage, color: DesignSystem.Colors.textMain, selectionNamespace: selectionNamespace)
            }
            
            Spacer()
            
            // Logout button
            Button(action: {}) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(DesignSystem.Fonts.main(size: 24))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding()
            }
            .debugLogTap("Sidebar: Logout")
            .padding(.bottom, 16)
        }
        .frame(width: 96)
        .background(DesignSystem.Colors.surface)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(hex: "f1f5f9")),
            alignment: .trailing
        )
    }
}

struct SidebarButton: View {
    let page: AppPage
    @Binding var activePage: AppPage
    let color: Color
    let selectionNamespace: Namespace.ID
    
    var isActive: Bool {
        activePage == page
    }
    
    var body: some View {
        Button(action: {
            DebugLogger.shared.ui("Sidebar: select page=\(page.rawValue)")
            activePage = page
        }) {
            VStack(spacing: 4) {
                Image(systemName: page.icon)
                    .font(DesignSystem.Fonts.main(size: 24))
                    .scaleEffect(isActive ? 1.06 : 1.0)

                Text(page.rawValue)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
            }
            .foregroundColor(isActive ? color : DesignSystem.Colors.textLight)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.10))
                        .matchedGeometryEffect(id: "sidebar.selection", in: selectionNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .debugLogTap("Sidebar: \(page.rawValue)")
        .buttonStyle(SidebarPressStyle())
        .animation(Animation.spring(response: 0.25, dampingFraction: 0.85), value: isActive)
    }
}

private struct SidebarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
