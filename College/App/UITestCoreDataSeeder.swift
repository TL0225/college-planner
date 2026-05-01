import Foundation

/// Idempotent planner seed for UI tests (`--uitest-seed-minimal-planner` with `--ui-test-boot-main`).
@MainActor
enum UITestCoreDataSeeder {
    static func seedMinimalPlannerDataIfNeeded(coreDataManager: CoreDataManager) {
        guard UITestLaunchFlags.forcesMainUI, UITestLaunchFlags.seedMinimalPlannerData else { return }
        guard coreDataManager.isStoreLoaded else { return }

        coreDataManager.updateProfile(
            name: "UITest Student",
            major: "Computer Science",
            minor: "",
            gpa: 3.4,
            classStanding: "Junior",
            expectedGraduation: "Spring 2027",
            collegeName: "State University",
            department: "CS"
        )

        let cal = Calendar.current
        let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        var startComps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        startComps.hour = 10
        startComps.minute = 0
        let start = cal.date(from: startComps) ?? tomorrow
        let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start

        let existingEvent = coreDataManager.searchCalendarEvents(semester: nil, query: "UITest Lecture")
        if existingEvent.isEmpty {
            _ = coreDataManager.addCalendarEvent(
                title: "UITest Lecture",
                startDate: start,
                endDate: end,
                allDay: false,
                semester: nil,
                course: nil,
                notes: nil,
                location: nil
            )
        }

        let existingTask = coreDataManager.searchTasks(semester: nil, query: "UITest Assignment", includeCompleted: true)
        if existingTask.isEmpty {
            _ = coreDataManager.addTask(
                title: "UITest Assignment",
                dueDate: tomorrow,
                semester: nil,
                course: nil,
                notes: nil,
                priority: 0,
                categoryName: nil,
                gradingCategory: nil,
                categoryWeightPercent: nil,
                weightPercent: nil,
                estimatedEffortMinutes: nil
            )
        }
    }
}
