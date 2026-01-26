import SwiftUI
import CoreData

/// Add/edit task UI used by the Calendar page.
struct AddTaskOverlay: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager

    enum PresentationStyle {
        case fullScreenOverlay
        case anchoredPanel
    }

    @Binding var isPresented: Bool
    let semester: SemesterEntity?
    let taskToEdit: TaskEntity?
    let presentationStyle: PresentationStyle

    @State private var title: String = ""
    @State private var hasDueDate: Bool = true
    @State private var dueDate: Date = Date()
    @State private var notesText: String = ""
    @State private var selectedCourseID: NSManagedObjectID? = nil
    @State private var priority: Int16 = 0

    @State private var showDeleteConfirmation: Bool = false
    @State private var showDiscardConfirmation: Bool = false

    private struct Snapshot: Equatable {
        let title: String
        let hasDueDate: Bool
        let dueDate: Date
        let notes: String
        let courseID: NSManagedObjectID?
        let priority: Int16
    }

    private let initialSnapshot: Snapshot

    private var courses: [CourseEntity] { semester?.coursesArray ?? [] }

    init(
        isPresented: Binding<Bool>,
        semester: SemesterEntity?,
        taskToEdit: TaskEntity? = nil,
        presentationStyle: PresentationStyle = .fullScreenOverlay
    ) {
        _isPresented = isPresented
        self.semester = semester
        self.taskToEdit = taskToEdit
        self.presentationStyle = presentationStyle

        if let taskToEdit {
            let initialDue = taskToEdit.dueDate ?? Date()
            let initialHasDue = taskToEdit.dueDate != nil

            _title = State(initialValue: taskToEdit.title ?? "")
            _hasDueDate = State(initialValue: initialHasDue)
            _dueDate = State(initialValue: initialDue)
            _notesText = State(initialValue: taskToEdit.notes ?? "")
            _selectedCourseID = State(initialValue: taskToEdit.course?.objectID)
            _priority = State(initialValue: taskToEdit.priority)

            initialSnapshot = Snapshot(
                title: (taskToEdit.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                hasDueDate: initialHasDue,
                dueDate: initialDue,
                notes: (taskToEdit.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                courseID: taskToEdit.course?.objectID,
                priority: taskToEdit.priority
            )
        } else {
            initialSnapshot = Snapshot(
                title: "",
                hasDueDate: true,
                dueDate: Date(),
                notes: "",
                courseID: nil,
                priority: 0
            )
        }
    }

    private func selectedCourse() -> CourseEntity? {
        guard let id = selectedCourseID else { return nil }
        return (try? coreDataManager.viewContext.existingObject(with: id)) as? CourseEntity
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentSnapshot: Snapshot {
        Snapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            hasDueDate: hasDueDate,
            dueDate: dueDate,
            notes: notesText.trimmingCharacters(in: .whitespacesAndNewlines),
            courseID: selectedCourseID,
            priority: priority
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

    private var editorCardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Title")
                TextField("Task", text: $title)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
                    .cornerRadius(10)

                HStack {
                    fieldLabel("Due Date")
                    Spacer()
                    Toggle("", isOn: $hasDueDate)
                        .labelsHidden()
                }

                if hasDueDate {
                    DatePicker("", selection: $dueDate)
                        .labelsHidden()
                }

                fieldLabel("Course")
                Picker(selection: $selectedCourseID) {
                    Text("None").tag(NSManagedObjectID?.none)
                    ForEach(courses, id: \.objectID) { course in
                        Text(course.code ?? course.name ?? "Course")
                            .tag(Optional(course.objectID))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(MenuPickerStyle())

                fieldLabel("Priority")
                Picker(selection: $priority) {
                    Text("Normal").tag(Int16(0))
                    Text("High").tag(Int16(1))
                    Text("Urgent").tag(Int16(2))
                } label: {
                    EmptyView()
                }
                .pickerStyle(SegmentedPickerStyle())

                fieldLabel("Notes")
                TextEditor(text: $notesText)
                    .font(DesignSystem.Fonts.main(size: 12))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
                    .cornerRadius(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if presentationStyle == .fullScreenOverlay {
                Spacer(minLength: 0)
            }

            footerRow
        }
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
        guard let taskToEdit else {
            // Calendar currently only edits existing tasks.
            isPresented = false
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        coreDataManager.updateTask(
            objectID: taskToEdit.objectID,
            title: trimmedTitle,
            dueDate: hasDueDate ? dueDate : nil,
            semester: semester,
            course: selectedCourse(),
            notes: notes,
            priority: priority
        )

        isPresented = false
    }

    var body: some View {
        ZStack {
            if presentationStyle == .fullScreenOverlay {
                Rectangle()
                    .fill(Color.black.opacity(0.60))
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
        .confirmationDialog(
            "Delete Task?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let taskToEdit else { return }
                coreDataManager.deleteTask(objectID: taskToEdit.objectID)
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

    private func editorCard(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        editorCardContent
        .padding(18)
        .frame(width: maxWidth, height: maxHeight)
        .background {
            if presentationStyle == .anchoredPanel {
                preferredHeightSizingProbe(maxWidth: maxWidth)
            }
        }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(presentationStyle == .fullScreenOverlay ? 0.25 : 0.14), radius: presentationStyle == .fullScreenOverlay ? 28 : 18)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text(taskToEdit == nil ? "Task" : "Edit Task")
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Spacer(minLength: 0)

            Button(action: { requestDismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            if taskToEdit != nil {
                Button("Delete") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(PlainButtonStyle())
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
                .cornerRadius(12)
            }

            Spacer(minLength: 0)

            Button("Cancel") { requestDismiss() }
                .buttonStyle(PlainButtonStyle())
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
                .cornerRadius(12)

            Button("Save") { save() }
                .buttonStyle(PlainButtonStyle())
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(canSave ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight.opacity(0.25))
                .cornerRadius(12)
                .disabled(!canSave)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
            .foregroundColor(DesignSystem.Colors.textLight)
            .textCase(.uppercase)
    }
}
