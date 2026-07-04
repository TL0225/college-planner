import Foundation

extension CalendarIntegrationManager {
    func outlookRemoteKey(forLocalID localID: String) -> String? {
        outlookSyncMap.first(where: { $0.value == localID })?.key
    }

    func iCloudRemoteKey(forLocalID localID: String) -> String? {
        iCloudSyncMap.first(where: { $0.value == localID })?.key
    }

    func performOutlookExportAsync(event: CalendarStoredEvent, token: String) async -> Bool {
        let localIDString = event.id.uuidString
        let calendarID = await MainActor.run {
            connectedCalendars.first {
                $0.source == "Outlook" && enabledCalendarIDs.contains($0.id)
            }?.remoteID
        }
        guard let calendarID, !calendarID.isEmpty else { return false }

        let exportTimeZone = Self.exportTimeZone()
        let notes = Self.appendCourseTagNotesIfNeeded(event: event)
        let attendees = CalendarGuestInviteExporter.outlookAttendees(from: event.attendeesJSON)
        let payload = OutlookEventUpload(
            subject: event.title,
            body: OutlookItemBody(contentType: "text", content: notes ?? ""),
            start: outlookDateTime(from: event.startDate, allDay: event.allDay, timeZone: exportTimeZone),
            end: outlookDateTime(from: event.endDate, allDay: event.allDay, timeZone: exportTimeZone),
            isAllDay: event.allDay,
            location: event.location.map { OutlookLocation(displayName: $0) },
            attendees: attendees.isEmpty ? nil : attendees,
            recurrence: outlookRecurrence(from: event.recurrenceRule)
        )

        var existingRemoteID = outlookRemoteKey(forLocalID: localIDString)
        if existingRemoteID == nil,
           let providerEventId = event.providerEventId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !providerEventId.isEmpty
        {
            existingRemoteID = providerEventId
        }

        let urlString: String
        let httpMethod: String
        if let existingRemoteID {
            urlString = "https://graph.microsoft.com/v1.0/me/events/\(existingRemoteID)"
            httpMethod = "PATCH"
        } else {
            urlString = "https://graph.microsoft.com/v1.0/me/calendars/\(calendarID)/events"
            httpMethod = "POST"
        }

        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONEncoder().encode(payload) else { return false }
        request.httpBody = body

        do {
            let (data, response) = try await secureSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            if httpMethod == "POST",
               let created = try? JSONDecoder().decode(OutlookCreatedEventResponse.self, from: data)
            {
                await MainActor.run {
                    var map = outlookSyncMap
                    map[created.id] = localIDString
                    outlookSyncMap = map
                }
            } else if httpMethod == "PATCH", let existingRemoteID {
                await MainActor.run {
                    var map = outlookSyncMap
                    map[existingRemoteID] = localIDString
                    outlookSyncMap = map
                }
            }
            return true
        } catch {
            return false
        }
    }

    func performiCloudExportAsync(
        event: CalendarStoredEvent,
        username: String,
        password: String
    ) async -> Bool {
        let localIDString = event.id.uuidString
        let calendarURLString = await MainActor.run {
            connectedCalendars.first {
                $0.source == "iCloudCalDAV" && enabledCalendarIDs.contains($0.id)
            }?.remoteID
        }
        guard let calendarURLString,
              let calendarURL = URL(string: calendarURLString)
        else { return false }

        let existingKey = iCloudRemoteKey(forLocalID: localIDString)
        let uid: String
        if let existingKey, let existingUID = existingKey.split(separator: "||", maxSplits: 1).last {
            uid = String(existingUID)
        } else if let providerEventId = event.providerEventId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !providerEventId.isEmpty {
            uid = providerEventId
        } else {
            uid = event.id.uuidString
        }

        let notes = Self.appendCourseTagNotesIfNeeded(event: event)
        let exportTimeZone = Self.exportTimeZone()
        let ical = buildICalExport(
            uid: uid,
            title: event.title,
            start: event.startDate,
            end: event.endDate,
            allDay: event.allDay,
            location: event.location,
            notes: notes,
            localID: localIDString,
            timeZone: exportTimeZone,
            recurrenceRule: event.recurrenceRule,
            attendeesJSON: event.attendeesJSON
        )

        let eventURL = calendarURL.appendingPathComponent("\(uid).ics")
        var request = URLRequest(url: eventURL)
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        addCalDAVAuth(&request, username: username, password: password)
        request.httpBody = Data(ical.utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            await MainActor.run {
                var map = iCloudSyncMap
                map["\(calendarURLString)||\(uid)"] = localIDString
                iCloudSyncMap = map
            }
            return true
        } catch {
            return false
        }
    }

    private func outlookRecurrence(from recurrenceRule: String?) -> OutlookRecurrence? {
        let settings = CalendarRecurrenceRuleCodec.recurrenceSettings(fromStoredRule: recurrenceRule)
        guard settings.frequency != "none" else { return nil }

        let patternType: String
        switch settings.frequency {
        case "daily": patternType = "daily"
        case "weekly": patternType = "weekly"
        case "monthly": patternType = "absoluteMonthly"
        case "yearly": patternType = "absoluteYearly"
        default: return nil
        }

        let daysOfWeek: [String]? = {
            guard settings.frequency == "weekly", !settings.weekdays.isEmpty else { return nil }
            let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
            let mapped = settings.weekdays.compactMap { names[safe: $0 - 1] }
            return mapped.isEmpty ? nil : mapped
        }()

        let range: OutlookRecurrenceRange
        if let endDate = settings.endDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = Self.exportTimeZone()
            formatter.dateFormat = "yyyy-MM-dd"
            range = OutlookRecurrenceRange(type: "endDate", endDate: formatter.string(from: endDate), numberOfOccurrences: nil)
        } else {
            range = OutlookRecurrenceRange(type: "noEnd", endDate: nil, numberOfOccurrences: nil)
        }

        return OutlookRecurrence(
            pattern: OutlookRecurrencePattern(
                type: patternType,
                interval: max(1, settings.interval),
                daysOfWeek: daysOfWeek
            ),
            range: range
        )
    }

    private func outlookDateTime(from date: Date, allDay: Bool, timeZone: TimeZone) -> OutlookDateTimeTimeZone {
        if allDay {
            let day = Self.formatYMD(date, timeZone: timeZone)
            return OutlookDateTimeTimeZone(dateTime: day, timeZone: timeZone.identifier)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return OutlookDateTimeTimeZone(dateTime: formatter.string(from: date), timeZone: timeZone.identifier)
    }

    private func buildICalExport(
        uid: String,
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        location: String?,
        notes: String?,
        localID: String,
        timeZone: TimeZone,
        recurrenceRule: String?,
        attendeesJSON: String?
    ) -> String {
        let dtStart: String
        let dtEnd: String
        if allDay {
            dtStart = "DTSTART;VALUE=DATE:\(icalDateStamp(start, timeZone: timeZone))"
            dtEnd = "DTEND;VALUE=DATE:\(icalDateStamp(end, timeZone: timeZone))"
        } else {
            dtStart = "DTSTART;TZID=\(timeZone.identifier):\(icalDateTimeStamp(start, timeZone: timeZone))"
            dtEnd = "DTEND;TZID=\(timeZone.identifier):\(icalDateTimeStamp(end, timeZone: timeZone))"
        }

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//College//Calendar//EN",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "SUMMARY:\(icalEscape(title))",
            dtStart,
            dtEnd,
            "X-COLLEGE-LOCAL-ID:\(localID)",
        ]
        if let location, !location.isEmpty {
            lines.append("LOCATION:\(icalEscape(location))")
        }
        if let notes, !notes.isEmpty {
            lines.append("DESCRIPTION:\(icalEscape(notes))")
        }
        if let recurrenceLines = CalendarRecurrenceRuleCodec.googleRecurrenceArray(from: recurrenceRule) {
            lines.append(contentsOf: recurrenceLines)
        }
        lines.append(contentsOf: CalendarGuestInviteExporter.icalAttendeeLines(from: attendeesJSON))
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private func icalDateStamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func icalDateTimeStamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    private func icalEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

private struct OutlookEventUpload: Encodable {
    let subject: String
    let body: OutlookItemBody?
    let start: OutlookDateTimeTimeZone
    let end: OutlookDateTimeTimeZone
    let isAllDay: Bool
    let location: OutlookLocation?
    let attendees: [OutlookAttendeeUpload]?
    let recurrence: OutlookRecurrence?
}

private struct OutlookItemBody: Encodable {
    let contentType: String
    let content: String
}

private struct OutlookDateTimeTimeZone: Encodable {
    let dateTime: String
    let timeZone: String
}

private struct OutlookLocation: Encodable {
    let displayName: String
}

private struct OutlookRecurrence: Encodable {
    let pattern: OutlookRecurrencePattern
    let range: OutlookRecurrenceRange
}

private struct OutlookRecurrencePattern: Encodable {
    let type: String
    let interval: Int
    let daysOfWeek: [String]?
}

private struct OutlookRecurrenceRange: Encodable {
    let type: String
    let endDate: String?
    let numberOfOccurrences: Int?
}

private struct OutlookCreatedEventResponse: Decodable {
    let id: String
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
