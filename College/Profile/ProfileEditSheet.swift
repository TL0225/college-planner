import SwiftUI
import CoreData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Profile Edit Sheet

struct ProfileEditSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coreDataManager: CoreDataManager

    @ObservedObject var profile: ProfileEntity

    @State private var name = ""
    @State private var pronouns = ""
    @State private var degreeLevel = ProfileEditOptions.degreeLevels.first ?? ""
    @State private var majorCount: Int = 1
    @State private var minorCount: Int = 0
    @State private var selectedMajors: [String] = [""]
    @State private var selectedMinors: [String] = []
    @State private var universityEmail = ""
    @State private var personalPhone = ""
    @State private var permanentAddress = ""
    @State private var advisorName = ""
    @State private var studentId = ""
    @State private var pendingPhotoData: Data?
    @State private var shouldClearPhoto = false
    @State private var availableMajors: [String] = []
    @State private var availableMajorSections: [ProfileEditMajorSection] = []
    @State private var availableMinors: [String] = []

    private let maxProgramSelections: Int = 8

    var body: some View {
        ZStack {
            // Full-sheet Tahoe background — refracts wallpaper like other native Tahoe windows.
            Rectangle()
                .fill(.windowBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Title bar row ──────────────────────────────────────────
                EditSheetTitleBar(
                    onCancel: { dismiss() },
                    onDone:   { saveAndDismiss() }
                )

                Divider()
                    .opacity(0.35)

                // ── Scrollable body ────────────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // ── Photo hero ─────────────────────────────────────
                        ProfilePhotoHero(
                            pendingPhotoData: $pendingPhotoData,
                            shouldClearPhoto: $shouldClearPhoto,
                            existingPhotoData: profile.profilePhotoData
                        )

                        // ── Identity ───────────────────────────────────────
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

                        // ── Academics ──────────────────────────────────────
                        ProfileEditSection(
                            icon: "graduationcap.fill",
                            title: String(localized: "profile.edit.section.academic")
                        ) {
                            ProfileEditRow(label: String(localized: "profile.edit.field.university")) {
                                readOnlyLine(profile.collegeName)
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.department")) {
                                readOnlyLine(profile.department)
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.degree_level")) {
                                Picker("", selection: $degreeLevel) {
                                    ForEach(ProfileEditOptions.degreeLevels, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.major")) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Stepper(value: $majorCount, in: 1...maxProgramSelections) {
                                        Text("Count: \(majorCount)")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .onChange(of: majorCount) { _, _ in
                                        reconcileProgramSelections()
                                    }

                                    ForEach(selectedMajors.indices, id: \.self) { index in
                                        if availableMajors.isEmpty && availableMajorSections.isEmpty {
                                            TextField("Major \(index + 1)", text: majorBinding(at: index))
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            Picker("Major \(index + 1)", selection: majorBinding(at: index)) {
                                                Text("Select major").tag("")
                                                if !availableMajorSections.isEmpty {
                                                    ForEach(availableMajorSections) { section in
                                                        Section(section.title) {
                                                            ForEach(ProfileEditProgramMenuData.optionsPreservingCurrentSelection(base: section.majors, current: selectedMajors[index]), id: \.self) { major in
                                                                Text(major).tag(major)
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    ForEach(ProfileEditProgramMenuData.optionsPreservingCurrentSelection(base: availableMajors, current: selectedMajors[index]), id: \.self) { major in
                                                        Text(major).tag(major)
                                                    }
                                                }
                                            }
                                            .pickerStyle(.menu)
                                        }
                                    }
                                }
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.minor")) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Stepper(value: $minorCount, in: 0...maxProgramSelections) {
                                        Text("Count: \(minorCount)")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .onChange(of: minorCount) { _, _ in
                                        reconcileProgramSelections()
                                    }

                                    ForEach(selectedMinors.indices, id: \.self) { index in
                                        if availableMinors.isEmpty {
                                            TextField("Minor \(index + 1)", text: minorBinding(at: index))
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            Picker("Minor \(index + 1)", selection: minorBinding(at: index)) {
                                                Text("Select minor").tag("")
                                                ForEach(ProfileEditProgramMenuData.optionsPreservingCurrentSelection(base: availableMinors, current: selectedMinors[index]), id: \.self) { minor in
                                                    Text(minor).tag(minor)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                        }
                                    }
                                }
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.class_standing")) {
                                readOnlyLine(profile.classStanding)
                            }
                            ProfileEditDivider()
                            ProfileEditRow(label: String(localized: "profile.edit.field.expected_graduation")) {
                                readOnlyLine(profile.expectedGraduation)
                            }
                        }

                        // ── Contact ────────────────────────────────────────
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

                        // ── Advisor ────────────────────────────────────────
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
        .onAppear(perform: loadFromProfile)
        .onChange(of: degreeLevel) { _, _ in
            refreshProgramOptions()
        }
    }

    // MARK: - Program pickers & read-only lines

    @ViewBuilder
    private func readOnlyLine(_ value: String?) -> some View {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Text(t.isEmpty ? "—" : t)
    }

    /// Native pull-down menu (macOS `Menu`), not a `Picker`, so the control never presents as a combo text field.
    @ViewBuilder
    private func programMenuPicker(
        options: [String],
        selection: Binding<String>,
        clearChoiceTitle: String?,
        emptyLabel: String
    ) -> some View {
        Menu {
            if let clearChoiceTitle {
                Button(clearChoiceTitle) { selection.wrappedValue = "" }
            }
            if options.isEmpty {
                Button(String(localized: "profile.edit.menu.no_options")) {}
                    .disabled(true)
            } else {
                ForEach(options, id: \.self) { value in
                    Button(value) { selection.wrappedValue = value }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(programMenuTitle(selection: selection.wrappedValue, emptyLabel: emptyLabel))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    private func programMenuTitle(selection: String, emptyLabel: String) -> String {
        let t = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? emptyLabel : t
    }

    // MARK: - Load / Save

    private func loadFromProfile() {
        name               = profile.name ?? ""
        pronouns           = profile.pronouns ?? ""
        degreeLevel        = (profile.degreeLevel?.isEmpty == false) ? (profile.degreeLevel ?? ProfileEditOptions.degreeLevels.first ?? "") : (ProfileEditOptions.degreeLevels.first ?? "")

        let csvMajors = ProfileProgramLists.majors(from: profile)
        var majorList: [String] = csvMajors
        if majorList.isEmpty {
            let primary = profile.major?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let secondary = profile.secondaryMajor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !primary.isEmpty { majorList.append(primary) }
            if !secondary.isEmpty, secondary.caseInsensitiveCompare(primary) != .orderedSame {
                majorList.append(secondary)
            }
        }
        if majorList.isEmpty { majorList = [""] }
        selectedMajors = majorList
        majorCount = max(1, majorList.count)

        let csvMinors = ProfileProgramLists.minors(from: profile)
        var minorList = csvMinors
        if minorList.isEmpty {
            let legacyMinor = normalizedMinorFromProfile(profile.minor)
            if !legacyMinor.isEmpty { minorList = [legacyMinor] }
        }
        selectedMinors = minorList
        minorCount = minorList.count

        universityEmail    = profile.universityEmail ?? ""
        personalPhone      = profile.personalPhone ?? ""
        permanentAddress   = profile.permanentAddress ?? ""
        advisorName        = profile.advisorName ?? ""
        studentId          = profile.studentId ?? ""
        pendingPhotoData   = nil
        shouldClearPhoto   = false

        reconcileProgramSelections()
        refreshProgramOptions()
    }

    private func saveAndDismiss() {
        profile.name               = name.nilIfEmptyEdit
        profile.pronouns           = pronouns.nilIfEmptyEdit
        profile.degreeLevel        = degreeLevel.nilIfEmptyEdit
        profile.universityEmail    = universityEmail.nilIfEmptyEdit
        profile.personalPhone      = personalPhone.nilIfEmptyEdit
        profile.permanentAddress   = permanentAddress.nilIfEmptyEdit
        profile.advisorName        = advisorName.nilIfEmptyEdit
        profile.studentId          = studentId.nilIfEmptyEdit

        if shouldClearPhoto {
            profile.profilePhotoData = nil
        } else if let pending = pendingPhotoData {
            profile.profilePhotoData = pending
        }

        let validMajors = normalizedProgramList(from: selectedMajors)
        let validMinors = normalizedProgramList(from: selectedMinors)

        profile.major = validMajors.first
        profile.secondaryMajor = validMajors.count > 1 ? validMajors[1] : nil
        profile.minor = validMinors.first

        // Preserve list-based representation for views that read CSV-style selections.
        ProfileProgramLists.syncToProfile(majors: validMajors, minors: validMinors, profile: profile)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            #if DEBUG
            print("[ProfileEditSheet] save failed: \(error)")
            #endif
        }
    }

    /// Aligns with `AcademicIdentityView`: no minor uses `nil`, not the literal `"None"`.
    private func normalizedMinorFromProfile(_ raw: String?) -> String {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty || t.lowercased() == "none" { return "" }
        return t
    }

    private func majorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { selectedMajors[index] },
            set: { selectedMajors[index] = $0 }
        )
    }

    private func minorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { selectedMinors[index] },
            set: { selectedMinors[index] = $0 }
        )
    }

    private func reconcileProgramSelections() {
        majorCount = min(max(1, majorCount), maxProgramSelections)
        minorCount = min(max(0, minorCount), maxProgramSelections)

        if selectedMajors.count < majorCount {
            selectedMajors.append(contentsOf: Array(repeating: "", count: majorCount - selectedMajors.count))
        } else if selectedMajors.count > majorCount {
            selectedMajors = Array(selectedMajors.prefix(majorCount))
        }

        if selectedMinors.count < minorCount {
            selectedMinors.append(contentsOf: Array(repeating: "", count: minorCount - selectedMinors.count))
        } else if selectedMinors.count > minorCount {
            selectedMinors = Array(selectedMinors.prefix(minorCount))
        }
    }

    private func normalizedProgramList(from raw: [String]) -> [String] {
        var out: [String] = []
        for value in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if out.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) { continue }
            out.append(trimmed)
        }
        return out
    }

    private func refreshProgramOptions() {
        let choices = ProfileEditProgramMenuData.programChoices(
            coreData: coreDataManager,
            profile: profile,
            degreeLevelForQueries: degreeLevel
        )
        availableMajors = choices.majors
        availableMajorSections = choices.majorSections
        availableMinors = choices.minors
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
                .font(.system(size: 15, weight: .semibold))
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
                #if os(macOS)
                Button(String(localized: "profile.edit.choose_photo")) { choosePhoto() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                #endif

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
        #if os(macOS)
        if let data = displayData, !data.isEmpty, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.5))
        } else {
            placeholderCircle
        }
        #else
        placeholderCircle
        #endif
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
                    .padding(8)
            )
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1.5))
    }

    #if os(macOS)
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
    #endif
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 170, alignment: .leading)
                .lineLimit(1)

            control()
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Intra-section divider

private struct ProfileEditDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
            .opacity(0.5)
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmptyEdit: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
