// ExperienceView.swift
// Feature: Profile
// Purpose: Profile module — ExperienceView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - Experience List View
struct ExperienceView: View {
    @Bindable var profile: Profile
    @EnvironmentObject var collegePersistence: CollegePersistence
    @Environment(ModalCoordinator.self) var modalCoordinator

    var body: some View {
        // Main Card
        VStack(alignment: .leading, spacing: 24) {
            header

            if profile.experiencesArray.isEmpty {
                Text("No experience added yet.")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textLight)
            } else {
                ForEach(profile.experiencesArray) { experience in
                    ExperienceCard(experience: experience)
                }
            }
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var header: some View {
        HStack {
            Label("Experience", systemImage: "briefcase.fill")
                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))

            Spacer()

            AddButton {
                modalCoordinator.activeModal = .addExperience
            }
        }
    }
}

struct ExperienceCard: View {
    @Bindable var experience: Experience
    @Environment(ModalCoordinator.self) var modalCoordinator
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            modalCoordinator.activeModal = .editExperience(experience)
        }) {
            HStack(alignment: .top, spacing: 16) {
                // Logo placeholder (rounded square) – matches reference layout.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
                    .overlay(
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "94a3b8"))
                    )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(experience.title ?? "Unknown")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 12)

                        Text(dateRange)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "94a3b8"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                            )
                    }

                    Text(experience.company ?? "")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(1)
                        .padding(.top, 4)

                    if let desc = experience.descriptionText, !desc.isEmpty {
                        Text(desc)
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .lineLimit(2)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isHovering ? DesignSystem.Colors.primary.opacity(0.5) : Color(hex: "e2e8f0"), lineWidth: isHovering ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.08 : 0.03), radius: isHovering ? 12 : 8, x: 0, y: isHovering ? 6 : 4)
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var dateRange: String {
        let formatter = Self.monthYearFormatter
        let start = experience.startDate.map { formatter.string(from: $0) } ?? "—"
        let end = experience.isCurrent ? "Present" :
            experience.endDate.map { formatter.string(from: $0) } ?? "—"

        return "\(start) – \(end)"
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()
}

struct AddExperienceView: View {
    @EnvironmentObject var collegePersistence: CollegePersistence
    @EnvironmentObject var notifications: AppNotificationCenter
    @Binding var isPresented: Bool
    let experience: Experience?  // nil for add, non-nil for edit

    @State private var title: String = ""
    @State private var company: String = ""
    @State private var location: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var isCurrent: Bool = false
    @State private var description: String = ""
    
    private var isEditMode: Bool {
        experience != nil
    }

    var body: some View {
        ZStack {
            // Web-style dim backdrop (no native frosted blur)
            Color(hex: "0f172a")
                .opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // Modal Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(isEditMode ? "Edit Experience" : "Add Experience")
                        .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .padding(8)
                            .background(Color.clear)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)

                Text("Fill in the details below to add an experience to your profile.")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 16) {
                        labeledTextField(title: "TITLE / ROLE *", placeholder: "e.g. Research Assistant", text: $title)
                        labeledTextField(title: "COMPANY / ORGANIZATION *", placeholder: "e.g. University Lab", text: $company)
                        labeledTextField(title: "LOCATION", placeholder: "e.g. New York, NY", text: $location)

                        HStack(spacing: 16) {
                            CustomDatePickerInput(title: "Start Date", date: $startDate)

                            if !isCurrent {
                                CustomDatePickerInput(title: "End Date", date: $endDate)
                            } else {
                                presentEndDate
                            }
                        }

                        Toggle(isOn: $isCurrent) {
                            Text("I currently work here")
                                .font(DesignSystem.Fonts.main(size: 14))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        .toggleStyle(.checkbox)

                        labeledDescription
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                // Footer
                HStack(spacing: 12) {
                    // Delete button (only show in edit mode)
                    if isEditMode, let exp = experience {
                        Button(action: {
                            collegePersistence.deleteExperience(exp)

                            notifications.post(
                                kind: .success,
                                title: "Experience Deleted",
                                message: "Removed \((exp.title ?? "Experience").trimmingCharacters(in: .whitespacesAndNewlines)).",
                                isDismissible: true,
                                autoDismissAfter: 3
                            )
                            isPresented = false
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Delete")
                                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red)
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Save button
                    Button(action: {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !trimmedTitle.isEmpty, !trimmedCompany.isEmpty else {
                            notifications.post(
                                kind: .warning,
                                title: "Missing Fields",
                                message: "Please enter a title and company.",
                                isDismissible: true,
                                autoDismissAfter: 4
                            )
                            return
                        }

                        if let exp = experience {
                            // Edit existing experience
                            exp.title = trimmedTitle
                            exp.company = trimmedCompany
                            exp.location = location
                            exp.startDate = startDate
                            exp.endDate = isCurrent ? nil : endDate
                            exp.isCurrent = isCurrent
                            exp.descriptionText = description
                            collegePersistence.save()

                            notifications.post(
                                kind: .success,
                                title: "Experience Updated",
                                message: "Saved changes for \(trimmedTitle).",
                                isDismissible: true,
                                autoDismissAfter: 3
                            )
                        } else {
                            // Add new experience
                            collegePersistence.addExperience(
                                title: trimmedTitle,
                                company: trimmedCompany,
                                location: location,
                                startDate: startDate,
                                endDate: isCurrent ? nil : endDate,
                                isCurrent: isCurrent,
                                description: description
                            )

                            notifications.post(
                                kind: .success,
                                title: "Experience Added",
                                message: "Added \(trimmedTitle) at \(trimmedCompany).",
                                isDismissible: true,
                                autoDismissAfter: 3
                            )
                        }
                        isPresented = false
                    }) {
                        Text("Save Experience")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(DesignSystem.Colors.primary)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .disabled(title.isEmpty || company.isEmpty)
                    .opacity((title.isEmpty || company.isEmpty) ? 0.6 : 1.0)
                }
                .padding(24)
            }
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.2), radius: 20)
            .frame(maxWidth: 500, maxHeight: 700)
            .padding(24)
        }
        .transition(.opacity)
        .zIndex(100)
        .onAppear {
            // Populate fields when editing an existing experience
            if let exp = experience {
                title = exp.title ?? ""
                company = exp.company ?? ""
                location = exp.location ?? ""
                startDate = exp.startDate ?? Date()
                endDate = exp.endDate ?? Date()
                isCurrent = exp.isCurrent
                description = exp.descriptionText ?? ""
            }
        }
    }

    private func labeledTextField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)

            TextField(placeholder, text: text)
                .font(DesignSystem.Fonts.main(size: 14))
                .foregroundColor(DesignSystem.Colors.textMain)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        }
    }

    private var labeledDescription: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESCRIPTION / KEY RESPONSIBILITIES")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)

            ZStack(alignment: .topLeading) {
                if description.isEmpty {
                    Text("Describe your key responsibilities and achievements...")
                        .font(DesignSystem.Fonts.main(size: 14))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(12)
                }

                TextEditor(text: $description)
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(height: 120)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
            )
        }
    }

    private var presentEndDate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("END DATE")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)

            Text("Present")
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.bgMain)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

struct CustomDatePickerInput: View {
    let title: String
    @Binding var date: Date
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)

            Button {
                showPicker.toggle()
            } label: {
                HStack {
                    Text(date, style: .date)
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .frame(width: 300)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Button Component
struct AddButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false
    
    var body: some View {
        Button {
            action()
        } label: {
            Label("Add", systemImage: "plus")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(isPressed ? DesignSystem.Colors.primary.opacity(0.7) : DesignSystem.Colors.primary)
                .scaleEffect(isPressed ? 0.95 : (isHovering ? 1.05 : 1.0))
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
