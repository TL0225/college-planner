// UITestPersistenceSeeder.swift
// Feature: App
// Purpose: App module — UITestPersistenceSeeder.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

/// Parallel UI-test seed for local store profile partition (Phase 7c).
@MainActor
enum UITestPersistenceSeeder {
    static func seedUITestDataIfNeeded() {
        seedMinimalPlannerDataIfNeeded()
        seedDeclaredMajorDataIfNeeded()
        Task { @MainActor in
            await seedCareerResumesIfNeeded()
        }
    }

    static func seedMinimalPlannerDataIfNeeded() {
        guard UITestLaunchFlags.forcesMainUI, UITestLaunchFlags.seedMinimalPlannerData else { return }

        let context = AppDataStore.shared.profileContext
        let existingPlans = (try? ProfileRepository(context: context).fetchPlans(limit: 1)) ?? []
        guard existingPlans.isEmpty else { return }

        let profile = Profile(name: "UITest Student")
        let plan = PlannerPlan(name: "UITest Plan", type: "Major")
        let semester = PlannerSemester(name: "UITest Fall", year: 2026, season: "Fall", seasonOrder: 1)
        let course = PlannerCourse(code: "UIT 101", name: "UITest Intro", credits: 3)
        semester.plan = plan
        course.semester = semester
        context.insert(profile)
        context.insert(plan)
        context.insert(semester)
        context.insert(course)

        let calendarRepo = CalendarRepository(context: context)
        let existingEvents = (try? calendarRepo.fetchEvents(
            from: Date.distantPast,
            to: Date.distantFuture,
            limit: 5
        )) ?? []
        if existingEvents.isEmpty {
            let start = Date()
            let event = CalendarEvent(
                title: "UITest local store Lecture",
                startDate: start,
                endDate: start.addingTimeInterval(3600)
            )
            context.insert(event)
        }

        let existingTasks = (try? calendarRepo.fetchTasks(dueBefore: Date.distantFuture, limit: 5)) ?? []
        if existingTasks.isEmpty {
            context.insert(PlannerTask(title: "UITest local store Assignment", dueDate: Date()))
        }

        try? context.save()
    }

    static func seedDeclaredMajorDataIfNeeded() {
        guard UITestLaunchFlags.forcesMainUI, UITestLaunchFlags.seedDeclaredMajorData else { return }
        let context = AppDataStore.shared.profileContext
        seedDeclaredMajorIfNeeded(context: context)
    }

    private static func seedDeclaredMajorIfNeeded(context: ModelContext) {
        let fetch = FetchDescriptor<AcademicProfile>()
        let academic = (try? context.fetch(fetch))?.first ?? {
            let created = AcademicProfile()
            context.insert(created)
            return created
        }()
        AcademicProfileProgramLists.syncToProfile(
            majors: ["UITest Computer Science"],
            minors: [],
            profile: academic
        )
        try? context.save()
    }

    static func seedCareerResumesIfNeeded() async {
        guard UITestLaunchFlags.forcesMainUI, UITestLaunchFlags.seedCareerResumes else { return }
        seedMinimalPlannerDataIfNeeded()

        let persistence = CollegePersistence.shared
        let existing = CareerReadBridge.careerResumeDocuments(collegePersistence: persistence)
        guard existing.isEmpty else { return }

        let pdfData = Data("%PDF-1.4 UITest resume fixture".utf8)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("uitest_resume.pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard (try? pdfData.write(to: tempURL)) != nil else { return }

        var meta = CareerResumeMetadataV1()
        meta.kind = .general
        meta.parserHealthPercent = 88
        meta.ingestCompletedAt = .now
        meta.parsedTextHash = "uitest-hash"
        if let snapshot = try? ResumeSnapshotBuilder.build(collegePersistence: persistence) {
            var document = ResumeDocument.seed(from: snapshot)
            document.title = "UITest Builder Draft"
            document.setFieldOverride("UITest Builder Name", for: .personal(.name))
            meta.documentJSON = document.encodedJSON()
            if let structured = try? JSONEncoder().encode(CareerResumeStructuredProfile(
                name: "UITest Student",
                email: "uitest@example.edu",
                skills: ["Swift"]
            )),
               let json = String(data: structured, encoding: .utf8) {
                meta.structuredSectionsJSON = json
                meta.canonicalProfileJSON = json
            }
        }

        guard let doc = try? await persistence.importCareerResume(from: tempURL, initialMetadata: meta) else {
            return
        }
        persistence.setCareerResumeFavorite(true, for: doc)
    }
}
