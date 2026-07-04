// AddCalendarItemOverlay+ScrollableEditor.swift
// Feature: Calendar
// Purpose: Full-screen / anchored scrollable editor card (Phase 6 decomposition).

import CollegeCalendar
import CollegePlatform
import SwiftUI
import Contacts
import ContactsUI
import MapKit
import AppKit
import UniformTypeIdentifiers

extension AddCalendarItemOverlay {
    var scrollableEditorCardContent: some View {
        Group {
            if isInspectorEmbedded {
                ScrollView(showsIndicators: true) {
                    VStack(spacing: 14) {
                        if showInspectorOnboardingTips {
                            CalendarInspectorOnboardingTipsBanner {
                                showInspectorOnboardingTips = false
                                CalendarInspectorOnboarding.markTipsSeen()
                            }
                        }
                        scrollableEditorSections(isWide: false, detailsRowHeight: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .inspectorSidebarBackground()
            } else {
                GeometryReader { proxy in
                    let isWide = proxy.size.width >= 920
                    let detailsRowHeight = max(280, proxy.size.height * 0.46)

                    ScrollView(showsIndicators: false) {
                        scrollableEditorSections(isWide: isWide, detailsRowHeight: detailsRowHeight)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .frame(maxWidth: 980, alignment: .top)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func scrollableEditorSections(isWide: Bool, detailsRowHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            topHeaderPill

            if isWide && !isInspectorEmbedded {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        macTimeCard
                        macLocationCard
                        macDescriptionCard
                            .frame(height: detailsRowHeight, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 14) {
                        macCourseCard
                        macExtrasCard
                        macEventDetailsCard
                            .frame(height: detailsRowHeight, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    macTimeCard
                    macLocationCard
                    macCourseCard
                    if CalendarInspectorLayout.showsExtrasCard(isInspectorEmbedded: isInspectorEmbedded) {
                        macExtrasCard
                    }
                    macDescriptionCard
                    macEventDetailsCard
                }
            }
        }
    }

    var compactFloatingCardsContent: some View {
        let spacing: CGFloat = 10
        let rightColumnWidth: CGFloat = 260

        return ViewThatFits(in: .horizontal) {
            VStack(spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        timeCard
                        locationTravelCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: spacing) {
                        guestsCard
                        toolsCard
                    }
                    .frame(width: rightColumnWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.clear)

            VStack(spacing: spacing) {
                timeCard
                locationTravelCard
                guestsCard
                toolsCard
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.clear)
        }
    }

    var topHeaderPill: some View {
        HStack(alignment: .center, spacing: 12) {
            if isInspectorEmbedded {
                Button {
                    requestDismissAnimated()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close inspector")
                .inspectorAccessibility(
                    label: "Close inspector",
                    hint: CalendarInspectorAccessibility.closeInspectorHint
                )
            } else {
                Button {
                    if eventToEdit != nil {
                        deleteEventNow()
                    } else {
                        requestDismissAnimated()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(fieldBackgroundColor))
                }
                .buttonStyle(.plain)
                .help(eventToEdit == nil ? "Dismiss" : "Delete Event")
                .accessibilityLabel(eventToEdit == nil ? "Dismiss" : "Delete Event")
            }

            Spacer(minLength: 2)

            VStack(alignment: .center, spacing: 2) {
                TextField("Event Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: isInspectorEmbedded ? 18 : 20, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 220)

                Text(headerSubtitle)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isInspectorEmbedded ? 44 : 34, height: isInspectorEmbedded ? 44 : 34)
                    .background(
                        Circle().fill(
                            isInspectorEmbedded
                                ? associatedCalendarColor
                                : associatedCalendarColor
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)
            .help(eventToEdit == nil ? "Create Event" : "Save & Sync")
            .inspectorAccessibility(
                label: eventToEdit == nil ? "Create Event" : "Save and Sync",
                hint: eventToEdit == nil
                    ? CalendarInspectorAccessibility.createEventHint
                    : CalendarInspectorAccessibility.saveAndSyncHint
            )
        }
        .padding(.horizontal, isInspectorEmbedded ? 20 : 12)
        .padding(.vertical, 9)
        .background {
            if isInspectorEmbedded {
                Color.clear
            } else {
                DesignSystem.Colors.glassCardBase
            }
        }
        .background {
            if isInspectorEmbedded {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            }
        }
        .overlay {
            if isInspectorEmbedded {
                Divider()
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            }
        }
    }

        var headerSubtitle: String {
                startDateTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }

            func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if isInspectorEmbedded {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    } else {
                        DesignSystem.Colors.glassCardBase
                    }
                }
                .background {
                    if isInspectorEmbedded {
                        EmptyView()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.thinMaterial)
                    }
                }
                .overlay {
                    if isInspectorEmbedded {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                    }
                }
            }

            var macTimeCard: some View {
                groupedCard {
                    HStack {
                        Label("Time", systemImage: "clock")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: 10)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeBottomPanel = .recurrence
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                    .foregroundStyle(secondaryTextColor)
                                Text(recurrenceSummaryLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                    .foregroundStyle(secondaryTextColor)
                            }
                        }
                        .buttonStyle(.plain)

                        Toggle("All day", isOn: $allDay)
                            .toggleStyle(.switch)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Start")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .frame(width: 34, alignment: .leading)

                            DatePicker(
                                "",
                                selection: Binding<Date>(
                                    get: { Calendar.current.startOfDay(for: startDateTime) },
                                    set: { newDay in
                                        let calendar = Calendar.current
                                        let hour = calendar.component(.hour, from: startDateTime)
                                        let minute = calendar.component(.minute, from: startDateTime)
                                        let newStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
                                        startDateTime = newStart
                                    }
                                ),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.field)
                            .labelsHidden()

                            if !allDay {
                                TimeMenuField(
                                    selection: $startDateTime,
                                    isDisabled: false,
                                    fontSize: 13,
                                    textColor: DesignSystem.Colors.textMain,
                                    showsDurationFrom: nil,
                                    onSelect: { startDateTime = $0 }
                                )
                            }
                        }

                        HStack(spacing: 8) {
                            Text("End")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .frame(width: 34, alignment: .leading)

                            DatePicker(
                                "",
                                selection: Binding<Date>(
                                    get: { Calendar.current.startOfDay(for: endDateTime) },
                                    set: { newDay in
                                        let calendar = Calendar.current
                                        let hour = calendar.component(.hour, from: endDateTime)
                                        let minute = calendar.component(.minute, from: endDateTime)
                                        let newEnd = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
                                        endDateTime = newEnd
                                    }
                                ),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.field)
                            .labelsHidden()

                            if !allDay {
                                TimeMenuField(
                                    selection: $endDateTime,
                                    isDisabled: false,
                                    fontSize: 13,
                                    textColor: DesignSystem.Colors.textMain,
                                    showsDurationFrom: startDateTime,
                                    onSelect: { endDateTime = $0 }
                                )
                            }
                        }
                    }

                    if hasAutoAdjustedEndTime && !allDay {
                        Text("End time was adjusted to stay after start time.")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }

                    if isInspectorEmbedded {
                        inspectorOverlapSection
                    }
                }
                .accessibilityElement(children: .contain)
                .inspectorAccessibility(
                    label: "Event time and recurrence",
                    hint: CalendarInspectorAccessibility.timeCardHint
                )
            }

            @ViewBuilder
            private var inspectorOverlapSection: some View {
                let overlaps = previewOverlappingEvents
                VStack(alignment: .leading, spacing: 8) {
                    if !overlaps.isEmpty {
                        let titles = overlaps.compactMap(\.title).prefix(2).joined(separator: ", ")
                        let more = overlaps.count > 2 ? " and \(overlaps.count - 2) more" : ""
                        Text("Overlaps with \(titles)\(more).")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }

                    Picker("Overlap policy", selection: $overlapPolicyRaw) {
                        ForEach(CalendarOverlapPolicy.allCases) { policy in
                            Text(policy.label).tag(policy.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help(overlapPolicy.description)
                    .accessibilityLabel("Overlap policy")
                    .accessibilityHint(overlapPolicy.description)

                    Text(overlapPolicy.description)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(.top, 4)
            }

            var macLocationCard: some View {
                groupedCard {
                    Label("Location", systemImage: "mappin.and.ellipse")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    HStack(spacing: 10) {
                        TextField("Add location", text: $location)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                            .focused($focusedLocationInput, equals: .anchoredPanel)

                        Button {
                            isShowingLocationPicker = true
                            locationSearchService.query = ""
                            locationSearchService.applyLocationBias(from: locationPermissionService.lastLocation)
                        } label: {
                            Image(systemName: "map")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(DesignSystem.Colors.primary.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Pick location on map")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        fieldBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
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
                                .fill(fieldBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                }
                .inspectorAccessibility(
                    label: "Event location",
                    hint: CalendarInspectorAccessibility.locationCardHint
                )
            }

            var macCourseCard: some View {
                groupedCard {
                    Label("Course / Category", systemImage: "book.closed")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    Menu {
                        Button("No course") {
                            selectedCourseID = nil
                        }

                        if !allCourses.isEmpty {
                            Divider()
                            ForEach(allCourses, id: \.id) { course in
                                Button {
                                    selectedCourseID = course.id
                                } label: {
                                    Text(courseDisplayLabel(course))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Label("Assign to Course", systemImage: "graduationcap")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            Spacer(minLength: 0)
                            Text(selectedCourseSummaryLabel)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundStyle(primaryTextColor)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundStyle(secondaryTextColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            fieldBackgroundColor,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    Button {
                        openCourseSearchOrBuilder()
                    } label: {
                        Label("Search or add course", systemImage: "magnifyingglass")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    .buttonStyle(.plain)

                    if allCourses.isEmpty {
                        Text("No courses found yet. Add a course to unlock assignment.")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
                .inspectorAccessibility(
                    label: "Course assignment",
                    hint: CalendarInspectorAccessibility.courseCardHint
                )
            }

            var macExtrasCard: some View {
                groupedCard {
                    HStack(spacing: 0) {
                        macExtraButton(title: "Alerts", systemImage: "bell", tint: .secondary) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeBottomPanel = .alerts
                            }
                        }
                        macExtraButton(title: "Color", systemImage: "paintpalette", tint: .orange) {
                            isShowingHexPopover = true
                        }
                        macExtraButton(title: "Notes", systemImage: "doc.text", tint: .green) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeBottomPanel = .notes
                            }
                        }
                    }
                    .background(fieldBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Divider()

                    HStack(spacing: 10) {
                        Label(reminderSummaryText(), systemImage: "bell")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Label(selectedCourseSummaryLabel, systemImage: "graduationcap")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(associatedCalendarColor.opacity(0.9))
                            .lineLimit(1)
                        Label(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No notes" : "Notes added", systemImage: "doc.text")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: 0)
                    }
                }
                .popover(isPresented: $isShowingHexPopover) {
                    hexColorEditor
                }
            }

            var macDescriptionCard: some View {
                groupedCard {
                    Label("Description", systemImage: "text.alignleft")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $descriptionText)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.textMain)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: isInspectorEmbedded ? 140 : 230)

                        if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Add context, agenda, links, or prep notes for this event...")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                                .foregroundStyle(secondaryTextColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(
                        fieldBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        Label(eventDurationSummaryLabel, systemImage: "clock")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Label(descriptionWordCountLabel, systemImage: "text.word.spacing")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: 0)
                    }
                }
                .inspectorAccessibility(
                    label: "Description",
                    hint: CalendarInspectorAccessibility.descriptionCardHint
                )
            }

            var travelSummaryLabel: String {
                guard travelTimeEnabled else { return "Off" }
                guard let estimate = travelEstimateMinutes else { return "Estimating..." }
                if estimate < 60 {
                    return "\(estimate)m"
                }
                let hours = estimate / 60
                let minutes = estimate % 60
                if minutes == 0 {
                    return "\(hours)h"
                }
                return "\(hours)h \(minutes)m"
            }

            var eventDurationSummaryLabel: String {
                let minutes = max(0, Int(endDateTime.timeIntervalSince(startDateTime) / 60))
                if allDay { return "All day" }
                if minutes < 60 { return "\(minutes)m duration" }
                let hours = minutes / 60
                let remaining = minutes % 60
                if remaining == 0 { return "\(hours)h duration" }
                return "\(hours)h \(remaining)m duration"
            }

            var descriptionWordCountLabel: String {
                let words = descriptionText
                    .split { $0.isWhitespace || $0.isNewline }
                    .count
                return words == 1 ? "1 word" : "\(words) words"
            }

            func macExtraButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
                Button(action: action) {
                    VStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(title)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

        var cardPadding: CGFloat {
            switch presentationStyle {
            case .anchoredPanel, .inspectorSidebar:
                return 12
            case .fullScreenOverlay, .dynamicIsland, .bottomSheet:
                return 18
            }
        }

        var cardCornerRadius: CGFloat {
            switch presentationStyle {
            case .anchoredPanel, .inspectorSidebar:
                return 18
            case .fullScreenOverlay, .dynamicIsland, .bottomSheet:
                return 24
            }
        }

        func softCard<Content: View>(
            padding: CGFloat = 18,
            cornerRadius: CGFloat = 24,
            @ViewBuilder content: () -> Content
        ) -> some View {
            content()
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.thinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
                )
        }

        var timeCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                let timeFontSize: CGFloat = usesCompactEditorLayout ? 18 : 20

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "clock")
                        .font(DesignSystem.Fonts.main(size: 22, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .frame(width: 28)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 12) {
                        if !showsInternalHeaderPill {
                            TextField(
                                "Event Name",
                                text: $title,
                                prompt: Text("Event").foregroundStyle(DesignSystem.Colors.textLight)
                            )
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textMain)
                            .textFieldStyle(.plain)

                            DashedDivider()
                        }

                        HStack(alignment: .center, spacing: 10) {
                            HStack(spacing: 8) {
                                if allDay {
                                    HStack(spacing: 8) {
                                        Image(systemName: "sun.max")
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                        Text("All day")
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                    }
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.04))
                                            .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                                    )
                                } else {
                                    TimeMenuField(
                                        selection: $startDateTime,
                                        isDisabled: false,
                                        fontSize: timeFontSize,
                                        textColor: DesignSystem.Colors.textMain,
                                        showsDurationFrom: nil,
                                        onSelect: { newStart in
                                            let calendar = Calendar.current
                                            startDateTime = newStart

                                            let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                                            if endDateTime < minimumEnd {
                                                endDateTime = minimumEnd
                                            }
                                        }
                                    )
                                    Text("→")
                                        .font(DesignSystem.Fonts.main(size: 16, weight: .regular))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                    TimeMenuField(
                                        selection: $endDateTime,
                                        isDisabled: false,
                                        fontSize: timeFontSize,
                                        textColor: DesignSystem.Colors.textMain,
                                        showsDurationFrom: startDateTime,
                                        onSelect: { newEndSameDay in
                                            let calendar = Calendar.current
                                            var adjustedEnd = newEndSameDay
                                            if adjustedEnd <= startDateTime {
                                                adjustedEnd = calendar.date(byAdding: .day, value: 1, to: adjustedEnd) ?? adjustedEnd
                                            }
                                            let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                                            if adjustedEnd < minimumEnd {
                                                adjustedEnd = minimumEnd
                                            }
                                            endDateTime = adjustedEnd
                                        }
                                    )
                                }
                            }

                            Spacer(minLength: 0)

                            HStack(spacing: 10) {
                                Text("All day")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                Toggle("", isOn: $allDay)
                                    .labelsHidden()
                                    .accessibilityLabel("All day event")
                                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.success))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.04))
                                    .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                            )
                        }

                        if presentationStyle != .anchoredPanel {
                            Text(startDateTime.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)

                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                                Menu {
                                    ForEach(Self.recurrenceOptions, id: \.self) { option in
                                        Button {
                                            setRecurrenceRule(option)
                                        } label: {
                                            if recurrenceRule == option {
                                                Label(recurrenceLabel(for: option), systemImage: "checkmark")
                                            } else {
                                                Text(recurrenceLabel(for: option))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(recurrenceSummaryLabel)
                                            .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                            .foregroundStyle(DesignSystem.Colors.textLight)
                                        Image(systemName: "chevron.down")
                                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                            .foregroundStyle(DesignSystem.Colors.textLight)
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                            }
                        }
                    }
                }
            }
        }

        var locationTravelCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                let locationFontSize: CGFloat = usesCompactEditorLayout ? 16 : 18

                VStack(spacing: 16) {
                    Button {
                        isShowingLocationPicker = true
                        locationSearchService.query = ""
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                        .foregroundStyle(.orange)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("LOCATION")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                                Text(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add location" : location)
                                    .font(DesignSystem.Fonts.main(size: locationFontSize, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                                .opacity(0.75)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    DashedDivider()

                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "car")
                                    .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("TRAVEL TIME")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                                Spacer(minLength: 0)

                                Menu {
                                    Button("Off") {
                                        travelTimeEnabled = false
                                        travelTimeMinutes = nil
                                        travelEstimateMinutes = nil
                                    }

                                    if let estimate = travelEstimateMinutes {
                                        Divider()
                                        Button("Suggested: \(estimate) min") {
                                            travelTimeEnabled = true
                                            travelTimeMinutes = roundedToNearestFive(estimate)
                                            locationPermissionService.requestWhenInUseAuthorizationIfNeeded()
                                            locationPermissionService.requestOneShotLocation()
                                            recomputeTravelEstimateIfPossible()
                                        }
                                    }

                                    Divider()
                                    ForEach(travelTimeMinuteOptions, id: \.self) { minutes in
                                        Button("\(minutes) min") {
                                            travelTimeEnabled = true
                                            travelTimeMinutes = minutes
                                            locationPermissionService.requestWhenInUseAuthorizationIfNeeded()
                                            locationPermissionService.requestOneShotLocation()
                                            recomputeTravelEstimateIfPossible()
                                        }
                                    }
                                } label: {
                                    Text(travelTimeEnabled ? ((travelTimeMinutes != nil) ? "\(travelTimeMinutes!) min" : "On") : "Off")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                        .foregroundStyle(DesignSystem.Colors.textMain)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.black.opacity(0.06))
                                        )
                                }
                                .menuStyle(.borderlessButton)
                            }

                            HStack(spacing: 8) {
                                Text("Starting from")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                    .foregroundStyle(DesignSystem.Colors.textMain)

                                HStack(spacing: 6) {
                                    Image(systemName: "location.north.fill")
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    Text("Current Location")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(DesignSystem.Colors.primary)
                            }

                            Text(travelArrivalLine)
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }

        private struct DashedDivider: View {
            var body: some View {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 1)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.clear)
                    )
            }
        }

        var travelArrivalLine: String {
            guard travelTimeEnabled else {
                return "Travel time is off."
            }
            guard resolvedLocation != nil else {
                return "Add a location to estimate travel time."
            }
            guard locationPermissionService.status == .authorized else {
                return "Enable Location Services to estimate travel time."
            }
            if isEstimatingTravel {
                return "Estimating travel time…"
            }
            if let estimate = travelEstimateMinutes {
                let arrival = Date().addingTimeInterval(Double(estimate) * 60)
                return "Est. arrival at \(arrival.formatted(date: .omitted, time: .shortened)) if you leave now."
            }
            return "Travel time unavailable."
        }

        func showContactPicker(anchorWindowPoint: NSPoint? = nil) {
            let picker = CNContactPicker()
            let delegate = CalendarContactPickerDelegate(
                onSelect: { contact in
                    if !self.selectedGuests.contains(where: { $0.identifier == contact.identifier }) {
                        self.selectedGuests.append(contact)
                    }
                },
                onClose: {
                    self.contactPickerDelegate = nil
                }
            )
            self.contactPickerDelegate = delegate
            picker.delegate = delegate
            
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                let windowPoint = anchorWindowPoint ?? NSApp.currentEvent?.locationInWindow ?? window.mouseLocationOutsideOfEventStream
                let localPoint = contentView.convert(windowPoint, from: nil)
                let anchorRect = NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1)
                picker.showRelative(to: anchorRect, of: contentView, preferredEdge: .maxX)
            }
        }

        func removeGuest(_ contact: CNContact) {
            selectedGuests.removeAll(where: { $0.identifier == contact.identifier })
        }

        var guestsCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                let placeholderVerticalPadding: CGFloat = usesCompactEditorLayout ? 24 : 34

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("GUESTS")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Spacer(minLength: 0)
                        Button {
                            showContactPicker()
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.primary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(DesignSystem.Colors.primary.opacity(0.10)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if selectedGuests.isEmpty {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color.black.opacity(0.04))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "person.2")
                                        .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                )
                            Text("Add guests")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textMain)
                            Text("Invite via email")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, placeholderVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                .foregroundStyle(Color.black.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showContactPicker()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(selectedGuests.enumerated()), id: \.element.identifier) { index, guest in
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        if let imageData = guest.thumbnailImageData, let nsImage = NSImage(data: imageData) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 32, height: 32)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .frame(width: 32, height: 32)
                                                .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.5))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(CNContactFormatter.string(from: guest, style: .fullName) ?? "Unknown")
                                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                                .foregroundStyle(DesignSystem.Colors.textMain)
                                            
                                            if let email = guest.emailAddresses.first?.value as String? {
                                                Text(email)
                                                    .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                                                    .foregroundStyle(DesignSystem.Colors.textLight)
                                                    .lineLimit(1)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            removeGuest(guest)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                                .foregroundStyle(DesignSystem.Colors.textLight)
                                                .frame(width: 24, height: 24)
                                                .background(Circle().fill(Color.black.opacity(0.05)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 8)
                                    
                                    if index < selectedGuests.count - 1 {
                                        DashedDivider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var toolsCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        toolButton(title: "Alerts", systemImage: "bell", tint: DesignSystem.Colors.textLight) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeBottomPanel = .alerts
                            }
                        }
                        toolButton(title: "Color", systemImage: "paintpalette", tint: .orange) {
                            isShowingHexPopover = true
                        }
                        toolButton(title: "Notes", systemImage: "doc.text", tint: .green) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeBottomPanel = .notes
                            }
                        }
                        toolButton(title: "Files", systemImage: "paperclip", tint: .blue) {
                            isShowingFileImporter = true
                        }
                    }

                    if usesCompactEditorLayout {
                        DashedDivider()

                        HStack(spacing: 10) {
                            Button {
                                requestDismissAnimated()
                            } label: {
                                Text("Cancel")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.05))
                                            .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: save) {
                                Text(eventToEdit == nil ? "Create" : "Save")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(
                                        Capsule()
                                            .fill(DesignSystem.Colors.primary)
                                            .shadow(color: DesignSystem.Colors.primary.opacity(0.18), radius: 10, x: 0, y: 6)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.6)
                        }
                    }
                }
            }
            .popover(isPresented: $isShowingHexPopover) {
                hexColorEditor
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }

        func toolButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                let iconSize: CGFloat = usesCompactEditorLayout ? 16 : 18
                let labelSize: CGFloat = usesCompactEditorLayout ? 9 : 10

                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(DesignSystem.Fonts.main(size: iconSize, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title.uppercased())
                        .font(DesignSystem.Fonts.main(size: labelSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }

}
