import Foundation
import SwiftUI
import Combine

enum AppPage: String, CaseIterable {
    case degree = "Degree"
    case calendar = "Calendar"
    case whatIf = "What If"
    case flowChart = "FlowChart"
    case resources = "Resources"
    case profile = "Profile"
    case settings = "Settings"
    case debug = "Debug" // Intelligence Service debugger
    
    var icon: String {
        switch self {
        case .degree: return "graduationcap.fill"
        case .calendar: return "calendar"
        case .whatIf: return "arrow.triangle.branch"
        case .flowChart: return "arrow.up.arrow.down.square"
        case .resources: return "books.vertical.fill"
        case .profile: return "person.fill"
        case .settings: return "gearshape.fill"
        case .debug: return "wrench.and.screwdriver.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .degree: return DesignSystem.Colors.primary
        case .calendar: return DesignSystem.Colors.primary
        case .whatIf: return DesignSystem.Colors.secondary
        case .flowChart: return DesignSystem.Colors.accent
        case .resources: return DesignSystem.Colors.warning
        case .profile: return DesignSystem.Colors.info
        case .settings: return DesignSystem.Colors.textMain
        case .debug: return Color.purple
        }
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
