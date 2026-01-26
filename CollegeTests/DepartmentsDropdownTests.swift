import XCTest
import CoreData
@testable import College

final class DepartmentsDropdownTests: XCTestCase {
	private var mgr: CoreDataManager?

	override func tearDown() {
		mgr = nil
		super.tearDown()
	}

	private func makeInMemoryManager() -> CoreDataManager {
		let modelURL = Bundle(for: CoreDataManager.self).url(forResource: "CollegeDataModel", withExtension: "momd")
		XCTAssertNotNil(modelURL)
		let model = NSManagedObjectModel(contentsOf: modelURL!)
		XCTAssertNotNil(model)

		let container = NSPersistentContainer(name: "CollegeDataModel", managedObjectModel: model!)
		let desc = NSPersistentStoreDescription()
		desc.type = NSInMemoryStoreType
		container.persistentStoreDescriptions = [desc]
		container.loadPersistentStores { _, error in
			XCTAssertNil(error)
		}

		let manager = CoreDataManager(testContainer: container, skipBootstrapFetches: true)
		self.mgr = manager
		return manager
	}

	private func seedUniversity(_ mgr: CoreDataManager, name: String) throws {
		let ctx = mgr.viewContext
		let uni = UniversityEntity(context: ctx)
		uni.id = UUID()
		uni.name = name
		uni.isActive = true
		try ctx.save()
	}

	func testFetchDepartments_returnsSavedDepartments() throws {
		let mgr = makeInMemoryManager()
		try seedUniversity(mgr, name: "Test U")

		try mgr.saveDepartments(
			[
				(name: "Computer Science", code: "CSE", school: ""),
				(name: "Mathematics", code: "MAT", school: ""),
			],
			for: "Test U"
		)

		let departments = mgr.fetchDepartments(for: "Test U")
		XCTAssertTrue(departments.contains("Computer Science"))
		XCTAssertTrue(departments.contains("Mathematics"))
		XCTAssertEqual(departments.sorted(), departments, "Departments list should be sorted")
	}
}
