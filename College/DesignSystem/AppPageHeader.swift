// AppPageHeader.swift
// Shared top header bar used by every app panel.
//
// Design reference: Student Profile header
//   Left  — page title (22pt bold)
//   Center — optional per-page action buttons
//   Right  — optional search bar · notification bell · profile avatar
//
// Usage (no trailing actions):
//   AppPageHeader(title: "Settings", showSearch: false)
//
// Usage (with trailing actions):
//   AppPageHeader(title: "My Planner", showSearch: false) {
//       Button("+ Add") { ... }
//   }

import SwiftUI
import CoreData
import AppKit

// MARK: - AppPageHeader

struct AppPageHeader<Actions: View>: View {

    // MARK: Configuration

    let title: String

    /// Placeholder text shown inside the search field.
    var searchPlaceholder: String = "Search..."

    /// Two-way binding for the search field text.
    @Binding var searchText: String

    /// Set to `false` to hide the search bar entirely (e.g. Calendar, Settings).
    var showSearch: Bool = true

    /// Optional tap handler for the avatar — used by ProfileView to open the photo picker.
    var onAvatarTap: (() -> Void)? = nil

    /// Optional trailing action buttons placed between the Spacer and the search bar.
    @ViewBuilder let actions: () -> Actions

    // MARK: Environment

    @EnvironmentObject private var securityManager: SecurityManager

    @FetchRequest(fetchRequest: AppPageHeader.profileRequest)
    private var profiles: FetchedResults<ProfileEntity>

    private static var profileRequest: NSFetchRequest<ProfileEntity> {
        let r = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
        r.fetchLimit = 1
        r.sortDescriptors = []
        return r
    }

    private var profile: ProfileEntity? { profiles.first }

    // MARK: Body

    var body: some View {
        HStack(spacing: 12) {
            // ── Title ───────────────────────────────────────────────────────
            Text(title)
                .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Spacer()

            // ── Per-page actions slot ────────────────────────────────────────
            actions()

            // ── Search bar ───────────────────────────────────────────────────
            if showSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    TextField(searchPlaceholder, text: $searchText)
                        .font(DesignSystem.Fonts.main(size: 13))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.underPageBackgroundColor))
                .cornerRadius(9)
                .frame(width: 210)
            }

            // ── Notification bell ─────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(width: 34, height: 34)
                    .background(Color(NSColor.underPageBackgroundColor))
                    .clipShape(Circle())
                Circle()
                    .fill(DesignSystem.Colors.error)
                    .frame(width: 7, height: 7)
                    .offset(x: 1, y: 1)
            }

            // ── Profile avatar ────────────────────────────────────────────────
            avatarView
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .onTapGesture { onAvatarTap?() }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .background(DesignSystem.Colors.bgMain)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "f1f5f9")),
            alignment: .bottom
        )
    }

    // MARK: Avatar

    @ViewBuilder
    private var avatarView: some View {
        if let p = profile,
           let encrypted = p.profilePhotoData,
           let data = securityManager.decryptBlobFromStorage(encrypted),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Circle().fill(DesignSystem.Colors.primary.opacity(0.12))
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
        }
    }
}

// MARK: - Convenience init (no trailing actions)

extension AppPageHeader where Actions == EmptyView {
    init(
        title: String,
        searchText: Binding<String> = .constant(""),
        searchPlaceholder: String = "Search...",
        showSearch: Bool = true,
        onAvatarTap: (() -> Void)? = nil
    ) {
        self.title = title
        self._searchText = searchText
        self.searchPlaceholder = searchPlaceholder
        self.showSearch = showSearch
        self.onAvatarTap = onAvatarTap
        self.actions = { EmptyView() }
    }
}
