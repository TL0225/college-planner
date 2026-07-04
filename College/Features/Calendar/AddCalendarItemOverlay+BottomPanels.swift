// AddCalendarItemOverlay+BottomPanels.swift
// Feature: Calendar
// Purpose: Bottom sheet panels for AddCalendarItemOverlay (Phase 6 decomposition).

import SwiftUI
import Contacts
import UniformTypeIdentifiers
import AppKit

extension AddCalendarItemOverlay {
    // MARK: - Bottom Panels

    struct CalendarRecurrencePanel: View {
        @Binding var frequency: String
        @Binding var interval: Int
        @Binding var weekdays: Set<Int>
        @Binding var hasEndDate: Bool
        @Binding var endDate: Date
        let startDate: Date
        let onClose: () -> Void

        private let frequencyOptions: [(String, String)] = [
            ("none", "Does not repeat"),
            ("daily", "Daily"),
            ("weekly", "Weekly"),
            ("monthly", "Monthly"),
            ("yearly", "Yearly")
        ]

        private let weekdaySymbols: [(Int, String)] = [
            (1, "Mon"),
            (2, "Tue"),
            (3, "Wed"),
            (4, "Thu"),
            (5, "Fri"),
            (6, "Sat"),
            (7, "Sun")
        ]

        private var frequencyLabel: String {
            frequencyOptions.first(where: { $0.0 == frequency })?.1 ?? "Does not repeat"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Repeat")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Frequency")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Spacer(minLength: 0)
                        Menu {
                            ForEach(frequencyOptions, id: \.0) { option in
                                Button {
                                    frequency = option.0
                                    interval = max(1, interval)
                                    if frequency != "weekly" {
                                        weekdays = []
                                    }
                                    if frequency == "none" {
                                        hasEndDate = false
                                    }
                                } label: {
                                    if frequency == option.0 {
                                        Label(option.1, systemImage: "checkmark")
                                    } else {
                                        Text(option.1)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(frequencyLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                Image(systemName: "chevron.down")
                                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }

                    if frequency != "none" {
                        HStack(spacing: 8) {
                            Text("Every")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            Stepper(value: $interval, in: 1...30) {
                                Text("\(interval)")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                            }
                            .labelsHidden()
                            Text(frequency == "daily" ? "day(s)" : frequency == "weekly" ? "week(s)" : frequency == "monthly" ? "month(s)" : "year(s)")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            Spacer(minLength: 0)
                        }

                        if frequency == "weekly" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Repeat on")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    .foregroundStyle(DesignSystem.Colors.textLight)

                                HStack(spacing: 6) {
                                    ForEach(weekdaySymbols, id: \.0) { weekday in
                                        let selected = weekdays.contains(weekday.0)
                                        Button {
                                            if selected {
                                                weekdays.remove(weekday.0)
                                            } else {
                                                weekdays.insert(weekday.0)
                                            }
                                        } label: {
                                            Text(weekday.1)
                                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                .foregroundStyle(selected ? .white : DesignSystem.Colors.textMain)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(selected ? DesignSystem.Colors.primary : Color.black.opacity(0.06))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Toggle("Ends", isOn: $hasEndDate)
                                .toggleStyle(.switch)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            Spacer(minLength: 0)
                        }

                        if hasEndDate {
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.field)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                        )
                )

                HStack {
                    Button("Clear") {
                        frequency = "none"
                        interval = 1
                        weekdays = []
                        hasEndDate = false
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)

                    Spacer(minLength: 0)

                    Button("Done") { onClose() }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    struct CalendarCoursePanel: View {
        let courses: [PlannerCourse]
        let selectedCourseID: UUID?
        let semesterName: String?
        let isFullscreen: Bool
        let onSelectCourse: (UUID?) -> Void
        let onCreateCourse: (String, String) -> Void
        let onDeleteSelectedCourse: () -> Void
        let onOpenCourseBuilder: () -> Void
        let onBack: () -> Void
        let onClose: () -> Void

        @State private var searchText: String = ""
        @State private var newCourseCode: String = ""
        @State private var newCourseName: String = ""
        @State private var showDeleteConfirmation: Bool = false
        @State private var showAllCourses: Bool = false

        private var filteredCourses: [PlannerCourse] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return courses }
            return courses.filter { course in
                let code = course.code.localizedLowercase
                let name = course.name.localizedLowercase
                let q = query.localizedLowercase
                return code.contains(q) || name.contains(q)
            }
        }

        private func label(for course: PlannerCourse) -> String {
            let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty && !name.isEmpty { return "\(code) - \(name)" }
            if !code.isEmpty { return code }
            if !name.isEmpty { return name }
            return "Course"
        }

        private var canCreateCourse: Bool {
            !newCourseCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !newCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private var shouldCollapseCourses: Bool {
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private var visibleCourses: [PlannerCourse] {
            guard shouldCollapseCourses, !showAllCourses else { return filteredCourses }
            return Array(filteredCourses.prefix(4))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if isFullscreen {
                        Button(action: onBack) {
                            Label("Back", systemImage: "chevron.left")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Course Assignment")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                TextField("Search courses", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(spacing: 0) {
                            Button {
                                onSelectCourse(nil)
                            } label: {
                                HStack {
                                    Image(systemName: selectedCourseID == nil ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedCourseID == nil ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                                    Text("No course")
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)

                            Divider()

                            if filteredCourses.isEmpty {
                                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No courses available" : "No matching courses")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(visibleCourses, id: \.id) { course in
                                    Button {
                                        onSelectCourse(course.id)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: selectedCourseID == course.id ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedCourseID == course.id ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                                            Text(label(for: course))
                                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                                .foregroundColor(DesignSystem.Colors.textMain)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)

                                    if course.id != visibleCourses.last?.id {
                                        Divider()
                                    }
                                }

                                if shouldCollapseCourses && filteredCourses.count > 4 {
                                    Divider()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showAllCourses.toggle()
                                        }
                                    } label: {
                                        HStack {
                                            Text(showAllCourses ? "Show fewer courses" : "Show all courses (\(filteredCourses.count))")
                                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                .foregroundColor(DesignSystem.Colors.primary)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                                )
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create New Course")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)

                            Button {
                                onOpenCourseBuilder()
                            } label: {
                                Label("Open Full Course Roster", systemImage: "square.and.pencil")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.primary)

                            TextField("Course code (e.g. CSE 191)", text: $newCourseCode)
                                .textFieldStyle(.roundedBorder)

                            TextField("Course name", text: $newCourseName)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Text(semesterName.map { "Will add to \($0)" } ?? "Select a semester first to add courses")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Spacer(minLength: 0)
                                Button("Add") {
                                    onCreateCourse(newCourseCode, newCourseName)
                                    newCourseCode = ""
                                    newCourseName = ""
                                }
                                .buttonStyle(.plain)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .disabled(!canCreateCourse || semesterName == nil)
                            }
                        }

                        if selectedCourseID != nil {
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Unlink from event", systemImage: "trash")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                "Unlink course from event?",
                                isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Unlink from event", role: .destructive) {
                                    onDeleteSelectedCourse()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("This removes the course link from this event.")
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: isFullscreen ? nil : 340)
            .frame(maxWidth: isFullscreen ? .infinity : nil, alignment: .leading)
            .frame(maxHeight: isFullscreen ? .infinity : nil, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    struct CalendarAlertsPanel: View {
        let options: [Int]
        let selectedOffsets: [Int]
        let onToggle: (Int) -> Void
        let onAddCustom: (Int) -> Void
        let onClear: () -> Void
        let onClose: () -> Void

        @State private var customMinutesText: String = ""

        private var allOffsets: [Int] {
            Array(Set(options + selectedOffsets)).sorted()
        }

        private func label(for minutes: Int) -> String {
            if minutes == 0 { return "At time of event" }
            if minutes < 60 { return "\(minutes) mins before" }
            if minutes == 60 { return "1 hour before" }
            if minutes == 1440 { return "1 day before" }
            return "\(minutes / 60) hours before"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Alerts")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    ForEach(allOffsets, id: \.self) { minutes in
                        Button {
                            onToggle(minutes)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedOffsets.contains(minutes) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedOffsets.contains(minutes) ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                                Text(label(for: minutes))
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if minutes != allOffsets.last {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                        )
                )

                HStack(spacing: 8) {
                    TextField(
                        "Custom minutes",
                        text: Binding(
                            get: { customMinutesText },
                            set: { customMinutesText = String($0.filter(\.isNumber).prefix(4)) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        guard let minutes = Int(customMinutesText) else { return }
                        onAddCustom(minutes)
                        customMinutesText = ""
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .disabled(Int(customMinutesText) == nil)
                }

                HStack {
                    Button("Clear") { onClear() }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    Spacer(minLength: 0)
                    Button("Done") { onClose() }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(14)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    struct CalendarNotesPanel: View {
        @Binding var text: String
        let onSave: () -> Void
        @State private var measuredHeight: CGFloat = 100

        var body: some View {
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 16) {
                    Text("Notes")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)

                    Spacer()

                    Button(action: onSave) {
                        Text("Done")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.thinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor).opacity(0.6)), alignment: .bottom)

                // Editor
                ScrollView {
                    AutoGrowingTextEditor(
                        text: $text,
                        measuredHeight: $measuredHeight,
                        font: NSFont.systemFont(ofSize: 15, weight: .regular),
                        textColor: NSColor.labelColor.withAlphaComponent(0.85),
                        placeholder: "Start typing your event notes here..."
                    )
                    .padding(20)
                    .frame(minHeight: 200)
                }

                // Footer
                VStack {
                   Button(action: onSave) {
                        Text("Done")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DesignSystem.Colors.primary)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(16)
            }
            .background(.thinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 30, x: 0, y: -5)
            .frame(height: 500)
        }
    }

    struct CalendarFilesPanel: View {
        let linkedDocuments: [VaultDocument]
        let recentImports: [URL]
        let compactStyle: Bool
        let onClose: () -> Void
        let onBrowse: () -> Void
        let onOpenDocument: (VaultDocument) -> Void
        let onUnlinkDocument: (VaultDocument) -> Void

        private var totalCount: Int {
            linkedDocuments.count + recentImports.count
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(compactStyle ? "Attachments" : "ATTACHMENTS")
                        .font(DesignSystem.Fonts.main(size: compactStyle ? 14 : 12, weight: compactStyle ? .semibold : .bold))
                        .foregroundColor(DesignSystem.Colors.textMain.opacity(compactStyle ? 1 : 0.7))
                        .tracking(compactStyle ? 0 : 1)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close attachments")

                    Text("\(totalCount) file\(totalCount == 1 ? "" : "s")")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DesignSystem.Colors.primary.opacity(0.12))
                        .cornerRadius(12)
                }
                .padding(compactStyle ? 16 : 24)

                ScrollView {
                    VStack(spacing: 16) {
                        Button(action: onBrowse) {
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(DesignSystem.Colors.primary.opacity(0.08))
                                    .frame(width: compactStyle ? 48 : 64, height: compactStyle ? 48 : 64)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: compactStyle ? 18 : 24, weight: .semibold))
                                            .foregroundColor(DesignSystem.Colors.primary)
                                    )

                                VStack(spacing: 4) {
                                    Text("Add attachment")
                                        .font(DesignSystem.Fonts.main(size: compactStyle ? 13 : 15, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    Text("Browse files from your Mac")
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: compactStyle ? 120 : 180)
                            .background(
                                RoundedRectangle(cornerRadius: compactStyle ? 14 : 24)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(linkedDocuments) { document in
                            attachmentRow(
                                title: document.fileName,
                                detail: formattedSize(bytes: document.fileSizeBytes),
                                icon: fileIcon(forName: document.fileName),
                                iconColor: fileIconColor(forName: document.fileName),
                                onOpen: { onOpenDocument(document) },
                                onRemove: { onUnlinkDocument(document) },
                                removeLabel: "Unlink"
                            )
                        }

                        ForEach(recentImports, id: \.self) { url in
                            attachmentRow(
                                title: url.lastPathComponent,
                                detail: formattedSize(for: url),
                                icon: fileIcon(for: url),
                                iconColor: fileIconColor(for: url),
                                onOpen: { NSWorkspace.shared.open(url) },
                                onRemove: nil,
                                removeLabel: nil
                            )
                        }
                    }
                    .padding(.horizontal, compactStyle ? 16 : 24)
                    .padding(.bottom, compactStyle ? 16 : 24)
                }
            }
            .background {
                if compactStyle {
                    DesignSystem.Colors.surface
                } else {
                    Color.clear.background(.thinMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: compactStyle ? 14 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compactStyle ? 14 : 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(compactStyle ? 0.06 : 0.08), radius: compactStyle ? 10 : 24, x: 0, y: compactStyle ? 4 : -4)
            .frame(maxHeight: compactStyle ? 420 : 550)
        }

        @ViewBuilder
        private func attachmentRow(
            title: String,
            detail: String,
            icon: String,
            iconColor: Color,
            onOpen: @escaping () -> Void,
            onRemove: (() -> Void)?,
            removeLabel: String?
        ) -> some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundColor(iconColor)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                    Text(detail)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }

                Spacer(minLength: 0)

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Open file")
                .accessibilityLabel("Open \(title)")

                if let onRemove, let removeLabel {
                    Button(action: onRemove) {
                        Image(systemName: "link.badge.minus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(removeLabel)
                    .accessibilityLabel("\(removeLabel) \(title)")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
                    )
            )
        }

        private func fileIcon(for url: URL) -> String {
            fileIcon(forName: url.lastPathComponent)
        }

        private func fileIcon(forName name: String) -> String {
            let ext = (name as NSString).pathExtension.lowercased()
            if ext == "pdf" { return "doc.text.fill" }
            if ["jpg", "png", "jpeg"].contains(ext) { return "photo.fill" }
            return "doc.fill"
        }

        private func fileIconColor(for url: URL) -> Color {
            fileIconColor(forName: url.lastPathComponent)
        }

        private func fileIconColor(forName name: String) -> Color {
            let ext = (name as NSString).pathExtension.lowercased()
            if ext == "pdf" { return .red }
            if ["jpg", "png", "jpeg"].contains(ext) { return .blue }
            return .gray
        }

        private func formattedSize(for url: URL) -> String {
            guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resources.fileSize else { return "Unknown size" }
            return formattedSize(bytes: Int64(fileSize))
        }

        private func formattedSize(bytes: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }
}
