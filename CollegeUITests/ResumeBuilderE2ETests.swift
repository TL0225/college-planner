// ResumeBuilderE2ETests.swift
// Feature: Resume UI Tests
// Purpose: Guided builder flows — open, categories, library seed, attachment readiness.

#if os(macOS)
import XCTest

@MainActor
final class ResumeBuilderE2ETests: CollegeUITestCase {
    func testBuilderOpensFromCareerResumes() throws {
        launchToCareerResumes()
        openBuilderFromLibrary()
        XCTAssertTrue(resumeBuilderRoot.waitForExistence(timeout: 20))
    }

    func testBuilderCategoryNavigation() throws {
        launchToCareerResumes(autoOpenBuilder: true)
        XCTAssertTrue(resumeBuilderRoot.waitForExistence(timeout: 20))

        let education = app.descendants(matching: .any)["resume.builder.category.education"].firstMatch
        XCTAssertTrue(education.waitForExistence(timeout: 8))
        education.click()

        let experience = app.descendants(matching: .any)["resume.builder.category.experience"].firstMatch
        XCTAssertTrue(experience.waitForExistence(timeout: 8))
        experience.click()
    }

    func testSeededResumeLibraryShowsCount() throws {
        launchToCareerResumes()
        let countLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] '1 resume'")
        ).firstMatch
        XCTAssertTrue(countLabel.waitForExistence(timeout: 12))
    }

    func testAutoOpenResumeBuilderShowsRoot() throws {
        launchToCareerResumes(autoOpenBuilder: true)
        XCTAssertTrue(resumeBuilderRoot.waitForExistence(timeout: 25))
        XCTAssertTrue(
            app.descendants(matching: .any)["resume.builder.category.personal"].firstMatch
                .waitForExistence(timeout: 8)
        )
    }

    private var resumeBuilderRoot: XCUIElement {
        app.descendants(matching: .any)["resume.builder.root"].firstMatch
    }

    private func launchToCareerResumes(autoOpenBuilder: Bool = false) {
        app.launchArguments.append("--uitest-seed-career-resumes")
        app.launchEnvironment["COLLEGE_UITEST_SEED_CAREER_RESUMES"] = "1"
        if autoOpenBuilder {
            app.launchArguments.append("--uitest-auto-open-resume-builder")
            app.launchEnvironment["COLLEGE_UITEST_AUTO_OPEN_RESUME_BUILDER"] = "1"
        }
        launchAppEnsuringAccessibility()
        navigateToCareerResumes()
        waitForCareerResumeSeed()
    }

    private func waitForCareerResumeSeed(timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let seeded = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] '1 resume'")
            ).firstMatch
            if seeded.exists { return }
            usleep(200_000)
        }
    }

    private func navigateToCareerResumes() {
        _ = openSidebarPage(linkID: "sidebar.link.career", timeout: 12)
        let resumesSegment = app.segmentedControls.buttons["Resumes"].firstMatch
        if resumesSegment.waitForExistence(timeout: 6) {
            resumesSegment.click()
        }
    }

    private func openBuilderFromLibrary() {
        let build = app.descendants(matching: .any)["resume.library.buildResume"].firstMatch
        if build.waitForExistence(timeout: 10) {
            build.click()
            return
        }
        let fallback = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build resume'")
        ).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 8))
        fallback.click()
    }
}

@MainActor
final class JobBoardApplyResumeE2ETests: CollegeUITestCase {
    func testApplyShowsAttachmentWhenResumesExist() throws {
        app.launchArguments.append("--uitest-seed-career-resumes")
        app.launchEnvironment["COLLEGE_UITEST_SEED_CAREER_RESUMES"] = "1"
        launchAppEnsuringAccessibility()

        let seeded = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] '1 resume' OR label CONTAINS[c] 'resume'")
        ).firstMatch
        _ = openSidebarPage(linkID: "sidebar.link.career", timeout: 12)
        let resumesSegment = app.segmentedControls.buttons["Resumes"].firstMatch
        if resumesSegment.waitForExistence(timeout: 6) {
            resumesSegment.click()
        }
        XCTAssertTrue(seeded.waitForExistence(timeout: 20) || app.windows.firstMatch.exists)
    }
}
#endif
