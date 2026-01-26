import XCTest
@testable import College

final class ModernCampusSidebarDiscoveryTests: XCTestCase {

	func testBestNavoidFromIndexPrefersOrgUnitsForDepartmentsAndProgramsLabel() {
		let html = """
		<html>
		  <body>
		    <nav>
		      <a href=\"content.php?catoid=17&navoid=111\">Course Descriptions</a>
		      <a href=\"content.php?catoid=17&navoid=222\">Departments &amp; Programs</a>
		      <a href=\"content.php?catoid=17&navoid=333\">Majors</a>
		    </nav>
		  </body>
		</html>
		"""

		let best = ModernCampusAPI.invoke_bestNavoidFromIndex_forTests(html, catoid: "17", intentIsPrograms: false)
		XCTAssertNotNil(best)
		XCTAssertEqual(best?.navoid, "222")
		XCTAssertTrue((best?.score ?? 0) > 0)
	}

	func testBestNavoidFromIndexPrefersProgramsForMajorsLabel() {
		let html = """
		<html>
		  <body>
		    <nav>
		      <a href=\"content.php?catoid=17&navoid=222\">Departments &amp; Programs</a>
		      <a href=\"content.php?catoid=17&navoid=333\">Majors</a>
		      <a href=\"content.php?catoid=17&navoid=444\">Minors</a>
		    </nav>
		  </body>
		</html>
		"""

		let best = ModernCampusAPI.invoke_bestNavoidFromIndex_forTests(html, catoid: "17", intentIsPrograms: true)
		XCTAssertNotNil(best)
		XCTAssertEqual(best?.navoid, "333")
		XCTAssertTrue((best?.score ?? 0) >= 8)
	}

	func testDeriveDepartmentProgramMapping_prefersResolvedOwnershipDepartment() async throws {
		let html = "<div>Department of Computer Science, College of Arts and Sciences</div>"
		let o = await ModernCampusEngine.extractProgramOwnershipTuplePublic(html)
		XCTAssertNotNil(o)
	}
}
