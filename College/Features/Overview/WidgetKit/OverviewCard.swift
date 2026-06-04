// OverviewCard.swift
// Feature: Overview
// Purpose: Overview module — OverviewCard.
// Data: CollegePersistence / repositories when applicable.

//
//  OverviewCard.swift
//  College
//
//  Shared scrollable card shell used by every widget that doesn't
//  need a fully custom background (all except Weather and Music).
//

import SwiftUI

/// A scrollable card shell with the standard surface background,
/// rounded corners, shadow and 1-pt border used by Overview widgets.
///
/// Usage:
/// ```swift
/// OverviewCard {
///     Text("Card title").font(...)
///     // content…
/// }
/// ```
struct OverviewCard<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(hex: "F3F4F6"), lineWidth: 1)
        )
    }
}
