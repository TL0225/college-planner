// JobBoardToolbarFilters.swift
// Feature: Career
// Purpose: Career module — JobBoardFilterMenuLabel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - Auto-width menu label (no trailing truncation)

struct JobBoardFilterMenuLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(DesignSystem.Colors.textLight)
            Text(value)
                .foregroundStyle(DesignSystem.Colors.textMain)
            Image(systemName: "chevron.down")
                .font(ToolbarMetrics.iconFont)
                .foregroundStyle(DesignSystem.Colors.textLight)
        }
        .font(ToolbarMetrics.labelFont)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Searchable location filter

struct JobBoardLocationFilterMenu: View {
    @Binding var selectionKey: String?
    let options: [JobBoardPostingParsing.LocationFilterOption]

    @State private var searchText = ""

    private var filteredOptions: [JobBoardPostingParsing.LocationFilterOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { $0.displayLabel.localizedCaseInsensitiveContains(query) }
    }

    private var selectedLabel: String {
        guard let selectionKey,
              let match = options.first(where: { $0.id == selectionKey })
        else { return "All locations" }
        return match.displayLabel
    }

    var body: some View {
        Menu {
            Button("All locations") { selectionKey = nil }

            Divider()

            TextField("Search locations", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredOptions.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredOptions) { option in
                    Button {
                        selectionKey = option.id
                    } label: {
                        HStack {
                            Text(option.displayLabel)
                            Spacer()
                            Text("\(option.jobCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            JobBoardFilterMenuLabel(title: "Location", value: selectedLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Posted / sort menus (full label width)

struct JobBoardPostedFilterMenu: View {
    @Binding var selection: JobBoardDaysPostedFilter

    var body: some View {
        Menu {
            ForEach(JobBoardDaysPostedFilter.allCases) { bucket in
                Button(bucket.displayName) { selection = bucket }
            }
        } label: {
            JobBoardFilterMenuLabel(title: "Posted", value: selection.displayName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct JobBoardSortFilterMenu: View {
    @Binding var selection: JobBoardJobListSort

    var body: some View {
        Menu {
            ForEach(JobBoardJobListSort.allCases) { sort in
                Button(sort.displayName) { selection = sort }
            }
        } label: {
            JobBoardFilterMenuLabel(title: "Sort", value: selection.displayName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct JobBoardJobTypeFilterMenu: View {
    @Binding var selectionKey: String?
    let options: [JobBoardPostingParsing.JobTypeFilterOption]

    @State private var searchText = ""

    private var filteredOptions: [JobBoardPostingParsing.JobTypeFilterOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { $0.displayLabel.localizedCaseInsensitiveContains(query) }
    }

    private var selectedLabel: String {
        guard let selectionKey,
              let match = options.first(where: { $0.id == selectionKey })
        else { return "All job types" }
        return match.displayLabel
    }

    var body: some View {
        Menu {
            Button("All job types") { selectionKey = nil }
            Divider()
            TextField("Search job types", text: $searchText)
                .textFieldStyle(.roundedBorder)
            if filteredOptions.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            } else {
                ForEach(filteredOptions) { option in
                    Button {
                        selectionKey = option.id
                    } label: {
                        HStack {
                            Text(option.displayLabel)
                            Spacer()
                            Text("\(option.jobCount)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            JobBoardFilterMenuLabel(title: "Job type", value: selectedLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct JobBoardTimeTypeFilterMenu: View {
    @Binding var selectionKey: String?
    let options: [JobBoardPostingParsing.TimeTypeFilterOption]

    private var selectedLabel: String {
        guard let selectionKey,
              let match = options.first(where: { $0.id == selectionKey })
        else { return "All schedules" }
        return match.displayLabel
    }

    var body: some View {
        Menu {
            Button("All schedules") { selectionKey = nil }
            ForEach(options) { option in
                Button {
                    selectionKey = option.id
                } label: {
                    HStack {
                        Text(option.displayLabel)
                        Spacer()
                        Text("\(option.jobCount)").foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            JobBoardFilterMenuLabel(title: "Schedule", value: selectedLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Secondary filters (job type, toggles) in one menu to keep the toolbar compact

struct JobBoardExtraFiltersMenu: View {
    @Binding var jobTypeFilterKey: String?
    @Binding var timeTypeFilterKey: String?
    @Binding var daysPostedFilter: JobBoardDaysPostedFilter
    @Binding var hideOnBoard: Bool
    @Binding var closingSoonOnly: Bool
    @Binding var showClosed: Bool

    let jobTypeFilterOptions: [JobBoardPostingParsing.JobTypeFilterOption]
    let timeTypeFilterOptions: [JobBoardPostingParsing.TimeTypeFilterOption]

    private var activeFilterCount: Int {
        var count = 0
        if jobTypeFilterKey != nil { count += 1 }
        if timeTypeFilterKey != nil { count += 1 }
        if daysPostedFilter != .all { count += 1 }
        if hideOnBoard { count += 1 }
        if closingSoonOnly { count += 1 }
        if showClosed { count += 1 }
        return count
    }

    var body: some View {
        Menu {
            Menu("Posted") {
                ForEach(JobBoardDaysPostedFilter.allCases) { bucket in
                    Button {
                        daysPostedFilter = bucket
                    } label: {
                        if daysPostedFilter == bucket {
                            Label(bucket.displayName, systemImage: "checkmark")
                        } else {
                            Text(bucket.displayName)
                        }
                    }
                }
            }

            if !jobTypeFilterOptions.isEmpty {
                Menu("Job type") {
                    Button("All job types") { jobTypeFilterKey = nil }
                    ForEach(jobTypeFilterOptions) { option in
                        Button {
                            jobTypeFilterKey = option.id
                        } label: {
                            HStack {
                                Text(option.displayLabel)
                                Spacer()
                                Text("\(option.jobCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if timeTypeFilterOptions.count > 1 {
                Menu("Schedule") {
                    Button("All schedules") { timeTypeFilterKey = nil }
                    ForEach(timeTypeFilterOptions) { option in
                        Button {
                            timeTypeFilterKey = option.id
                        } label: {
                            HStack {
                                Text(option.displayLabel)
                                Spacer()
                                Text("\(option.jobCount)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            Toggle("Hide on board", isOn: $hideOnBoard)
            Toggle("Closing soon", isOn: $closingSoonOnly)
            Toggle("Show closed", isOn: $showClosed)

            if activeFilterCount > 0 {
                Divider()
                Button("Reset filters") {
                    jobTypeFilterKey = nil
                    timeTypeFilterKey = nil
                    daysPostedFilter = .all
                    hideOnBoard = false
                    closingSoonOnly = false
                    showClosed = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(activeFilterCount > 0 ? "Filters (\(activeFilterCount))" : "Filters")
            }
            .font(ToolbarMetrics.font(activeFilterCount > 0 ? .semibold : .regular))
            .foregroundStyle(activeFilterCount > 0 ? DesignSystem.Colors.primary : DesignSystem.Colors.textMain)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}
