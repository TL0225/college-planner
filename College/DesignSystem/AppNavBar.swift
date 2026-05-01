// AppNavBar.swift
// Global top navigation bar — the single header used by every page in the app.
//
// Design: flat white full-width bar (matches the Student Portal screenshot).
//   Left  — "Student Portal" bold + green "Verified Student" pill
//   Center — 5 page tabs (Overview, Academics, Documents, Schedule, Profile)
//   Right  — ✦ Ask AI · ⚙ Settings · user name + initials avatar

import SwiftUI
import CoreData

// MARK: - AppNavBar

struct AppNavBar: View {
    @Binding var activePage: AppPage
    @Namespace private var tabIndicator

    @FetchRequest(fetchRequest: AppNavBar.profileRequest)
    private var profiles: FetchedResults<ProfileEntity>

    private static var profileRequest: NSFetchRequest<ProfileEntity> {
        let r = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
        r.fetchLimit = 1
        r.sortDescriptors = []
        return r
    }

    private var profile: ProfileEntity? { profiles.first }

    private struct NavTab {
        let label: String
        let page: AppPage
    }

    private let tabs: [NavTab] = [
        NavTab(label: "Overview",    page: .degree),
        NavTab(label: "Academics",   page: .academics),
        NavTab(label: "Schedule",    page: .calendar),
        NavTab(label: "Brightspace", page: .brightspace),
        NavTab(label: "Profile",     page: .profile),
    ]

    private var initials: String {
        let name = (profile?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")).uppercased()
                 + String((parts[1].first ?? "?")).uppercased()
        } else if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return "?"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {

            // ── LEFT: brand + verified badge ────────────────────────────────
            HStack(spacing: 8) {
                Text("Student Portal")
                    .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "1e1b4b"))

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "16a34a"))
                    Text("Verified Student")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "16a34a"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "dcfce7"))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: "bbf7d0"), lineWidth: 1))
            }
            .padding(.leading, 24)

            Spacer()

            // ── CENTER: tab navigation ───────────────────────────────────────
            HStack(spacing: 2) {
                ForEach(tabs, id: \.label) { tab in
                    AppNavTabButton(
                        label: tab.label,
                        isActive: activePage == tab.page,
                        namespace: tabIndicator,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                activePage = tab.page
                            }
                        }
                    )
                }
            }

            Spacer()

            // ── RIGHT: breadcrumb · Ask AI · Settings · user ────────────────
            HStack(spacing: 4) {
                // Breadcrumb path
                HStack(spacing: 4) {
                    Text("Student Portal")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: "9ca3af"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "d1d5db"))
                    Text(tabs.first(where: { $0.page == activePage })?.label ?? "")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "4f46e5"))
                }
                .padding(.trailing, 8)

                Rectangle()
                    .fill(Color(hex: "e5e7eb"))
                    .frame(width: 1, height: 16)
                    .padding(.trailing, 4)

                AppNavActionButton(icon: "sparkles", label: "Ask AI")

                AppNavActionButton(icon: "gearshape", label: "Settings", action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activePage = .settings
                    }
                })

                // User name + initials avatar
                HStack(spacing: 7) {
                    Text((profile?.name?.isEmpty == false ? profile?.name : nil) ?? "Student")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "374151"))

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "6366f1"), Color(hex: "4f46e5")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(initials)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 30, height: 30)
                }
                .padding(.trailing, 24)
            }
        }
        .frame(height: 52)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(hex: "e5e7eb"))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - AppNavTabButton

struct AppNavTabButton: View {
    let label: String
    let isActive: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DesignSystem.Fonts.main(
                    size: 13,
                    weight: isActive ? .bold : .medium
                ))
                .foregroundColor(
                    isActive
                        ? Color(hex: "1e1b4b")
                        : (isHovered ? Color(hex: "374151") : Color(hex: "6b7280"))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "e0e7ff").opacity(0.6))
                            .matchedGeometryEffect(id: "tabPill", in: namespace)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovered }
        }
    }
}

// MARK: - AppNavActionButton

struct AppNavActionButton: View {
    let icon: String
    let label: String
    var action: () -> Void = {}
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
            }
            .foregroundColor(isHovered ? Color(hex: "4f46e5") : Color(hex: "6b7280"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
