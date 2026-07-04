import Foundation

public enum CalendarFeedKind: String, Codable, Sendable {
    case auto
    case ics
    case rss
}

/// Detects and parses ICS, webcal, and RSS/Atom calendar subscription feeds.
public enum CalendarFeedParser {
    public static func detectKind(urlString: String, data: Data) -> CalendarFeedKind {
        let lowerURL = urlString.lowercased()
        if lowerURL.hasSuffix(".ics") || lowerURL.contains("webcal://") || lowerURL.contains("/ical/") {
            return .ics
        }
        if lowerURL.hasSuffix(".rss") || lowerURL.contains("/rss") || lowerURL.contains("format=rss") {
            return .rss
        }
        if RSSCalendarParser.looksLikeFeed(data) {
            return .rss
        }
        if looksLikeICS(data) {
            return .ics
        }
        return .ics
    }

    public static func parse(data: Data, urlString: String, kind: CalendarFeedKind = .auto) throws -> [ICSCalendarParser.ParsedEvent] {
        let resolved = kind == .auto ? detectKind(urlString: urlString, data: data) : kind
        switch resolved {
        case .ics, .auto:
            return try ICSCalendarParser.parse(data: data)
        case .rss:
            return try RSSCalendarParser.parse(data: data)
        }
    }

    private static func looksLikeICS(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(256), encoding: .utf8)?.uppercased() else { return false }
        return prefix.contains("BEGIN:VCALENDAR")
    }
}
