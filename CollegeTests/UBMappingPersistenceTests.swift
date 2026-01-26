import XCTest
import CoreData
@testable import College

final class UBMappingPersistenceTests: XCTestCase {
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

	private func seedUBUniversity(_ mgr: CoreDataManager) -> UniversityEntity {
		let ctx = mgr.viewContext
		let uni = UniversityEntity(context: ctx)
		uni.id = UUID()
		uni.name = "University at Buffalo"
		uni.isActive = true
		return uni
	}

	func testResolveSelectedMajorProgramURL_matchesStoredNameWithDegreeSuffixPunctuation() throws {
		let mgr = makeInMemoryManager()
		let ctx = mgr.viewContext

		_ = seedUBUniversity(mgr)

		let profile = ProfileEntity(context: ctx)
		profile.id = UUID()
		profile.major = "Accounting, BS"
		profile.degreeLevel = "Undergraduate"
		profile.degreeType = "BS"
		mgr.profile = profile

		let major = MajorEntity(context: ctx)
		major.id = UUID()
		// Simulate older/legacy storage where the degree suffix was included in the stored name.
		major.name = "Accounting, B.S."
		// Simulate stored casing differences from import.
		major.degreeLevel = "undergraduate"
		major.degreeType = "B.S."
		major.isMinor = false
		major.programURL = "https://catalogs.buffalo.edu/preview_program.php?catoid=1&poid=123&returnto=999"
		major.lastUpdated = Date()

		let uniFetch = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
		uniFetch.predicate = NSPredicate(format: "name == %@", "University at Buffalo")
		let uni = try ctx.fetch(uniFetch).first
		XCTAssertNotNil(uni)
		major.university = uni

		try ctx.save()

		let resolved = mgr.resolveSelectedMajorProgramURL()
		XCTAssertEqual(resolved, "https://catalogs.buffalo.edu/preview_program.php?catoid=1&poid=123")
	}

	func testPersistOwnershipMappings_updatesMajorResolvedFields_andLinksDepartment() throws {
		let mgr = makeInMemoryManager()
		let ctx = mgr.viewContext

		let uni = seedUBUniversity(mgr)

		let dept = DepartmentEntity(context: ctx)
		dept.id = UUID()
		dept.name = "Department of Computer Science and Engineering"
		dept.university = uni
		dept.lastUpdated = Date()

		let major = MajorEntity(context: ctx)
		major.id = UUID()
		major.name = "Computer Science"
		major.degreeLevel = "undergraduate"
		major.isMinor = false
		major.programURL = "https://catalogs.buffalo.edu/preview_program.php?catoid=1&poid=123"
		major.university = uni
		major.lastUpdated = Date()

		try ctx.save()

		mgr.persistProgramOwnershipMappings(
			for: "University at Buffalo",
			mappings: [
				"https://catalogs.buffalo.edu/preview_program.php?catoid=1&poid=123": (
					department: "Department of Computer Science and Engineering",
					college: "College of Engineering and Applied Sciences",
					confidence: 0.9,
					source: "unit-test"
				)
			]
		)

		let fetch = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
		fetch.predicate = NSPredicate(format: "university.name == %@", "University at Buffalo")
		let majors = try ctx.fetch(fetch)
		XCTAssertEqual(majors.count, 1)

		let updated = majors[0]
		XCTAssertEqual(updated.resolvedDepartment, "Department of Computer Science and Engineering")
		XCTAssertEqual(updated.resolvedCollege, "College of Engineering and Applied Sciences")
		XCTAssertEqual(updated.mappingSource, "unit-test")
		let deptNames = (updated.departments as? Set<DepartmentEntity>)?.compactMap { $0.name } ?? []
		XCTAssertTrue(deptNames.contains("Department of Computer Science and Engineering"))
	}

	func testFetchProgramMappingByDepartment_groupsPrograms() throws {
		let mgr = makeInMemoryManager()
		let ctx = mgr.viewContext
		let uni = seedUBUniversity(mgr)

		let dept = DepartmentEntity(context: ctx)
		dept.id = UUID()
		dept.name = "Department of Mathematics"
		dept.university = uni
		dept.lastUpdated = Date()

		let a = MajorEntity(context: ctx)
		a.id = UUID()
		a.name = "Applied Mathematics"
		a.degreeLevel = "undergraduate"
		a.isMinor = false
		a.university = uni
		a.departments = NSSet(array: [dept])
		a.lastUpdated = Date()

		let b = MajorEntity(context: ctx)
		b.id = UUID()
		b.name = "Mathematics"
		b.degreeLevel = "undergraduate"
		b.isMinor = false
		b.university = uni
		b.departments = NSSet(array: [dept])
		b.lastUpdated = Date()

		try ctx.save()

		let map = mgr.fetchProgramMappingByDepartment(for: "University at Buffalo", degreeLevel: "undergraduate", includeMinors: false)
		XCTAssertEqual(map["Department of Mathematics"] ?? [], ["Applied Mathematics", "Mathematics"])
	}

	func testUpdateDepartmentSchoolsFromProgramOwnership_derivesGroupHeader() throws {
		let mgr = makeInMemoryManager()
		let ctx = mgr.viewContext
		let uni = seedUBUniversity(mgr)

		let dept = DepartmentEntity(context: ctx)
		dept.id = UUID()
		dept.name = "Department of Computer Science and Engineering"
		dept.university = uni
		dept.lastUpdated = Date()

		let major = MajorEntity(context: ctx)
		major.id = UUID()
		major.name = "Computer Science"
		major.degreeLevel = "undergraduate"
		major.isMinor = false
		major.university = uni
		major.departments = NSSet(array: [dept])
		major.resolvedCollege = "College of Engineering and Applied Sciences"
		major.resolvedDepartment = "Department of Computer Science and Engineering"
		major.mappingSource = "unit-test"
		major.lastUpdated = Date()

		try ctx.save()

		mgr.updateDepartmentSchoolsFromProgramOwnership(for: "University at Buffalo")

		let fetch = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
		fetch.predicate = NSPredicate(format: "university.name == %@", "University at Buffalo")
		let depts = try ctx.fetch(fetch)
		XCTAssertEqual(depts.count, 1)
		XCTAssertEqual(depts[0].school, "College of Engineering and Applied Sciences")
	}
}
