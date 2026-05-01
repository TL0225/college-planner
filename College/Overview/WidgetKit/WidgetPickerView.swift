//
//  WidgetPickerView.swift
//  College
//
//  iOS-style sheet that lets users browse all registered widgets,
//  preview them with mock data, and instantly add or remove them
//  from the Overview grid.
//

import SwiftUI

// MARK: - WidgetPickerView

struct WidgetPickerView: View {

    @EnvironmentObject private var registry:     WidgetRegistry
    @EnvironmentObject private var widgetConfig: WidgetConfigurationStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText:       String          = ""
    @State private var selectedCategory: WidgetCategory? = nil

    private var filteredDescriptors: [WidgetDescriptor] {
        registry.allDescriptors.filter { desc in
            let matchesSearch = searchText.isEmpty
                || desc.displayName.localizedCaseInsensitiveContains(searchText)
                || desc.description.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || desc.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Widget")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Text("\(registry.allDescriptors.count) widgets available")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: "9CA3AF"), Color(hex: "F3F4F6"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // ── Search ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.Colors.textLight)
                TextField("Search widgets…", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(hex: "F3F4F6"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // ── Category pills ──────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryPill(label: "All", category: nil)
                    ForEach(WidgetCategory.allCases) { cat in
                        categoryPill(label: cat.rawValue, category: cat)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            }

            Divider().padding(.top, 8)

            // ── Grid ────────────────────────────────────────────────
            if filteredDescriptors.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    Text("No widgets match \"\(searchText)\"")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredDescriptors) { desc in
                            WidgetPickerCard(
                                descriptor: desc,
                                isAdded: widgetConfig.enabledIDs.contains(desc.id)
                            ) {
                                if widgetConfig.enabledIDs.contains(desc.id) {
                                    widgetConfig.removeWidget(id: desc.id)
                                } else {
                                    widgetConfig.addWidget(id: desc.id)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }

            // ── Footer ──────────────────────────────────────────────
            Divider()
            HStack {
                Button(action: { widgetConfig.resetToDefaults() }) {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "6366F1"))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(widgetConfig.enabledIDs.count) active")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 600, minHeight: 520)
        .background(DesignSystem.Colors.bgMain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func categoryPill(label: String, category: WidgetCategory?) -> some View {
        let isSelected = selectedCategory == category
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        }) {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.iconName)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : DesignSystem.Colors.textMain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color(hex: "6366F1") : Color(hex: "F3F4F6"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WidgetPickerCard

struct WidgetPickerCard: View {

    let descriptor: WidgetDescriptor
    let isAdded:    Bool
    let onToggle:   () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Preview area ────────────────────────────────────────
            ZStack {
                // Accent gradient header background
                LinearGradient(
                    colors: [descriptor.accentColor.opacity(0.85), descriptor.accentColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Static mock preview clipped and non-interactive
                AnyView(descriptor.makePreview())
                    .allowsHitTesting(false)
                    .scaleEffect(0.72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                // "Added" checkmark overlay
                if isAdded {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, descriptor.accentColor)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // ── Info + CTA ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: descriptor.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(descriptor.accentColor)
                    Text(descriptor.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                }

                Text(descriptor.description)
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Color.clear.frame(height: 6)

                Button(action: onToggle) {
                    HStack(spacing: 5) {
                        Image(systemName: isAdded ? "minus.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 12))
                        Text(isAdded ? "Remove" : "Add Widget")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(isAdded ? Color(hex: "EF4444") : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(isAdded ? Color(hex: "FEF2F2") : descriptor.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.05), radius: isHovered ? 16 : 8, x: 0, y: isHovered ? 8 : 3)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isAdded)
        .onHover { isHovered = $0 }
    }
}
