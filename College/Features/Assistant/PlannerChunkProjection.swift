// PlannerChunkProjection.swift
// Feature: Assistant
// Purpose: Assistant module — IndexedChunk.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation
import SwiftData

/// Deterministic local store → planner text + stable chunk ids for ``PlannerVectorStore``.
enum PlannerChunkProjection {
    struct IndexedChunk: Sendable, Equatable {
        let chunkId: String
        let sourceType: String
        let sourceId: String
        let segmentIndex: Int
        let ftsBody: String
        let metadataJSON: String
        let contentHash: String
        let referenceDate: Date?
    }

    static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func chunks(from event: CalendarEvent) -> [IndexedChunk] {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (event.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let courseCode = (event.course?.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let guestsRaw = (event.attendeesJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = ["Event: \(title.isEmpty ? "Untitled" : title)"]
        parts.append("Starts: \(isoDate(event.startDate))")
        if !courseCode.isEmpty { parts.append("Course: \(courseCode)") }
        if !location.isEmpty { parts.append("Location: \(location)") }
        if !notes.isEmpty { parts.append("Notes: \(notes)") }
        if !guestsRaw.isEmpty { parts.append("Guests: \(guestsRaw)") }
        let body = parts.joined(separator: "\n")
        return segment(body: body, sourceType: "calendar_event", sourceId: event.id.uuidString, referenceDate: event.startDate)
    }

    static func chunks(from task: PlannerTask) -> [IndexedChunk] {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (task.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = ["Task: \(title.isEmpty ? "Untitled" : title)"]
        if let due = task.dueDate {
            parts.append("Due: \(isoDate(due))")
        }
        parts.append(task.isCompleted ? "Status: completed" : "Status: open")
        if !notes.isEmpty { parts.append("Notes: \(notes)") }
        let body = parts.joined(separator: "\n")
        return segment(body: body, sourceType: "task", sourceId: task.id.uuidString, referenceDate: task.dueDate ?? task.createdAt)
    }

    static func chunks(from course: PlannerCourse) -> [IndexedChunk] {
        let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let semester = (course.semester?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = ["Enrollment: \(code.isEmpty ? "course" : code)"]
        if !name.isEmpty { parts.append("Title: \(name)") }
        if !semester.isEmpty { parts.append("Semester: \(semester)") }
        if course.credits > 0 { parts.append("Credits: \(course.credits)") }
        let body = parts.joined(separator: "\n")
        return segment(body: body, sourceType: "enrollment", sourceId: course.id.uuidString, referenceDate: nil)
    }

    static func chunks(from application: JobApplication) -> [IndexedChunk] {
        let company = (application.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let role = (application.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let status = application.statusRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = ["Job application: \(company.isEmpty ? "Company" : company)"]
        if !role.isEmpty { parts.append("Role: \(role)") }
        if !status.isEmpty { parts.append("Stage: \(status)") }
        if let updated = application.updatedAt {
            parts.append("Updated: \(isoDate(updated))")
        }
        let body = parts.joined(separator: "\n")
        return segment(
            body: body,
            sourceType: "career_application",
            sourceId: application.id.uuidString,
            referenceDate: application.updatedAt ?? application.createdAt
        )
    }

    static func degreeProgressChunk(
        majors: [String],
        minors: [String],
        creditsEarned: Int,
        creditsRequired: Int,
        gpa: Double?
    ) -> IndexedChunk? {
        let body = """
        Degree progress: \(creditsEarned)/\(creditsRequired) credits
        Majors: \(majors.isEmpty ? "none" : majors.joined(separator: ", "))
        Minors: \(minors.isEmpty ? "none" : minors.joined(separator: ", "))
        GPA: \(gpa.map { String(format: "%.2f", $0) } ?? "unknown")
        """
        let hash = contentHash(for: body)
        let chunkId = "degree_progress:profile#0"
        let meta: [String: Any] = ["type": "degree_progress", "chunkIndex": 0]
        let metaJSON = (try? JSONSerialization.data(withJSONObject: meta))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return IndexedChunk(
            chunkId: chunkId,
            sourceType: "degree_progress",
            sourceId: "profile",
            segmentIndex: 0,
            ftsBody: body,
            metadataJSON: metaJSON,
            contentHash: hash,
            referenceDate: nil
        )
    }

    static func vaultMetadataChunks(from doc: VaultDocument) -> [IndexedChunk] {
        guard !doc.isFolder else { return [] }
        let name = (doc.customDisplayName ?? doc.fileName).trimmingCharacters(in: .whitespacesAndNewlines)
        let category = doc.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = (doc.tags ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (doc.userNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = ["Document: \(name.isEmpty ? "Untitled" : name)"]
        if !category.isEmpty { parts.append("Category: \(category)") }
        if !tags.isEmpty { parts.append("Tags: \(tags)") }
        if !notes.isEmpty { parts.append("Notes: \(notes)") }
        let body = parts.joined(separator: "\n")
        return segment(
            body: body,
            sourceType: "vault_document",
            sourceId: doc.id.uuidString,
            referenceDate: doc.addedAt
        )
    }

    @MainActor
    static func fetchAllChunks(collegePersistence: CollegePersistence = .shared) -> [IndexedChunk] {
        var out: [IndexedChunk] = []
        let cal = collegePersistence.calendarRepository
        let profile = collegePersistence.profileRepository
        let vault = collegePersistence.vaultRepository
        let career = collegePersistence.careerRepository

        if let events = try? cal.fetchEvents(from: .distantPast, to: .distantFuture, limit: 5000) {
            for event in events { out.append(contentsOf: chunks(from: event)) }
        }
        if let tasks = try? cal.fetchTasks(dueBefore: .distantFuture, limit: 5000) {
            for task in tasks { out.append(contentsOf: chunks(from: task)) }
        }
        for course in ProfilePlannerReadBridge.allCoursesAcrossPlans(collegePersistence: collegePersistence) {
            out.append(contentsOf: chunks(from: course))
        }
        if let apps = try? career.fetchApplications(limit: 500) {
            for app in apps { out.append(contentsOf: chunks(from: app)) }
        }
        if let docs = try? vault.fetchDocuments(limit: 5000) {
            for doc in docs where !doc.isFolder {
                out.append(contentsOf: vaultMetadataChunks(from: doc))
            }
        }
        if let primary = collegePersistence.primaryAcademicProfile {
            let majors = AcademicProfileProgramLists.majors(from: primary)
            let minors = AcademicProfileProgramLists.minors(from: primary)
            if let chunk = degreeProgressChunk(
                majors: majors,
                minors: minors,
                creditsEarned: Int(primary.creditsEarned ?? 0),
                creditsRequired: Int(primary.creditsRequired ?? 120),
                gpa: primary.gpa
            ) {
                out.append(chunk)
            }
        }
        _ = profile
        return out
    }

    static func vaultTextChunks(documentId: UUID, plainText: String, referenceDate: Date?) -> [IndexedChunk] {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let segments = chunkText(trimmed, targetCharacters: 2_400, overlapCharacters: 256)
        return segments.enumerated().map { index, text in
            let hash = contentHash(for: text)
            let chunkId = "vault_document:\(documentId.uuidString)#\(index)"
            let meta: [String: Any] = [
                "type": "vault_document",
                "documentId": documentId.uuidString,
                "chunkIndex": index,
                "referenceDateISO": referenceDate.map(isoDate) as Any,
            ]
            let metaJSON = (try? JSONSerialization.data(withJSONObject: meta))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return IndexedChunk(
                chunkId: chunkId,
                sourceType: "vault_document",
                sourceId: documentId.uuidString,
                segmentIndex: index,
                ftsBody: text,
                metadataJSON: metaJSON,
                contentHash: hash,
                referenceDate: referenceDate
            )
        }
    }

    // MARK: - Internals

    private static func segment(
        body: String,
        sourceType: String,
        sourceId: String,
        referenceDate: Date?
    ) -> [IndexedChunk] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let segments = chunkText(trimmed, targetCharacters: 1_200, overlapCharacters: 128)
        return segments.enumerated().map { index, text in
            let hash = contentHash(for: text)
            let chunkId = "\(sourceType):\(sourceId)#\(index)"
            let meta: [String: Any] = [
                "type": sourceType,
                "sourceId": sourceId,
                "chunkIndex": index,
                "referenceDateISO": referenceDate.map(isoDate) as Any,
            ]
            let metaJSON = (try? JSONSerialization.data(withJSONObject: meta))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return IndexedChunk(
                chunkId: chunkId,
                sourceType: sourceType,
                sourceId: sourceId,
                segmentIndex: index,
                ftsBody: text,
                metadataJSON: metaJSON,
                contentHash: hash,
                referenceDate: referenceDate
            )
        }
    }

    private static func chunkText(_ text: String, targetCharacters: Int, overlapCharacters: Int) -> [String] {
        guard text.count > targetCharacters else { return [text] }
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: targetCharacters, limitedBy: text.endIndex) ?? text.endIndex
            out.append(String(text[start..<end]))
            if end >= text.endIndex { break }
            let overlapStart = text.index(end, offsetBy: -overlapCharacters, limitedBy: text.startIndex) ?? start
            start = overlapStart
        }
        return out
    }

    private static func isoDate(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: date)
    }
}
