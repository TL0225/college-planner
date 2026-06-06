import Foundation

/// Registry of planned feature Swift modules and allowed dependency edges (ADR 004).
public enum FeatureModuleRegistry {
    public struct Module: Sendable {
        public var name: String
        public var sourceRoot: String
        public var migrationRank: Int
        public var allowedDependencies: [String]

        public init(
            name: String,
            sourceRoot: String,
            migrationRank: Int,
            allowedDependencies: [String]
        ) {
            self.name = name
            self.sourceRoot = sourceRoot
            self.migrationRank = migrationRank
            self.allowedDependencies = allowedDependencies
        }
    }

    /// Migration order: Calendar → Academics → Career (lowest cross-feature coupling first).
    public static let plannedModules: [Module] = [
        Module(
            name: "CollegeCalendar",
            sourceRoot: "College/Features/Calendar",
            migrationRank: 1,
            allowedDependencies: ["CollegePlatform", "CollegeCore"]
        ),
        Module(
            name: "CollegeAcademics",
            sourceRoot: "College/Features/Academics",
            migrationRank: 2,
            allowedDependencies: ["CollegePlatform", "CollegeCore"]
        ),
        Module(
            name: "CollegeCareer",
            sourceRoot: "College/Features/Career",
            migrationRank: 3,
            allowedDependencies: ["CollegePlatform", "CollegeCore"]
        ),
    ]

    public static let sharedModules: Set<String> = ["CollegePlatform", "CollegeCore"]

    public static func isAllowedDependency(from module: String, to dependency: String) -> Bool {
        if sharedModules.contains(dependency) { return true }
        guard let source = plannedModules.first(where: { $0.name == module }) else {
            return false
        }
        return source.allowedDependencies.contains(dependency)
    }
}
