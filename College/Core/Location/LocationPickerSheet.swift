// LocationPickerSheet.swift
// Feature: Core
// Purpose: Core module — LocationPickerSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import MapKit

struct LocationPickerSheet: View {
    @Environment(AppContainer.self) private var container
    private var locationPermissionService: LocationPermissionService { container.locationPermissionService }
    var onDismiss: (() -> Void)?

    @ObservedObject var searchService: MapLocationSearchService
    let onSelect: (ResolvedLocation) -> Void

    @State private var showRecents: Bool = true
    @FocusState private var isSearchFocused: Bool
    @State private var rankedSuggestions: [ResolvedLocation] = []
    @State private var suggestionTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.04)))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Back")

                Text("Location")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                
                Spacer()
            }
            .padding(12)

            Divider().background(Color.black.opacity(0.08))

            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                TextField("Search for a location", text: $searchService.query)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.06))
            .cornerRadius(10)
            .padding(12)
            .onChange(of: searchService.query) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                showRecents = trimmed.isEmpty
                if trimmed.isEmpty {
                    rankedSuggestions = []
                } else {
                    refreshRankedSuggestions()
                }
            }

            // Content
            ScrollView {
                if showRecents {
                    recentsList
                } else {
                    suggestionsList
                }
            }
        }
        .background(Color.white)
        .onAppear {
            isSearchFocused = true
            searchService.applyLocationBias(from: locationPermissionService.lastLocation)
            if locationPermissionService.status == .authorized {
                locationPermissionService.requestOneShotLocation()
            }
        }
        .onChange(of: locationPermissionService.lastLocation) { _, newLocation in
            searchService.applyLocationBias(from: newLocation)
            if !showRecents {
                refreshRankedSuggestions()
            }
        }
        .onDisappear {
            suggestionTask?.cancel()
            suggestionTask = nil
        }
    }

    private var recentsList: some View {
        let recents = LocationRecentsStore.load()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Recents")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.horizontal, 12)
                .padding(.top, 4)

            if recents.isEmpty {
                Text("No recent locations")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(recents) { item in
                        Button {
                            onSelect(item)
                            onDismiss?()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Divider().padding(.leading, 44).opacity(0.5)
                    }
                }
            }
        }
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.horizontal, 12)
                .padding(.top, 4)

            VStack(spacing: 0) {
                if !rankedSuggestions.isEmpty {
                    ForEach(Array(rankedSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            LocationRecentsStore.add(suggestion)
                            onSelect(suggestion)
                            onDismiss?()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(suggestion.title)
                                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                            .foregroundColor(DesignSystem.Colors.textMain)
                                        if index == 0 && locationPermissionService.lastLocation != nil {
                                            Text("Nearest")
                                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                                .foregroundColor(DesignSystem.Colors.primary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(DesignSystem.Colors.primary.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 44).opacity(0.5)
                    }
                } else {
                    ForEach(searchService.completions, id: \.self) { completion in
                        Button {
                            Task { @MainActor in
                                if let resolved = await searchService.resolve(completion) {
                                    LocationRecentsStore.add(resolved)
                                    onSelect(resolved)
                                    onDismiss?()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 44).opacity(0.5)
                    }
                }
            }

            if searchService.completions.isEmpty && rankedSuggestions.isEmpty {
                Text(searchService.isSearching ? "Searching…" : "No results")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
        }
    }

    private func refreshRankedSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            let nearby = locationPermissionService.lastLocation
            let results = await searchService.resolveTopCompletions(limit: 6, near: nearby)
            if !Task.isCancelled {
                rankedSuggestions = results
            }
        }
    }
}
