import Foundation
import CoreData

/// Course catalog lookup service. Provides on-device search against already-imported catalog data.
/// AI-powered import has been removed. Catalog data is populated via the ModernCampus scraping pipeline.
@MainActor
class CourseCatalogService {
    private let coreDataManager: CoreDataManager

    init(coreDataManager: CoreDataManager) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Search Functions

    func searchCourses(query: String, universityID: UUID) -> [CourseCatalogEntity] {
        let context = coreDataManager.viewContext
        let fetchRequest: NSFetchRequest<CourseCatalogEntity> = CourseCatalogEntity.fetchRequest()

        fetchRequest.predicate = NSPredicate(
            format: "(courseCode CONTAINS[cd] %@ OR title CONTAINS[cd] %@) AND university.id == %@",
            query, query, universityID as CVarArg
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "courseCode", ascending: true)]
        fetchRequest.fetchLimit = 50

        return (try? context.fetch(fetchRequest)) ?? []
    }

    func getCoursePrerequisites(courseCode: String, universityID: UUID) -> [CourseCatalogEntity] {
        let context = coreDataManager.viewContext
        let fetchRequest: NSFetchRequest<CourseCatalogEntity> = CourseCatalogEntity.fetchRequest()

        fetchRequest.predicate = NSPredicate(
            format: "courseCode == %@ AND university.id == %@",
            courseCode, universityID as CVarArg
        )

        guard let course = try? context.fetch(fetchRequest).first,
              let prereqString = course.prerequisiteCodes else {
            return []
        }

        let prereqCodes = prereqString.split(separator: ",").map { String($0) }

        let prereqFetch: NSFetchRequest<CourseCatalogEntity> = CourseCatalogEntity.fetchRequest()
        prereqFetch.predicate = NSPredicate(
            format: "courseCode IN %@ AND university.id == %@",
            prereqCodes, universityID as CVarArg
        )

        return (try? context.fetch(prereqFetch)) ?? []
    }
}
