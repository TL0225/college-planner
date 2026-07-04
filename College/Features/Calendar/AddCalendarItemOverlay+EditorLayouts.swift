// AddCalendarItemOverlay+EditorLayouts.swift
// Feature: Calendar
// Purpose: Bottom-sheet and floating-cards editor layouts (Phase 6 decomposition).

import CollegeCalendar
import SwiftUI
import Contacts
import MapKit
import UniformTypeIdentifiers

extension AddCalendarItemOverlay {
    var bottomSheetEditorContent: some View {
        VStack(spacing: 0) {
            bottomSheetHeader
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Group {
                if isExpanded {
                    ViewThatFits(in: .vertical) {
                        bottomSheetExpandedContent

                        ScrollView {
                            bottomSheetExpandedContent
                        }
                    }
                } else {
                    bottomSheetMainFields
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().overlay(Color(hex: "f1f5f9"))

            bottomSheetFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: outerContainerCornerRadius, style: .continuous)
                .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
        )
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: isExpanded)
    }

    var bottomSheetExpandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            bottomSheetMainFields
            bottomSheetMoreOptionsExpanded
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var bottomSheetMainFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            bottomSheetTitleField
            bottomSheetCourseAndLocationRow
            bottomSheetDateAndTimeRow
            if !calendarManager.connectedCalendars.filter({ $0.source == "Google" }).isEmpty {
                bottomSheetCalendarPicker
            }
            bottomSheetMoreOptionsToggle
        }
    }

    var bottomSheetCalendarPicker: some View {
        let googleCals = calendarManager.connectedCalendars.filter { $0.source == "Google" }
        let selectedName = googleCals.first { $0.remoteID == selectedGoogleCalendarID }?.name
            ?? googleCals.first?.name
            ?? "Google Calendar"
        return VStack(alignment: .leading, spacing: 6) {
            Text("SAVE TO")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))
            Menu {
                ForEach(googleCals, id: \.id) { cal in
                    Button {
                        selectedGoogleCalendarID = cal.remoteID
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(cal.color)
                                .font(DesignSystem.Fonts.main(size: 10))
                            Text(cal.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primary)
                    Text(selectedName)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    var bottomSheetMoreOptionsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Text("More Options")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    var bottomSheetMoreOptionsExpanded: some View {
        VStack(alignment: .leading, spacing: 14) {
            bottomSheetNotesSection

            HStack(alignment: .top, spacing: 14) {
                bottomSheetColorTagSection
                bottomSheetAlertsSection
            }

            bottomSheetAttachmentsSection
        }
        .padding(.top, 6)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
    }

    var bottomSheetNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $descriptionText)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(minHeight: 86)

                if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add detailed notes about the event...")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                        .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(subtleStrokeColor.opacity(0.55), lineWidth: 1)
            )
        }
    }

    var bottomSheetColorTagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COLOR TAG")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

            HStack(spacing: 10) {
                ForEach(Array(AddCalendarItemOverlay.presetEventColors.enumerated()), id: \.offset) { index, color in
                    Button {
                        applySelectedColor(color, choice: .preset(index))
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(
                                    DesignSystem.Colors.textMain.opacity(isColorSelection(index: index) ? 0.25 : 0.0),
                                    lineWidth: 3
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func isColorSelection(index: Int) -> Bool {
        if case .preset(let selectedIndex) = eventColorChoice {
            return selectedIndex == index
        }
        return false
    }

    var bottomSheetAlertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALERTS")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

            Menu {
                Button("None") { alertLeadMinutes = [] }
                Divider()
                ForEach(supportedAlertOffsets, id: \.self) { minutes in
                    Button {
                        toggleAlertOffset(minutes)
                    } label: {
                        if reminderScheduleMinutes.contains(minutes) {
                            Label(reminderSummaryText([minutes]), systemImage: "checkmark")
                        } else {
                            Text(reminderSummaryText([minutes]))
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)

                    Text(reminderSummaryText())
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain.opacity(0.85))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(subtleStrokeColor.opacity(0.55), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var bottomSheetAttachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ATTACHMENTS")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

            Button {
                isShowingFileImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)

                    Text("Click to upload")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textMain.opacity(0.85))

                    Text("or drag and drop")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                        .foregroundStyle(DesignSystem.Colors.textLight)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            subtleStrokeColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    var bottomSheetHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(eventToEdit == nil ? "New Event" : "Edit Event")
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Spacer(minLength: 0)

            Button {
                requestDismissAnimated()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    var bottomSheetTitleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EVENT TITLE")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

            TextField("", text: $title, prompt: Text("e.g., Midterm Exam").foregroundStyle(DesignSystem.Colors.textLight.opacity(0.75)))
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                )
        }
    }

    var bottomSheetCourseAndLocationRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("COURSE")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

                bottomSheetCourseMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("LOCATION")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

                bottomSheetLocationField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var bottomSheetCourseMenu: some View {
        let selected = selectedCourse()
        let labelText: String = {
            guard let selected else { return "No course" }
            let code = selected.code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { return code }
            let name = selected.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Course" : name
        }()

        return Menu {
            Button("No course") {
                selectedCourseID = nil
            }

            Button("Search or add course…") {
                openCourseSearchOrBuilder()
            }

            if !allCourses.isEmpty {
                Divider()
                ForEach(allCourses, id: \.id) { course in
                    Button {
                        selectedCourseID = course.id
                        if !isColorOverridden {
                            setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: course))
                        }
                    } label: {
                        let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !code.isEmpty && !name.isEmpty {
                            Text("\(code) — \(name)")
                        } else if !code.isEmpty {
                            Text(code)
                        } else if !name.isEmpty {
                            Text(name)
                        } else {
                            Text("Course")
                        }
                    }
                }
            } else {
                Divider()
                Button("No courses available") { }
                    .disabled(true)
            }
        } label: {
            HStack(spacing: 8) {
                Text(labelText)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    var bottomSheetLocationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.9))

                TextField("", text: $location, prompt: Text("Add location").foregroundStyle(DesignSystem.Colors.textLight.opacity(0.75)))
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .focused($focusedLocationInput, equals: .bottomSheet)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
            )

            if !locationSuggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(locationSuggestions.prefix(5).enumerated()), id: \.element.id) { index, option in
                            Button {
                                highlightedLocationSuggestionIndex = index
                                applyLocationSuggestion(option)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.circle")
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.displayName)
                                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                            .foregroundStyle(DesignSystem.Colors.textMain)
                                            .lineLimit(1)
                                        if !option.subtitle.isEmpty {
                                            Text(option.subtitle)
                                                .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                                .foregroundStyle(DesignSystem.Colors.textLight)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 6)
                                    if let distanceLabel = distanceText(for: option) {
                                        Text(distanceLabel)
                                            .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                                            .foregroundStyle(DesignSystem.Colors.textLight)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(index == highlightedLocationSuggestionIndex ? Color.black.opacity(0.06) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                )
            }
        }
    }

    var bottomSheetDateAndTimeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DATE")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

                bottomSheetDateField
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("TIME")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.8))

                HStack(spacing: 10) {
                    bottomSheetTimeField(selection: $startDateTime, showsDurationFrom: nil) { newStart in
                        let calendar = Calendar.current
                        startDateTime = newStart
                        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                        if endDateTime < minimumEnd {
                            endDateTime = minimumEnd
                        }
                    }

                    bottomSheetTimeField(selection: $endDateTime, showsDurationFrom: startDateTime) { newEnd in
                        let calendar = Calendar.current
                        var adjusted = newEnd
                        if adjusted <= startDateTime {
                            adjusted = calendar.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
                        }
                        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                        if adjusted < minimumEnd {
                            adjusted = minimumEnd
                        }
                        endDateTime = adjusted
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(allDay ? 0.92 : 1)
    }

    var bottomSheetDateField: some View {
        let dateBinding = Binding<Date>(
            get: { Calendar.current.startOfDay(for: startDateTime) },
            set: { newDay in
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: startDateTime)
                let minute = calendar.component(.minute, from: startDateTime)
                let duration = max(15 * 60, endDateTime.timeIntervalSince(startDateTime))
                let newStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
                startDateTime = newStart
                endDateTime = newStart.addingTimeInterval(duration)
            }
        )

        return HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.9))

            DatePicker("", selection: dateBinding, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.field)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        )
    }

    func bottomSheetTimeField(
        selection: Binding<Date>,
        showsDurationFrom: Date?,
        onSelect: @escaping (Date) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TimeMenuField(
                selection: selection,
                isDisabled: allDay,
                fontSize: 13,
                textColor: DesignSystem.Colors.textMain,
                showsDurationFrom: showsDurationFrom,
                onSelect: onSelect
            )

            Spacer(minLength: 0)

            Image(systemName: "clock")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        )
    }

    var bottomSheetAllDayRow: some View {
        HStack(spacing: 10) {
            Text("All day")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Spacer(minLength: 0)

            Toggle("", isOn: $allDay)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.success))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "f8fafc"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        )
    }

    var bottomSheetFooter: some View {
        HStack(spacing: 12) {
            Button {
                requestDismissAnimated()
            } label: {
                Text("Cancel")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    Text(eventToEdit == nil ? "Create Event" : "Save")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)
        }
    }

    // MARK: - Google Calendar-style editor (floatingCards presentation)

    var verticalFloatingCardsContent: some View {
        VStack(spacing: 0) {
            gcTitleBar
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    gcDateTimeSection
                    gcInsetDivider
                    gcLocationSection
                    gcInsetDivider
                    gcGuestsSection
                    gcInsetDivider
                    gcCalendarSection
                    gcInsetDivider
                    gcColorSection
                    gcInsetDivider
                    gcNotesSection
                    gcInsetDivider
                    gcReminderSection
                }
                .padding(.vertical, 4)
            }
            // fixedSize makes the ScrollView use its content's natural height
            // instead of greedily expanding to fill whatever the parent offers.
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            gcFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 30, x: 0, y: 10)
        // Do NOT use .frame(maxHeight: .infinity) — that creates a circular
        // dependency where the content fills the panel height, the GeometryReader
        // reports that height back, and the panel never shrinks to fit content.
        // Natural sizing lets the GR measure intrinsic content height correctly.
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // Title bar: close button + large title field + optional delete
    var gcTitleBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { requestDismissAnimated() } label: {
                    Image(systemName: "xmark")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
                if eventToEdit != nil {
                    Button { deleteEventNow() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                    .help("Delete event")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            TextField(
                "Add title",
                text: $title,
                prompt: Text("Add title").foregroundStyle(Color.secondary.opacity(0.55))
            )
            .textFieldStyle(.plain)
            .font(DesignSystem.Fonts.main(size: 22, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // Shared icon-row layout used by all sections
    func gcRow<Content: View>(
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(DesignSystem.Fonts.main(size: 15, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // Divider inset to align with text content column
    var gcInsetDivider: some View {
        Divider().padding(.leading, 52)
    }

    // ── Date & Time ──────────────────────────────────────────────────────────
    var gcDateTimeSection: some View {
        gcRow(icon: "clock", iconColor: Color(hex: "1a73e8")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(startDateTime.formatted(
                    .dateTime.weekday(.wide).month(.wide).day().year()
                ))
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(.primary)

                if !allDay {
                    HStack(spacing: 6) {
                        TimeMenuField(
                            selection: $startDateTime,
                            isDisabled: false,
                            fontSize: 13,
                            textColor: DesignSystem.Colors.primary,
                            showsDurationFrom: nil,
                            onSelect: { newStart in
                                startDateTime = newStart
                                let minEnd = Calendar.current.date(byAdding: .minute, value: 15, to: newStart) ?? newStart
                                if endDateTime < minEnd { endDateTime = minEnd }
                            }
                        )
                        Text("–")
                            .font(DesignSystem.Fonts.main(size: 13))
                            .foregroundStyle(.secondary)
                        TimeMenuField(
                            selection: $endDateTime,
                            isDisabled: false,
                            fontSize: 13,
                            textColor: DesignSystem.Colors.primary,
                            showsDurationFrom: startDateTime,
                            onSelect: { newEnd in
                                var adj = newEnd
                                if adj <= startDateTime {
                                    adj = Calendar.current.date(byAdding: .day, value: 1, to: adj) ?? adj
                                }
                                let minEnd = Calendar.current.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                                if adj < minEnd { adj = minEnd }
                                endDateTime = adj
                            }
                        )
                    }
                }

                Toggle(isOn: $allDay) {
                    Text("All day")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
            }
        }
    }

    // ── Location ─────────────────────────────────────────────────────────────
    var gcLocationSection: some View {
        Button {
            isShowingLocationPicker = true
            locationSearchService.query = ""
            locationSearchService.applyLocationBias(from: locationPermissionService.lastLocation)
        } label: {
            gcRow(icon: "mappin", iconColor: Color(hex: "ea4335")) {
                let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(loc.isEmpty ? "Add location" : loc)
                    .font(DesignSystem.Fonts.main(size: 13))
                    .foregroundStyle(loc.isEmpty ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }

    // ── Guests ───────────────────────────────────────────────────────────────
    var gcGuestsSection: some View {
        gcRow(icon: "person", iconColor: Color(hex: "5f6368")) {
            if selectedGuests.isEmpty {
                Button { showContactPicker() } label: {
                    Text("Add guests")
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedGuests, id: \.identifier) { guest in
                        HStack(spacing: 10) {
                            if let data = guest.thumbnailImageData, let img = NSImage(data: data) {
                                Image(nsImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 28, height: 28).clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable().frame(width: 28, height: 28)
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CNContactFormatter.string(from: guest, style: .fullName) ?? "")
                                    .font(DesignSystem.Fonts.main(size: 13)).foregroundStyle(.primary)
                                if let email = guest.emailAddresses.first?.value as String? {
                                    Text(email).font(DesignSystem.Fonts.main(size: 11))
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button { removeGuest(guest) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(DesignSystem.Fonts.main(size: 14))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { showContactPicker() } label: {
                        Label("Add more guests", systemImage: "plus")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Calendar picker ───────────────────────────────────────────────────────
    var gcCalendarSection: some View {
        gcRow(icon: "calendar", iconColor: Color(hex: "1a73e8")) {
            let googleCals = calendarManager.connectedCalendars.filter { $0.source == "Google" }
            let selectedName = googleCals.first { $0.remoteID == selectedGoogleCalendarID }?.name
                ?? googleCals.first?.name
                ?? "Calendar"
            if googleCals.isEmpty {
                Text("Calendar")
                    .font(DesignSystem.Fonts.main(size: 13)).foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(googleCals, id: \.id) { cal in
                        Button { selectedGoogleCalendarID = cal.remoteID } label: {
                            Label(cal.name, systemImage: "circle.fill")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedName).font(DesignSystem.Fonts.main(size: 13)).foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    // current event display color (always tracks customColor)
    var currentDisplayColor: Color { customColor }

    // ── Color ────────────────────────────────────────────────────────────────
    var gcColorSection: some View {
        gcRow(icon: "circle.fill", iconColor: currentDisplayColor) {
            HStack(spacing: 12) {
                ForEach(Array(AddCalendarItemOverlay.presetEventColors.enumerated()), id: \.offset) { idx, col in
                    Button { applySelectedColor(col, choice: .preset(idx)) } label: {
                        ZStack {
                            Circle().fill(col).frame(width: 20, height: 20)
                            if eventColorChoice == .preset(idx) {
                                Circle().stroke(col, lineWidth: 2).frame(width: 25, height: 25)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // ── Notes / Description ───────────────────────────────────────────────────
    var gcNotesSection: some View {
        gcRow(icon: "text.alignleft", iconColor: Color(hex: "5f6368")) {
            ZStack(alignment: .topLeading) {
                if descriptionText.isEmpty {
                    Text("Add description")
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                }
                TextEditor(text: $descriptionText)
                    .font(DesignSystem.Fonts.main(size: 13))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 54, maxHeight: 110)
            }
        }
    }

    // ── Reminder ─────────────────────────────────────────────────────────────
    var gcReminderSection: some View {
        gcRow(icon: "bell", iconColor: Color(hex: "5f6368")) {
            Menu {
                Button("None") { alertLeadMinutes = [] }
                Divider()
                ForEach(supportedAlertOffsets, id: \.self) { mins in
                    Button {
                        toggleAlertOffset(mins)
                    } label: {
                        if reminderScheduleMinutes.contains(mins) {
                            Label(reminderSummaryText([mins]), systemImage: "checkmark")
                        } else {
                            Text(reminderSummaryText([mins]))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(reminderSummaryText())
                        .font(DesignSystem.Fonts.main(size: 13)).foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Button {
                openCourseSearchOrBuilder()
            } label: {
                Label("Search or add course", systemImage: "magnifyingglass")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    var gcFooter: some View {
        HStack(spacing: 8) {
            if eventToEdit != nil {
                Button { deleteEventNow() } label: {
                    Label("Delete", systemImage: "xmark.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { requestDismissAnimated() } label: {
                Text("Cancel")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Button(action: save) {
                Text(eventToEdit == nil ? "Save" : "Save")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.primary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
