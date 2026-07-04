// JobBoardUSAJobsCredentials.swift
// Feature: Career / Job Board Scrapers / USAJobs
// Purpose: Persist USAJobs API credentials (developer.usajobs.gov).

import Foundation

enum JobBoardUSAJobsCredentials {
    private static let apiKeyStorageKey = "jobBoard.usajobs.apiKey"
    private static let userEmailStorageKey = "jobBoard.usajobs.userEmail"

    static var apiKey: String? {
        get {
            if let env = ProcessInfo.processInfo.environment["COLLEGE_USAJOBS_API_KEY"],
               !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return env.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let stored = UserDefaults.standard.string(forKey: apiKeyStorageKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored?.isEmpty == false ? stored : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: apiKeyStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: apiKeyStorageKey)
            }
        }
    }

    static var userEmail: String? {
        get {
            if let env = ProcessInfo.processInfo.environment["COLLEGE_USAJOBS_USER_EMAIL"],
               !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return env.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let stored = UserDefaults.standard.string(forKey: userEmailStorageKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored?.isEmpty == false ? stored : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: userEmailStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userEmailStorageKey)
            }
        }
    }

    static var isConfigured: Bool {
        apiKey != nil && userEmail != nil
    }
}
