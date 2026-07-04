// SettingsPanels_Calendar.swift
import CollegeCalendar
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
    @AppStorage("calendar.defaultCalendarID")          private var defaultCalendarID: String = ""

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
        VStack(alignment: .leading, spacing: 28) {
            Group {
                connectedCalendarsCard
                generalCard
                eventPopoverCard
                latenessSignalsCard
                workHoursCard
                weekendsCard
            }
            Group {
                sleepFriendlyCard
                academicsCard
                subscriptionsCard
                AcademicCalendarSettingsSection()
                perCalendarNotificationsCard
                remindersCard
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
    }

    // MARK: - Shared chrome

    @ViewBuilder
    private var rowDivider: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.5))
            .padding(.horizontal, 18)
    }

    // MARK: - Connected calendars

    @ViewBuilder
    private var connectedCalendarsCard: some View {
        CalendarConnectionsSettingsSection()
    }

    // MARK: - General

    private var generalCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_general"),
            icon: "calendar",
            iconColor: .blue
        ) {
            SPickerRow(
                label: String(localized: "settings.calendar.first_day_week"),
                selection: $firstDayOfWeekRaw,
                options: [1, 2],
                optionLabel: { day in
                    day == 1
                        ? String(localized: "settings.common.weekday.sunday")
                        : String(localized: "settings.common.weekday.monday")
                }
            )

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.default_event_duration"),
                selection: $defaultEventDurationMinutes,
                options: [15, 30, 60, 90, 120],
                optionLabel: durationLabel
            )

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.default_reminder"),
                selection: $defaultReminderMinutes,
                options: [0, 5, 10, 15, 30, 60],
                optionLabel: reminderLabel
            )

            if !calendarManager.connectedCalendars.isEmpty {
                rowDivider

                SMenuRow(
                    label: String(localized: "settings.calendar.default_calendar", defaultValue: "Default calendar"),
                    subtitle: String(localized: "settings.calendar.default_calendar_sub", defaultValue: "Where new events are created"),
                    currentDisplay: selectedDefaultCalendarName,
                    options: calendarManager.connectedCalendars.map(\.id),
                    optionLabel: { id in
                        calendarManager.connectedCalendars.first(where: { $0.id == id })?.name ?? id
                    },
                    onSelect: { defaultCalendarID = $0 }
                )
            }

            rowDivider

            SToggleRow(
                label: String(localized: "settings.calendar.show_week_numbers"),
                isOn: $showWeekNumbers
            )

            rowDivider

            timezoneRow
        }
    }

    @ViewBuilder
    private var timezoneRow: some View {
        HStack(alignment: .center) {
            Text(String(localized: "settings.calendar.timezone"))
                .font(DesignSystem.Fonts.body(weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
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
                    Text(selectedTimezoneDisplay)
                        .font(DesignSystem.Fonts.body())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DesignSystem.Fonts.caption2())
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }

    // MARK: - Event popover

    private var eventPopoverCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
        SettingsCard(
            title: String(localized: "settings.calendar.popover.section_title"),
            icon: "rectangle.portrait.on.rectangle.portrait",
            iconColor: DesignSystem.Colors.primary
        ) {
            SPickerRow(
                label: String(localized: "settings.calendar.popover.detail_level"),
                selection: $popoverDetailLevelRaw,
                options: [
                    CalendarPopoverDetailLevel.compact.rawValue,
                    CalendarPopoverDetailLevel.standard.rawValue,
                    CalendarPopoverDetailLevel.detailed.rawValue
                ],
                optionLabel: { raw in
                    switch CalendarPopoverDetailLevel(rawValue: raw) {
                    case .standard: return String(localized: "settings.calendar.popover.level.standard")
                    case .detailed: return String(localized: "settings.calendar.popover.level.detailed")
                    default:        return String(localized: "settings.calendar.popover.level.compact")
                    }
                }
            )

            rowDivider
            Group {
                SToggleRow(label: String(localized: "settings.calendar.popover.show_leave_by"), isOn: $popoverShowLeaveBy)
                rowDivider
                SToggleRow(label: String(localized: "settings.calendar.popover.show_late_risk"), isOn: $popoverShowLateRisk)
                rowDivider
                SToggleRow(label: String(localized: "settings.calendar.popover.show_eta"), isOn: $popoverShowETA)
                rowDivider
                SToggleRow(label: String(localized: "settings.calendar.popover.show_meeting_actions"), isOn: $popoverShowMeetingActions)
            }
            rowDivider
            Group {
                SToggleRow(label: String(localized: "settings.calendar.popover.render_markdown"), isOn: $popoverRenderMarkdown)
                rowDivider
                SToggleRow(label: String(localized: "settings.calendar.popover.auto_link_urls"), isOn: $popoverAutoLinkURLs)
                rowDivider
                SToggleRow(label: String(localized: "settings.calendar.popover.show_provider_metadata"), isOn: $popoverShowProviderMetadata)
            }

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.popover.eta_transport"),
                selection: $popoverTransportModeRaw,
                options: TravelTransport.allCases.map(\.rawValue),
                optionLabel: { raw in TravelTransport(rawValue: raw)?.title ?? raw }
            )
        }

            Text(String(localized: "settings.calendar.popover.footer"))
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignSystem.Spacing.xs)
        }
    }

    // MARK: - Lateness signals

    private var latenessSignalsCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.lateness.section_title"),
            icon: "figure.walk.motion",
            iconColor: DesignSystem.Colors.warning
        ) {
            SPickerRow(
                label: String(localized: "settings.calendar.lateness.prep_buffer"),
                selection: $popoverPrepBufferMinutes,
                options: [5, 10, 15, 20, 30],
                optionLabel: durationLabel
            )

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.lateness.grace"),
                selection: $popoverLateRiskGraceMinutes,
                options: [0, 3, 5, 8, 10, 15],
                optionLabel: { opt in
                    opt == 0
                        ? String(localized: "settings.calendar.lateness.no_grace")
                        : String(format: String(localized: "settings.calendar.lateness.minutes"), opt)
                }
            )

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.lateness.escalation_lead"),
                selection: $popoverEscalationLeadMinutes,
                options: [5, 10, 15, 20, 30],
                optionLabel: { opt in
                    String(format: String(localized: "settings.calendar.lateness.before_minutes"), opt)
                }
            )
        }
    }

    // MARK: - Work hours

    private var workHoursCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_work_hours"),
            icon: "clock",
            iconColor: .indigo
        ) {
            SToggleRow(
                label: String(localized: "settings.calendar.dim_non_work"),
                isOn: $workHoursEnabled
            )

            if workHoursEnabled {
                rowDivider
                SStepperRow(
                    label: String(localized: "settings.calendar.start"),
                    value: $workHoursStartHour,
                    range: 0...22,
                    valueLabel: hourLabel
                )
                rowDivider
                SStepperRow(
                    label: String(localized: "settings.calendar.end"),
                    value: $workHoursEndHour,
                    range: 1...23,
                    valueLabel: hourLabel
                )
            }
        }
    }

    // MARK: - Weekends

    private var weekendsCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_weekends"),
            icon: "calendar.badge.clock",
            iconColor: .teal
        ) {
            SPickerRow(
                label: String(localized: "settings.calendar.weekend_visibility"),
                selection: $weekendVisibilityRaw,
                options: [
                    WeekendVisibility.show.rawValue,
                    WeekendVisibility.dim.rawValue,
                    WeekendVisibility.hide.rawValue
                ],
                optionLabel: { raw in
                    switch WeekendVisibility(rawValue: raw) {
                    case .dim:  return String(localized: "settings.calendar.weekend.dim")
                    case .hide: return String(localized: "settings.calendar.weekend.hide")
                    default:    return String(localized: "settings.calendar.weekend.show")
                    }
                }
            )
        }
    }

    // MARK: - Sleep-friendly scheduling

    private var sleepFriendlyCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_sleep"),
            icon: "moon.zzz",
            iconColor: .purple
        ) {
            SToggleRow(
                label: String(localized: "settings.calendar.sleep_warn"),
                isOn: $sleepFriendlyEnabled
            )

            if sleepFriendlyEnabled {
                rowDivider
                SStepperRow(
                    label: String(localized: "settings.calendar.typical_day_starts"),
                    value: $sleepFriendlyStartHour,
                    range: 0...12,
                    valueLabel: hourLabel
                )
                rowDivider
                SStepperRow(
                    label: String(localized: "settings.calendar.typical_day_ends"),
                    value: $sleepFriendlyEndHour,
                    range: 18...24,
                    valueLabel: hourLabel
                )
            }
        }
    }

    // MARK: - Academics

    private var academicsCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_academics"),
            icon: "graduationcap",
            iconColor: .green
        ) {
            SToggleRow(
                label: String(localized: "settings.calendar.grade_badges"),
                isOn: $gradeWeightBadgeEnabled
            )

            if gradeWeightBadgeEnabled {
                rowDivider
                gradeThresholdRow
            }

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.study_block_length"),
                selection: $studyBlockLengthMinutes,
                options: [30, 45, 60, 90, 120],
                optionLabel: durationLabel
            )

            rowDivider

            SPickerRow(
                label: String(localized: "settings.calendar.study_buffer"),
                selection: $studyBlockBufferMinutes,
                options: [0, 10, 15, 30],
                optionLabel: durationLabel
            )
        }
    }

    @ViewBuilder
    private var gradeThresholdRow: some View {
        HStack(alignment: .center) {
            Text(String(localized: "settings.calendar.badge_threshold"))
                .font(DesignSystem.Fonts.body(weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Slider(value: $gradeWeightThreshold, in: 5...50, step: 5)
                .frame(width: 140)
            Text("\(Int(gradeWeightThreshold))%")
                .font(DesignSystem.Fonts.caption1(weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }

    // MARK: - ICS subscriptions

    private var subscriptionsCard: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.card_ics_feeds", defaultValue: "Calendar Feed Subscriptions"),
            icon: "link.circle",
            iconColor: .cyan
        ) {
            SRow(
                label: String(
                    localized: "settings.calendar.ics_feeds_intro",
                    defaultValue: "Subscribe to read-only .ics, webcal, or RSS calendar feeds from Google Calendar, Outlook, university sites, and other providers."
                )
            )

            ForEach(icsSubscriptions) { sub in
                rowDivider
                ICSSubscriptionRow(subscription: sub) {
                    icsSubscriptions.removeAll(where: { $0.id == sub.id })
                    ICSSubscription.saveAll(icsSubscriptions)
                }
            }

            rowDivider

            if isAddingSubscription {
                addSubscriptionRow
            } else {
                Button {
                    isAddingSubscription = true
                } label: {
                    HStack {
                        Label(
                            String(localized: "settings.calendar.add_subscription"),
                            systemImage: "plus.circle"
                        )
                        .font(DesignSystem.Fonts.body(weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var addSubscriptionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                String(localized: "settings.calendar.paste_url_placeholder"),
                text: $subscriptionURLDraft
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .font(DesignSystem.Fonts.body())

            if let err = subscriptionURLError {
                Text(err)
                    .font(DesignSystem.Fonts.caption1())
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Per-calendar notifications

    @ViewBuilder
    private var perCalendarNotificationsCard: some View {
        if !calendarManager.connectedCalendars.isEmpty {
            SettingsCard(
                title: String(localized: "settings.calendar.card_notification_muting"),
                icon: "bell.slash",
                iconColor: DesignSystem.Colors.warning
            ) {
                SRow(
                    label: String(localized: "settings.calendar.mute_intro")
                )

                ForEach(calendarManager.connectedCalendars) { cal in
                    rowDivider
                    let isMuted = mutedCalendarIDs.contains(cal.id)
                    SToggleRow(
                        label: cal.name,
                        isOn: Binding(
                            get: { isMuted },
                            set: { newVal in toggleMute(calendarID: cal.id, muted: newVal) }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Reminders

    private var remindersCard: some View {
        SettingsCard(
            title: String(localized: "settings.notifications.card_title", defaultValue: "Reminders"),
            icon: "bell",
            iconColor: .orange
        ) {
            SToggleRow(
                label: String(localized: "settings.notifications.event_reminders"),
                isOn: $eventReminders
            )
        }
    }

    // MARK: - Helpers

    private var selectedDefaultCalendarName: String {
        if let match = calendarManager.connectedCalendars.first(where: { $0.id == defaultCalendarID }) {
            return match.name
        }
        return calendarManager.connectedCalendars.first?.name
            ?? String(localized: "settings.calendar.default_calendar_none", defaultValue: "None")
    }

    private var selectedTimezoneDisplay: String {
        let parts = timezoneIdentifier.split(separator: "/")
        if let last = parts.last {
            return String(last).replacingOccurrences(of: "_", with: " ")
        }
        return timezoneIdentifier
    }

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
        let lower = cleaned.lowercased()
        let feedKind: CalendarFeedKind
        if lower.hasSuffix(".rss") || lower.contains("/rss") || lower.contains("format=rss") {
            feedKind = .rss
        } else if lower.hasSuffix(".ics") || lower.contains("/ical/") {
            feedKind = .ics
        } else {
            feedKind = .auto
        }
        let sub = ICSSubscription(
            id: UUID().uuidString,
            urlString: cleaned,
            name: url.host ?? cleaned,
            refreshIntervalHours: 6,
            feedKind: feedKind
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
    var feedKind: CalendarFeedKind

    enum CodingKeys: String, CodingKey {
        case id, urlString, name, refreshIntervalHours, feedKind
    }

    init(
        id: String,
        urlString: String,
        name: String,
        refreshIntervalHours: Int,
        feedKind: CalendarFeedKind = .auto
    ) {
        self.id = id
        self.urlString = urlString
        self.name = name
        self.refreshIntervalHours = refreshIntervalHours
        self.feedKind = feedKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        urlString = try container.decode(String.self, forKey: .urlString)
        name = try container.decode(String.self, forKey: .name)
        refreshIntervalHours = try container.decode(Int.self, forKey: .refreshIntervalHours)
        feedKind = try container.decodeIfPresent(CalendarFeedKind.self, forKey: .feedKind) ?? .auto
    }

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
                .font(DesignSystem.Fonts.main(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                Text(subscription.urlString)
                    .font(DesignSystem.Fonts.main(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(subscription.feedKind == .rss ? "RSS feed" : "ICS / webcal feed")
                    .font(DesignSystem.Fonts.main(size: 10))
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "settings.calendar.subscription_refresh"), subscription.refreshIntervalHours))
                    .font(DesignSystem.Fonts.main(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(DesignSystem.Fonts.main(size: 13))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}
