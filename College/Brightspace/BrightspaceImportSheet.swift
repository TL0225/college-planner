import SwiftUI
import CoreData

// MARK: - BrightspaceImportSheet
// Context-aware sheet that lets users selectively import assignments,
// grades, or announcements detected on the current Brightspace page.

struct BrightspaceImportSheet: View {
    @Binding var items: [BrightspaceImportItem]
    @Binding var isPresented: Bool

    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    @State private var allCourses: [CourseEntity] = []
    @State private var courseSelections: [String: CourseEntity?] = [:]  // itemID → course
    @State private var isImporting: Bool = false
    @State private var importError: String? = nil

    private var pageType: BrightspacePageType {
        items.first?.pageType ?? .other
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sheetTitle)
                        .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    Text("\(items.filter(\.isSelected).count) of \(items.count) item(s) selected")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Items list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items.indices, id: \.self) { idx in
                        ImportItemRow(
                            item: $items[idx],
                            courses: allCourses,
                            selectedCourse: Binding(
                                get: { courseSelections[items[idx].id] ?? nil },
                                set: { courseSelections[items[idx].id] = $0 }
                            )
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 400)

            Divider()

            // Footer
            HStack {
                Button(action: { selectAll(false) }) {
                    Text("Deselect All")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .buttonStyle(.plain)

                Button(action: { selectAll(true) }) {
                    Text("Select All")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { isPresented = false }) {
                    Text("Cancel")
                }
                .keyboardShortcut(.escape)

                Button(action: performImport) {
                    HStack(spacing: 5) {
                        if isImporting {
                            ProgressView().scaleEffect(0.6)
                        }
                        Text("Import")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "4f46e5"))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isImporting || items.filter(\.isSelected).isEmpty)
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.bgMain)
        .frame(minWidth: 500, minHeight: 300)
        .onAppear(perform: loadCourses)
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Computed

    private var sheetTitle: String {
        switch pageType {
        case .assignment:    return "Import Assignment"
        case .grades:        return "Import Grades"
        case .announcement:  return "Import Announcement"
        default:             return "Import from Brightspace"
        }
    }

    // MARK: - Actions

    private func loadCourses() {
        let request = NSFetchRequest<CourseEntity>(entityName: "CourseEntity")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CourseEntity.code, ascending: true)]
        allCourses = (try? coreDataManager.viewContext.fetch(request)) ?? []

        // Pre-match course codes
        for item in items {
            let matched = matchCourse(for: item)
            courseSelections[item.id] = matched
        }
    }

    private func matchCourse(for item: BrightspaceImportItem) -> CourseEntity? {
        // Use courseCode hint if available, otherwise try to match from title
        let needle = item.courseCode ?? String(item.title.prefix(while: { $0.isLetter || $0.isNumber }))
        guard !needle.isEmpty else { return nil }
        return allCourses.first { ($0.code ?? "").localizedCaseInsensitiveContains(needle) }
    }

    private func selectAll(_ value: Bool) {
        for idx in items.indices {
            items[idx].isSelected = value
        }
    }

    // Known valid letter grade values for validation
    private static let validLetterGrades: Set<String> = [
        "A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-",
        "D+", "D", "D-", "F", "P", "NP", "I", "W", "WF"
    ]

    private func performImport() {
        isImporting = true
        let selected = items.filter(\.isSelected)

        Task { @MainActor in
            var importedCount = 0
            var firstError: String? = nil
            var importedAnnouncements: [CalendarEventEntity] = []

            for item in selected {
                let course = courseSelections[item.id] ?? nil

                do {
                    switch item.pageType {
                    case .assignment:
                        // Skip duplicates keyed by brightspaceItemId
                        if !coreDataManager.taskExists(brightspaceItemId: item.brightspaceItemId) {
                            let task = coreDataManager.addTask(
                                title: item.title,
                                dueDate: item.dueDate,
                                semester: course?.semester,
                                course: course,
                                notes: item.description
                            )
                            task.setValue(item.brightspaceItemId, forKey: "brightspaceItemId")
                            importedCount += 1
                        }

                    case .grades:
                        if let course {
                            // `description` holds letterGrade, `points` holds percentage (mapped in coordinator)
                            let letterGrade = item.description?.trimmingCharacters(in: .whitespaces)
                            let percentage  = item.points?.replacingOccurrences(of: "%", with: "")
                                                           .trimmingCharacters(in: .whitespaces)

                            // Prefer validated letter grade; fall back to percentage as a label
                            if let lg = letterGrade, Self.validLetterGrades.contains(lg) {
                                course.grade = lg
                                importedCount += 1
                            } else if let pct = percentage, !pct.isEmpty, Double(pct) != nil {
                                course.grade = pct + "%"
                                importedCount += 1
                            }
                            // If neither is valid, skip silently (don't overwrite with garbage)
                        }

                    case .announcement:
                        // Dedup by brightspaceAnnouncementId
                        if !coreDataManager.announcementExists(brightspaceAnnouncementId: item.brightspaceItemId) {
                            let start = item.dueDate ?? Date()
                            let end   = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
                            let event = coreDataManager.addCalendarEvent(
                                title: item.title,
                                startDate: start,
                                endDate: end,
                                allDay: item.dueDate == nil,
                                semester: course?.semester,
                                course: course,
                                notes: item.description
                            )
                            event.setValue(item.brightspaceItemId, forKey: "brightspaceAnnouncementId")
                            importedAnnouncements.append(event)
                            importedCount += 1
                        }

                    default:
                        break
                    }
                } catch {
                    if firstError == nil {
                        firstError = "Failed to import \"\(item.title)\": \(error.localizedDescription)"
                    }
                }
            }

            if importedCount > 0 {
                coreDataManager.save()
                for event in importedAnnouncements {
                    calendarManager.exportEventToGoogle(event)
                    calendarManager.exportEventToAppleCalendar(event)
                }
            }

            isImporting = false
            isPresented = false
            items = []

            if let err = firstError {
                importError = err
            } else if importedCount > 0 {
                appNotifications.post(
                    kind: .success,
                    title: "Brightspace Import",
                    message: "\(importedCount) item(s) imported successfully."
                )
            }
        }
    }
}

// MARK: - ImportItemRow

private struct ImportItemRow: View {
    @Binding var item: BrightspaceImportItem
    let courses: [CourseEntity]
    @Binding var selectedCourse: CourseEntity?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(2)

                if let due = item.dueDate {
                    Label(ImportItemRow.dateFormatter.string(from: due), systemImage: "calendar")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }

                if let pts = item.points {
                    Label(pts, systemImage: "star")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Course picker
            if !courses.isEmpty {
                Picker("", selection: $selectedCourse) {
                    Text("No Course").tag(CourseEntity?.none)
                    ForEach(courses, id: \.objectID) { course in
                        Text(course.code ?? course.name ?? "Course")
                            .tag(CourseEntity?.some(course))
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .font(DesignSystem.Fonts.main(size: 11))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.isSelected ? Color(hex: "4f46e5").opacity(0.04) : DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.isSelected ? Color(hex: "4f46e5").opacity(0.15) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { item.isSelected.toggle() }
    }
}
