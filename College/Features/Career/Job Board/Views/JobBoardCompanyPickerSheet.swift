// JobBoardCompanyPickerSheet.swift
// Feature: Career / Job Board
// Purpose: Plaid-style company picker for tracking job board openings.

import SwiftUI

struct JobBoardCompanyPickerSheet: View {
    var onSelect: (JobBoardCompany) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logoStore = JobBoardCompanyLogoStore.shared

    @State private var searchText = ""
    @State private var manualURL = ""
    @State private var manualDisplayName = ""
    @State private var selectedPlatform: JobBoardPlatform = .workday
    @State private var urlValidationMessage: String?
    @State private var urlValidationOK = false
    @State private var isProbingPlatform = false
    @State private var isAdding = false
    @State private var platformProbeTask: Task<Void, Never>?
    @State private var usajobsSetupEntry: JobBoardCompanyCatalogEntry?
    @State private var credentialsRefreshToken = 0
    @FocusState private var isSearchFocused: Bool

    private var companiesStore: JobBoardCompaniesStore { JobBoardCompaniesStore.shared }

    private var trackedSlugs: Set<String> {
        Set(companiesStore.companies.map(\.normalizedSlug))
    }

    private var filteredEntries: [JobBoardCompanyCatalogEntry] {
        JobBoardCompanyCatalog.search(searchText, excludingTracked: trackedSlugs)
    }

    private var showManualSection: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !JobBoardCompanyCatalog.looksLikeURL(searchText) {
                        companyGrid
                    }
                    if showManualSection {
                        manualEntrySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 620)
        .background(DesignSystem.Colors.surface)
        .onAppear {
            isSearchFocused = true
            for entry in JobBoardCompanyCatalog.entries.prefix(12) {
                logoStore.loadLogoIfNeeded(for: entry.asCompany())
            }
        }
        .onChange(of: searchText) { _, newValue in
            if JobBoardCompanyCatalog.looksLikeURL(newValue), manualURL.isEmpty {
                manualURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                validateManualURL()
            }
        }
        .onDisappear {
            platformProbeTask?.cancel()
        }
        .sheet(item: $usajobsSetupEntry) { entry in
            JobBoardUSAJobsSetupSheet(entry: entry) {
                addCompany(
                    displayName: entry.displayName,
                    careersURL: entry.careersURL,
                    platform: entry.platform
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Select your company")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignSystem.Colors.textMain)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)
            TextField("Search companies or paste a careers URL", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var companyGrid: some View {
        if filteredEntries.isEmpty {
            VStack(spacing: 8) {
                Text("No matching companies")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                Text("Paste a careers page URL below to track any employer.")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(filteredEntries) { entry in
                    companyCard(entry)
                }
            }
        }
    }

    private func companyCard(_ entry: JobBoardCompanyCatalogEntry) -> some View {
        let company = entry.asCompany()
        let isTracked = trackedSlugs.contains(entry.id)

        return Button {
            guard !isAdding else { return }
            if isTracked, let existing = companiesStore.companies.first(where: { $0.normalizedSlug == entry.id }) {
                onSelect(existing)
                dismiss()
                return
            }
            if entry.platform == .usajobs {
                usajobsSetupEntry = entry
                return
            }
            addCompany(
                displayName: entry.displayName,
                careersURL: entry.careersURL,
                platform: entry.platform
            )
        } label: {
            VStack(spacing: 10) {
                companyLogo(for: company)
                Text(entry.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if isTracked {
                    Label("Tracking", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.success)
                } else {
                    JobBoardPlatformBadge(platform: entry.platform)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignSystem.Colors.bgMain)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
        .onAppear {
            logoStore.loadLogoIfNeeded(for: company)
        }
    }

    @ViewBuilder
    private func companyLogo(for company: JobBoardCompany) -> some View {
        Group {
            if let image = logoStore.image(for: company) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: company.platform.icon)
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        }
        .frame(width: 36, height: 36)
    }

    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or link a careers page")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Text("Works with Workday, Greenhouse, Lever, Oracle, iCIMS, Talemetry, public boards, and government sources (USAJobs, NYC, NY State).")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)

            TextField("Company name (optional)", text: $manualDisplayName)
                .textFieldStyle(.roundedBorder)

            TextField("https://… careers page URL", text: $manualURL)
                .textFieldStyle(.roundedBorder)
                .onChange(of: manualURL) { _, _ in validateManualURL() }

            if let msg = urlValidationMessage {
                HStack(spacing: 6) {
                    Image(systemName: urlValidationOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(urlValidationOK ? Color.green : Color.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(urlValidationOK ? Color.secondary : Color.orange)
                    Spacer(minLength: 0)
                    if isProbingPlatform {
                        ProgressView().controlSize(.small)
                    } else {
                        JobBoardPlatformBadge(platform: selectedPlatform)
                    }
                }
            }

            if selectedPlatform == .usajobs {
                JobBoardUSAJobsCredentialsForm(style: .inline) {
                    credentialsRefreshToken += 1
                    validateManualURL()
                }
                .id(credentialsRefreshToken)
            }

            Button {
                let name = manualDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName = URL(string: manualURL.trimmingCharacters(in: .whitespacesAndNewlines))?
                    .host?
                    .replacingOccurrences(of: "www.", with: "") ?? "Company"
                addCompany(
                    displayName: name.isEmpty ? fallbackName : name,
                    careersURL: manualURL,
                    platform: selectedPlatform
                )
            } label: {
                HStack {
                    if isAdding {
                        ProgressView().controlSize(.small)
                    }
                    Text(isAdding ? "Adding…" : "Track this company")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !urlValidationOK
                    || isAdding
                    || (selectedPlatform == .usajobs && !JobBoardUSAJobsCredentials.isConfigured)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func addCompany(displayName: String, careersURL: String, platform: JobBoardPlatform) {
        isAdding = true
        defer { isAdding = false }

        guard let result = JobBoardCompanyConfigurator.configureIfNeeded(
            displayName: displayName,
            careersURL: careersURL,
            platform: platform
        ) else { return }

        JobBoardSyncCoordinator.shared.rebuildIdleUIState()
        logoStore.loadLogoIfNeeded(for: result.company)
        onSelect(result.company)
        dismiss()
    }

    private func validateManualURL() {
        let url = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            urlValidationMessage = nil
            urlValidationOK = false
            return
        }
        if let detected = JobBoardPlatformDetector.detect(from: url) {
            selectedPlatform = detected
        }
        let result = JobBoardPlatformDetector.validationMessage(for: url, platform: selectedPlatform)
        urlValidationMessage = result.message
        urlValidationOK = result.ok
        if selectedPlatform == .usajobs {
            urlValidationOK = result.ok && JobBoardUSAJobsCredentials.isConfigured
        }

        if JobBoardPlatformDetector.detect(from: url) == nil {
            platformProbeTask?.cancel()
            isProbingPlatform = true
            platformProbeTask = Task {
                if let probed = await JobBoardPlatformDetector.probe(urlString: url) {
                    guard !Task.isCancelled else { return }
                    selectedPlatform = probed
                    let r = JobBoardPlatformDetector.validationMessage(for: url, platform: probed)
                    urlValidationMessage = r.message
                    urlValidationOK = r.ok
                    if probed == .usajobs {
                        urlValidationOK = r.ok && JobBoardUSAJobsCredentials.isConfigured
                    }
                }
                guard !Task.isCancelled else { return }
                isProbingPlatform = false
            }
        } else {
            platformProbeTask?.cancel()
            platformProbeTask = nil
            isProbingPlatform = false
        }
    }
}
