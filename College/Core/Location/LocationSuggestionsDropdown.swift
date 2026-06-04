// LocationSuggestionsDropdown.swift
// Feature: Core
// Purpose: Core module — LocationSuggestionsDropdown.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Inline location autocomplete menu (popover/sheet — no navigation sidebar).
struct LocationSuggestionsDropdown: View {
    let suggestions: [ResolvedLocation]
    var highlightedIndex: Int = 0
    var distanceText: ((ResolvedLocation) -> String?)? = nil
    var onSelect: (ResolvedLocation) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 36

    var body: some View {
        let maxHeight = min(220, rowHeight * CGFloat(max(suggestions.count, 1)))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: index == highlightedIndex ? "mappin.circle.fill" : "mappin.circle")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        locationLabel(for: item)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if let distance = distanceText?(item) {
                            Text(distance)
                                .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == highlightedIndex ? Color.primary.opacity(0.08) : .clear)
                    )
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider().padding(.leading, 38)
                }
            }
        }
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func locationLabel(for item: ResolvedLocation) -> some View {
        if item.hasEstablishmentName {
            HStack(spacing: 0) {
                Text(item.title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(" · ")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(item.subtitle)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(item.displayName)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

/// Compact banner shown while editing location when permissions can improve nearby results.
struct LocationPermissionInlineBanner: View {
    let status: LocationPermissionService.Status
    var onRequestPermission: () -> Void

    var body: some View {
        switch status {
        case .notDetermined:
            HStack(spacing: 8) {
                Image(systemName: "location")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Use your location for nearby places and addresses")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Allow", action: onRequestPermission)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
        case .denied, .restricted:
            HStack(spacing: 6) {
                Image(systemName: "location.slash")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Location off — results may be less accurate")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        case .authorized:
            EmptyView()
        }
    }
}
