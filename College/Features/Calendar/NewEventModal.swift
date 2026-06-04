// NewEventModal.swift
// Feature: Calendar
// Purpose: Calendar module — NewEventModal.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Clean centered pop-up modal for creating a new calendar event.
struct NewEventModal: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isPresented: Bool
    let semester: PlannerSemester?
    let initialTitle: String?
    let initialStart: Date?
    let initialEnd: Date?

    // MARK: – Form state
    @State private var title: String = ""
    @State private var calendarSource: String = "University Schedule"
    @State private var allDay: Bool = false
    @State private var startDateTime: Date = Date()
    @State private var endDateTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var location: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var notes: String = ""

    // MARK: – Design tokens
    private let colorPresets: [(Color, String)] = [
        (Color(hex: "6366f1"), "6366f1"),
        (Color(hex: "14b8a6"), "14b8a6"),
        (Color(hex: "f59e0b"), "f59e0b"),
        (Color(hex: "f43f5e"), "f43f5e"),
        (Color(hex: "9ca3af"), "9ca3af")
    ]

    private let calendarSources = [
        "University Schedule",
        "Personal",
        "Study Groups",
        "Work"
    ]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: – Body
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { dismiss() }

            // Card
            VStack(spacing: 0) {
                cardHeader
                Divider().overlay(Color(hex: "f3f4f6"))

                ScrollView(.vertical, showsIndicators: false) {
                    cardForm
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }

                Divider().overlay(Color(hex: "f3f4f6"))
                cardFooter
            }
            .frame(width: 480)
            .frame(maxHeight: 660)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.14), radius: 40, x: 0, y: 16)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
        }
        .onAppear { applyPrefill() }
    }

    // MARK: – Sections

    private var cardHeader: some View {
        HStack {
            Text("New Event")
                .font(.custom("Georgia", size: 20))
                .fontWeight(.bold)
                .foregroundColor(Color(hex: "111827"))

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "9ca3af"))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: "f3f4f6"))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var cardForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Event Title
            formSection(label: "Event Title") {
                TextField("Final Exam Review", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color(hex: "111827"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "f9fafb"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Calendar
            formSection(label: "Calendar") {
                Menu {
                    ForEach(calendarSources, id: \.self) { source in
                        Button(source) { calendarSource = source }
                    }
                } label: {
                    HStack {
                        Text(calendarSource)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "374151"))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "9ca3af"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "f9fafb"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
            }

            // All Day
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Day")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "111827"))
                    Text("This event lasts the entire day")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "9ca3af"))
                }
                Spacer()
                Toggle("", isOn: $allDay)
                    .toggleStyle(.switch)
                    .tint(Color(hex: "6366f1"))
                    .labelsHidden()
            }

            // Starts
            formSection(label: "Starts") {
                dateTimeRow(date: $startDateTime, includeTime: !allDay)
            }

            // Ends
            formSection(label: "Ends") {
                dateTimeRow(date: $endDateTime, includeTime: !allDay)
            }

            // Location
            formSection(label: "Location") {
                HStack(spacing: 8) {
                    Image(systemName: "location")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "9ca3af"))
                    TextField("Add location or room number", text: $location)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "374151"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "f9fafb"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Color Label
            formSection(label: "Color Label") {
                HStack(spacing: 12) {
                    ForEach(colorPresets.indices, id: \.self) { index in
                        let (color, _) = colorPresets[index]
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedColorIndex = index
                            }
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(color, lineWidth: selectedColorIndex == index ? 2.5 : 0)
                                        .padding(-4)
                                )
                                .scaleEffect(selectedColorIndex == index ? 1.1 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Notes
            formSection(label: "Notes") {
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Add description or notes...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "9ca3af"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    TextEditor(text: $notes)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "374151"))
                        .frame(minHeight: 80, maxHeight: 100)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                }
                .background(Color(hex: "f9fafb"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", action: dismiss)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "6b7280"))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .buttonStyle(.plain)
                .onHover { hovering in
                    // handled by hover modifier below
                }

            Button("Create Event", action: save)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(canSave ? Color(hex: "4f46e5") : Color(hex: "a5b4fc"))
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .shadow(color: Color(hex: "6366f1").opacity(0.30), radius: 10, x: 0, y: 4)
                .disabled(!canSave)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(hex: "f9fafb"))
    }

    // MARK: – Helpers

    @ViewBuilder
    private func formSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Color(hex: "9ca3af"))
            content()
        }
    }

    @ViewBuilder
    private func dateTimeRow(date: Binding<Date>, includeTime: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9ca3af"))
                DatePicker("", selection: date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color(hex: "6366f1"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hex: "f9fafb"))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if includeTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "9ca3af"))
                    DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Color(hex: "6366f1"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(hex: "f9fafb"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: – Actions

    private func applyPrefill() {
        if let t = initialTitle, !t.isEmpty { title = t }
        if let s = initialStart {
            startDateTime = s
            endDateTime = initialEnd ?? (Calendar.current.date(byAdding: .hour, value: 1, to: s) ?? s)
        } else if let e = initialEnd {
            endDateTime = e
        }
    }

    private func dismiss() {
        if reduceMotion {
            isPresented = false
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                isPresented = false
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            AppNotificationCenter.shared.post(
                kind: .warning,
                title: "Missing Title",
                message: "Please enter an event title",
                autoDismissAfter: 3
            )
            return
        }

        let cal = Calendar.current
        let start: Date
        let end: Date
        if allDay {
            start = cal.startOfDay(for: startDateTime)
            end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        } else {
            start = startDateTime
            let minEnd = cal.date(byAdding: .minute, value: 15, to: start) ?? start
            end = max(endDateTime, minEnd)
        }

        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let createdID = collegePersistence.addCalendarEvent(
            title: trimmedTitle,
            startDate: start,
            endDate: end,
            allDay: allDay,
            semester: semester,
            course: nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            location: trimmedLocation.isEmpty ? nil : trimmedLocation
        )

        // Apply chosen color override
        let (_, colorHex) = colorPresets[selectedColorIndex]
        EventColorOverrides.setColor(Color(hex: colorHex), for: createdID)

        AppNotificationCenter.shared.post(
            kind: .success,
            title: "Event Created",
            message: "\(trimmedTitle) added to your calendar",
            autoDismissAfter: 3
        )

        dismiss()
    }
}
