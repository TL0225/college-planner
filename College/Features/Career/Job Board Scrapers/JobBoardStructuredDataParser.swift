// JobBoardStructuredDataParser.swift
// Feature: Career / Job Board Scrapers
// Purpose: JSON-LD JobPosting extraction shared by public hub scrapers.

import Foundation

struct JobBoardStructuredJobPosting: Sendable, Equatable {
    var title: String?
    var descriptionHTML: String?
    var descriptionPlain: String?
    var datePosted: String?
    var employmentType: String?
    var locationText: String?
    var applyURL: String?
    var identifier: String?
}

enum JobBoardStructuredDataParser {
    static func extractJobPostings(from html: String) -> [JobBoardStructuredJobPosting] {
        let blocks = jsonLDBlocks(from: html)
        return blocks.compactMap(parseJobPostingObject)
    }

    static func firstJobPosting(in html: String) -> JobBoardStructuredJobPosting? {
        extractJobPostings(from: html).first
    }

    static func jsonLDBlocks(from html: String) -> [[String: Any]] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var results: [[String: Any]] = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) else { continue }
            let jsonText = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            if let dict = object as? [String: Any] {
                results.append(dict)
            } else if let array = object as? [[String: Any]] {
                results.append(contentsOf: array)
            }
        }
        return results
    }

    private static func parseJobPostingObject(_ object: [String: Any]) -> JobBoardStructuredJobPosting? {
        if let type = object["@type"] as? String, type.lowercased().contains("jobposting") {
            return mapPosting(object)
        }
        if let graph = object["@graph"] as? [[String: Any]] {
            for node in graph {
                if let type = node["@type"] as? String, type.lowercased().contains("jobposting") {
                    return mapPosting(node)
                }
            }
        }
        return nil
    }

    private static func mapPosting(_ object: [String: Any]) -> JobBoardStructuredJobPosting {
        var posting = JobBoardStructuredJobPosting()
        posting.title = object["title"] as? String
        if let desc = object["description"] as? String {
            posting.descriptionHTML = desc
            posting.descriptionPlain = JobBoardHTTP.htmlToPlain(desc)
        }
        posting.datePosted = object["datePosted"] as? String
        posting.employmentType = object["employmentType"] as? String
        posting.identifier = (object["identifier"] as? [String: Any])?["value"] as? String
            ?? object["identifier"] as? String
        if let loc = object["jobLocation"] as? [String: Any],
           let address = loc["address"] as? [String: Any] {
            let city = address["addressLocality"] as? String
            let region = address["addressRegion"] as? String
            posting.locationText = [city, region].compactMap { $0 }.joined(separator: ", ")
        }
        if let url = object["url"] as? String { posting.applyURL = url }
        return posting
    }
}
