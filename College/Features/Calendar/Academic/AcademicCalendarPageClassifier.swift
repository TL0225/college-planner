// AcademicCalendarPageClassifier.swift
// Feature: Calendar
// Purpose: Classify academic calendar pages (ICS feed, hub, or calendar content).

import Foundation
import SwiftSoup

struct AcademicCalendarClassification: Sendable {
    var kind: AcademicCalendarPageKind
    var icsFeedURL: String?
    var subCalendars: [AcademicCalendarSubCalendarCandidate]
}

enum AcademicCalendarPageClassifier {
    static func classify(
        content: String,
        baseURL: URL,
        forcedMode: AcademicCalendarForcedMode?
    ) -> AcademicCalendarClassification {
        if let forcedMode, forcedMode != .auto {
            switch forcedMode {
            case .ics:
                let feed = detectICSFeed(in: content, baseURL: baseURL)
                return AcademicCalendarClassification(kind: .hasICSFeed, icsFeedURL: feed, subCalendars: [])
            case .hub:
                return AcademicCalendarClassification(kind: .indexHub, icsFeedURL: nil, subCalendars: extractSubCalendars(content: content, baseURL: baseURL))
            case .scrape:
                return AcademicCalendarClassification(kind: .calendar, icsFeedURL: nil, subCalendars: [])
            case .auto:
                break
            }
        }

        if let feed = detectICSFeed(in: content, baseURL: baseURL) {
            return AcademicCalendarClassification(kind: .hasICSFeed, icsFeedURL: feed, subCalendars: [])
        }

        let subCals = extractSubCalendars(content: content, baseURL: baseURL)
        let dateDensity = estimateDateDensity(content)
        if dateDensity < 3 && subCals.count >= 2 {
            return AcademicCalendarClassification(kind: .indexHub, icsFeedURL: nil, subCalendars: subCals)
        }
        return AcademicCalendarClassification(kind: .calendar, icsFeedURL: nil, subCalendars: subCals)
    }

    static func detectICSFeed(in content: String, baseURL: URL) -> String? {
        if let embedded = detectEmbeddedICSCID(in: content) {
            return normalizeFeedURL(embedded, baseURL: baseURL)
        }

        if let doc = try? SwiftSoup.parse(content, baseURL.absoluteString) {
            let anchors = (try? doc.select("a[href]").array()) ?? []
            for anchor in anchors {
                let href = (try? anchor.attr("href")) ?? ""
                let text = (try? anchor.text())?.lowercased() ?? ""
                if href.lowercased().contains(".ics")
                    || href.lowercased().hasPrefix("webcal://")
                    || href.lowercased().contains("/ical/")
                    || text.contains("add to my calendar")
                    || text.contains("ical feed")
                    || (text.contains("subscribe") && text.contains("calendar")) {
                    return normalizeFeedURL(href, baseURL: baseURL)
                }
            }
            let links = (try? doc.select("link[href]").array()) ?? []
            for link in links {
                let href = (try? link.attr("href")) ?? ""
                let type = (try? link.attr("type"))?.lowercased() ?? ""
                if type.contains("calendar") || href.lowercased().contains(".ics") || href.lowercased().contains("/ical/") {
                    return normalizeFeedURL(href, baseURL: baseURL)
                }
            }
        }
        let patterns = [
            #"(webcal|https?)://[^\s\"']+\.ics"#,
            #"https?://[^\s\"']+/ical/[^\s\"']+"#,
            #"cid=(https?://[^\s\"'&]+/ical/[^\s\"'&]+)"#
        ]
        for pattern in patterns {
            if let match = content.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                var candidate = String(content[match])
                if candidate.hasPrefix("cid=") {
                    candidate = String(candidate.dropFirst(4))
                }
                return normalizeFeedURL(candidate, baseURL: baseURL)
            }
        }
        return nil
    }

    static func detectRSSFeed(in content: String, baseURL: URL) -> String? {
        if let doc = try? SwiftSoup.parse(content, baseURL.absoluteString) {
            let anchors = (try? doc.select("a[href]").array()) ?? []
            for anchor in anchors {
                let href = (try? anchor.attr("href")) ?? ""
                let text = (try? anchor.text())?.lowercased() ?? ""
                if href.lowercased().contains(".rss")
                    || href.lowercased().contains("/rss")
                    || text.contains("rss feed")
                    || text.contains("rss") {
                    return normalizeFeedURL(href, baseURL: baseURL)
                }
            }
            let links = (try? doc.select("link[href]").array()) ?? []
            for link in links {
                let href = (try? link.attr("href")) ?? ""
                let type = (try? link.attr("type"))?.lowercased() ?? ""
                if type.contains("rss") || type.contains("atom") || href.lowercased().contains(".rss") {
                    return normalizeFeedURL(href, baseURL: baseURL)
                }
            }
        }
        if let match = content.range(of: #"https?://[^\s\"'<>]+\.rss"#, options: .regularExpression) {
            return normalizeFeedURL(String(content[match]), baseURL: baseURL)
        }
        return nil
    }

    private static func detectEmbeddedICSCID(in content: String) -> String? {
        let pattern = #"cid=(https?://[^\s\"'&]+/ical/[^\s\"'&]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[range])
    }

    static func extractSubCalendars(content: String, baseURL: URL) -> [AcademicCalendarSubCalendarCandidate] {
        var results: [AcademicCalendarSubCalendarCandidate] = []
        var seen = Set<String>()

        if let doc = try? SwiftSoup.parse(content, baseURL.absoluteString) {
            let anchors = (try? doc.select("a[href]").array()) ?? []
            for anchor in anchors {
                let label = (try? anchor.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let href = (try? anchor.attr("href")) ?? ""
                guard let candidate = makeSubCalendarCandidate(label: label, href: href, baseURL: baseURL) else { continue }
                if seen.insert(candidate.url).inserted {
                    results.append(candidate)
                }
            }
        }

        let urlPattern = #"https?://[^\s\"'<>]+"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
            for match in matches {
                guard let range = Range(match.range, in: content) else { continue }
                let href = String(content[range])
                guard let candidate = makeSubCalendarCandidate(label: href, href: href, baseURL: baseURL) else { continue }
                if seen.insert(candidate.url).inserted {
                    results.append(candidate)
                }
            }
        }

        return results.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private static func makeSubCalendarCandidate(
        label: String,
        href: String,
        baseURL: URL
    ) -> AcademicCalendarSubCalendarCandidate? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHref.isEmpty else { return nil }
        let lower = trimmedLabel.lowercased()
        guard lower.contains("calendar")
            || lower.contains("school")
            || lower.contains("college")
            || lower.contains("business")
            || lower.contains("law")
            || lower.contains("summer")
            || lower.contains("spring")
            || lower.contains("fall")
            || lower.contains("winter")
            || trimmedHref.lowercased().contains("calendar")
            || parseTermLabel(trimmedLabel) != nil
            || parseTermLabel(humanizedURL(trimmedHref)) != nil else {
            return nil
        }
        guard let resolved = URL(string: trimmedHref, relativeTo: baseURL)?.absoluteString else { return nil }
        if baseURL.scheme != nil, !resolved.hasPrefix("http") {
            return nil
        }
        let displayLabel: String
        if trimmedLabel.isEmpty || trimmedLabel == trimmedHref {
            displayLabel = humanizedURL(trimmedHref)
        } else {
            displayLabel = trimmedLabel
        }
        return AcademicCalendarSubCalendarCandidate(label: displayLabel, url: resolved)
    }

    private static func humanizedURL(_ href: String) -> String {
        let last = href.split(separator: "/").last.map(String.init) ?? href
        let stem = last
            .replacingOccurrences(of: ".php", with: "")
            .replacingOccurrences(of: ".html", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return stem.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    private static func parseTermLabel(_ line: String) -> (term: String, year: Int)? {
        AcademicCalendarDeterministicParser.parseTermHeader(line)
    }

    private static func estimateDateDensity(_ content: String) -> Int {
        let pattern = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return content.ranges(of: regex).count
    }

    private static func normalizeFeedURL(_ href: String, baseURL: URL) -> String? {
        var cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("webcal://") {
            cleaned = "https://" + cleaned.dropFirst("webcal://".count)
        }
        if cleaned.hasPrefix("http://") {
            cleaned = "https://" + cleaned.dropFirst("http://".count)
        }
        guard let url = URL(string: cleaned, relativeTo: baseURL) else { return nil }
        return url.absoluteString
    }
}

private extension String {
    func ranges(of regex: NSRegularExpression) -> [Range<String.Index>] {
        let ns = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, options: [], range: ns)
        return matches.compactMap { Range($0.range, in: self) }
    }
}
