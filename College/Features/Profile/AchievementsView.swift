// AchievementsView.swift
// Feature: Profile
// Purpose: Profile module — AchievementsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject var collegePersistence: CollegePersistence
    @Environment(ModalCoordinator.self) var modalCoordinator
    @Bindable var profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Awards & Scholarships", systemImage: "trophy.fill")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()

                AddButton {
                    modalCoordinator.activeModal = .addAchievement
                }
            }

            if profile.achievementsArray.isEmpty {
                Text("No awards or scholarships added yet.")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding()
            } else {
                ForEach(profile.achievementsArray) { achievement in
                    AchievementCard(achievement: achievement)
                }
            }
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

struct AchievementCard: View {
    @Environment(ModalCoordinator.self) var modalCoordinator
    @Bindable var achievement: Achievement
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            modalCoordinator.activeModal = .editAchievement(achievement)
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Logo placeholder (rounded circle for awards)
                Circle()
                    .fill(Color(hex: "fef3c7").opacity(0.5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "f59e0b"))
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(achievement.name ?? "Unknown Award")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 4) {
                        Text(achievement.organization ?? "Unknown Organization")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(Color(hex: "64748b"))
                        
                        if let date = achievement.dateReceived {
                            Text("•")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundColor(Color(hex: "64748b"))
                            
                            Text(yearFormatter.string(from: date))
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundColor(Color(hex: "64748b"))
                        }
                    }
                    .padding(.top, 2)
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isHovering ? Color(hex: "e2e8f0") : Color(hex: "f1f5f9"), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.05 : 0.02), radius: isHovering ? 8 : 4, x: 0, y: isHovering ? 4 : 2)
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var yearFormatter: DateFormatter {
        Self.yearFormatter
    }

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

struct AddAchievementOverlay: View {
    @EnvironmentObject var collegePersistence: CollegePersistence
    @EnvironmentObject var notifications: AppNotificationCenter
    @Binding var isPresented: Bool
    let achievement: Achievement?
    
    var isEditMode: Bool {
        achievement != nil
    }

    @State private var name: String = ""
    @State private var organization: String = ""
    @State private var dateReceived: Date = Date()
    @State private var amount: String = ""
    @State private var description: String = ""
    @State private var url: String = ""

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case organization
        case amount
        case description
        case url
    }

    var body: some View {
        ZStack {
            // Match Experience modal backdrop (covers entire app when hosted globally)
            Color(hex: "0f172a")
                .opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                header

                Divider().foregroundColor(Color(hex: "e2e8f0"))

                form

                Divider().foregroundColor(Color(hex: "eef2f7"))

                footer
            }
            .frame(maxWidth: 640)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 30, x: 0, y: 20)
            .padding(24)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isPresented)
        .onAppear {
            // Populate fields when editing an existing achievement
            if let ach = achievement {
                name = ach.name ?? ""
                organization = ach.organization ?? ""
                dateReceived = ach.dateReceived ?? Date()
                amount = ach.amount ?? ""
                description = ach.descriptionText ?? ""
                url = ach.url ?? ""
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(DesignSystem.Colors.warning.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.warning)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditMode ? "Edit Achievement" : "Add Achievement")
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text(isEditMode ? "Update award or scholarship details" : "Record a new award or scholarship")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.Colors.bgMain)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RequiredLabeledField(title: "Award/Scholarship Name") {
                    IconTextField(
                        icon: "trophy",
                        placeholder: "e.g. President's Scholarship",
                        text: $name
                    )
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .organization }
                }

                RequiredLabeledField(title: "Issuing Organization") {
                    IconTextField(
                        icon: "building.columns",
                        placeholder: "e.g. University Name or Foundation",
                        text: $organization
                    )
                    .focused($focusedField, equals: .organization)
                    .submitLabel(.next)
                    .onSubmit { focusedField = nil }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date Received")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DesignSystem.Colors.bgMain)

                            HStack(spacing: 10) {
                                TextField("---------- ----", text: .constant(""))
                                    .disabled(true)
                                    .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .opacity(0) // keeps layout stable

                                Spacer()

                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }
                            .padding(.horizontal, 14)

                            DatePicker("", selection: $dateReceived, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .opacity(0.02) // keep tappable but visually hidden
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity)

                    LabeledField(title: "Amount/Benefit (Optional)") {
                        IconTextField(
                            icon: "dollarsign",
                            placeholder: "e.g. $5,000 or Full Tuition",
                            text: $amount
                        )
                        .focused($focusedField, equals: .amount)
                    }
                    .frame(maxWidth: .infinity)
                }

                LabeledField(title: "Description/Criteria (Optional)") {
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Briefly describe the criteria or significance of this award...")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                        }

                        TextEditor(text: $description)
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .frame(height: 120)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .focused($focusedField, equals: .description)
                    }
                    .background(DesignSystem.Colors.bgMain)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
                }

                LabeledField(title: "External URL (Optional)") {
                    IconTextField(
                        icon: "link",
                        placeholder: "e.g. https://scholarship.edu/award",
                        text: $url
                    )
                    .focused($focusedField, equals: .url)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Upload Supporting Documents")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("(Optional)")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }

                    UploadDropzone()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
        // Don't stretch the form to fill extra vertical space.
        // This keeps the footer close to the last field (Upload Supporting Documents).
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        let disabled = name.isEmpty || organization.isEmpty

        return HStack(spacing: 12) {
            // Delete button (only show in edit mode)
            if isEditMode, let ach = achievement {
                Button {
                    collegePersistence.deleteAchievement(ach)

                    notifications.post(
                        kind: .success,
                        title: "Award Deleted",
                        message: "Removed \((ach.name ?? "Award").trimmingCharacters(in: .whitespacesAndNewlines)).",
                        isDismissible: true,
                        autoDismissAfter: 3
                    )
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("Delete")
                    }
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
            .foregroundColor(DesignSystem.Colors.textLight)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Button {
                if let ach = achievement {
                    // Edit existing achievement
                    ach.name = name
                    ach.organization = organization
                    ach.dateReceived = dateReceived
                    ach.amount = amount
                    ach.descriptionText = description
                    ach.url = url
                    collegePersistence.save()

                    notifications.post(
                        kind: .success,
                        title: "Award Updated",
                        message: "Saved changes for \(name.trimmingCharacters(in: .whitespacesAndNewlines)).",
                        isDismissible: true,
                        autoDismissAfter: 3
                    )
                } else {
                    // Add new achievement
                    collegePersistence.addAchievement(
                        name: name,
                        organization: organization,
                        dateReceived: dateReceived,
                        amount: amount,
                        description: description,
                        url: url
                    )

                    notifications.post(
                        kind: .success,
                        title: "Award Added",
                        message: "Added \(name.trimmingCharacters(in: .whitespacesAndNewlines)).",
                        isDismissible: true,
                        autoDismissAfter: 3
                    )
                }
                isPresented = false
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                    Text("Save Award")
                }
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.primary)
                .clipShape(Capsule())
                .shadow(color: DesignSystem.Colors.primary.opacity(0.25), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1.0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            content
        }
    }
}

private struct RequiredLabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("*")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(Color.red.opacity(0.75))
            }

            content
        }
    }
}

private struct IconTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.bgMain)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
        )
    }
}

private struct UploadDropzone: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                Color(hex: "cbd5e1"),
                                style: StrokeStyle(lineWidth: 1, dash: [7, 6])
                            )
                    )

                VStack(spacing: 10) {
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "doc")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.primary)
                        )

                    Text("Click to upload files")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)

                    Text("PDF, JPG, or PNG (max 5MB) Upload award letters or certificates.")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }
}
