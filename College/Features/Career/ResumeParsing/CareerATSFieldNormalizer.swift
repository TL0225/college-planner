// CareerATSFieldNormalizer.swift
// Feature: Career / ResumeParsing
// Purpose: Normalize dates, phones, links for ATS apply payloads.

import Foundation

enum CareerATSFieldNormalizer {
    static func normalizePhone(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : digits
    }

    static func normalizeEmail(_ raw: String?) -> String? {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizeURL(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http") { value = "https://" + value }
        return value
    }

    static func expandAcronym(_ token: String, aliases: [String: String]) -> String {
        aliases[token.uppercased()] ?? token
    }

    static func normalizePayload(_ payload: CareerApplicationAutofillPayload) -> CareerApplicationAutofillPayload {
        var copy = payload
        copy.personal.email = normalizeEmail(copy.personal.email)
        copy.personal.phone = normalizePhone(copy.personal.phone)
        copy.personal.linkedInURL = normalizeURL(copy.personal.linkedInURL)
        copy.personal.githubURL = normalizeURL(copy.personal.githubURL)
        copy.personal.portfolioURL = normalizeURL(copy.personal.portfolioURL)
        copy.experienceBlocks = copy.experienceBlocks.map { block in
            var next = block
            next.positions = block.positions.map { position in
                var pos = position
                pos.startDate = ResumeATSDates.normalizeForATS(position.startDate)
                pos.endDate = ResumeATSDates.normalizeForATS(position.endDate)
                return pos
            }
            return next
        }
        copy.education = copy.education.map { entry in
            var next = entry
            next.graduation = ResumeATSDates.normalizeForATS(entry.graduation)
            return next
        }
        return copy
    }
}
