// WorkdayJobDetailPane.swift
// Feature: Career
// Purpose: Career module — WorkdayJobDetailPane.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

struct WorkdayJobDetailPane: View {
    @Environment(AppContainer.self) private var container
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
        let posting: WorkdayJobPosting

    let company: WorkdayCompanyConfigEntry
    var onClose: () -> Void
    var onInterested: (JobApplication) -> Void
    var onNavigateToBoard: () -> Void
    /// When true, omits the inspector-style header; `NavigationSplitView` owns the column chrome.
    var embeddedInNavigationSplit: Bool = false

    @State private var isLoadingDetail = false
    @State private var detailError: String?

    private var isTracked: Bool {
        collegePersistence.isPostingTracked(posting)
    }

    private var boardStatus: CareerApplicationStatus? {
        collegePersistence.boardStatus(for: posting)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock
                metadataBlock
                actionLinks
                detailContent
                actionButtons
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignSystem.Colors.surface)
        .navigationTitle(posting.title ?? "Job")
        .toolbarTitleDisplayMode(.inline)
        .task(id: posting.id) {
            await loadDetailIfNeeded(force: false)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(posting.title ?? "Untitled role")
                .font(.title3.bold())
            if let jid = posting.displayJobId, !jid.isEmpty {
                Text("Job ID: \(jid)")
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            if let boardStatus {
                HStack(spacing: 8) {
                    Text("On your board:")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textLight)
                    WorkdayBoardStatusPill(status: boardStatus)
                }
                .padding(.top, 4)
            }
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            let allLocations = WorkdayPostingParsing.filterLocations(
                locationText: posting.locationText,
                locationsFilterText: posting.locationsFilterText,
                externalPath: posting.externalPath
            )
            if allLocations.count > 1 {
                Label(posting.locationText ?? "\(allLocations.count) locations", systemImage: "mappin.and.ellipse")
                    .font(.caption)
                Text(allLocations.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let location = posting.locationText, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
            }
            if let posted = posting.postedOnText, !posted.isEmpty {
                Text(posted)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            if let jobType = posting.jobTypeText, !jobType.isEmpty {
                Label(jobType, systemImage: "briefcase")
                    .font(.caption)
            }
            if let timeType = posting.timeType, !timeType.isEmpty {
                Label(timeType, systemImage: "clock")
                    .font(.caption)
            }
            if let model = posting.workModel, !model.isEmpty {
                Label(model, systemImage: "building.2")
                    .font(.caption)
            }
            if let salary = salaryLabel {
                Label(salary, systemImage: "dollarsign.circle")
                    .font(.caption)
            }
            if let deadline = posting.deadlineAt,
               let badge = JobPostingEnrichment.deadlineBadgeText(for: deadline) {
                Text(badge.text)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badge.urgent ? Color.orange.opacity(0.2) : Color.yellow.opacity(0.15), in: Capsule())
                    .foregroundStyle(badge.urgent ? Color.orange : Color.primary)
            }
            if let modified = posting.lastModifiedAt,
               let first = posting.firstSeenAt,
               modified.timeIntervalSince(first) > 60 {
                Text("Updated \(modified.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
        }
        .foregroundStyle(DesignSystem.Colors.textLight)
    }

    private var salaryLabel: String? {
        if let text = posting.salaryText, !text.isEmpty { return text }
        if let min = posting.salaryMin, let max = posting.salaryMax, min > 0, max > 0 {
            return JobPostingEnrichment.formatSalaryRange(min: Int(min), max: Int(max))
        }
        return nil
    }

    @ViewBuilder
    private var actionLinks: some View {
        if let urlString = posting.applyURLString,
           let url = URL(string: urlString) {
            Link(destination: url) {
                Label("Apply on company site", systemImage: "safari")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if isLoadingDetail {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading full description…")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        } else if let detailError {
            Text(detailError)
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if let requirements = posting.requirementsText, !requirements.isEmpty {
            Text("Requirements")
                .font(.subheadline.weight(.semibold))
            JobDescriptionFormattedView(text: requirements)
                .textSelection(.enabled)
        }

        if let description = posting.jobDescriptionText, !description.isEmpty {
            Text("Description")
                .font(.subheadline.weight(.semibold))
            JobDescriptionFormattedView(text: description)
                .textSelection(.enabled)
        } else if !isLoadingDetail, detailError == nil,
                  !collegePersistence.shouldFetchWorkdayDetail(for: posting, force: false) {
            Text("No description cached.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if isTracked, let app = posting.trackedApplication {
                Button("View on board") {
                    onInterested(app)
                    onNavigateToBoard()
                }
                .buttonStyle(.borderedProminent)
            } else if !isTracked {
                Button("Add to Board") {
                    let app = collegePersistence.promoteWorkdayPostingToTracker(posting)
                    notifications.post(
                        kind: .success,
                        title: "Added to board",
                        message: app.title ?? "Role"
                    )
                    onInterested(app)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                Task { await loadDetailIfNeeded(force: true) }
            } label: {
                Label("Refresh details", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingDetail)
        }
    }

    private func loadDetailIfNeeded(force: Bool) async {
        guard collegePersistence.shouldFetchWorkdayDetail(for: posting, force: force) else { return }

        isLoadingDetail = true
        detailError = nil
        defer { isLoadingDetail = false }

        do {
            let scraper = JobBoardScraperRegistry.scraper(for: company.platform)
            let request = JobDetailScrapeRequest(
                externalId: posting.externalId,
                externalPath: posting.externalPath,
                fallbackTitle: posting.title,
                applyURLString: posting.applyURLString,
                cachedDescription: posting.jobDescriptionText
            )
            let detail = try await scraper.scrapeDetail(request: request, company: company)
            collegePersistence.applyJobBoardDetail(posting: posting, detail: detail)
        } catch let err as JobBoardScraperError {
            detailError = err.displayMessage
        } catch let err as WorkdayScraperError {
            detailError = err.displayMessage
        } catch {
            detailError = error.localizedDescription
        }
    }
}
