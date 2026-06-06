// CareerIngestCoordinator.swift
// Feature: Career
// Purpose: Career module — CareerIngestCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CollegeCareer

@MainActor
final class CareerIngestCoordinator {
    static let shared = CareerIngestCoordinator()

    private let fm = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let ingestFileName = "career_ingest_payload.json"
    private let parseResultFileName = "career_parse_result.json"
    private let saveRequestFileName = "career_save_request.json"
    private let ingestFreshnessInterval: TimeInterval = 15 * 60

    func writeIngestPayload(url: URL, text: String, requestId: UUID = UUID()) throws -> CareerIngestPayload {
        let payload = CareerIngestPayload(requestId: requestId, sourceURL: url.absoluteString, rawText: text, createdAt: Date())
        try write(payload, to: ingestFileName)
        return payload
    }

    func validatePendingIngest(requestId: UUID) async -> Bool {
        guard let payload: CareerIngestPayload = read(from: ingestFileName) else { return false }
        guard payload.requestId == requestId else { return false }
        guard Date().timeIntervalSince(payload.createdAt) <= ingestFreshnessInterval else {
            try? deleteFile(named: ingestFileName)
            return false
        }
        return true
    }

    func processPendingIngestIfNeeded() async {
        guard let payload: CareerIngestPayload = read(from: ingestFileName) else { return }
        guard Date().timeIntervalSince(payload.createdAt) <= ingestFreshnessInterval else {
            try? deleteFile(named: ingestFileName)
            return
        }
        guard let result = await CareerAIService.shared.parseJobPosting(payload) else { return }
        do {
            try write(result, to: parseResultFileName)
            postDarwin(name: "career.parseResultReady")
            try? deleteFile(named: ingestFileName)
        } catch {
            print("[CareerIngest] Failed writing parse result: \(error.localizedDescription)")
        }
    }

    func readParseResult() -> CareerParseResult? {
        read(from: parseResultFileName)
    }

    func writeSaveRequest(_ request: CareerSaveRequest) throws {
        try write(request, to: saveRequestFileName)
        postDarwin(name: "career.saveRequestReady")
    }

    func processPendingSaveRequests() async {
        guard let request: CareerSaveRequest = read(from: saveRequestFileName) else { return }
        CollegePersistence.shared.upsertCareerApplication(from: request)
        try? deleteFile(named: saveRequestFileName)
        try? deleteFile(named: parseResultFileName)
    }

    private func appGroupDirectory() -> URL {
        if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.timothy.college") {
            return url
        }
        let fallback = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CareerIPC", isDirectory: true)
        if !fm.fileExists(atPath: fallback.path) {
            try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        }
        return fallback
    }

    private func fileURL(for name: String) -> URL {
        appGroupDirectory().appendingPathComponent(name, isDirectory: false)
    }

    private func write<T: Codable>(_ value: T, to file: String) throws {
        let plain = try encoder.encode(value)
        let stored = SecurityManager.shared.encryptBlobForStorage(plain) ?? plain
        try stored.write(to: fileURL(for: file), options: [.atomic])
    }

    private func read<T: Codable>(from file: String) -> T? {
        let url = fileURL(for: file)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let data = SecurityManager.shared.decryptBlobFromStorage(raw) ?? raw
        return try? decoder.decode(T.self, from: data)
    }

    private func deleteFile(named name: String) throws {
        let url = fileURL(for: name)
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }

    private func postDarwin(name: String) {
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), cfName, nil, nil, true)
    }
}
