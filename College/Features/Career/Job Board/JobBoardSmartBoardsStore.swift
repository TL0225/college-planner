// JobBoardSmartBoardsStore.swift
// Feature: Career / Job Board
// Purpose: Persists user-defined smart boards that combine multiple companies.

import Foundation
import Observation

@Observable
@MainActor
final class JobBoardSmartBoardsStore {
    static let shared = JobBoardSmartBoardsStore()

    private static let storageKey = "workday.smartBoards.v1"

    private(set) var boards: [JobBoardSmartBoard] = []

    private init() {
        loadFromUserDefaults()
    }

    func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([JobBoardSmartBoard].self, from: data)
        else {
            boards = []
            return
        }
        boards = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(boards) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func addBoard(_ board: JobBoardSmartBoard) {
        boards.append(board)
        persist()
    }

    func updateBoard(_ board: JobBoardSmartBoard) {
        guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        var normalized = board
        normalized.updatedAt = Date()
        boards[index] = normalized
        persist()
    }

    func removeBoard(id: UUID) {
        boards.removeAll { $0.id == id }
        persist()
    }

    func board(id: UUID) -> JobBoardSmartBoard? {
        boards.first { $0.id == id }
    }

    func resolvedCompanies(for board: JobBoardSmartBoard) -> [JobBoardCompany] {
        let store = JobBoardCompaniesStore.shared
        let idSet = Set(board.companyIDs)
        return store.enabledCompanies.filter { idSet.contains($0.id) }
    }
}
