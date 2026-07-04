// AppModels.swift
// Feature: App
// Purpose: App module — Course.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import Combine

enum AppPage: Equatable, Hashable {
    case degree
    case academics
    case transferDatabase
    case calendar
    case career
    case assistant
    case profile
    case settings
    case lms
    case documents
    case webShortcut(id: UUID)
    #if DEBUG
    case debug // Intelligence Service debugger
    #endif

    private static let shortcutRawPrefix = "Shortcut:"

    var rawValue: String {
        switch self {
        case .degree: return "Degree"
        case .academics: return "Academics"
        case .transferDatabase: return "Transfer Database"
        case .calendar: return "Calendar"
        case .career: return "Career"
        case .assistant: return "Assistant"
        case .profile: return "Profile"
        case .settings: return "Settings"
        case .lms: return "LMS"
        case .documents: return "Documents"
        case .webShortcut(let id):
            return Self.shortcutRawPrefix + id.uuidString
        #if DEBUG
        case .debug: return "Debug"
        #endif
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "Degree": self = .degree
        case "Academics": self = .academics
        case "Transfer Database": self = .transferDatabase
        case "Calendar": self = .calendar
        case "Career": self = .career
        case "Assistant": self = .assistant
        case "Profile": self = .profile
        case "Settings": self = .settings
        case "LMS", "Brightspace": self = .lms
        case "Documents": self = .documents
        #if DEBUG
        case "Debug": self = .debug
        #endif
        default:
            if rawValue.hasPrefix(Self.shortcutRawPrefix) {
                let idText = String(rawValue.dropFirst(Self.shortcutRawPrefix.count))
                guard let id = UUID(uuidString: idText) else { return nil }
                self = .webShortcut(id: id)
            } else {
                return nil
            }
        }
    }
    
    var icon: String {
        switch self {
        case .degree: return "graduationcap.fill"
        case .academics: return "books.vertical.fill"
        case .transferDatabase: return "arrow.left.arrow.right.circle.fill"
        case .calendar: return "calendar"
        case .career: return "briefcase.fill"
        case .assistant: return "sparkles"
        case .profile: return "person.fill"
        case .settings: return "gearshape.fill"
        case .lms: return "network"
        case .documents: return "folder.fill"
        case .webShortcut: return "link.circle.fill"
        #if DEBUG
        case .debug: return "wrench.and.screwdriver.fill"
        #endif
        }
    }
    
    var color: Color {
        switch self {
        case .degree: return DesignSystem.Colors.primary
        case .academics: return Color(hex: "4f46e5")
        case .transferDatabase: return Color(hex: "0891b2")
        case .calendar: return Color.black
        case .career: return Color(hex: "2563eb")
        case .assistant: return Color(hex: "0ea5e9")
        case .profile: return DesignSystem.Colors.info
        case .settings: return DesignSystem.Colors.textMain
        case .lms: return Color(hex: "0ea5e9")
        case .documents: return Color(hex: "3451b2")
        case .webShortcut: return DesignSystem.Colors.primary
        #if DEBUG
        case .debug: return Color.purple
        #endif
        }
    }
    
    var displayTitle: String {
        switch self {
        case .degree: return "Overview"
        case .academics: return "Academics"
        case .transferDatabase: return "Transfer Database"
        case .calendar: return "Calendar"
        case .career: return "Career"
        case .assistant: return "AI Assistant"
        case .profile: return "Profile"
        case .settings: return "Settings"
        case .lms: return LMSPortalConfiguration.lmsDisplayName
        case .documents: return "Documents"
        case .webShortcut(let id):
            return WebShortcutStore.shortcutSync(id: id)?.title ?? "Shortcut"
        #if DEBUG
        case .debug: return "Debug"
        #endif
        }
    }

    var preloadFeatureID: String {
        switch self {
        case .degree: return "degree"
        case .academics: return "academics"
        case .transferDatabase: return "transferDatabase"
        case .calendar: return "calendar"
        case .career: return "career"
        case .assistant: return "assistant"
        case .profile: return "profile"
        case .settings: return "settings"
        case .lms: return "lms"
        case .documents: return "documents"
        case .webShortcut: return "webShortcut"
        #if DEBUG
        case .debug: return "debug"
        #endif
        }
    }

    static var preloadCoverageFeatureIDs: [String] {
        var ids: [String] = [
            "degree",
            "academics",
            "transferDatabase",
            "calendar",
            "career",
            "assistant",
            "profile",
            "settings",
            "lms",
            "documents",
        ]
        #if DEBUG
        ids.append("debug")
        #endif
        return ids
    }
}

// MARK: - App appearance (Light / Dark / System)

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct Course: Identifiable, Hashable {
    let id = UUID()
    let code: String
    let name: String
    let credits: Int
    let type: String // e.g., "Design & Dev", "Summer"
    let isCompleted: Bool
    let grade: String?
}

struct Semester: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let year: Int
    let season: String // "Fall", "Spring", "Winter", "Summer"
    var courses: [Course]
    var isPlanned: Bool
    
    var totalCredits: Int {
        courses.reduce(0) { $0 + $1.credits }
    }
    
    var progress: Double {
        // Dummy logic for progress
        return isPlanned ? 0.0 : 1.0
    }
}

// Semester Manager
class SemesterManager: ObservableObject {
    @Published var semesters: [Semester] = []
    
    // Helper function to get the numeric order of a season
    private func seasonOrder(_ season: String) -> Int {
        switch season {
        case "Fall": return 0
        case "Winter": return 1
        case "Spring": return 2
        case "Summer": return 3
        default: return 4
        }
    }
    
    func addSemester(term: String, year: String) {
        guard let yearInt = Int(year) else { return }
        let name = "\(term) \(year)"
        let newSemester = Semester(name: name, year: yearInt, season: term, courses: [], isPlanned: true)
        semesters.append(newSemester)
        
        // Sort semesters by year (ascending), then by season order (Winter, Spring, Summer, Fall)
        semesters.sort { semester1, semester2 in
            if semester1.year != semester2.year {
                return semester1.year < semester2.year
            }
            return seasonOrder(semester1.season) < seasonOrder(semester2.season)
        }
    }
}

// Mock Data
let mockSemesters: [Semester] = [
    Semester(name: "Fall 2026", year: 2026, season: "Fall", courses: [
        Course(code: "CS 1110", name: "Intro to Computing", credits: 4, type: "Design & Dev", isCompleted: false, grade: nil)
    ], isPlanned: true),
    Semester(name: "Spring 2026", year: 2026, season: "Spring", courses: [], isPlanned: true),
    Semester(name: "Fall 2025", year: 2025, season: "Fall", courses: [], isPlanned: true),
    Semester(name: "Spring 2025", year: 2025, season: "Spring", courses: [], isPlanned: true),
    Semester(name: "Fall 2023", year: 2023, season: "Fall", courses: [
        Course(code: "CS 1109", name: "Fundamental Prog.", credits: 2, type: "Summer", isCompleted: true, grade: "A")
    ], isPlanned: false)
]
