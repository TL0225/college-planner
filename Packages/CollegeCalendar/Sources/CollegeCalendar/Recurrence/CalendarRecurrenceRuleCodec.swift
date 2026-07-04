import EventKit
import Foundation

/// Encodes/decodes stored recurrence payloads for Google Calendar, EventKit, and local JSON storage.
public enum CalendarRecurrenceRuleCodec {
    public struct RecurrenceSettings: Codable, Equatable, Sendable {
        public let frequency: String
        public let interval: Int
        public let weekdays: [Int]
        public let endDate: Date?

        public static let none = RecurrenceSettings(
            frequency: "none",
            interval: 1,
            weekdays: [],
            endDate: nil
        )

        public init(frequency: String, interval: Int, weekdays: [Int], endDate: Date?) {
            self.frequency = frequency
            self.interval = interval
            self.weekdays = weekdays
            self.endDate = endDate
        }
    }

    private static let recurrenceOptions = ["none", "daily", "weekly", "monthly", "yearly"]

    private static let googleByDaySymbols = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    // MARK: - Decode stored rule

    public static func recurrenceSettings(fromStoredRule raw: String?) -> RecurrenceSettings {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }

        if raw.hasPrefix("FREQ=") || raw.contains("RRULE:") {
            return recurrenceSettings(fromRRULE: raw)
        }

        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RecurrenceSettings.self, from: data)
        {
            return normalized(decoded)
        }

        let legacy = normalizedFrequency(raw)
        if legacy == "none" { return .none }
        return RecurrenceSettings(frequency: legacy, interval: 1, weekdays: [], endDate: nil)
    }

    // MARK: - Google export

    /// Returns false when weekly recurrence is selected without any weekdays.
    public static func isSavableRecurrence(frequency: String, weekdays: [Int]) -> Bool {
        let normalized = normalizedFrequency(frequency)
        if normalized == "none" { return true }
        if normalized == "weekly" { return !weekdays.isEmpty }
        return true
    }

    public static func googleRecurrenceArray(from recurrenceRule: String?) -> [String]? {
        let settings = recurrenceSettings(fromStoredRule: recurrenceRule)
        guard settings.frequency != "none" else { return nil }

        var parts = ["FREQ=\(settings.frequency.uppercased())"]
        if settings.interval > 1 {
            parts.append("INTERVAL=\(settings.interval)")
        }
        if settings.frequency == "weekly", !settings.weekdays.isEmpty {
            let days = settings.weekdays.sorted().compactMap { googleByDaySymbols[safe: $0 - 1] }
            if !days.isEmpty {
                parts.append("BYDAY=\(days.joined(separator: ","))")
            }
        }
        if let endDate = settings.endDate {
            parts.append("UNTIL=\(googleUntilString(from: endDate))")
        }
        return ["RRULE:\(parts.joined(separator: ";"))"]
    }

    // MARK: - EventKit export

    public static func ekRecurrenceRules(from recurrenceRule: String?) -> [EKRecurrenceRule]? {
        let settings = recurrenceSettings(fromStoredRule: recurrenceRule)
        guard settings.frequency != "none",
              let frequency = ekFrequency(from: settings.frequency)
        else { return nil }

        let daysOfWeek: [EKRecurrenceDayOfWeek]? = {
            guard settings.frequency == "weekly", !settings.weekdays.isEmpty else { return nil }
            let mapped = settings.weekdays.sorted().map {
                EKRecurrenceDayOfWeek(ekWeekday(fromAppWeekday: $0))
            }
            return mapped.isEmpty ? nil : mapped
        }()

        let end: EKRecurrenceEnd? = settings.endDate.map { EKRecurrenceEnd(end: $0) }

        let rule = EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: settings.interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
        return [rule]
    }

    // MARK: - EventKit import

    public static func storedRecurrenceRule(from ekRules: [EKRecurrenceRule]?) -> String? {
        guard let rule = ekRules?.first else { return nil }

        let frequency = storedFrequency(from: rule.frequency)
        guard frequency != "none" else { return nil }

        let interval = max(1, rule.interval)
        let weekdays: [Int] = (rule.daysOfTheWeek ?? [])
            .map { appWeekday(fromEKWeekday: $0.dayOfTheWeek) }
            .filter { (1...7).contains($0) }
            .sorted()

        let endDate = rule.recurrenceEnd?.endDate
        let settings = RecurrenceSettings(
            frequency: frequency,
            interval: interval,
            weekdays: weekdays,
            endDate: endDate
        )
        return storedPayloadString(from: settings)
    }

    // MARK: - Private helpers

    private static func normalized(_ settings: RecurrenceSettings) -> RecurrenceSettings {
        let frequency = normalizedFrequency(settings.frequency)
        if frequency == "none" { return .none }
        return RecurrenceSettings(
            frequency: frequency,
            interval: max(1, settings.interval),
            weekdays: Array(Set(settings.weekdays.filter { (1...7).contains($0) })).sorted(),
            endDate: settings.endDate
        )
    }

    private static func normalizedFrequency(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recurrenceOptions.contains(value) ? value : "none"
    }

    private static func storedPayloadString(from settings: RecurrenceSettings) -> String? {
        let normalized = normalized(settings)
        guard normalized.frequency != "none" else { return nil }
        guard let data = try? JSONEncoder().encode(normalized),
              let json = String(data: data, encoding: .utf8)
        else {
            return normalized.frequency
        }
        return json
    }

    private static func recurrenceSettings(fromRRULE raw: String) -> RecurrenceSettings {
        let rruleBody = raw.replacingOccurrences(of: "RRULE:", with: "")
        var frequency = "weekly"
        var interval = 1
        var weekdays: [Int] = []
        var endDate: Date?

        for part in rruleBody.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0].uppercased() {
            case "FREQ":
                frequency = storedFrequency(fromGoogle: kv[1])
            case "INTERVAL":
                interval = max(1, Int(kv[1]) ?? 1)
            case "BYDAY":
                weekdays = kv[1].split(separator: ",").compactMap { appWeekday(fromGoogleByDay: String($0)) }
            case "UNTIL":
                endDate = parseGoogleUntil(kv[1])
            default:
                break
            }
        }

        return normalized(
            RecurrenceSettings(
                frequency: frequency,
                interval: interval,
                weekdays: weekdays,
                endDate: endDate
            )
        )
    }

    private static func storedFrequency(fromGoogle raw: String) -> String {
        switch raw.uppercased() {
        case "DAILY": return "daily"
        case "WEEKLY": return "weekly"
        case "MONTHLY": return "monthly"
        case "YEARLY": return "yearly"
        default: return "none"
        }
    }

    private static func storedFrequency(from frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return "none"
        }
    }

    private static func ekFrequency(from stored: String) -> EKRecurrenceFrequency? {
        switch stored {
        case "daily": return .daily
        case "weekly": return .weekly
        case "monthly": return .monthly
        case "yearly": return .yearly
        default: return nil
        }
    }

    private static func ekWeekday(fromAppWeekday day: Int) -> EKWeekday {
        switch day {
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        case 6: return .saturday
        case 7: return .sunday
        default: return .monday
        }
    }

    private static func appWeekday(fromEKWeekday day: EKWeekday) -> Int {
        switch day {
        case .monday: return 1
        case .tuesday: return 2
        case .wednesday: return 3
        case .thursday: return 4
        case .friday: return 5
        case .saturday: return 6
        case .sunday: return 7
        @unknown default: return 1
        }
    }

    private static func appWeekday(fromGoogleByDay token: String) -> Int? {
        guard let index = googleByDaySymbols.firstIndex(of: token.uppercased()) else { return nil }
        return index + 1
    }

    private static func googleUntilString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func parseGoogleUntil(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let year = Int(trimmed.prefix(4)) ?? 0
        let monthStart = trimmed.index(trimmed.startIndex, offsetBy: 4)
        let monthEnd = trimmed.index(monthStart, offsetBy: 2)
        let dayStart = trimmed.index(monthEnd, offsetBy: 0)
        let dayEnd = trimmed.index(dayStart, offsetBy: 2)
        let month = Int(trimmed[monthStart..<monthEnd]) ?? 0
        let day = Int(trimmed[dayStart..<dayEnd]) ?? 0

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
