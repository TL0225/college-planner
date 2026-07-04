// ScreeningQuestionSynonymRegistry.swift
// Feature: Career / ApplicationProfile

import Foundation

enum ScreeningQuestionSynonymRegistry {
    static func preferenceKey(forQuestion question: String) -> String? {
        let normalized = normalize(question)
        if normalized.contains("u.s") && normalized.contains("citizen") { return "workAuthorization.usCitizen" }
        if normalized.contains("authorized") && normalized.contains("work") { return "workAuthorization.usAuthorized" }
        if normalized.contains("sponsorship") && normalized.contains("now") { return "workAuthorization.requiresSponsorshipNow" }
        if normalized.contains("sponsorship") && normalized.contains("future") { return "workAuthorization.requiresSponsorshipFuture" }
        if normalized.contains("require") && normalized.contains("sponsorship") { return "workAuthorization.requiresSponsorshipNow" }
        if normalized.contains("relocate") { return "preferences.willingToRelocate" }
        if normalized.contains("salary") || normalized.contains("compensation") { return "preferences.salaryExpectation" }
        if normalized.contains("18") && normalized.contains("older") { return "eligibility.age18OrOlder" }
        return nil
    }

    static func answer(
        forKey key: String,
        profile: ApplyApplicationProfile
    ) -> String? {
        switch key {
        case "workAuthorization.usCitizen":
            return profile.workAuthorization.usCitizen.map { $0 ? "Yes" : "No" }
        case "workAuthorization.usAuthorized":
            return profile.workAuthorization.usAuthorized.map { $0 ? "Yes" : "No" }
        case "workAuthorization.requiresSponsorshipNow":
            return profile.workAuthorization.requiresSponsorshipNow.map { $0 ? "Yes" : "No" }
        case "workAuthorization.requiresSponsorshipFuture":
            return profile.workAuthorization.requiresSponsorshipFuture.map { $0 ? "Yes" : "No" }
        case "preferences.willingToRelocate":
            return profile.preferences.willingToRelocate
        case "preferences.salaryExpectation":
            return profile.preferences.salaryExpectation
        default:
            return profile.screeningAnswerCache[key]?.answer
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "u.s.", with: "us")
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
