// CollegeSchemaV1.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — FocusBlockRecord.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Versioned schema (Phase 7a)

enum CollegeSchemaV1_0: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1.coreModels
    }
}

enum CollegeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    static var coreModels: [any PersistentModel.Type] {
        [
            PlannerSemester.self,
            PlannerPlan.self,
            PlannerCourse.self,
            CourseGradingCategory.self,
            CourseOverride.self,
            CourseCatalog.self,
            AcademicProfile.self,
            GraduationPlanTerm.self,
            CalendarEvent.self,
            PlannerTask.self,
            Profile.self,
            Experience.self,
            Achievement.self,
            VaultDocument.self,
            WatchedFolder.self,
            JobApplication.self,
            RecruiterContact.self,
            WorkdayJobPosting.self,
            CareerEvent.self,
            University.self,
            Department.self,
            Major.self,
            CatalogDegreeRequirement.self,
            RequirementFulfillment.self,
            CatalogPolicyDocument.self,
            CatalogScrapeState.self,
        ]
    }

    static var models: [any PersistentModel.Type] {
        coreModels + [FocusBlockRecord.self]
    }
}

// MARK: - Focus blocks (profile partition)

@Model
final class FocusBlockRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var startHour: Int
    var endHour: Int
    /// JSON-encoded `[Int]` weekday indices (1 = Sunday … 7 = Saturday).
    var weekdaysJSON: String

    init(
        id: UUID = UUID(),
        title: String,
        startHour: Int,
        endHour: Int,
        weekdaysJSON: String
    ) {
        self.id = id
        self.title = title
        self.startHour = startHour
        self.endHour = endHour
        self.weekdaysJSON = weekdaysJSON
    }
}

// MARK: - Profile partition

@Model
final class PlannerSemester {
    @Attribute(.unique) var id: UUID
    var name: String
    var year: Int16
    var season: String
    var seasonOrder: Int16
    var isPlanned: Bool

    @Relationship(deleteRule: .cascade, inverse: \PlannerCourse.semester)
    var courses: [PlannerCourse]?

    @Relationship(deleteRule: .cascade, inverse: \CalendarEvent.semester)
    var calendarEvents: [CalendarEvent]?

    @Relationship(deleteRule: .cascade, inverse: \PlannerTask.semester)
    var tasks: [PlannerTask]?

    var plan: PlannerPlan?

    init(
        id: UUID = UUID(),
        name: String,
        year: Int16 = 0,
        season: String,
        seasonOrder: Int16 = 0,
        isPlanned: Bool = true
    ) {
        self.id = id
        self.name = name
        self.year = year
        self.season = season
        self.seasonOrder = seasonOrder
        self.isPlanned = isPlanned
    }
}

@Model
final class PlannerPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String
    var major: String?
    var minor: String?
    var concentration: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlannerSemester.plan)
    var semesters: [PlannerSemester]?

    var academicProfile: AcademicProfile?

    init(
        id: UUID = UUID(),
        name: String,
        type: String,
        major: String? = nil,
        minor: String? = nil,
        concentration: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.major = major
        self.minor = minor
        self.concentration = concentration
        self.createdAt = createdAt
    }
}

@Model
final class AcademicProfile {
    @Attribute(.unique) var id: UUID
    var sortOrder: Int16
    var isPrimary: Bool
    var isActive: Bool
    var status: String
    var accentColorIndex: Int16
    var startedAt: Date?
    var completedAt: Date?
    var degreeLevel: String?
    var degreeType: String?
    var majorsCSV: String?
    var minorsCSV: String?
    var major: String?
    var secondaryMajor: String?
    var minor: String?
    var department: String?
    var collegeName: String?
    var classStanding: String?
    var expectedGraduation: String?
    var creditsEarned: Int32?
    var creditsRequired: Int32?
    var gpa: Double?
    var transferGpa: Double?
    var advisorName: String?
    var universityEmail: String?
    var personalPhone: String?
    var permanentAddress: String?
    var studentId: String?
    var expectedGraduationYear: Int16?
    var expectedGraduationSeason: String?

    var profile: Profile?
    var plan: PlannerPlan?

    init(
        id: UUID = UUID(),
        sortOrder: Int16 = 0,
        isPrimary: Bool = false,
        isActive: Bool = true,
        status: String = "active",
        accentColorIndex: Int16 = 0
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.isPrimary = isPrimary
        self.isActive = isActive
        self.status = status
        self.accentColorIndex = accentColorIndex
        self.degreeLevel = "Undergraduate"
        self.creditsEarned = 0
        self.creditsRequired = 120
        self.gpa = 0
        self.transferGpa = 0
        self.expectedGraduationYear = 0
    }
}

@Model
final class GraduationPlanTerm {
    @Attribute(.unique) var id: UUID
    var year: Int16
    var season: String
    var seasonOrder: Int16
    var plannedCreditCap: Int16
    var noteText: String?
    /// Cross-container reference to `AcademicProfile` in the profile store (mirrors local store Catalog config).
    var profileID: UUID

    init(
        id: UUID = UUID(),
        profileID: UUID,
        year: Int16 = 0,
        season: String,
        seasonOrder: Int16 = 0,
        plannedCreditCap: Int16 = 0,
        noteText: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.year = year
        self.season = season
        self.seasonOrder = seasonOrder
        self.plannedCreditCap = plannedCreditCap
        self.noteText = noteText
    }
}

@Model
final class PlannerCourse {
    @Attribute(.unique) var id: UUID
    var code: String
    var name: String
    var credits: Int16
    var status: String
    var gradingType: String
    var professor: String?
    var isCompleted: Bool
    var grade: String?
    var sortOrder: Int32
    var autoLinked: Bool
    var countsTowardGenEd: Bool
    var isArchived: Bool
    /// Cross-catalog reference (Catalog store); mirrors `CourseEntity.catalogCourse`.
    var catalogCourseID: UUID?

    var semester: PlannerSemester?

    @Relationship(deleteRule: .cascade, inverse: \CalendarEvent.course)
    var calendarEvents: [CalendarEvent]?

    @Relationship(deleteRule: .nullify, inverse: \PlannerTask.course)
    var tasks: [PlannerTask]?

    @Relationship(deleteRule: .cascade, inverse: \CourseGradingCategory.course)
    var gradingCategories: [CourseGradingCategory]?

    init(
        id: UUID = UUID(),
        code: String,
        name: String,
        credits: Int16 = 0,
        status: String = "Planned",
        gradingType: String = "Letter Grade",
        isCompleted: Bool = false,
        sortOrder: Int32 = 0,
        autoLinked: Bool = false,
        countsTowardGenEd: Bool = false,
        isArchived: Bool = false,
        catalogCourseID: UUID? = nil
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.credits = credits
        self.status = status
        self.gradingType = gradingType
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.autoLinked = autoLinked
        self.countsTowardGenEd = countsTowardGenEd
        self.isArchived = isArchived
        self.catalogCourseID = catalogCourseID
    }
}

@Model
final class CourseGradingCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var weightPercent: Double?
    var notes: String?
    var source: String?
    var createdAt: Date
    var lastUpdated: Date

    var course: PlannerCourse?

    @Relationship(deleteRule: .nullify, inverse: \PlannerTask.gradingCategory)
    var tasks: [PlannerTask]?

    init(
        id: UUID = UUID(),
        name: String,
        weightPercent: Double? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.name = name
        self.weightPercent = weightPercent
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
}

@Model
final class CalendarEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var allDay: Bool
    var notes: String?
    var location: String?
    var createdAt: Date
    var lastUpdated: Date
    var providerSource: String?
    var providerEventId: String?
    var customColorHex: String?
    var recurrenceRule: String?
    var attendeesJSON: String?
    var brightspaceAnnouncementId: String?

    var semester: PlannerSemester?
    var course: PlannerCourse?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool = false,
        createdAt: Date = .now,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
}

@Model
final class PlannerTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var notes: String?
    var priority: Int16
    var categoryName: String?
    var categoryWeightPercent: Double?
    var weightPercent: Double?
    var estimatedEffortMinutes: Int32?
    var brightspaceItemId: String?
    var createdAt: Date
    var lastUpdated: Date

    var semester: PlannerSemester?
    var course: PlannerCourse?
    var gradingCategory: CourseGradingCategory?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        priority: Int16 = 0,
        createdAt: Date = .now,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.priority = priority
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
}

@Model
final class Profile {
    @Attribute(.unique) var id: UUID
    var name: String?
    var pronouns: String?
    var collegeName: String?
    var savedSelectionsJSON: String?
    var studentId: String?
    var universityEmail: String?
    var personalPhone: String?
    var permanentAddress: String?
    var advisorName: String?
    @Attribute(.externalStorage) var profilePhotoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Experience.profile)
    var experiences: [Experience]?

    @Relationship(deleteRule: .cascade, inverse: \Achievement.profile)
    var achievements: [Achievement]?

    @Relationship(deleteRule: .cascade, inverse: \AcademicProfile.profile)
    var academicProfiles: [AcademicProfile]?

    init(id: UUID = UUID(), name: String? = nil) {
        self.id = id
        self.name = name
    }
}

@Model
final class Experience {
    @Attribute(.unique) var id: UUID
    var title: String?
    var company: String?
    var location: String?
    var startDate: Date?
    var endDate: Date?
    var isCurrent: Bool
    var descriptionText: String?

    var profile: Profile?

    init(id: UUID = UUID(), isCurrent: Bool = false) {
        self.id = id
        self.isCurrent = isCurrent
    }
}

@Model
final class Achievement {
    @Attribute(.unique) var id: UUID
    var name: String?
    var organization: String?
    var dateReceived: Date?
    var amount: String?
    var descriptionText: String?
    var url: String?

    var profile: Profile?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
final class VaultDocument {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var category: String
    var addedAt: Date
    var fileSizeBytes: Int64
    var localRelativePath: String
    var isFavorite: Bool
    var sortOrder: Int32
    var isFolder: Bool
    var parentFolderID: UUID?
    /// User-facing title override (mirrors `VaultDocumentEntity.customDisplayName`).
    var customDisplayName: String?
    /// Normalized uppercase course link for syllabus / course dashboards.
    var courseCodeLinked: String?
    var lastOpenedAt: Date?
    var tags: String?
    var source: String?
    var userNotes: String?
    var needsReview: Bool
    var colorLabel: String?
    var careerResumeMetadataJSON: String?
    var readingProgress: Int16
    var readingTotalPages: Int16
    var linkedTaskID: UUID?
    var summaryText: String?
    var classificationConfidence: Float
    var isDuplicate: Bool
    var versionOf: UUID?
    var dueDateExtracted: Date?
    var contentIndexed: Bool

    var parentFolder: VaultDocument?

    @Relationship(deleteRule: .cascade, inverse: \VaultDocument.parentFolder)
    var children: [VaultDocument]?

    @Relationship(deleteRule: .nullify, inverse: \JobApplication.submittedResume)
    var submittedApplications: [JobApplication]?

    init(
        id: UUID = UUID(),
        fileName: String,
        category: String = "Other",
        addedAt: Date = .now,
        fileSizeBytes: Int64 = 0,
        localRelativePath: String,
        isFavorite: Bool = false,
        sortOrder: Int32 = 0,
        isFolder: Bool = false,
        needsReview: Bool = false,
        readingProgress: Int16 = 0,
        readingTotalPages: Int16 = 0,
        classificationConfidence: Float = 0,
        isDuplicate: Bool = false,
        contentIndexed: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.category = category
        self.addedAt = addedAt
        self.fileSizeBytes = fileSizeBytes
        self.localRelativePath = localRelativePath
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.isFolder = isFolder
        self.needsReview = needsReview
        self.readingProgress = readingProgress
        self.readingTotalPages = readingTotalPages
        self.classificationConfidence = classificationConfidence
        self.isDuplicate = isDuplicate
        self.contentIndexed = contentIndexed
    }
}

@Model
final class WatchedFolder {
    @Attribute(.unique) var id: UUID
    var path: String
    var isEnabled: Bool
    var addedAt: Date
    var bookmarkData: Data?

    init(
        id: UUID = UUID(),
        path: String,
        isEnabled: Bool = true,
        addedAt: Date = .now,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.bookmarkData = bookmarkData
    }
}

@Model
final class JobApplication {
    @Attribute(.unique) var id: UUID
    var createdAt: Date?
    var updatedAt: Date?
    var lastStatusChangeAt: Date?
    var statusRaw: String
    var sortOrder: Int32
    var title: String?
    var company: String?
    var interviewStatus: String?
    var applicationDeadline: Date?
    var dateApplied: Date?
    var postingURLString: String?
    var jobDescriptionText: String?
    var extractedKeywordsJSON: String?
    var source: String?
    var sourceRequestId: UUID?
    var provenanceJSON: String?
    var workdayExternalId: String?
    var workdayCompanySlug: String?
    var locationText: String?
    var baseSalaryText: String?
    var resumeDisplayName: String?

    @Relationship(deleteRule: .cascade, inverse: \RecruiterContact.application)
    var contacts: [RecruiterContact]?

    @Relationship(deleteRule: .cascade, inverse: \CareerEvent.application)
    var events: [CareerEvent]?

    var submittedResume: VaultDocument?
    var workdaySourcePosting: WorkdayJobPosting?

    init(
        id: UUID = UUID(),
        statusRaw: String = "interested",
        sortOrder: Int32 = 0
    ) {
        self.id = id
        self.statusRaw = statusRaw
        self.sortOrder = sortOrder
    }
}

@Model
final class RecruiterContact {
    @Attribute(.unique) var id: UUID
    var fullName: String?
    var email: String?
    var linkedInURL: String?
    var lastContactedAt: Date?
    var roleTitle: String?
    var companyName: String?
    var contactKindRaw: String?
    var isFavorite: Bool
    var lastInteractionChannelRaw: String?
    var lastInteractionSummary: String?
    var lastInteractionDetailedAt: Date?

    var application: JobApplication?

    @Relationship(deleteRule: .cascade, inverse: \CareerEvent.recruiterContact)
    var networkingEvents: [CareerEvent]?

    init(id: UUID = UUID(), isFavorite: Bool = false) {
        self.id = id
        self.isFavorite = isFavorite
    }
}

@Model
final class WorkdayJobPosting {
    @Attribute(.unique) var id: UUID
    var companySlug: String
    var companyDisplayName: String?
    var externalId: String
    var externalPath: String?
    var title: String?
    var locationText: String?
    var locationsFilterText: String?
    var postedAt: Date?
    var postedOnText: String?
    var applyURLString: String?
    var jobDescriptionText: String?
    var requirementsText: String?
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var lastScrapedAt: Date?
    var detailScrapedAt: Date?
    var isActive: Bool
    var jobIdDisplayText: String?
    var jobTypeText: String?
    var timeType: String?
    var workModel: String?
    var salaryText: String?
    var salaryMin: Int64?
    var salaryMax: Int64?
    var listingHash: String?
    var platform: String?
    var deadlineAt: Date?
    var closedAt: Date?
    var descriptionHash: String?
    var lastModifiedAt: Date?
    var changeLog: String?

    var trackedApplication: JobApplication?

    init(
        id: UUID = UUID(),
        companySlug: String,
        externalId: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.companySlug = companySlug
        self.externalId = externalId
        self.isActive = isActive
    }
}

@Model
final class CareerEvent {
    @Attribute(.unique) var id: UUID
    var kindRaw: String?
    var title: String?
    var notes: String?
    var date: Date?
    var completed: Bool

    var application: JobApplication?
    var recruiterContact: RecruiterContact?

    init(id: UUID = UUID(), completed: Bool = false) {
        self.id = id
        self.completed = completed
    }
}

// MARK: - Catalog partition

@Model
final class University {
    @Attribute(.unique) var id: UUID
    var name: String
    var shortName: String?
    var catalogURL: String?
    var lastCatalogSync: Date?
    var catalogFormat: String?
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \CourseCatalog.university)
    var courses: [CourseCatalog]?

    @Relationship(deleteRule: .cascade, inverse: \CourseOverride.university)
    var courseOverrides: [CourseOverride]?

    @Relationship(deleteRule: .cascade, inverse: \CatalogScrapeState.university)
    var courseScrapeStates: [CatalogScrapeState]?

    @Relationship(deleteRule: .cascade, inverse: \CatalogDegreeRequirement.university)
    var degreeRequirements: [CatalogDegreeRequirement]?

    @Relationship(deleteRule: .cascade, inverse: \Department.university)
    var departments: [Department]?

    @Relationship(deleteRule: .cascade, inverse: \Major.university)
    var majors: [Major]?

    @Relationship(deleteRule: .cascade, inverse: \CatalogPolicyDocument.university)
    var policyDocuments: [CatalogPolicyDocument]?

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
    }
}

@Model
final class CourseCatalog {
    @Attribute(.unique) var id: UUID
    var courseCode: String
    var title: String
    var catalogCoid: String?
    var isHydrated: Bool
    var descriptionText: String?
    var prerequisiteText: String?
    var prerequisiteRulesJSON: String?
    var credits: Int16
    var department: String?
    var lastUpdated: Date
    var isArchived: Bool
    var catalogStableID: UUID?
    var provenanceJSON: String?

    var university: University?

    @Relationship(deleteRule: .nullify, inverse: \Department.courses)
    var departmentEntity: Department?

    init(
        id: UUID = UUID(),
        courseCode: String,
        title: String,
        credits: Int16 = 3,
        isHydrated: Bool = false,
        lastUpdated: Date = .now,
        isArchived: Bool = false
    ) {
        self.id = id
        self.courseCode = courseCode
        self.title = title
        self.credits = credits
        self.isHydrated = isHydrated
        self.lastUpdated = lastUpdated
        self.isArchived = isArchived
    }
}

@Model
final class CourseOverride {
    @Attribute(.unique) var id: UUID
    var courseCode: String
    var courseName: String?
    var credits: Double?
    var professor: String?
    var semesterText: String?
    var status: String?
    var grade: String?
    var gradingType: String?
    var externalURL: String?
    var syllabusFileName: String?
    var syllabusFileBookmarkData: Data?
    var syllabusFileSizeBytes: Int64
    var syllabusUploadedAt: Date?
    var lastUpdated: Date

    var university: University?

    init(
        id: UUID = UUID(),
        courseCode: String,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.courseCode = courseCode
        self.syllabusFileSizeBytes = 0
        self.lastUpdated = lastUpdated
    }
}

@Model
final class Department {
    @Attribute(.unique) var id: UUID
    var name: String
    var code: String?
    var school: String?
    var lastUpdated: Date

    var university: University?

    var majors: [Major]?
    var courses: [CourseCatalog]?

    init(
        id: UUID = UUID(),
        name: String,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.name = name
        self.lastUpdated = lastUpdated
    }
}

@Model
final class Major {
    @Attribute(.unique) var id: UUID
    var name: String
    var degreeLevel: String
    var degreeType: String?
    var isMinor: Bool
    var programURL: String?
    var programURLs: String?
    var sourceCatoids: String?
    var resolvedDepartment: String?
    var resolvedCollege: String?
    var lastUpdated: Date
    var catalogStableID: UUID?
    var provenanceJSON: String?
    var mappingConfidence: Double?
    var mappingSource: String?

    var university: University?

    @Relationship(deleteRule: .nullify, inverse: \Department.majors)
    var departments: [Department]?

    init(
        id: UUID = UUID(),
        name: String,
        degreeLevel: String,
        isMinor: Bool = false,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.name = name
        self.degreeLevel = degreeLevel
        self.isMinor = isMinor
        self.lastUpdated = lastUpdated
    }
}

@Model
final class CatalogDegreeRequirement {
    @Attribute(.unique) var id: UUID
    var programName: String?
    var programURL: String?
    var degreeType: String
    var major: String
    var requirementCategory: String
    var sectionOrder: Int16
    var creditsRequired: Int16
    var descriptionText: String?
    var requiredCourses: String?
    var requiredCoursesDetailedJSON: String?
    var selectFromJSON: String?
    var selectFromDetailedJSON: String?
    var selectCount: Int16
    var requirementKind: String?
    var parentCategory: String?
    var displayTitle: String?
    var trackVariant: String?
    var requirementsHash: String?
    var lastScrapedAt: Date?
    var lastUpdated: Date
    var catalogStableID: UUID?
    var provenanceJSON: String?

    var university: University?

    init(
        id: UUID = UUID(),
        degreeType: String,
        major: String,
        requirementCategory: String,
        sectionOrder: Int16 = 0,
        creditsRequired: Int16 = 0,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.degreeType = degreeType
        self.major = major
        self.requirementCategory = requirementCategory
        self.sectionOrder = sectionOrder
        self.creditsRequired = creditsRequired
        self.selectCount = 0
        self.lastUpdated = lastUpdated
    }
}

@Model
final class RequirementFulfillment {
    @Attribute(.unique) var id: UUID
    var university: String
    var programURL: String
    var requirementCategory: String
    var courseCode: String
    var assignmentSource: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        university: String,
        programURL: String,
        requirementCategory: String,
        courseCode: String,
        assignmentSource: String = "userAssumed",
        createdAt: Date = .now
    ) {
        self.id = id
        self.university = university
        self.programURL = programURL
        self.requirementCategory = requirementCategory
        self.courseCode = courseCode
        self.assignmentSource = assignmentSource
        self.createdAt = createdAt
    }
}

@Model
final class CatalogPolicyDocument {
    @Attribute(.unique) var id: UUID
    var catoid: String
    var sourceURL: String
    var navTitle: String
    var bodyText: String
    var catalogScope: String
    var contentHash: String
    var lastUpdated: Date

    var university: University?

    init(
        id: UUID = UUID(),
        catoid: String,
        sourceURL: String,
        navTitle: String,
        bodyText: String,
        catalogScope: String,
        contentHash: String,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.catoid = catoid
        self.sourceURL = sourceURL
        self.navTitle = navTitle
        self.bodyText = bodyText
        self.catalogScope = catalogScope
        self.contentHash = contentHash
        self.lastUpdated = lastUpdated
    }
}

@Model
final class CatalogScrapeState {
    @Attribute(.unique) var id: UUID
    var catoid: String
    var catalogTitle: String?
    var courseCount: Int32
    var lastScrapedAt: Date

    var university: University?

    init(
        id: UUID = UUID(),
        catoid: String,
        courseCount: Int32 = 0,
        lastScrapedAt: Date = .now
    ) {
        self.id = id
        self.catoid = catoid
        self.courseCount = courseCount
        self.lastScrapedAt = lastScrapedAt
    }
}