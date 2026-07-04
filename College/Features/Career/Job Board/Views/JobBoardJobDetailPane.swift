// JobBoardJobDetailPane.swift
// Feature: Career
// Purpose: Career module — JobBoardJobDetailPane.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

struct JobBoardJobDetailPane: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
        let posting: JobBoardPosting

    let company: JobBoardCompany
    var onClose: () -> Void
    var onInterested: (JobApplication) -> Void
    var onNavigateToApplicationTracker: () -> Void
    /// When true, omits the inspector-style header; `NavigationSplitView` owns the column chrome.
    var embeddedInNavigationSplit: Bool = false

    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var matchController = JobBoardResumeMatchController(collegePersistence: CollegePersistence.shared)
    @State private var gapParagraph: String?
    @State private var showTailoringSheet = false
    @State private var tailoringSession: CareerResumeEditSession?
    @State private var inspectorTab: JobBoardDetailInspectorTab = .job
    @State private var showResumeAttachmentSheet = false
    @State private var pendingApplyURL: URL?

    private var isTracked: Bool {
        collegePersistence.isPostingTracked(posting)
    }

    private var boardStatus: CareerApplicationStatus? {
        collegePersistence.boardStatus(for: posting)
    }

    var body: some View {
        Group {
            if embeddedInNavigationSplit {
                detailScrollContent
            } else {
                detailScrollContent
                    .navigationTitle(posting.title ?? "Job")
                    .toolbarTitleDisplayMode(.inline)
            }
        }
    }

    private var detailScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock
                metadataBlock
                timingAdvisory
                actionLinks
                Picker("Inspector", selection: $inspectorTab) {
                    ForEach(JobBoardDetailInspectorTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch inspectorTab {
                case .match:
                    resumeMatchPanel
                case .job:
                    detailContent
                    actionButtons
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignSystem.Colors.surface)
        .task(id: posting.id) {
            matchController.cancelScoring()
            gapParagraph = nil
            inspectorTab = .job
            matchController.reset(for: posting)
            await loadDetailIfNeeded(force: false)
        }
        .onChange(of: inspectorTab) { _, tab in
            guard tab == .match else { return }
            matchController.ensureMatchScoresIfNeeded(for: posting, company: company)
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            matchController.reloadResumeContext()
        }
        .onDisappear {
            matchController.cancelScoring()
        }
        .sheet(isPresented: $showTailoringSheet) {
            if let tailoringSession {
                ResumeTailoringSheet(session: tailoringSession)
                    .interactiveDismissDisabled(tailoringSession.isGenerating)
            }
        }
        .sheet(isPresented: $showResumeAttachmentSheet) {
            if let applyURL = pendingApplyURL {
                ResumeAttachmentSheet(
                    rows: matchController.attachmentRows,
                    jobTitle: posting.title ?? "Role",
                    companyName: company.displayName
                ) { row in
                    launchApplyInCollege(applyURL: applyURL, resumeRow: row)
                }
            }
        }
    }

    @ViewBuilder
    private var resumeMatchPanel: some View {
        JobBoardResumeMatchPanel(
            rows: matchController.matchRows,
            matchState: matchController.detailMatchState(for: posting),
            isLoading: matchController.isScoringResumes,
            usedPartialFallback: matchController.usedPartialFallback,
            platform: company.platform,
            jobTitle: posting.title ?? "",
            companyName: company.displayName,
            jobDescriptionText: posting.jobDescriptionText ?? "",
            isPostingTracked: isTracked,
            gapParagraph: $gapParagraph,
            onAddToBoard: { resumeID in
                let app = collegePersistence.promoteJobBoardPostingToTracker(posting, recommendedResumeID: resumeID)
                notifications.post(kind: .success, title: "Added to board", message: app.title ?? "Role")
                onInterested(app)
            },
            onDraftGapParagraph: { row in
                Task {
                    let paragraph = await CareerAIService.shared.draftGapParagraph(
                        resumeDocumentID: row.resumeDocumentID,
                        jobDescriptionText: posting.jobDescriptionText ?? "",
                        missingKeywords: row.missingKeywords,
                        using: collegePersistence
                    )
                    await MainActor.run { gapParagraph = paragraph }
                }
            },
            onExportATSSafePDF: { resumeID in
                Task {
                    do {
                        if let exported = try await CareerResumePDFExporter.exportATSSafePDF(
                            sourceDocumentID: resumeID,
                            collegePersistence: collegePersistence
                        ) {
                            notifications.post(
                                kind: .success,
                                title: "ATS-safe PDF ready",
                                message: exported.customDisplayName ?? exported.fileName
                            )
                        }
                    } catch {
                        notifications.post(
                            kind: .error,
                            title: "Export failed",
                            message: error.localizedDescription
                        )
                    }
                }
            },
            onTailorResume: { row in
                openTailoring(for: row)
            }
        )
    }

    private func openTailoring(for row: CareerResumeMatchRow) {
        Task {
            guard let document = try? collegePersistence.vaultRepository.fetchDocument(id: row.resumeDocumentID),
                  let profile = collegePersistence.careerResumeMetadata(for: document).structuredProfile
            else {
                _ = await MainActor.run {
                    notifications.post(
                        kind: .error,
                        title: "Can't tailor yet",
                        message: "Re-analyze this resume so structured sections are available."
                    )
                }
                return
            }

            let jd = [posting.jobDescriptionText ?? "", posting.requirementsText ?? ""]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            let skillsGap = SkillsGapTaxonomy(
                entries: row.skillsGapTaxonomy ?? [],
                transferableScore: row.transferableScore
            )

            let session = CareerResumeEditSession(
                sourceDocumentID: row.resumeDocumentID,
                jobTitle: posting.title ?? "",
                companyName: company.displayName,
                platform: company.platform,
                baseProfile: profile,
                liveMatchScoreBefore: row.overallScore
            )
            session.isGenerating = true
            await MainActor.run {
                tailoringSession = session
                showTailoringSheet = true
            }

            let suggestions = await CareerResumeSuggestionService.shared.generateSuggestions(
                profile: profile,
                jobDescription: jd,
                jobTitle: posting.title ?? "",
                skillsGap: skillsGap,
                platform: company.platform
            )
            await MainActor.run {
                session.suggestions = suggestions
                session.isGenerating = false
            }
        }
    }

    @ViewBuilder
    private var timingAdvisory: some View {
        if let postedAt = posting.postedAt {
            let days = Calendar.current.dateComponents([.day], from: postedAt, to: Date()).day ?? 0
            if days <= 7 {
                let urgency = days <= 2 ? "early applications get more attention on Workday" : "consider applying soon"
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.orange)
                    Text("Posted \(days == 0 ? "today" : "\(days) day\(days == 1 ? "" : "s") ago") — \(urgency)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TranslatableText(text: posting.title ?? "Untitled role")
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
                    JobBoardStatusPill(status: boardStatus)
                }
                .padding(.top, 4)
            }
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            let allLocations = JobBoardPostingParsing.filterLocations(
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
            HStack(spacing: 12) {
                Button("Apply in College") {
                    applyInCollege(applyURL: url)
                }
                .buttonStyle(.borderedProminent)
                Link(destination: url) {
                    Label("Apply on company site", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func applyInCollege(applyURL: URL) {
        guard matchController.resolvedResumeForApply() != nil else {
            notifications.post(
                kind: .warning,
                title: "Add a resume first",
                message: "Upload and parse a resume in Career → Resumes to use Apply in College autofill."
            )
            return
        }

        pendingApplyURL = applyURL
        showResumeAttachmentSheet = true
    }

    private func launchApplyInCollege(applyURL: URL, resumeRow: CareerResumeMatchRow) {
        let opened = CareerApplyLauncher.openApplyInCollege(
            postingURL: applyURL,
            platform: JobBoardPlatform(rawValue: posting.platform ?? company.platform.rawValue) ?? company.platform,
            resumeDocumentID: resumeRow.resumeDocumentID,
            resumeFileName: resumeRow.displayName,
            companyName: company.displayName,
            jobTitle: posting.title ?? "Role",
            jobApplicationID: applicationIDForApply(recommendedResumeID: resumeRow.resumeDocumentID),
            openWindow: openWindow,
            collegePersistence: collegePersistence,
            notifications: notifications
        )
        if !opened { return }
        pendingApplyURL = nil
    }

    private func applicationIDForApply(recommendedResumeID: UUID?) -> UUID? {
        if let id = posting.trackedApplication?.id { return id }
        return collegePersistence.promoteJobBoardPostingToTracker(
            posting,
            recommendedResumeID: recommendedResumeID
        ).id
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
            if let recommended = matchController.recommendedRow {
                JobDescriptionHighlightedView(
                    text: requirements,
                    matchingSkills: recommended.matchingSkills,
                    missingKeywords: recommended.missingKeywords
                )
                .textSelection(.enabled)
            } else {
                JobDescriptionFormattedView(text: requirements)
                    .textSelection(.enabled)
            }
        }

        if let description = posting.jobDescriptionText, !description.isEmpty {
            Text("Description")
                .font(.subheadline.weight(.semibold))
            if let recommended = matchController.recommendedRow {
                JobDescriptionHighlightedView(
                    text: description,
                    matchingSkills: recommended.matchingSkills,
                    missingKeywords: recommended.missingKeywords
                )
                .textSelection(.enabled)
            } else {
                JobDescriptionFormattedView(text: description)
                    .textSelection(.enabled)
            }
        } else if !isLoadingDetail, detailError == nil,
                  !collegePersistence.shouldFetchJobBoardDetail(for: posting, force: false) {
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
                    onNavigateToApplicationTracker()
                }
                .buttonStyle(.borderedProminent)
            } else if !isTracked, matchController.matchRows.isEmpty {
                Button("Add to Board") {
                    let recommendedID = matchController.recommendedRow?.resumeDocumentID
                    let app = collegePersistence.promoteJobBoardPostingToTracker(
                        posting,
                        recommendedResumeID: recommendedID
                    )
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
        guard collegePersistence.shouldFetchJobBoardDetail(for: posting, force: force) else { return }

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
            matchController.reloadCachedMatchRows(for: posting)
            if inspectorTab == .match {
                matchController.ensureMatchScoresIfNeeded(for: posting, company: company)
            }
        } catch let err as JobBoardScraperError {
            detailError = err.displayMessage
        } catch let err as WorkdayScraperError {
            detailError = err.displayMessage
        } catch {
            detailError = error.localizedDescription
        }
    }

}
