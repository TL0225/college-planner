// AddCalendarItemOverlay+InspectorEventDetails.swift
// Feature: Calendar
// Purpose: Inspector event details card (decomposed for compile time).

import CollegeCalendar
import CollegePlatform
import Contacts
import SwiftUI
import AppKit

extension AddCalendarItemOverlay {
    var macEventDetailsCard: some View {
        groupedCard {
            Label("Event Details", systemImage: "slider.horizontal.3")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(secondaryTextColor)

            VStack(spacing: 0) {
                inspectorGoogleCalendarSection
                if !inspectorAppleCalendars.isEmpty {
                    Divider()
                    inspectorAppleCalendarSection
                }
                Divider()
                inspectorColorSection
                Divider()
                inspectorAlertsSection
                Divider()
                inspectorTravelSection
                Divider()
                inspectorGuestsSection
                Divider()
                inspectorAttachmentsSection
                if eventToEdit != nil {
                    Divider()
                    inspectorDeleteSection
                }
            }
            .background(fieldBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .contain)
        .inspectorAccessibility(
            label: "Event details",
            hint: CalendarInspectorAccessibility.eventDetailsHint
        )
    }

    func inspectorFieldCaption(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
            .foregroundStyle(secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var inspectorGoogleCalendars: [ConnectedCalendar] {
        calendarManager.connectedCalendars.filter { $0.source == "Google" }
    }

    private var inspectorAppleCalendars: [ConnectedCalendar] {
        calendarManager.connectedCalendars.filter { $0.source == "Apple" }
    }

    private var inspectorGoogleCalendarName: String {
        inspectorGoogleCalendars.first { $0.remoteID == selectedGoogleCalendarID }?.name
            ?? inspectorGoogleCalendars.first?.name
            ?? "Planner Calendar"
    }

    private var inspectorAppleCalendarName: String {
        inspectorAppleCalendars.first { $0.remoteID == selectedAppleCalendarID }?.name
            ?? inspectorAppleCalendars.first?.name
            ?? "Primary Calendar"
    }

    @ViewBuilder
    private var inspectorGoogleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(associatedCalendarColor)
                Text("Google Calendar")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                Spacer(minLength: 0)
                if calendarManager.googleSyncRequiresReconnectPublic {
                    Text("Reconnect")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.warning)
                } else {
                    IntegrationStatusBadge(integrationID: .google, healthStore: IntegrationHealthStore.shared)
                }
                inspectorGoogleCalendarPicker
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            if isInspectorEmbedded {
                inspectorFieldCaption("Where this event is exported when you save.")
                if !NetworkConnectivityMonitor.shared.isOnline {
                    inspectorFieldCaption("Offline — changes save locally until you're back online.")
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var inspectorGoogleCalendarPicker: some View {
        if inspectorGoogleCalendars.isEmpty {
            Button {
                AppNotificationCenter.shared.post(
                    kind: .info,
                    title: "Calendar Selection",
                    message: "Connect a Google calendar in Settings to choose a destination.",
                    autoDismissAfter: 3
                )
            } label: {
                Text(inspectorGoogleCalendarName)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(associatedCalendarColor)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(inspectorGoogleCalendars, id: \.id) { cal in
                    Button { selectedGoogleCalendarID = cal.remoteID } label: { Text(cal.name) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(inspectorGoogleCalendarName)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(associatedCalendarColor)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(calendarManager.googleSyncRequiresReconnectPublic)
        }
    }

    @ViewBuilder
    private var inspectorAppleCalendarSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.logo")
                .foregroundStyle(associatedCalendarColor)
            Text("Apple Calendar")
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundStyle(secondaryTextColor)
            Spacer(minLength: 0)
            IntegrationStatusBadge(integrationID: .apple, healthStore: IntegrationHealthStore.shared)
            Menu {
                ForEach(inspectorAppleCalendars, id: \.id) { cal in
                    Button { selectedAppleCalendarID = cal.remoteID } label: { Text(cal.name) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(inspectorAppleCalendarName)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(associatedCalendarColor)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var inspectorColorSection: some View {
        inspectorLabeledRow(
            icon: "paintpalette",
            title: "Color",
            help: "How this event appears on your College calendar grid."
        ) {
            Menu {
                ForEach(Array(AddCalendarItemOverlay.presetEventColors.enumerated()), id: \.offset) { index, color in
                    Button { applySelectedColor(color, choice: .preset(index)) } label: {
                        Text("Preset \(index + 1)")
                    }
                }
                Divider()
                Button("Custom hex…") { isShowingHexPopover = true }
                if isColorOverridden {
                    Button("Reset to default") {
                        isColorOverridden = false
                        scheduleAutosaveIfEditing()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isColorOverridden ? customColor : associatedCalendarColor)
                        .frame(width: 10, height: 10)
                    Text(isColorOverridden ? (customColor.hexRGBString() ?? "Custom") : "Default")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .popover(isPresented: $isShowingHexPopover) { hexColorEditor }
        }
    }

    @ViewBuilder
    private var inspectorAlertsSection: some View {
        inspectorLabeledRow(
            icon: "bell",
            title: "Alerts",
            help: "macOS notification before the event starts."
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { activeBottomPanel = .alerts }
            } label: {
                Text(reminderSummaryText())
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var inspectorTravelSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .foregroundStyle(secondaryTextColor)
                Text("Travel")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                Spacer(minLength: 0)
                Menu {
                    Button("Off") {
                        travelTimeEnabled = false
                        travelTimeMinutes = nil
                        travelEstimateMinutes = nil
                        persistTravelSettingsIfEditing()
                    }
                    if let estimate = travelEstimateMinutes {
                        Divider()
                        Button("Suggested: \(estimate) min") {
                            travelTimeEnabled = true
                            travelTimeMinutes = roundedToNearestFive(estimate)
                            recomputeTravelEstimateIfPossible()
                            persistTravelSettingsIfEditing()
                        }
                    }
                    Divider()
                    ForEach(travelTimeMinuteOptions, id: \.self) { minutes in
                        Button("\(minutes) min") {
                            travelTimeEnabled = true
                            travelTimeMinutes = minutes
                            recomputeTravelEstimateIfPossible()
                            persistTravelSettingsIfEditing()
                        }
                    }
                } label: {
                    Text(travelSummaryLabel)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            if travelTimeEnabled {
                Text(travelArrivalLine)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .padding(.horizontal, 10)
            }
            if isInspectorEmbedded {
                inspectorFieldCaption("Adds leave-by time based on your location.")
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        .help("Adds leave-by time based on your location.")
    }

    @ViewBuilder
    private var inspectorGuestsSection: some View {
        let label = selectedGuests.isEmpty
            ? "No guests"
            : "\(selectedGuests.count) guest\(selectedGuests.count == 1 ? "" : "s")"
        let rsvpSummary = guestRSVPSummaryLabel
        VStack(alignment: .leading, spacing: 4) {
            inspectorLabeledRow(
                icon: "person.2.fill",
                title: "Guests",
                help: "Saved with this event. Invites sync when you save."
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        showContactPicker(anchorWindowPoint: NSApp.currentEvent?.locationInWindow)
                    } label: {
                        Text(label)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the contact picker to add guests.")
                    if let rsvpSummary {
                        Text(rsvpSummary)
                            .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            if guestInviteSyncFailed, !selectedGuests.isEmpty {
                HStack(spacing: 8) {
                    Text("Invite sync failed")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.warning)
                    Spacer(minLength: 0)
                    Button("Resend invites", action: retryGuestInviteSync)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .buttonStyle(.plain)
                        .inspectorAccessibility(
                            label: "Resend invites",
                            hint: CalendarInspectorAccessibility.resendInvitesHint
                        )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
    }

    private var guestRSVPSummaryLabel: String? {
        let statuses = selectedGuests.compactMap { guest -> String? in
            guard let email = guest.emailAddresses.first?.value as String? else { return nil }
            return guestResponseByEmail[email.lowercased()]
        }
        guard !statuses.isEmpty else { return nil }
        let accepted = statuses.filter { $0.lowercased() == "accepted" }.count
        let declined = statuses.filter { $0.lowercased() == "declined" }.count
        let tentative = statuses.filter { $0.lowercased() == "tentative" }.count
        var parts: [String] = []
        if accepted > 0 { parts.append("\(accepted) yes") }
        if tentative > 0 { parts.append("\(tentative) maybe") }
        if declined > 0 { parts.append("\(declined) no") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var inspectorAttachmentsSection: some View {
        let count = linkedAttachmentIDs.count + recentFileImports.count
        let label = count == 0 ? "No attachments" : "\(count) attachment\(count == 1 ? "" : "s")"
        inspectorLabeledRow(
            icon: "paperclip",
            title: "Attachments",
            help: "Files saved to Documents and linked to this event."
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { activeBottomPanel = .files }
            } label: {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var inspectorDeleteSection: some View {
        Button(role: .destructive, action: deleteEventNow) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Event")
                Spacer(minLength: 0)
            }
            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.error)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .help("Permanently removes this event.")
        .inspectorAccessibility(
            label: "Delete Event",
            hint: CalendarInspectorAccessibility.deleteEventHint
        )
    }

    @ViewBuilder
    private func inspectorLabeledRow<Trailing: View>(
        icon: String,
        title: String,
        help: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            if isInspectorEmbedded {
                inspectorFieldCaption(help)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        .help(help)
        .accessibilityHint(help)
    }
}
