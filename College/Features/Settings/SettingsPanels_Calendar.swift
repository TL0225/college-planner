// SettingsPanels_Calendar.swift
// Feature: Settings
// Purpose: Settings module — SettingsCalendarPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

// MARK: - SettingsCalendarPanel

struct SettingsCalendarPanel: View {
    @Environment(AppContainer.self) private var container
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    // MARK: Event popover density + intelligence
    @AppStorage("calendar.popoverDetailLevel") private var popoverDetailLevelRaw: String = CalendarPopoverDetailLevel.compact.rawValue
    @AppStorage("calendar.popoverShowLeaveBy") private var popoverShowLeaveBy: Bool = true
    @AppStorage("calendar.popoverShowLateRisk") private var popoverShowLateRisk: Bool = true
    @AppStorage("calendar.popoverShowETA") private var popoverShowETA: Bool = true
    @AppStorage("calendar.popoverShowMeetingActions") private var popoverShowMeetingActions: Bool = true
    @AppStorage("calendar.popoverShowProviderMetadata") private var popoverShowProviderMetadata: Bool = false
    @AppStorage("calendar.popoverRenderMarkdown") private var popoverRenderMarkdown: Bool = true
    @AppStorage("calendar.popoverAutoLinkURLs") private var popoverAutoLinkURLs: Bool = true
    @AppStorage("calendar.popoverPrepBufferMinutes") private var popoverPrepBufferMinutes: Int = 15
    @AppStorage("calendar.popoverLateRiskGraceMinutes") private var popoverLateRiskGraceMinutes: Int = 5
    @AppStorage("calendar.popoverEscalationLeadMinutes") private var popoverEscalationLeadMinutes: Int = 10
    @AppStorage("calendar.popoverTransportMode") private var popoverTransportModeRaw: String = TravelTransport.driving.rawValue

    // MARK: General defaults
    @AppStorage("calendar.defaultReminderMinutes")      private var defaultReminderMinutes: Int = 15
    @AppStorage("calendar.defaultEventDurationMinutes") private var defaultEventDurationMinutes: Int = 60
    @AppStorage("calendar.firstDayOfWeek")             private var firstDayOfWeekRaw: Int = 1
    @AppStorage("calendar.showWeekNumbers")            private var showWeekNumbers: Bool = false

    // MARK: Work hours
    @AppStorage("calendar.workHoursEnabled")   private var workHoursEnabled: Bool = true
    @AppStorage("calendar.workHoursStartHour") private var workHoursStartHour: Int = 9
    @AppStorage("calendar.workHoursEndHour")   private var workHoursEndHour: Int = 18

    // MARK: Weekend
    @AppStorage("calendar.weekendVisibility") private var weekendVisibilityRaw: String = WeekendVisibility.show.rawValue

    // MARK: Sleep-friendly
    @AppStorage("calendar.sleepFriendlyEnabled")   private var sleepFriendlyEnabled: Bool = true
    @AppStorage("calendar.sleepFriendlyStartHour") private var sleepFriendlyStartHour: Int = 8
    @AppStorage("calendar.sleepFriendlyEndHour")   private var sleepFriendlyEndHour: Int = 23

    // MARK: Grade-weight priority
    @AppStorage("calendar.gradeWeightBadgeEnabled") private var gradeWeightBadgeEnabled: Bool = true
    @AppStorage("calendar.gradeWeightThreshold")    private var gradeWeightThreshold: Double = 20.0

    // MARK: Study scheduler
    @AppStorage("calendar.studyBlockLengthMinutes") private var studyBlockLengthMinutes: Int = 60
    @AppStorage("calendar.studyBlockBufferMinutes") private var studyBlockBufferMinutes: Int = 15

    // MARK: ICS subscriptions
    @AppStorage("calendar.academicCalendarURL") private var academicCalendarURL: String = ""
    @State private var subscriptionURLDraft: String = ""
    @State private var subscriptionURLError: String? = nil
    @State private var icsSubscriptions: [ICSSubscription] = ICSSubscription.loadAll()
    @State private var isAddingSubscription: Bool = false

    // MARK: Per-calendar notifications (muted IDs)
    @AppStorage("calendar.mutedCalendarIDs") private var mutedCalendarIDsRaw: String = ""
    private var mutedCalendarIDs: Set<String> {
        Set(mutedCalendarIDsRaw.split(separator: ",").map(String.init))
    }

    // MARK: Timezone
    @AppStorage("calendar.timezone") private var timezoneIdentifier: String = TimeZone.current.identifier

    @AppStorage("notifications.eventReminders") private var eventReminders: Bool = true

    var body: some View {
        Form {
            Section {
                CalendarConnectionsSettingsSection()
            } header: {
                Label(String(localized: "settings.calendar.connections_title", defaultValue: "Connected calendars"), systemImage: "link.circle")
            }

            // MARK: — General

            Section {
                LabeledContent(String(localized: "settings.calendar.first_day_week")) {
                    Picker("", selection: $firstDayOfWeekRaw) {
                        Text(String(localized: "settings.common.weekday.sunday")).tag(1)
                        Text(String(localized: "settings.common.weekday.monday")).tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                Picker(String(localized: "settings.calendar.default_event_duration"), selection: $defaultEventDurationMinutes) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) { opt in
                        Text(durationLabel(opt)).tag(opt)
                    }
                }

                Picker(String(localized: "settings.calendar.default_reminder"), selection: $defaultReminderMinutes) {
                    ForEach([0, 5, 10, 15, 30, 60], id: \.self) { opt in
                        Text(reminderLabel(opt)).tag(opt)
                    }
                }

                Toggle(String(localized: "settings.calendar.show_week_numbers"), isOn: $showWeekNumbers)

                LabeledContent(String(localized: "settings.calendar.timezone")) {
                    Menu {
                        ForEach(commonTimezones, id: \.identifier) { tz in
                            Button(tz.identifier) { timezoneIdentifier = tz.identifier }
                        }
                        Divider()
                        Button(String(format: String(localized: "settings.calendar.system_default_tz"), TimeZone.current.identifier)) {
                            timezoneIdentifier = TimeZone.current.identifier
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(String(localized: "settings.calendar.change"))
                                .foregroundStyle(DesignSystem.Colors.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignSystem.Colors.primary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } header: {
                Label(String(localized: "settings.calendar.card_general"), systemImage: "calendar")
            }

            // MARK: — Event Popover

            Section {
                LabeledContent(String(localized: "settings.calendar.popover.detail_level")) {
                    Picker("", selection: $popoverDetailLevelRaw) {
                        Text(String(localized: "settings.calendar.popover.level.compact")).tag(CalendarPopoverDetailLevel.compact.rawValue)
                        Text(String(localized: "settings.calendar.popover.level.standard")).tag(CalendarPopoverDetailLevel.standard.rawValue)
                        Text(String(localized: "settings.calendar.popover.level.detailed")).tag(CalendarPopoverDetailLevel.detailed.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                Toggle(String(localized: "settings.calendar.popover.show_leave_by"), isOn: $popoverShowLeaveBy)
                Toggle(String(localized: "settings.calendar.popover.show_late_risk"), isOn: $popoverShowLateRisk)
                Toggle(String(localized: "settings.calendar.popover.show_eta"), isOn: $popoverShowETA)
                Toggle(String(localized: "settings.calendar.popover.show_meeting_actions"), isOn: $popoverShowMeetingActions)
                Toggle(String(localized: "settings.calendar.popover.render_markdown"), isOn: $popoverRenderMarkdown)
                Toggle(String(localized: "settings.calendar.popover.auto_link_urls"), isOn: $popoverAutoLinkURLs)
                Toggle(String(localized: "settings.calendar.popover.show_provider_metadata"), isOn: $popoverShowProviderMetadata)

                LabeledContent(String(localized: "settings.calendar.popover.eta_transport")) {
                    Picker("", selection: $popoverTransportModeRaw) {
                        ForEach(TravelTransport.allCases, id: \.rawValue) { transport in
                            Text(transport.title).tag(transport.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            } header: {
                Label(String(localized: "settings.calendar.popover.section_title"), systemImage: "rectangle.portrait.on.rectangle.portrait")
            } footer: {
                Text(String(localized: "settings.calendar.popover.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: — Lateness Signals

            Section {
                Picker(String(localized: "settings.calendar.lateness.prep_buffer"), selection: $popoverPrepBufferMinutes) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { opt in
                        Text(durationLabel(opt)).tag(opt)
                    }
                }

                Picker(String(localized: "settings.calendar.lateness.grace"), selection: $popoverLateRiskGraceMinutes) {
                    ForEach([0, 3, 5, 8, 10, 15], id: \.self) { opt in
                        Text(
                            opt == 0
                                ? String(localized: "settings.calendar.lateness.no_grace")
                                : String(
                                    format: String(localized: "settings.calendar.lateness.minutes"),
                                    opt
                                )
                        )
                        .tag(opt)
                    }
                }

                Picker(String(localized: "settings.calendar.lateness.escalation_lead"), selection: $popoverEscalationLeadMinutes) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { opt in
                        Text(
                            String(
                                format: String(localized: "settings.calendar.lateness.before_minutes"),
                                opt
                            )
                        )
                        .tag(opt)
                    }
                }
            } header: {
                Label(String(localized: "settings.calendar.lateness.section_title"), systemImage: "figure.walk.motion")
            }

            // MARK: — Work Hours

            Section {
                Toggle(String(localized: "settings.calendar.dim_non_work"), isOn: $workHoursEnabled)

                if workHoursEnabled {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings.calendar.start"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Stepper(hourLabel(workHoursStartHour), value: $workHoursStartHour, in: 0...22)
                                .font(.system(size: 13))
                                .frame(width: 140)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(localized: "settings.calendar.end"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Stepper(hourLabel(workHoursEndHour), value: $workHoursEndHour, in: 1...23)
                                .font(.system(size: 13))
                                .frame(width: 140)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Label(String(localized: "settings.calendar.card_work_hours"), systemImage: "clock")
            }

            // MARK: — Weekends

            Section {
                LabeledContent(String(localized: "settings.calendar.weekend_visibility")) {
                    Picker("", selection: $weekendVisibilityRaw) {
                        Text(String(localized: "settings.calendar.weekend.show")).tag(WeekendVisibility.show.rawValue)
                        Text(String(localized: "settings.calendar.weekend.dim")).tag(WeekendVisibility.dim.rawValue)
                        Text(String(localized: "settings.calendar.weekend.hide")).tag(WeekendVisibility.hide.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            } header: {
                Label(String(localized: "settings.calendar.card_weekends"), systemImage: "calendar.badge.clock")
            }

            // MARK: — Sleep-Friendly Scheduling

            Section {
                Toggle(String(localized: "settings.calendar.sleep_warn"), isOn: $sleepFriendlyEnabled)

                if sleepFriendlyEnabled {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings.calendar.typical_day_starts"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Stepper(hourLabel(sleepFriendlyStartHour), value: $sleepFriendlyStartHour, in: 0...12)
                                .font(.system(size: 13))
                                .frame(width: 160)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(localized: "settings.calendar.typical_day_ends"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Stepper(hourLabel(sleepFriendlyEndHour), value: $sleepFriendlyEndHour, in: 18...24)
                                .font(.system(size: 13))
                                .frame(width: 160)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Label(String(localized: "settings.calendar.card_sleep"), systemImage: "moon.zzz")
            }

            // MARK: — Academics

            Section {
                Toggle(String(localized: "settings.calendar.grade_badges"), isOn: $gradeWeightBadgeEnabled)

                if gradeWeightBadgeEnabled {
                    LabeledContent(String(localized: "settings.calendar.badge_threshold")) {
                        HStack(spacing: 8) {
                            Slider(value: $gradeWeightThreshold, in: 5...50, step: 5)
                                .frame(width: 140)
                            Text("\(Int(gradeWeightThreshold))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                Picker(String(localized: "settings.calendar.study_block_length"), selection: $studyBlockLengthMinutes) {
                    ForEach([30, 45, 60, 90, 120], id: \.self) { opt in
                        Text(durationLabel(opt)).tag(opt)
                    }
                }

                Picker(String(localized: "settings.calendar.study_buffer"), selection: $studyBlockBufferMinutes) {
                    ForEach([0, 10, 15, 30], id: \.self) { opt in
                        Text(durationLabel(opt)).tag(opt)
                    }
                }
            } header: {
                Label(String(localized: "settings.calendar.card_academics"), systemImage: "graduationcap")
            }

            // MARK: — ICS Subscriptions

            Section {
                LabeledContent(String(localized: "settings.calendar.academic_url_label")) {
                    TextField(
                        String(localized: "settings.calendar.url_placeholder"),
                        text: $academicCalendarURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .font(.system(size: 12))
                    .autocorrectionDisabled()
                }

                ForEach(icsSubscriptions) { sub in
                    ICSSubscriptionRow(subscription: sub) {
                        icsSubscriptions.removeAll(where: { $0.id == sub.id })
                        ICSSubscription.saveAll(icsSubscriptions)
                    }
                }

                if isAddingSubscription {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(
                            String(localized: "settings.calendar.paste_url_placeholder"),
                            text: $subscriptionURLDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .font(.system(size: 12))

                        if let err = subscriptionURLError {
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.red)
                        }

                        HStack {
                            Button(String(localized: "common.cancel")) {
                                isAddingSubscription = false
                                subscriptionURLDraft = ""
                                subscriptionURLError = nil
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.secondary)

                            Spacer()

                            Button(String(localized: "settings.calendar.subscribe")) {
                                addSubscription(urlString: subscriptionURLDraft)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(subscriptionURLDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        isAddingSubscription = true
                    } label: {
                        Label(
                            String(localized: "settings.calendar.add_subscription"),
                            systemImage: "plus.circle"
                        )
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Label(String(localized: "settings.calendar.card_subscribed"), systemImage: "link.circle")
            }

            // MARK: — Per-Calendar Notifications

            if !calendarManager.connectedCalendars.isEmpty {
                Section {
                    Text(String(localized: "settings.calendar.mute_intro"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    ForEach(calendarManager.connectedCalendars) { cal in
                        let isMuted = mutedCalendarIDs.contains(cal.id)
                        Toggle(
                            cal.name,
                            isOn: Binding(
                                get: { isMuted },
                                set: { newVal in toggleMute(calendarID: cal.id, muted: newVal) }
                            )
                        )
                    }
                } header: {
                    Label(
                        String(localized: "settings.calendar.card_notification_muting"),
                        systemImage: "bell.slash"
                    )
                }
            }

            Section {
                Toggle(String(localized: "settings.notifications.event_reminders"), isOn: $eventReminders)
            } header: {
                Label(String(localized: "settings.notifications.card_title", defaultValue: "Reminders"), systemImage: "bell")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return String(format: String(localized: "settings.calendar.duration_minutes"), minutes) }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0
            ? String(format: String(localized: "settings.calendar.duration_hours"), h)
            : String(format: String(localized: "settings.calendar.duration_hours_minutes"), h, m)
    }

    private func reminderLabel(_ minutes: Int) -> String {
        if minutes == 0 { return String(localized: "settings.calendar.reminder_none") }
        if minutes < 60 { return String(format: String(localized: "settings.calendar.reminder_min_before"), minutes) }
        return String(format: String(localized: "settings.calendar.reminder_hr_before"), minutes / 60)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        if hour < 12 {
            return String(format: String(localized: "settings.calendar.time_am"), h)
        }
        return String(format: String(localized: "settings.calendar.time_pm"), h)
    }

    private func toggleMute(calendarID: String, muted: Bool) {
        var ids = mutedCalendarIDs
        if muted { ids.insert(calendarID) } else { ids.remove(calendarID) }
        mutedCalendarIDsRaw = ids.joined(separator: ",")
    }

    private func addSubscription(urlString: String) {
        var cleaned = urlString.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("webcal://") {
            cleaned = "https://" + cleaned.dropFirst("webcal://".count)
        }
        guard let url = URL(string: cleaned), url.scheme == "https" || url.scheme == "http" else {
            subscriptionURLError = String(localized: "settings.calendar.subscription_invalid")
            return
        }
        let sub = ICSSubscription(
            id: UUID().uuidString,
            urlString: cleaned,
            name: url.host ?? cleaned,
            refreshIntervalHours: 6
        )
        icsSubscriptions.append(sub)
        ICSSubscription.saveAll(icsSubscriptions)
        subscriptionURLDraft = ""
        subscriptionURLError = nil
        isAddingSubscription = false
    }

    private var commonTimezones: [TimeZone] {
        ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
         "America/Toronto", "Europe/London", "Europe/Paris", "Asia/Tokyo", "Asia/Shanghai",
         "Australia/Sydney", "Pacific/Auckland"]
            .compactMap { TimeZone(identifier: $0) }
    }
}

// MARK: - WeekendVisibility

enum WeekendVisibility: String {
    case show = "show"
    case dim  = "dim"
    case hide = "hide"
}

enum CalendarPopoverDetailLevel: String {
    case compact = "compact"
    case standard = "standard"
    case detailed = "detailed"
}

// MARK: - ICSSubscription

struct ICSSubscription: Identifiable, Codable {
    let id: String
    var urlString: String
    var name: String
    var refreshIntervalHours: Int

    static func loadAll() -> [ICSSubscription] {
        guard let data = UserDefaults.standard.data(forKey: "calendar.icsSubscriptions"),
              let decoded = try? JSONDecoder().decode([ICSSubscription].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveAll(_ subscriptions: [ICSSubscription]) {
        if let encoded = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(encoded, forKey: "calendar.icsSubscriptions")
        }
    }
}

// MARK: - ICSSubscriptionRow

private struct ICSSubscriptionRow: View {
    let subscription: ICSSubscription
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Color.teal)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.system(size: 13, weight: .medium))
                Text(subscription.urlString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(format: String(localized: "settings.calendar.subscription_refresh"), subscription.refreshIntervalHours))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
