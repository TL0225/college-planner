// ProfileEditSheet.swift
// Feature: Profile
// Purpose: Profile module — ProfileEditSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Profile Edit Sheet

struct ProfileEditSheet: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) private var dismiss
    private var collegePersistence: CollegePersistence { container.persistence }
        let profile: Profile

    @State private var name = ""
    @State private var pronouns = ""
    @State private var universityEmail = ""
    @State private var personalPhone = ""
    @State private var permanentAddress = ""
    @State private var advisorName = ""
    @State private var studentId = ""
    @State private var pendingPhotoData: Data?
    @State private var shouldClearPhoto = false
    @State private var academicProfiles: [AcademicProfile] = []
    @State private var selectedAcademicProfileID: UUID?
    @State private var commitSelectedAcademicProfileEdits: (() -> Void)?
    @State private var showDiscardConfirmation = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.windowBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EditSheetTitleBar(
                    onCancel: { requestCancel() },
                    onDone:   { saveAndDismiss() }
                )

                Divider()
                    .opacity(0.35)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        ProfilePhotoHero(
                            pendingPhotoData: $pendingPhotoData,
                            shouldClearPhoto: $shouldClearPhoto,
                            existingPhotoData: profile.profilePhotoData
                        )

                        ProfileEditSection(
                            icon: "person.fill",
                            title: String(localized: "profile.edit.section.identity")
                        ) {
                            ProfileEditRow(label: String(localized: "profile.edit.field.name")) {
                                TextField(String(localized: "profile.edit.field.name"), text: $name)
                                    .textFieldStyle(.plain)
                                    .labelsHidden()
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.pronouns")) {
                                Picker("", selection: $pronouns) {
                                    Text(String(localized: "profile.edit.picker.select")).tag("")
                                    ForEach(ProfileEditOptions.pronounSuggestions, id: \.self) {
                                        Text($0).tag($0)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        academicDegreesSection

                        ProfileEditSection(
                            icon: "envelope.fill",
                            title: String(localized: "profile.edit.section.contact")
                        ) {
                            ProfileEditRow(label: String(localized: "profile.edit.field.university_email")) {
                                TextField(String(localized: "profile.edit.field.university_email"), text: $universityEmail)
                                    .textFieldStyle(.plain).labelsHidden()
                                    .textContentType(.emailAddress)
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.phone")) {
                                TextField(String(localized: "profile.edit.field.phone"), text: $personalPhone)
                                    .textFieldStyle(.plain).labelsHidden()
                                    .textContentType(.telephoneNumber)
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.address")) {
                                TextField(String(localized: "profile.edit.field.address"), text: $permanentAddress, axis: .vertical)
                                    .textFieldStyle(.plain).labelsHidden()
                                    .lineLimit(2...4)
                            }
                        }

                        ProfileEditSection(
                            icon: "person.text.rectangle.fill",
                            title: String(localized: "profile.edit.section.advisor")
                        ) {
                            ProfileEditRow(label: String(localized: "profile.edit.field.advisor")) {
                                TextField(String(localized: "profile.edit.field.advisor"), text: $advisorName)
                                    .textFieldStyle(.plain).labelsHidden()
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.student_id")) {
                                TextField(String(localized: "profile.edit.field.student_id"), text: $studentId)
                                    .textFieldStyle(.plain).labelsHidden()
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 660, idealHeight: 740)
        .onAppear {
            loadFromProfile()
            refreshAcademicProfiles()
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            refreshAcademicProfiles()
        }
        .confirmationDialog(
            "Discard profile changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your profile edits have not been saved.")
        }
    }

    @ViewBuilder
    private var academicDegreesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                Text(String(localized: "profile.edit.section.academic"))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .padding(.leading, 4)

            if academicProfiles.count > 1 {
                AcademicDegreeTabBar(
                    profiles: academicProfiles,
                    selectedID: $selectedAcademicProfileID,
                    showOverviewPill: false,
                    centersContent: true,
                    allowsAdd: true,
                    allowsDelete: academicProfiles.count > 1,
                    onAdd: addAcademicDegree,
                    onDelete: deleteAcademicDegree,
                    onReorder: { collegePersistence.reorderAcademicProfiles($0) }
                )
            }

            if let academicProfile = selectedAcademicProfile {
                Form {
                    AcademicProfileEditFields(
                        academicProfile: academicProfile,
                        onCommitHandlerReady: { handler in
                            commitSelectedAcademicProfileEdits = handler
                        }
                    )
                }
                .formStyle(.grouped)
            } else {
                Text(String(localized: "profile.identity.placeholder_degree"))
                    .font(DesignSystem.Fonts.main(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                    )
            }
        }
    }

    private var selectedAcademicProfile: AcademicProfile? {
        if let id = selectedAcademicProfileID {
            return academicProfiles.first { $0.id == id }
        }
        return academicProfiles.first
    }

    private func refreshAcademicProfiles() {
        if academicProfiles.isEmpty {
            _ = collegePersistence.ensurePrimaryAcademicProfile()
        }
        collegePersistence.fetchAcademicProfiles()
        academicProfiles = AcademicProfileReadBridge.profiles(collegePersistence: collegePersistence)
        if selectedAcademicProfileID == nil || !academicProfiles.contains(where: { $0.id == selectedAcademicProfileID }) {
            selectedAcademicProfileID = academicProfiles.first?.id
        }
    }

    private func addAcademicDegree() {
        let level = selectedAcademicProfile?.degreeLevel
            ?? academicProfiles.first?.degreeLevel
            ?? collegePersistence.primaryDegreeLevel(default: DegreeConfiguration.undergraduate)
        if let created = collegePersistence.addAcademicProfile(degreeLevel: level) {
            refreshAcademicProfiles()
            selectedAcademicProfileID = created.id
        }
    }

    private func deleteAcademicDegree(_ academicProfile: AcademicProfile) {
        try? collegePersistence.profileRepository.deleteAcademicProfile(id: academicProfile.id)
        collegePersistence.fetchAcademicProfiles()
        refreshAcademicProfiles()
    }

    @ViewBuilder
    private func readOnlyLine(_ value: String?) -> some View {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Text(t.isEmpty ? "—" : t)
    }

    private func loadFromProfile() {
        name               = profile.name ?? ""
        pronouns           = profile.pronouns ?? ""
        universityEmail    = profile.universityEmail ?? ""
        personalPhone      = profile.personalPhone ?? ""
        permanentAddress   = profile.permanentAddress ?? ""
        advisorName        = profile.advisorName ?? ""
        studentId          = profile.studentId ?? ""
        pendingPhotoData   = nil
        shouldClearPhoto   = false
    }

    private var hasUnsavedShellChanges: Bool {
        name != (profile.name ?? "")
            || pronouns != (profile.pronouns ?? "")
            || universityEmail != (profile.universityEmail ?? "")
            || personalPhone != (profile.personalPhone ?? "")
            || permanentAddress != (profile.permanentAddress ?? "")
            || advisorName != (profile.advisorName ?? "")
            || studentId != (profile.studentId ?? "")
            || pendingPhotoData != nil
            || shouldClearPhoto
    }

    private func requestCancel() {
        if hasUnsavedShellChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func saveAndDismiss() {
        commitSelectedAcademicProfileEdits?()
        collegePersistence.commitPrimaryAcademicProfileEdits()

        let photoData: Data?
        if shouldClearPhoto {
            photoData = nil
        } else if let pending = pendingPhotoData {
            photoData = pending
        } else {
            photoData = profile.profilePhotoData
        }

        do {
            try collegePersistence.profileRepository.updateProfileShell(
                id: profile.id,
                name: name.nilIfEmptyEdit,
                pronouns: pronouns.nilIfEmptyEdit,
                universityEmail: universityEmail.nilIfEmptyEdit,
                personalPhone: personalPhone.nilIfEmptyEdit,
                permanentAddress: permanentAddress.nilIfEmptyEdit,
                advisorName: advisorName.nilIfEmptyEdit,
                studentId: studentId.nilIfEmptyEdit,
                profilePhotoData: photoData
            )
            ModelMergeCoalescer.flushNow()
        } catch {
            #if DEBUG
            print("[ProfileEditSheet] local store save failed: \(error)")
            #endif
        }

        dismiss()
    }
}

// MARK: - Title bar

private struct EditSheetTitleBar: View {
    let onCancel: () -> Void
    let onDone:   () -> Void

    var body: some View {
        HStack {
            Button(String(localized: "profile.edit.cancel"), action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Text(String(localized: "profile.edit.title"))
                .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(String(localized: "profile.edit.done"), action: onDone)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .fontWeight(.semibold)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Photo hero

private struct ProfilePhotoHero: View {
    @Binding var pendingPhotoData: Data?
    @Binding var shouldClearPhoto: Bool
    let existingPhotoData: Data?

    private var displayData: Data? {
        shouldClearPhoto ? nil : (pendingPhotoData ?? existingPhotoData)
    }

    var body: some View {
        VStack(spacing: 14) {
            photoCircle
                .frame(width: 96, height: 96)

            HStack(spacing: 12) {
                Button(String(localized: "profile.edit.choose_photo")) { choosePhoto() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if !shouldClearPhoto && displayData != nil {
                    Button(String(localized: "profile.edit.remove_photo"), role: .destructive) {
                        shouldClearPhoto = true
                        pendingPhotoData = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var photoCircle: some View {
        if let data = displayData, !data.isEmpty, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.5))
        } else {
            placeholderCircle
        }
    }

    private var placeholderCircle: some View {
        Circle()
            .fill(Color.primary.opacity(0.06))
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .padding(DesignSystem.Spacing.sm)
            )
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1.5))
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .jpeg, .png, .gif]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        shouldClearPhoto = false
        pendingPhotoData = data
    }
}

// MARK: - Section card

private struct ProfileEditSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .padding(.bottom, 8)
            .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
        }
    }
}

// MARK: - Row

private struct ProfileEditRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 170, alignment: .leading)
                .lineLimit(1)

            control()
                .font(DesignSystem.Fonts.main(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct ProfileEditDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
            .opacity(0.5)
    }
}

private extension String {
    var nilIfEmptyEdit: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
