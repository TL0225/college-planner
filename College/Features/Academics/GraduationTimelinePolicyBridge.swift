import CollegeAcademics
import Foundation

extension GraduationTimelineEngine.PolicyInput {
    init(policies: SchoolPolicies?) {
        self.init(
            minCreditsForFullTime: policies?.minCreditsForFullTime,
            maxCreditsPerSemester: policies?.maxCreditsPerSemester
        )
    }
}
