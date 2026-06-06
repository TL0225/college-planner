// AddTaskOverlay.swift
import CollegeCalendar
// Feature: Calendar
// Purpose: Calendar module — AddTaskOverlay.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Add/edit task UI used by the Calendar page.
struct AddTaskOverlay: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    enum PresentationStyle {
        case fullScreenOverlay
        case anchoredPanel
    }

    @Binding var isPresented: Bool
    let semester: PlannerSemester?
    let taskToEdit: PlannerTask?
    let prefillCourseID: UUID?
    let presentationStyle: PresentationStyle

    private struct CategoryOption: Identifiable, Hashable {
        var id: String
        var name: String
        var weightPercent: Double?
        var gradingCategoryID: UUID?

        var label: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Category" : trimmed
        }
    }

    private struct TaskMeta: Codable, Equatable {
        var category: String?
        var weightPercent: Int?
        var effortHours: Int?
        var effortMinutes: Int?
    }

    private static let metaStartTag = "[CollegeTaskMeta]"
    private static let metaEndTag = "[/CollegeTaskMeta]"

    private enum DateFormatters {
        static let dueDateDisplay: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MM/dd/yyyy"
            return f
        }()

        static let dueDateParsers: [DateFormatter] = [
            "M/d/yyyy",
            "MM/dd/yyyy",
            "M/d/yy",
            "MM/dd/yy"
        ].map { format in
            let f = DateFormatter()
            f.dateFormat = format
            return f
        }

        static let monthTitle: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            return f
        }()
    }

    @State private var title: String = ""
    @State private var selectedCourseID: UUID? = nil

    /// User-selected task category name (course-specific when available).
    @State private var categoryName: String = ""
    /// Optional link to a syllabus-derived grading category for the selected course.
    @State private var selectedGradingCategoryID: UUID? = nil

    @State private var dueDate: Date = Date()
    @State private var dueDateEnabled: Bool = true
    @State private var isDueDatePopoverPresented: Bool = false

    @State private var dueDateText: String = ""

    @State private var priority: Int16 = 1

    @State private var weightPercentText: String = ""
    @State private var effortHoursText: String = ""
    @State private var effortMinutesText: String = ""

    /// Preserve any existing user notes while we store structured fields in a tagged metadata block.
    @State private var preservedUserNotes: String = ""

    @State private var showDeleteConfirmation: Bool = false
    @State private var showDiscardConfirmation: Bool = false

    private struct Snapshot: Equatable {
        let title: String
        let dueDateEnabled: Bool
        let dueDate: Date
        let courseID: UUID?
        let priority: Int16
        let categoryName: String
        let gradingCategoryID: UUID?
        let weightPercentText: String
        let effortHoursText: String
        let effortMinutesText: String
    }

    private let initialSnapshot: Snapshot

    private var courses: [PlannerCourse] {
        if let semester {
            return semester.coursesArray
        }
        return collegePersistence.semesters.flatMap(\.coursesArray)
    }

    private static func stripMetaBlock(from notes: String) -> (userNotes: String, meta: TaskMeta?) {
        let start = notes.range(of: metaStartTag)
        let end = notes.range(of: metaEndTag)
        guard let start, let end, start.lowerBound < end.lowerBound else {
            return (notes.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let jsonStart = start.upperBound
        let jsonEnd = end.lowerBound
        let jsonString = String(notes[jsonStart..<jsonEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        let before = notes[..<start.lowerBound]
        let after = notes[end.upperBound...]
        let userNotes = (String(before) + String(after)).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            return (userNotes, nil)
        }
        let meta = try? JSONDecoder().decode(TaskMeta.self, from: data)
        return (userNotes, meta)
    }

    private static func assembleNotes(userNotes: String, meta: TaskMeta) -> String? {
        let trimmedUser = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMeta = (meta.category != nil) || (meta.weightPercent != nil) || (meta.effortHours != nil) || (meta.effortMinutes != nil)

        guard hasMeta else {
            return trimmedUser.isEmpty ? nil : trimmedUser
        }

        guard let data = try? JSONEncoder().encode(meta),
              let json = String(data: data, encoding: .utf8) else {
            return trimmedUser.isEmpty ? nil : trimmedUser
        }

        let metaBlock = "\n\n\(metaStartTag)\n\(json)\n\(metaEndTag)"
        let combined = trimmedUser.isEmpty ? metaBlock.trimmingCharacters(in: .whitespacesAndNewlines) : (trimmedUser + metaBlock)
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        isPresented: Binding<Bool>,
        semester: PlannerSemester?,
        taskToEdit: PlannerTask? = nil,
        prefillCourseID: UUID? = nil,
        presentationStyle: PresentationStyle = .fullScreenOverlay
    ) {
        _isPresented = isPresented
        self.semester = semester
        self.taskToEdit = taskToEdit
        self.prefillCourseID = prefillCourseID
        self.presentationStyle = presentationStyle

        if let taskToEdit {
            let initialDue = taskToEdit.dueDate ?? Date()
            let initialHasDue = taskToEdit.dueDate != nil
            let stripped = Self.stripMetaBlock(from: taskToEdit.notes ?? "")

            let storedCategoryName: String = {
                let direct = (taskToEdit.categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !direct.isEmpty { return direct }
                let legacy = (stripped.meta?.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return legacy
            }()

            let storedWeightPercent: String = {
                if let w = taskToEdit.weightPercent, w > 0 {
                    return String(Int(w.rounded()))
                }
                if let legacy = stripped.meta?.weightPercent {
                    return String(legacy)
                }
                return ""
            }()

            let storedEffort: (hours: String, minutes: String) = {
                let total = taskToEdit.estimatedEffortMinutes.map(Int.init)

                if let total, total > 0 {
                    let clamped = max(0, total)
                    let h = clamped / 60
                    let m = clamped % 60
                    return (hours: h == 0 ? "" : String(h), minutes: m == 0 ? "" : String(m))
                }
                let h = stripped.meta?.effortHours
                let m = stripped.meta?.effortMinutes
                return (hours: h.map(String.init) ?? "", minutes: m.map(String.init) ?? "")
            }()

            _title = State(initialValue: taskToEdit.title)
            _dueDateEnabled = State(initialValue: initialHasDue)
            _dueDate = State(initialValue: initialDue)
            _dueDateText = State(initialValue: initialHasDue ? Self.formatDueDateDisplay(initialDue) : "")
            _selectedCourseID = State(initialValue: taskToEdit.course?.id)
            _priority = State(initialValue: taskToEdit.priority)

            _categoryName = State(initialValue: storedCategoryName)
            _selectedGradingCategoryID = State(initialValue: taskToEdit.gradingCategory?.id)

            _weightPercentText = State(initialValue: storedWeightPercent)
            _effortHoursText = State(initialValue: storedEffort.hours)
            _effortMinutesText = State(initialValue: storedEffort.minutes)
            _preservedUserNotes = State(initialValue: stripped.userNotes)

            initialSnapshot = Snapshot(
                title: taskToEdit.title.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDateEnabled: initialHasDue,
                dueDate: initialDue,
                courseID: taskToEdit.course?.id,
                priority: taskToEdit.priority,
                categoryName: storedCategoryName,
                gradingCategoryID: taskToEdit.gradingCategory?.id,
                weightPercentText: storedWeightPercent,
                effortHoursText: storedEffort.hours,
                effortMinutesText: storedEffort.minutes
            )
        } else {
            _selectedCourseID = State(initialValue: prefillCourseID)
            _priority = State(initialValue: 1)
            _dueDateText = State(initialValue: Self.formatDueDateDisplay(Date()))

            initialSnapshot = Snapshot(
                title: "",
                dueDateEnabled: true,
                dueDate: Date(),
                courseID: prefillCourseID,
                priority: 1,
                categoryName: "",
                gradingCategoryID: nil,
                weightPercentText: "",
                effortHoursText: "",
                effortMinutesText: ""
            )
        }
    }

    private static func formatDueDateDisplay(_ date: Date) -> String {
        let fmt = DateFormatters.dueDateDisplay
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }

    private static func formatDueDateDigitsAsText(_ rawText: String) -> String {
        let trimmed = rawText.replacingOccurrences(of: " ", with: "")

        // If the user already typed/pasted slashes, preserve that structure and
        // just strip invalid characters.
        if trimmed.contains("/") {
            let filtered = trimmed.filter { $0.isNumber || $0 == "/" }

            // Cap the total digits so we don't grow indefinitely.
            var digitCount = 0
            var slashCount = 0
            var result = ""
            for ch in filtered {
                if ch == "/" {
                    guard slashCount < 2 else { continue }
                    slashCount += 1
                    result.append(ch)
                } else {
                    guard digitCount < 8 else { continue }
                    digitCount += 1
                    result.append(ch)
                }
            }
            return result
        }

        // Digits-only typing: auto-insert slashes after MM and DD.
        let digits = trimmed.filter { $0.isNumber }
        let clamped = String(digits.prefix(8))
        var result = ""
        for (idx, ch) in clamped.enumerated() {
            if idx == 2 || idx == 4 { result.append("/") }
            result.append(ch)
        }
        return result
    }

    private func syncDueDateFromText() {
        let text = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.filter { $0.isNumber }

        if digits.isEmpty {
            dueDateEnabled = false
            return
        }

        dueDateEnabled = true

        let normalized = text.replacingOccurrences(of: " ", with: "")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)

        // Only commit a Date once the user has typed a complete year.
        if parts.count == 3 {
            let year = parts[2]
            if year.count == 2 || year.count == 4 {
                if let parsed = Self.parseDueDateInput(normalized) {
                    dueDate = parsed
                }
            }
            return
        }

        // Digits-only entry (auto-slash): allow MMDDYY or MMDDYYYY.
        if digits.count == 6 || digits.count == 8 {
            if let parsed = Self.parseDueDateInput(normalized) {
                dueDate = parsed
            }
        }
    }

    private static func parseDueDateInput(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: " ", with: "")

        for fmt in DateFormatters.dueDateParsers {
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone.current
            if let date = fmt.date(from: normalized) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    private func selectedCourse() -> PlannerCourse? {
        guard let id = selectedCourseID else { return nil }
        return try? collegePersistence.profileRepository.fetchCourse(id: id)
    }

    private func selectedCourseTitle() -> String {
        guard let c = selectedCourse() else { return "Select Course" }
        let code = c.code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty { return code }
        let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Course" : name
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentSnapshot: Snapshot {
        Snapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDateEnabled: dueDateEnabled,
            dueDate: dueDate,
            courseID: selectedCourseID,
            priority: priority,
            categoryName: categoryName.trimmingCharacters(in: .whitespacesAndNewlines),
            gradingCategoryID: selectedGradingCategoryID,
            weightPercentText: weightPercentText.trimmingCharacters(in: .whitespacesAndNewlines),
            effortHoursText: effortHoursText.trimmingCharacters(in: .whitespacesAndNewlines),
            effortMinutesText: effortMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var hasUnsavedChanges: Bool {
        currentSnapshot != initialSnapshot
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            isPresented = false
        }
    }

    private enum Visual {
        static let canvas = Color(hex: "f6f7fb")
        static let card = Color.white
        static let border = Color.black.opacity(0.08)
        static let divider = Color.black.opacity(0.07)
        static let text = Color.black.opacity(0.86)
        static let muted = Color.black.opacity(0.52)
        static let fieldFill = Color(hex: "f8fafc")

        static let accentYellow = Color(hex: "e8f000")
        static let accentYellowSoft = Color(hex: "fff9c4")
        static let orange = Color(hex: "f59e0b")

        static let corner: CGFloat = 24
        static let fieldCorner: CGFloat = 14
    }

    private var editorCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

            Rectangle()
                .fill(Visual.divider)
                .frame(height: 1)

            Group {
                if presentationStyle == .anchoredPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        topFieldsRow
                        categoryRow
                        Rectangle().fill(Visual.divider).frame(height: 1)
                        dueAndPriorityRow
                        Rectangle().fill(Visual.divider).frame(height: 1)
                        weightAndEffortRow
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            topFieldsRow
                            categoryRow
                            Rectangle().fill(Visual.divider).frame(height: 1)
                            dueAndPriorityRow
                            Rectangle().fill(Visual.divider).frame(height: 1)
                            weightAndEffortRow
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Rectangle()
                .fill(Visual.divider)
                .frame(height: 1)

            footerRow
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
        }
    }

    private var topFieldsRow: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let total = max(0, proxy.size.width)
            let titleW = max(220, (total - spacing) * 0.75)
            let courseW = max(160, (total - spacing) * 0.25)

            HStack(alignment: .top, spacing: spacing) {
                titleField
                    .frame(width: titleW)

                courseField
                    .frame(width: courseW)
            }
        }
        .frame(height: 74)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("TITLE")
            roundedField {
                TextField("e.g. Essay Draft", text: $title)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Visual.text)
            }
        }
    }

    private var courseField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("COURSE")
            roundedField {
                if prefillCourseID != nil {
                    HStack(spacing: 10) {
                        Text(selectedCourseTitle())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedCourseID == nil ? Visual.muted : Visual.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                } else {
                    hideMenuIndicatorIfAvailable(
                        Menu {
                            Button("None") {
                                selectedCourseID = nil
                            }

                            if !courses.isEmpty {
                                Divider()
                            }

                            ForEach(courses, id: \.id) { course in
                                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                                let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                Button(code.isEmpty ? (name.isEmpty ? "Course" : name) : code) {
                                    selectedCourseID = course.id
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(selectedCourseTitle())
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedCourseID == nil ? Visual.muted : Visual.text)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Visual.muted)
                            }
                        }
                        .menuStyle(.borderlessButton)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func hideMenuIndicatorIfAvailable<Content: View>(_ content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.menuIndicator(.hidden)
        } else {
            content
        }
    }

    private var categoryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("CATEGORY")

            let cols = max(1, min(4, categoryOptions.count))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .center), count: cols),
                alignment: .center,
                spacing: 14
            ) {
                ForEach(categoryOptions) { opt in
                    categoryChip(opt)
                }
            }
        }
    }

    private func plannerGradingCategories(for course: PlannerCourse) -> [CourseGradingCategory] {
        (course.gradingCategories ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var categoryOptions: [CategoryOption] {
        guard let course = selectedCourse() else {
            return defaultCategoryOptions
        }

        let categories = plannerGradingCategories(for: course)
        if categories.isEmpty {
            return defaultCategoryOptions
        }

        return categories.map { cat in
            CategoryOption(
                id: cat.id.uuidString,
                name: cat.name.trimmingCharacters(in: .whitespacesAndNewlines),
                weightPercent: cat.weightPercent,
                gradingCategoryID: cat.id
            )
        }
    }

    private var defaultCategoryOptions: [CategoryOption] {
        [
            CategoryOption(id: "assignment", name: "Assignment", weightPercent: nil, gradingCategoryID: nil),
            CategoryOption(id: "exam", name: "Exam", weightPercent: nil, gradingCategoryID: nil),
            CategoryOption(id: "reading", name: "Reading", weightPercent: nil, gradingCategoryID: nil),
            CategoryOption(id: "project", name: "Project", weightPercent: nil, gradingCategoryID: nil)
        ]
    }

    private func categoryVisuals(for name: String) -> (systemImage: String, accent: Color) {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("exam") || s.contains("final") || s.contains("midterm") {
            return ("stopwatch", Color(hex: "64748b"))
        }
        if s.contains("quiz") {
            return ("questionmark.circle", Color(hex: "64748b"))
        }
        if s.contains("homework") || s.contains("assignment") || s.contains("problem") {
            return ("doc.text", Color(hex: "f59e0b"))
        }
        if s.contains("project") || s.contains("paper") || s.contains("presentation") {
            return ("paperplane", Color(hex: "8b5cf6"))
        }
        if s.contains("reading") {
            return ("book", Color(hex: "3b82f6"))
        }
        if s.contains("lab") {
            return ("testtube.2", Color(hex: "06b6d4"))
        }
        if s.contains("discussion") {
            return ("text.bubble", Color(hex: "10b981"))
        }
        return ("tag", Color(hex: "94a3b8"))
    }

    private func categoryChip(_ opt: CategoryOption) -> some View {
        let trimmed = opt.label
        let isSelectedByID = (opt.gradingCategoryID != nil) && (opt.gradingCategoryID == selectedGradingCategoryID)
        let isSelectedByName = !trimmed.isEmpty && trimmed.caseInsensitiveCompare(categoryName) == .orderedSame
        let isSelected = isSelectedByID || isSelectedByName

        let visuals = categoryVisuals(for: trimmed)

        return Button {
            categoryName = trimmed
            selectedGradingCategoryID = opt.gradingCategoryID

            // Prefill weight if the user hasn't typed one yet.
            if weightPercentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let w = opt.weightPercent {
                weightPercentText = String(Int(w.rounded()))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: visuals.systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(trimmed)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                if let w = opt.weightPercent {
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f%%", w))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? visuals.accent : Visual.muted)
                }
            }
            .foregroundColor(isSelected ? visuals.accent : Visual.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(isSelected ? visuals.accent.opacity(0.10) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(isSelected ? visuals.accent.opacity(0.45) : Visual.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var dueAndPriorityRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("DUE DATE")

                roundedField {
                    HStack(spacing: 10) {
                        TextField("mm/dd/yyyy", text: $dueDateText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .kerning(0.6)
                            .foregroundColor(dueDateEnabled ? Visual.text : Visual.muted)
                            .onChange(of: dueDateText) { _, newValue in
                                let formatted = Self.formatDueDateDigitsAsText(newValue)
                                if formatted != newValue {
                                    dueDateText = formatted
                                    return
                                }

                                syncDueDateFromText()
                            }
                            .onSubmit {
                                syncDueDateFromText()
                                if dueDateEnabled {
                                    dueDateText = Self.formatDueDateDisplay(dueDate)
                                }
                            }

                        Spacer(minLength: 0)

                        Button {
                            isDueDatePopoverPresented.toggle()
                        } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Visual.muted)
                                .frame(width: 28, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isDueDatePopoverPresented, arrowEdge: .bottom) {
                            DueDateCalendarPopover(
                                selectedDate: $dueDate,
                                dueDateEnabled: $dueDateEnabled
                            )
                            .padding(14)
                            .frame(width: 320)
                        }
                    }
                }
                .onChange(of: dueDate) { _, newValue in
                    if dueDateEnabled {
                        dueDateText = Self.formatDueDateDisplay(newValue)
                    }
                }
                .onChange(of: dueDateEnabled) { _, enabled in
                    if enabled {
                        dueDateText = Self.formatDueDateDisplay(dueDate)
                    } else {
                        if dueDateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            dueDateText = ""
                        }
                    }
                }

                HStack(spacing: 14) {
                    quickDateButton("TODAY") {
                        dueDateEnabled = true
                        dueDate = Calendar.current.startOfDay(for: Date())
                    }
                    quickDateButton("TOMORROW") {
                        dueDateEnabled = true
                        dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    }
                    quickDateButton("NEXT WEEK") {
                        dueDateEnabled = true
                        dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("PRIORITY")
                priorityControl
            }
        }
    }

    private struct DueDateCalendarPopover: View {
        @Binding var selectedDate: Date
        @Binding var dueDateEnabled: Bool

        @State private var displayedMonth: Date

        private let calendar: Calendar = {
            var c = Calendar.current
            c.firstWeekday = 1 // Sunday
            return c
        }()

        init(selectedDate: Binding<Date>, dueDateEnabled: Binding<Bool>) {
            _selectedDate = selectedDate
            _dueDateEnabled = dueDateEnabled

            let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue))
                ?? selectedDate.wrappedValue
            _displayedMonth = State(initialValue: start)
        }

        var body: some View {
            VStack(alignment: .center, spacing: 12) {
                header
                weekdays
                daysGrid
                quickPills
            }
            .onChange(of: selectedDate) { _, newValue in
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: newValue)) ?? newValue
                displayedMonth = start
            }
        }

        private var header: some View {
            HStack {
                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text(monthTitle(displayedMonth))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.black.opacity(0.80))

                Spacer(minLength: 0)

                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        private var weekdays: some View {
            let symbols = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            return HStack(spacing: 0) {
                ForEach(symbols, id: \.self) { s in
                    Text(s)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.40))
                        .frame(maxWidth: .infinity)
                }
            }
        }

        private var daysGrid: some View {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
            let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2
            let daysInMonth = Array(range)

            let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
            let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
            let cells = Array(repeating: Optional<Int>.none, count: leadingBlanks) + daysInMonth.map(Optional.some)
            let rowCount = Int(ceil(Double(cells.count) / 7.0))
            let totalCells = rowCount * 7
            let padded = cells + Array(repeating: Optional<Int>.none, count: max(0, totalCells - cells.count))

            return VStack(spacing: 8) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let idx = row * 7 + col
                            dayCell(day: padded[idx], monthStart: monthStart)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }

        private func dayCell(day: Int?, monthStart: Date) -> some View {
            Group {
                if let day {
                    let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

                    Button {
                        dueDateEnabled = true
                        selectedDate = calendar.startOfDay(for: date)
                    } label: {
                        Text("\(day)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(isSelected ? Color.black.opacity(0.85) : Color.black.opacity(0.70))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(isSelected ? AddTaskOverlay.Visual.accentYellow : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(" ")
                        .frame(width: 32, height: 32)
                        .hidden()
                }
            }
        }

        private var quickPills: some View {
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today
            let selected = calendar.startOfDay(for: selectedDate)

            return HStack(spacing: 10) {
                quickPill(title: "Today", isActive: calendar.isDate(selected, inSameDayAs: today)) {
                    dueDateEnabled = true
                    selectedDate = today
                }
                quickPill(title: "Tomorrow", isActive: calendar.isDate(selected, inSameDayAs: tomorrow)) {
                    dueDateEnabled = true
                    selectedDate = tomorrow
                }
                quickPill(title: "Next Week", isActive: calendar.isDate(selected, inSameDayAs: nextWeek)) {
                    dueDateEnabled = true
                    selectedDate = nextWeek
                }
            }
            .padding(.top, 6)
        }

        private func quickPill(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isActive ? Color.black.opacity(0.85) : Color.black.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isActive ? AddTaskOverlay.Visual.accentYellow : Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }

        private func monthTitle(_ date: Date) -> String {
            let fmt = DateFormatters.monthTitle
            fmt.locale = Locale.current
            fmt.timeZone = TimeZone.current
            return fmt.string(from: date)
        }
    }

    private func quickDateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Visual.muted)
        }
        .buttonStyle(.plain)
    }

    private var priorityControl: some View {
        HStack(spacing: 0) {
            priorityPill(title: "Low", value: 0)
            priorityPill(title: "Med", value: 1)
            priorityPill(title: "High", value: 2)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(Visual.border, lineWidth: 1)
        )
    }

    private func priorityPill(title: String, value: Int16) -> some View {
        let isSelected = priority == value
        return Button {
            priority = value
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? Visual.orange : Visual.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var weightAndEffortRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("WEIGHT (%)")
                roundedField {
                    HStack(spacing: 10) {
                        TextField("0", text: $weightPercentText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Visual.text)
                            .onChange(of: weightPercentText) { _, newValue in
                                weightPercentText = newValue.filter { $0.isNumber }
                            }

                        Spacer(minLength: 0)

                        Text("%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Visual.muted)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("TIME ALLOCATION")

                HStack(spacing: 10) {
                    roundedField {
                        HStack(spacing: 10) {
                            TextField("0", text: $effortHoursText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Visual.text)
                                .onChange(of: effortHoursText) { _, newValue in
                                    effortHoursText = newValue.filter { $0.isNumber }
                                }

                            Spacer(minLength: 0)

                            Text("HR")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Visual.muted)
                        }
                    }

                    roundedField {
                        HStack(spacing: 10) {
                            TextField("0", text: $effortMinutesText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Visual.text)
                                .onChange(of: effortMinutesText) { _, newValue in
                                    effortMinutesText = newValue.filter { $0.isNumber }
                                }

                            Spacer(minLength: 0)

                            Text("MIN")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Visual.muted)
                        }
                    }
                }
            }
        }
    }

    private func roundedField<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Visual.fieldCorner, style: .continuous)
                .fill(Visual.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Visual.fieldCorner, style: .continuous)
                .stroke(Visual.border, lineWidth: 1)
        )
    }

    private func preferredHeightSizingProbe(maxWidth: CGFloat) -> some View {
        editorCardContent
            .padding(18)
            .frame(width: maxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: AddTaskOverlayPreferredHeightKey.self, value: proxy.size.height)
                }
            )
            .hidden()
    }

    private func save() {
        guard canSave else { return }

        // Keep the underlying Date in sync with what the user typed.
        syncDueDateFromText()

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let weightValue: Int? = {
            let t = weightPercentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Int(t)
        }()

        let effortHoursValue: Int? = {
            let t = effortHoursText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Int(t)
        }()

        let effortMinutesValue: Int? = {
            let t = effortMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Int(t)
        }()

        let gradingCategory: CourseGradingCategory? = {
            guard let id = selectedGradingCategoryID else { return nil }
            guard let course = selectedCourse() else { return nil }
            return plannerGradingCategories(for: course).first(where: { $0.id == id })
        }()

        let taskWeightPercent: Double? = weightValue.map(Double.init)

        let estimatedMinutes: Int32? = {
            let h = max(0, effortHoursValue ?? 0)
            let m = max(0, effortMinutesValue ?? 0)
            let total = h * 60 + m
            return total == 0 ? nil : Int32(total)
        }()

        let trimmedCategoryName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedCategoryName = trimmedCategoryName.isEmpty ? nil : trimmedCategoryName
        let categoryWeight = gradingCategory?.weightPercent

        let trimmedNotes = preservedUserNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        let calendarRepo = collegePersistence.calendarRepository
        let effectiveSemester = semester ?? selectedCourse()?.semester

        if let taskToEdit {
            try? calendarRepo.updatePlannerTask(
                id: taskToEdit.id,
                title: trimmedTitle,
                dueDate: dueDateEnabled ? dueDate : nil,
                semester: effectiveSemester,
                course: selectedCourse(),
                notes: notes,
                priority: priority,
                categoryName: storedCategoryName,
                gradingCategory: gradingCategory,
                categoryWeightPercent: categoryWeight,
                weightPercent: taskWeightPercent,
                estimatedEffortMinutes: estimatedMinutes
            )
            collegePersistence.notifyCalendarDidChange()
            collegePersistence.bumpProfileRevision()
            isPresented = false
            return
        }

        _ = try? calendarRepo.createPlannerTask(
            title: trimmedTitle,
            dueDate: dueDateEnabled ? dueDate : nil,
            semester: effectiveSemester,
            course: selectedCourse(),
            notes: notes,
            priority: priority,
            categoryName: storedCategoryName,
            gradingCategory: gradingCategory,
            categoryWeightPercent: categoryWeight,
            weightPercent: taskWeightPercent,
            estimatedEffortMinutes: estimatedMinutes
        )
        collegePersistence.notifyCalendarDidChange()
        collegePersistence.bumpProfileRevision()

        isPresented = false
    }

    var body: some View {
        ZStack {
            if presentationStyle == .fullScreenOverlay {
                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .ignoresSafeArea()
                    .onTapGesture { requestDismiss() }
            }

            GeometryReader { geometry in
                let maxWidth = (presentationStyle == .fullScreenOverlay)
                    ? min(geometry.size.width * 0.92, 760)
                    : min(geometry.size.width, 560)
                let maxHeight = (presentationStyle == .fullScreenOverlay)
                    ? min(geometry.size.height * 0.90, 620)
                    : min(geometry.size.height, 560)

                editorCard(maxWidth: maxWidth, maxHeight: maxHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: presentationStyle == .fullScreenOverlay ? .center : .topLeading)
            }
        }
        .onAppear { syncCategorySelectionForCourse() }
        .onChange(of: selectedCourseID) { _, _ in
            syncCategorySelectionForCourse()
        }
        .confirmationDialog(
            "Delete Task?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let taskToEdit else { return }
                try? collegePersistence.calendarRepository.deletePlannerTask(id: taskToEdit.id)
                collegePersistence.notifyCalendarDidChange()
                collegePersistence.bumpProfileRevision()
                isPresented = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Discard changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                isPresented = false
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Your changes haven’t been saved.")
        }
    }

    private func syncCategorySelectionForCourse() {
        let options = categoryOptions

        if let selectedGradingCategoryID,
           !options.contains(where: { $0.gradingCategoryID == selectedGradingCategoryID }) {
            self.selectedGradingCategoryID = nil
        }

        // If the name matches a syllabus-derived category, prefer linking it.
        if self.selectedGradingCategoryID == nil {
            let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let match = options.first(where: { $0.gradingCategoryID != nil && $0.label.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                self.selectedGradingCategoryID = match.gradingCategoryID
            }
        }

        // If nothing is selected yet, pick the first available option.
        if categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let first = options.first {
            categoryName = first.label
            selectedGradingCategoryID = first.gradingCategoryID
        }
    }

    private func editorCard(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        editorCardContent
        .padding(18)
        .frame(width: maxWidth, height: maxHeight)
        .background {
            if presentationStyle == .anchoredPanel {
                preferredHeightSizingProbe(maxWidth: maxWidth)
            }
        }
        .background(Visual.card)
        .cornerRadius(Visual.corner)
        .overlay(
            RoundedRectangle(cornerRadius: Visual.corner)
                .stroke(Visual.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(presentationStyle == .fullScreenOverlay ? 0.18 : 0.12), radius: presentationStyle == .fullScreenOverlay ? 28 : 18, x: 0, y: presentationStyle == .fullScreenOverlay ? 18 : 12)
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Visual.accentYellowSoft)
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.circle.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.65))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(taskToEdit == nil ? "Create Task" : "Edit Task")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Visual.text)

                Text(taskToEdit == nil ? "Add a new assignment to your schedule" : "Update details for your task")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Visual.muted)
            }

            Spacer(minLength: 0)

            Button(action: { requestDismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Visual.muted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 14) {
            if taskToEdit != nil {
                Button("Delete") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Visual.muted)
            }

            Spacer(minLength: 0)

            Button(action: { save() }) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Save Task")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(Color.black.opacity(0.80))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(canSave ? Visual.accentYellow : Visual.accentYellow.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Visual.muted)
            .kerning(1)
    }

    private func formattedDate(_ date: Date) -> String {
        Self.formatDueDateDisplay(date)
    }
}
