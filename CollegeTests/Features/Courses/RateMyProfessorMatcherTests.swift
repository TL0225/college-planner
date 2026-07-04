// RateMyProfessorMatcherTests.swift
// Feature: Courses
// Purpose: Verifies strict RMP matching favors Not found over wrong professor data.

import XCTest
@testable import College

final class RateMyProfessorMatcherTests: XCTestCase {
    func testExactFullNameAcceptsUniqueCandidate() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [
                candidate(first: "Jane", last: "Doe", ratings: 12),
                candidate(first: "Janet", last: "Doe", ratings: 8),
            ],
            professorName: "Jane Doe",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(result, .match(match(first: "Jane", last: "Doe", ratings: 12)))
    }

    func testConsistentInitialAcceptsUniqueCandidate() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [candidate(first: "John", last: "Smith", ratings: 9)],
            professorName: "J. Smith",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(result, .match(match(first: "John", last: "Smith", ratings: 9)))
    }

    func testBareLastNameReturnsNotFound() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [candidate(first: "John", last: "Smith", ratings: 9)],
            professorName: "Smith",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(result, .notFound)
    }

    func testAmbiguousSameNameReturnsNotFoundWhenDepartmentCannotDisambiguate() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [
                candidate(first: "Benjamin", last: "Smith", department: "Information Technology", ratings: 8),
                candidate(first: "Benjamin", last: "Smith", department: "Cyber & Information Security", ratings: 4),
            ],
            professorName: "Benjamin Smith",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(result, .notFound)
    }

    func testDepartmentCanDisambiguateOnlyAfterNameMatch() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [
                candidate(first: "Alex", last: "Rivera", department: "Business", ratings: 8),
                candidate(first: "Alex", last: "Rivera", department: "Cyber Security", ratings: 10),
            ],
            professorName: "Alex Rivera",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(
            result,
            .match(match(first: "Alex", last: "Rivera", department: "Cyber Security", ratings: 10))
        )
    }

    func testLowRatingCountReturnsNotFound() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [candidate(first: "Jane", last: "Doe", ratings: 2)],
            professorName: "Jane Doe",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(result, .notFound)
    }

    func testLastFirstOrderingAndTitleSuffixStripping() {
        let result = RateMyProfessorMatcher.selectTeacher(
            from: [candidate(first: "Jane", last: "Doe", ratings: 12)],
            professorName: "Dr. Doe, Jane PhD",
            courseCode: "INFA 754"
        )

        XCTAssertEqual(result, .match(match(first: "Jane", last: "Doe", ratings: 12)))
    }

    func testStrictSchoolResolutionAcceptsSingleExactNormalizedMatch() {
        let schools = [
            RateMyProfessorSchoolCandidate(id: "1", name: "University of Maryland Global Campus", city: "College Park", state: "MD"),
            RateMyProfessorSchoolCandidate(id: "2", name: "University of Maryland", city: "College Park", state: "MD"),
        ]

        let result = RateMyProfessorMatcher.selectSchool(
            from: schools,
            universityName: "University of Maryland Global Campus",
            universityShortName: "UMGC"
        )

        XCTAssertEqual(result?.id, "1")
    }

    func testStrictSchoolResolutionRejectsMultipleExactNormalizedMatches() {
        let schools = [
            RateMyProfessorSchoolCandidate(id: "1", name: "University of Maryland Global Campus", city: "College Park", state: "MD"),
            RateMyProfessorSchoolCandidate(id: "2", name: "University of Maryland Global Campus", city: "Largo", state: "MD"),
        ]

        let result = RateMyProfessorMatcher.selectSchool(
            from: schools,
            universityName: "University of Maryland Global Campus",
            universityShortName: nil
        )

        XCTAssertNil(result)
    }

    private func candidate(
        first: String,
        last: String,
        department: String = "Cyber Security",
        ratings: Int
    ) -> RateMyProfessorTeacherCandidate {
        RateMyProfessorTeacherCandidate(
            id: "teacher-\(first)-\(last)-\(department)-\(ratings)",
            legacyId: ratings * 100,
            firstName: first,
            lastName: last,
            department: department,
            avgRating: 4.2,
            avgDifficulty: 2.8,
            numRatings: ratings,
            wouldTakeAgainPercent: 80
        )
    }

    private func match(
        first: String,
        last: String,
        department: String = "Cyber Security",
        ratings: Int
    ) -> RateMyProfessorMatch {
        RateMyProfessorMatch(
            teacherID: "teacher-\(first)-\(last)-\(department)-\(ratings)",
            legacyID: ratings * 100,
            firstName: first,
            lastName: last,
            department: department,
            averageRating: 4.2,
            averageDifficulty: 2.8,
            ratingCount: ratings,
            wouldTakeAgainPercent: 80
        )
    }
}
