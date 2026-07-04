// CareerApplicationsListView.swift
// Feature: Career
// Purpose: Career module — CareerApplicationsListView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct CareerApplicationsListView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    let applications: [JobApplication]
    @Binding var selectedJobID: UUID?
    var reduceMotion: Bool = false

    @State private var lastAppliedSortAscending = false

    private var sortedApplications: [JobApplication] {
        applications.sorted { lhs, rhs in
            let l = CareerApplicationPresentation.lastAppliedDate(for: lhs)
            let r = CareerApplicationPresentation.lastAppliedDate(for: rhs)
            if l != r {
                return lastAppliedSortAscending ? l < r : l > r
            }
            let lc = CareerApplicationPresentation.companyName(for: lhs)
            let rc = CareerApplicationPresentation.companyName(for: rhs)
            return lc.localizedCaseInsensitiveCompare(rc) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if applications.isEmpty {
                ContentUnavailableView {
                    Label("No applications yet", systemImage: "briefcase")
                } description: {
                    Text("Use the + button in the toolbar to add your first role.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listCard
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.35)

            applicationsTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var columnHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            headerLabel("COMPANY", width: CareerListTableTheme.columnCompany, alignment: .leading)
            headerLabel("JOB TITLE", width: CareerListTableTheme.columnJobTitle, alignment: .leading)
            headerLabel("STAGE", width: CareerListTableTheme.columnStage, alignment: .center)
            headerLabel("LOCATION", width: CareerListTableTheme.columnLocation, alignment: .leading)
            lastAppliedHeader
            headerLabel("LINK", width: CareerListTableTheme.columnLink, alignment: .trailing)
            Spacer(minLength: 0)
        }
    }

    private var lastAppliedHeader: some View {
        Button {
            lastAppliedSortAscending.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("LAST APPLIED")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .tracking(0.4)
                Image(systemName: lastAppliedSortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .frame(width: CareerListTableTheme.columnLastApplied, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Sort by last applied date")
    }

    private func headerLabel(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignSystem.Colors.textLight)
            .tracking(0.4)
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    private var applicationsTable: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(sortedApplications, id: \.id) { application in
                        listDataRow(application)
                    }
                }
                .frame(minWidth: Self.tableContentMinWidth, alignment: .leading)
                .padding(DesignSystem.Spacing.md)
            }
        }
    }

    /// Fixed column widths; horizontal scroll keeps the app sidebar in place when the inspector opens.
    private static var tableContentMinWidth: CGFloat {
        let columns =
            CareerListTableTheme.columnCompany
            + CareerListTableTheme.columnJobTitle
            + CareerListTableTheme.columnStage
            + CareerListTableTheme.columnLocation
            + CareerListTableTheme.columnLastApplied
            + CareerListTableTheme.columnLink
        let gaps: CGFloat = 16 * 6
        let rowPadding: CGFloat = 14 * 2
        return columns + gaps + rowPadding
    }

    private func listDataRow(_ application: JobApplication) -> some View {
        let isSelected = selectedJobID == application.id
        return HStack(alignment: .center, spacing: 16) {
            CompanyTableCell(application: application)
                .frame(width: CareerListTableTheme.columnCompany, alignment: .leading)

            JobTitleTableCell(application: application)
                .frame(width: CareerListTableTheme.columnJobTitle, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                CareerListStageBadge(status: CareerApplicationPresentation.status(for: application))
                Spacer(minLength: 0)
            }
            .frame(width: CareerListTableTheme.columnStage)

            LocationTableCell(application: application)
                .frame(width: CareerListTableTheme.columnLocation, alignment: .leading)

            Text(CareerApplicationPresentation.formattedLastApplied(for: application))
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: CareerListTableTheme.columnLastApplied, alignment: .leading)

            LinkTableCell(application: application)
                .frame(width: CareerListTableTheme.columnLink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.primary.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.1 : 0.75)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedJobID = application.id }
        .careerApplicationContextMenu(for: application, persistence: collegePersistence)
    }
}

// MARK: - Table cells

private struct CompanyTableCell: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    let application: JobApplication

    var body: some View {
        let company = CareerApplicationPresentation.companyName(for: application)
        let priority = collegePersistence.careerPriority(for: application)
        let brand = CareerApplicationPresentation.brandColor(for: application)

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(brand.opacity(0.16))
                Text(CareerApplicationPresentation.companyInitials(company))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(brand.opacity(0.92))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(company)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(CareerApplicationPresentation.priorityLabel(priority))
                    .font(.caption)
                    .foregroundStyle(CareerApplicationPresentation.prioritySubheadlineColor(priority))
                    .lineLimit(1)
            }
        }
    }
}

private struct JobTitleTableCell: View {
    let application: JobApplication

    var body: some View {
        let keywords = CareerApplicationPresentation.keywords(from: application, limit: 2)
        let overflow = CareerApplicationPresentation.keywordsOverflowCount(from: application, limit: 2)

        VStack(alignment: .leading, spacing: 6) {
            Text(CareerApplicationPresentation.roleTitle(for: application))
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !keywords.isEmpty || overflow > 0 {
                HStack(spacing: 6) {
                    ForEach(keywords, id: \.self) { word in
                        CareerListTechTagPill(text: word)
                    }
                    if overflow > 0 {
                        CareerListTechTagPill(text: "+\(overflow)")
                    }
                }
            }
        }
    }
}

private struct LocationTableCell: View {
    let application: JobApplication

    var body: some View {
        let location = CareerApplicationPresentation.locationLine(for: application)
        if location.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            Label(location, systemImage: "mappin")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct LinkTableCell: View {
    let application: JobApplication

    var body: some View {
        let urlString = (application.postingURLString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        HStack {
            Spacer(minLength: 0)
            if urlString.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else if let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "link")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Open posting")
            } else {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
