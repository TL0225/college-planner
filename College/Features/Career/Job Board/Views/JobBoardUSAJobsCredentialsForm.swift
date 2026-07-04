// JobBoardUSAJobsCredentialsForm.swift
// Feature: Career / Job Board
// Purpose: Shared USAJobs API credential fields for Settings and the company picker.

import SwiftUI

struct JobBoardUSAJobsCredentialsForm: View {
    enum Style {
        case inline
        case settings
    }

    var style: Style = .inline
    var onCredentialsChange: (() -> Void)?

    @State private var apiKey = JobBoardUSAJobsCredentials.apiKey ?? ""
    @State private var userEmail = JobBoardUSAJobsCredentials.userEmail ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if style == .inline {
                Text("USAJobs requires a free API key from developer.usajobs.gov.")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            } else {
                SettingsInfoRow(
                    text: String(
                        localized: "settings.jobboards.usajobs.help",
                        defaultValue: "Request a free API key at developer.usajobs.gov. College uses the official Search API — not HTML scraping."
                    )
                )
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API authorization email")
                    .font(.subheadline.weight(.medium))
                TextField("you@example.com", text: $userEmail)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: userEmail) { _, newValue in
                        JobBoardUSAJobsCredentials.userEmail = newValue
                        onCredentialsChange?()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API key")
                    .font(.subheadline.weight(.medium))
                SecureField("Authorization-Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, newValue in
                        JobBoardUSAJobsCredentials.apiKey = newValue
                        onCredentialsChange?()
                    }
            }

            if JobBoardUSAJobsCredentials.isConfigured {
                Label("Credentials saved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .onAppear {
            apiKey = JobBoardUSAJobsCredentials.apiKey ?? ""
            userEmail = JobBoardUSAJobsCredentials.userEmail ?? ""
        }
    }
}

struct JobBoardUSAJobsSetupSheet: View {
    let entry: JobBoardCompanyCatalogEntry
    var onTrack: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect USAJobs")
                        .font(.title2.weight(.bold))
                    Text(entry.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            JobBoardUSAJobsCredentialsForm(style: .inline)

            Button {
                onTrack()
                dismiss()
            } label: {
                Text("Save & track USAJobs")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!JobBoardUSAJobsCredentials.isConfigured)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360)
    }
}
