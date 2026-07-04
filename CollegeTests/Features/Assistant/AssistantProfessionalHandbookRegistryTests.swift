// AssistantProfessionalHandbookRegistryTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant Professional Handbook Registry")
struct AssistantProfessionalHandbookRegistryTests {

    @Test("Law matches JD token not bare law word")
    func lawMatchesJDTokenNotBareLawWordInUnrelatedText() {
        #expect(AssistantProfessionalHandbookRegistry.entry(
            collegeName: "Arts and Sciences",
            resolvedCollegeFromMajor: nil,
            major: "JD expected",
            minor: nil,
            majorEntityName: nil,
            degreeType: nil
        ) != nil)
        #expect(AssistantProfessionalHandbookRegistry.entry(
            collegeName: "Arts and Sciences",
            resolvedCollegeFromMajor: nil,
            major: "business law seminar elective",
            minor: nil,
            majorEntityName: nil,
            degreeType: nil
        ) == nil)
    }

    @Test("Law school secondary signal from college string")
    func lawSchoolSecondarySignalFromCollegeString() {
        let e = AssistantProfessionalHandbookRegistry.entry(
            collegeName: "School of Law",
            resolvedCollegeFromMajor: nil,
            major: nil,
            minor: nil,
            majorEntityName: nil,
            degreeType: nil
        )
        #expect(e != nil)
        #expect(e?.url.contains("law.buffalo.edu") == true)
    }

    @Test("Planner block includes disclaimer line")
    func plannerBlockIncludesDisclaimerLine() {
        let block = AssistantProfessionalHandbookRegistry.plannerBlock(
            collegeName: "School of Law",
            resolvedCollegeFromMajor: nil,
            major: nil,
            minor: nil,
            majorEntityName: nil,
            degreeType: nil
        )
        #expect(block != nil)
        #expect(block?.localizedCaseInsensitiveContains("not legal advice") == true)
    }
}
