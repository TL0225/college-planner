import Foundation

public enum CareerSubView: String, CaseIterable, Identifiable, Hashable, Sendable {
    case board = "Board"
    case openings = "Openings"
    case stats = "Stats"
    case resumes = "Resumes"
    case stories = "Stories"
    case networking = "Networking"

    public var id: String { rawValue }
}

public enum CareerBoardLayout: String, CaseIterable, Identifiable, Sendable {
    case kanban
    case list

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kanban: return "Kanban Board"
        case .list: return "List"
        }
    }

    public static let storageKey = "career.board.layout"
}
