import Foundation

/// Parses RSS 2.0 and Atom calendar feeds into normalized calendar events.
public enum RSSCalendarParser {
    public static func parse(data: Data) throws -> [ICSCalendarParser.ParsedEvent] {
        let parser = FeedXMLParser(data: data)
        guard parser.parse() else {
            throw RSSParseError.invalidXML
        }
        return parser.events
    }

    public static func looksLikeFeed(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8)?.lowercased() else { return false }
        return prefix.contains("<rss")
            || prefix.contains("<feed")
            || prefix.contains("<rdf:rdf")
    }
}

public enum RSSParseError: Error {
    case invalidXML
}

private final class FeedXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private(set) var events: [ICSCalendarParser.ParsedEvent] = []

    private var rootKind: RootKind = .unknown
    private var inItem = false
    private var currentElement = ""
    private var currentText = ""

    private var title = ""
    private var link = ""
    private var pubDate = ""
    private var descriptionText = ""
    private var startDate = ""
    private var endDate = ""
    private var uid = ""

    private enum RootKind {
        case unknown, rss, atom
    }

    init(data: Data) {
        self.data = data
    }

    func parse() -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        let name = elementName.lowercased()
        if rootKind == .unknown {
            if name == "rss" { rootKind = .rss }
            if name == "feed" { rootKind = .atom }
        }
        if name == "item" || name == "entry" {
            resetItem()
            inItem = true
        }
        if inItem, name == "link", let href = attributeDict["href"], !href.isEmpty {
            link = href
        }
        if inItem, name == "id", rootKind == .atom {
            uid = ""
        }
        if inItem, let when = attributeDict["start"] ?? attributeDict["end"] {
            if name.contains("start") || attributeDict.keys.contains(where: { $0.lowercased().contains("start") }) {
                startDate = when
            }
            if name.contains("end") {
                endDate = when
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        guard inItem else { return }

        switch name {
        case "title":
            title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "link" where link.isEmpty:
            link = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "pubdate", "published", "updated":
            if pubDate.isEmpty {
                pubDate = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "description", "summary", "content":
            if descriptionText.isEmpty {
                descriptionText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "id":
            if uid.isEmpty {
                uid = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "item", "entry":
            appendCurrentItem()
            inItem = false
        default:
            break
        }
        currentText = ""
    }

    private func resetItem() {
        title = ""
        link = ""
        pubDate = ""
        descriptionText = ""
        startDate = ""
        endDate = ""
        uid = ""
    }

    private func appendCurrentItem() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let resolvedUID = uid.nilIfEmpty ?? link.nilIfEmpty ?? trimmedTitle
        let start = parseDate(startDate)
            ?? parseDate(pubDate)
            ?? parseDateFromText(trimmedTitle)
            ?? parseDateFromText(descriptionText)
        guard let start else { return }
        let end = parseDate(endDate) ?? start.addingTimeInterval(86_400)

        events.append(
            ICSCalendarParser.ParsedEvent(
                uid: resolvedUID,
                title: trimmedTitle,
                start: start,
                end: end,
                allDay: startDate.count <= 10 || !startDate.contains("T"),
                location: nil,
                notes: descriptionText.nilIfEmpty
            )
        )
    }

    private func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private func parseDateFromText(_ text: String) -> Date? {
        let pattern = #"\b(\d{4}-\d{2}-\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return parseDate(String(text[range]))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
