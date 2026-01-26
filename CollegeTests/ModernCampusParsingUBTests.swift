import XCTest
@testable import College

final class ModernCampusParsingUBTests: XCTestCase {

    func testParseUBCoursesFromContentPageAnchors() {
        // UB courses page uses preview_course_nopop.php anchors and includes a component suffix
        // appended to the course number (e.g., 101SEM).
        let html = """
        <div id=\"acalog-content\">
          <table class=\"table_default\">
            <tr>
              <td class=\"width\">&#8226;&#160;
                <a href=\"preview_course_nopop.php?catoid=17&coid=106865\" target=\"_blank\">AAP 101SEM&nbsp;-&nbsp;Introduction to Arts Management</a>
              </td>
            </tr>
            <tr>
              <td class=\"width\">&#8226;&#160;
                <a href=\"preview_course_nopop.php?catoid=17&coid=106866\" target=\"_blank\">AAS 100LEC&nbsp;-&nbsp;Introduction to African American Studies</a>
              </td>
            </tr>
          </table>
        </div>
        """

  let courses = ModernCampusEngine.invoke_parseCoursesFromCourseDescriptionsHTML_forTests(html)
        XCTAssertEqual(courses.count, 2)
  		XCTAssertEqual(courses[0].courseCode, "AAP 101SEM")
        XCTAssertEqual(courses[0].department, "AAP")
        XCTAssertEqual(courses[0].title, "Introduction to Arts Management")
  		XCTAssertEqual(courses[1].courseCode, "AAS 100LEC")
    }

  func testParseUBPreviewCoursePage_extractsCreditsAndDescription() {
    let html = """
    <div id=\"acalog-content\">
      <div class=\"courseblock\">
        <p class=\"courseblocktitle\"><strong>AAP 101SEM - Introduction to Arts Management (3 Credits)</strong></p>
        <p class=\"courseblockdesc\">Introduction to the arts sector and its management. Prerequisite: AAS 100.</p>
      </div>
    </div>
    """

    let course = ModernCampusEngine.invoke_parseCourseDetailFromPreviewHTML_forTests(
      html,
      fallbackCourseCode: "AAP 101SEM",
      fallbackTitle: "Introduction to Arts Management",
      fallbackDepartment: "AAP"
    )

    XCTAssertNotNil(course)
		XCTAssertEqual(course?.courseCode, "AAP 101SEM")
    XCTAssertEqual(course?.credits, 3)
    XCTAssertEqual(course?.title, "Introduction to Arts Management")
    XCTAssertEqual(course?.department, "AAP")
    XCTAssertNotNil(course?.description)
    XCTAssertTrue((course?.description ?? "").contains("arts sector"))
    XCTAssertEqual(course?.prerequisiteText, "AAS 100")
  }

    func testParseUBDepartmentsFromPreviewEntityLinks() {
        // The UB "Departments & Programs" page begins with the true colleges/schools (11 items)
        // followed by headings and many linked sub-entities (preview_entity.php).
        // For our app's department picker, we want ONLY the college/school org units.
        let html = """
        <div id=\"acalog-content\">
          <ul>
            <li class=\"acalog-export-remove\"><a href=\"#cas\">College of Arts and Sciences</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#gse\">Graduate School of Education</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#jsm\">Jacobs School of Medicine and Biomedical Sciences</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#arch\">School of Architecture and Planning</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#eng\">School of Engineering and Applied Sciences</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#law\">School of Law</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#som\">School of Management</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#son\">School of Nursing</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#spps\">School of Pharmacy and Pharmaceutical Sciences</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#sph\">School of Public Health and Health Professions</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#ssw\">School of Social Work</a></li>
            <li class=\"acalog-export-remove\"><a href=\"#other\">Other Departments</a></li>
          </ul>
          <h2>College of Arts and Sciences</h2>
          &#8226; <a href=\"preview_entity.php?catoid=17&ent_oid=1440\">Africana and American Studies</a>
          &#8226; <a href=\"preview_entity.php?catoid=17&ent_oid=1441\">Anthropology</a>
        </div>
        """

  let buckets = ModernCampusEngine.invoke_parseDepartmentsFromContentPage_forTests(html)
    XCTAssertEqual(buckets.count, 12)
        XCTAssertTrue(buckets.contains(where: { $0.name == "College of Arts and Sciences" }))
        XCTAssertTrue(buckets.contains(where: { $0.name == "Other Departments" }))
        XCTAssertFalse(buckets.contains(where: { $0.name == "Anthropology" }))
    }

  func testParseUBBucketEntities_groupsByBucketHeading() {
    let html = """
    <div id=\"acalog-content\">
      <ul>
        <li class=\"acalog-export-remove\"><a href=\"#cas\">College of Arts and Sciences</a></li>
        <li class=\"acalog-export-remove\"><a href=\"#eng\">School of Engineering and Applied Sciences</a></li>
      </ul>
      <h2>College of Arts and Sciences</h2>
      &#8226; <a href=\"preview_entity.php?catoid=17&ent_oid=1440\">Africana and American Studies</a>
      &#8226; <a href=\"preview_entity.php?catoid=17&ent_oid=1441\">Anthropology</a>
      <h2>School of Engineering and Applied Sciences</h2>
      &#8226; <a href=\"preview_entity.php?catoid=17&ent_oid=2000\">Computer Science and Engineering</a>
    </div>
    """

    let buckets = ModernCampusEngine.parseUBBucketListFromDepartmentsHTMLPublic(html)
    XCTAssertEqual(buckets, ["College of Arts and Sciences", "School of Engineering and Applied Sciences"])

    let entities = ModernCampusEngine.parseUBBucketEntitiesFromDepartmentsHTMLPublic(html, baseURL: "https://catalogs.buffalo.edu")
    XCTAssertEqual(entities["College of Arts and Sciences"] ?? [], ["Africana and American Studies", "Anthropology"])
    XCTAssertEqual(entities["School of Engineering and Applied Sciences"] ?? [], ["Computer Science and Engineering"])
  }

  func testUBEntityPagesProduceProgramOwnershipOverrides() throws {
    // Departments & Programs page: bucket heading then preview_entity links.
    let deptsHTML = """
    <div id=\"acalog-content\">
      <h2>School of Engineering and Applied Sciences</h2>
      <ul>
        <li>• <a href=\"preview_entity.php?catoid=17&ent_oid=2000\">Engineering Education (Engineering Science)</a></li>
      </ul>
      <h2>College of Arts and Sciences</h2>
      <ul>
        <li>• <a href=\"preview_entity.php?catoid=17&ent_oid=3000\">Sociology and Criminology</a></li>
      </ul>
    </div>
    """

    // Entity pages list majors/minors using preview_program links.
    let entity1URL = "https://catalogs.buffalo.edu/preview_entity.php?catoid=17&ent_oid=2000"
    let entity2URL = "https://catalogs.buffalo.edu/preview_entity.php?catoid=17&ent_oid=3000"

    let entity1HTML = """
    <div id=\"acalog-content\">
      <h3>Majors</h3>
      <ul>
        <li><a href=\"preview_program.php?catoid=17&poid=11111\">Engineering Education Minor</a></li>
      </ul>
    </div>
    """

    let entity2HTML = """
    <div id=\"acalog-content\">
      <h3>Programs</h3>
      <ul>
        <li><a href=\"preview_program.php?catoid=17&poid=22222\">Sociology BA</a></li>
      </ul>
    </div>
    """

    let overrides = try UniversalCatalogScraper.invoke_parseUBOwnershipOverrides_forTests(
      departmentsAndProgramsHTML: deptsHTML,
      entityHTMLByURL: [entity1URL: entity1HTML, entity2URL: entity2HTML],
      baseURL: "https://catalogs.buffalo.edu"
    )

    let p1 = "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=11111"
    let p2 = "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=22222"

    XCTAssertEqual(overrides[p1]?.college, "School of Engineering and Applied Sciences")
    XCTAssertEqual(overrides[p2]?.college, "College of Arts and Sciences")
    XCTAssertEqual(overrides[p1]?.department, "Engineering Education (Engineering Science)")
    XCTAssertEqual(overrides[p2]?.department, "Sociology and Criminology")
  }

  func testUBOwnershipOverrides_sanitizesNewlinesAndRefinesAccountingDepartment() throws {
    // Regression: program URLs can contain embedded whitespace/newlines (e.g. "ca\ntoid=17")
    // which previously broke URLComponents parsing and caused UB ownership overrides to miss.
    // Also, the School of Management entity page is school-level; Accounting programs should
    // map to Accounting department when we already know we're within SOM context.

    let deptsHTML = """
    <div id=\"acalog-content\">
      <h2>School of Management</h2>
      <ul>
        <li>• <a href=\"preview_entity.php?catoid=17&ent_oid=1503\">School of Management</a></li>
      </ul>
    </div>
    """

    let entityURL = "https://catalogs.buffalo.edu/preview_entity.php?catoid=17&ent_oid=1503"

    // Intentionally broken href containing an embedded newline.
    let brokenHref = "preview_program.php?poid=5800&ca\n" + "toid=17"
    let entityHTML = """
    <div id=\"acalog-content\">
      <h3>Programs</h3>
      <ul>
        <li><a href=\"\(brokenHref)\">Accounting BS/Accounting MS</a></li>
      </ul>
    </div>
    """

    let overrides = try UniversalCatalogScraper.invoke_parseUBOwnershipOverrides_forTests(
      departmentsAndProgramsHTML: deptsHTML,
      entityHTMLByURL: [entityURL: entityHTML],
      baseURL: "https://catalogs.buffalo.edu"
    )

    // Canonical key should be stable (sorted query items, no embedded whitespace).
    let expectedProgramURL = "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=5800"
    XCTAssertEqual(overrides[expectedProgramURL]?.college, "School of Management")
    XCTAssertEqual(overrides[expectedProgramURL]?.department, "Accounting")
  }

  func testUBDepartmentProgramPage_mapsProgramsDirectlyUnderSchool() throws {
    // UB Graduate "Department/Program" page can list programs directly under an h3 school/college
    // without an intervening h4 department heading.
    let html = """
    <div id=\"acalog-content\">
      <h3>School of Management</h3>
      <ul class=\"program-list\">
        <li><a href=\"preview_program.php?catoid=19&poid=7557&returnto=1040\">Management Information Systems MS</a></li>
      </ul>
      <div style=\"padding-left: 20px\"><h4>Accounting and Law</h4>
        <ul class=\"program-list\">
          <li><a href=\"preview_program.php?catoid=19&poid=8422&returnto=1040\">Accounting Analytics MS</a></li>
        </ul>
      </div>
    </div>
    """

    let overrides = try UniversalCatalogScraper.invoke_parseUBOwnershipOverrides_forTests(
      departmentsAndProgramsHTML: html,
      entityHTMLByURL: [:],
      baseURL: "https://catalogs.buffalo.edu"
    )

    // Test hook canonicalizes program URLs (drops returnto, sorts query).
    let p1 = "https://catalogs.buffalo.edu/preview_program.php?catoid=19&poid=7557"
    let p2 = "https://catalogs.buffalo.edu/preview_program.php?catoid=19&poid=8422"

    XCTAssertEqual(overrides[p1]?.college, "School of Management")
    XCTAssertEqual(overrides[p1]?.department, "School of Management")

    XCTAssertEqual(overrides[p2]?.college, "School of Management")
    XCTAssertEqual(overrides[p2]?.department, "Accounting and Law")
  }

  func testUBAccountingRequirementsCategoryOrderPreserved() throws {
    let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDir.deletingLastPathComponent()
    let fixtureURL = repoRoot.appendingPathComponent("ub_accounting_program_page.html")

    // Occasionally, reading fixtures can fail transiently (e.g., EINTR). Retry a few times.
    func readFixtureWithRetry(_ url: URL, attempts: Int = 3) throws -> String {
      var lastError: Error?
      for _ in 0..<max(1, attempts) {
        do {
          return try String(contentsOf: url, encoding: .utf8)
        } catch {
          lastError = error
          Thread.sleep(forTimeInterval: 0.05)
        }
      }
      throw lastError ?? NSError(domain: "CollegeTests", code: 1)
    }

    let html = try readFixtureWithRetry(fixtureURL)

    let programURL = "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=5799&returnto=878"
    let requirements = try UniversalCatalogScraper.invoke_parseProgramRequirementsFromHTML_forTests(
      html,
      programURL: programURL
    )

    func normalize(_ s: String) -> String {
      s
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }

    let categories = requirements.map { normalize($0.category) }

    func firstIndex(containing needle: String) -> Int? {
      let n = normalize(needle)
      return categories.firstIndex(where: { $0.contains(n) })
    }

    let iFoundation = firstIndex(containing: "Accounting Foundation Courses")
    let iCore = firstIndex(containing: "Accounting Core Courses")
    let iFinance = firstIndex(containing: "Finance Elective")

    guard let iFoundation, let iCore, let iFinance else {
      XCTFail("Missing expected categories. Parsed categories: \(categories)")
      return
    }

    XCTAssertLessThan(iFoundation, iCore)
    XCTAssertLessThan(iCore, iFinance)
  }

  func testParseUBProgramRequirements_extractsRequiredAndSelectCourses() throws {
    // UB program pages list requirements in div.acalog-core blocks and course items
    // as li.acalog-course with links that use onClick="showCourse(...)".
    let html = """
    <div class=\"acalog-core\"><h2>Major Requirements</h2><hr></div>
    <div class=\"acalog-core\"><h3>Accounting Foundation Courses (32 credits)</h3><hr>
      <ul>
        <li class=\"acalog-course\"><span><a href=\"#\" onClick=\"showCourse('17','1',this,'x'); return false;\">MGG 150LEC - Business and Society</a></span></li>
        <li class=\"acalog-course\"><span><a href=\"#\" onClick=\"showCourse('17','2',this,'x'); return false;\">MTH 131LR - Mathematical Analysis for Management</a></span></li>
        <li class=\"acalog-course\"><span><a href=\"#\" onClick=\"showCourse('17','3',this,'x'); return false;\">MGA 201LR - Introduction to Financial Accounting</a></span></li>
      </ul>
    </div>
    <div class=\"acalog-core\"><h3>One Finance Elective (3 credits)</h3><hr>
      <ul>
        <li class=\"acalog-course\"><span><a href=\"#\" onClick=\"showCourse('17','4',this,'x'); return false;\">MGF 401LEC - Financial Institutions</a></span></li>
        <li class=\"acalog-course\"><span><a href=\"#\" onClick=\"showCourse('17','5',this,'x'); return false;\">MGF 402LEC - Investment Management</a></span></li>
      </ul>
    </div>
    <div class=\"acalog-core\"><h2>Academic Requirements</h2><hr></div>
    """

    let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: "https://catalogs.buffalo.edu")
    XCTAssertTrue(parsed.diagnostics.usedMajorRequirementsSection)
    XCTAssertGreaterThanOrEqual(parsed.diagnostics.categoriesFound, 2)
    XCTAssertGreaterThan(parsed.diagnostics.uniqueCourseCount, 0)

    let reqs = parsed.requirements

    let foundation = reqs.first(where: { $0.category.contains("Foundation") })
    XCTAssertNotNil(foundation)
    XCTAssertEqual(Set(foundation?.requiredCourses ?? []), Set(["MGG 150", "MTH 131", "MGA 201"]))
    XCTAssertNil(foundation?.selectFrom)

    let elective = reqs.first(where: { $0.category.contains("Finance Elective") })
    XCTAssertNotNil(elective)
    XCTAssertNil(elective?.requiredCourses)
    XCTAssertEqual(Set(elective?.selectFrom ?? []), Set(["MGF 401", "MGF 402"]))
    XCTAssertEqual(elective?.selectCount, 1)
  }

  func testUBAerospaceGeneralTechnicalElective_ignoresRangesAndNestedExcludedLists() throws {
    // Regression: some UB electives include prose bullets like "Any 300/400 level..." with nested
    // excluded-course sublists. SwiftSoup's `.text()` can flatten those and cause bogus "ANY 300"
    // / "MTH 300" entries and multi-course titles.
    let html = """
    <div class=\"acalog-core\"><h2>Course Requirements</h2><hr></div>
    <div class=\"acalog-core\"><h3>General Technical Elective (3 credits minimum)</h3><hr>
      <ul>
        <li>
          Any 300/400 level 3-credit course that is offered by a department within SEAS.
          <ul>
            <li>Excluded courses (too much overlap with MAE courses):
              <ul>
                <li>CE 304LR - Chemical Engineering Thermodynamics</li>
                <li>CE 317LR - Transport Processes I</li>
              </ul>
            </li>
          </ul>
        </li>
        <li>MTH 300/400-level courses except MTH 337, MTH 399, MTH 437, MTH 438, and MTH 49X courses.</li>
        <li>BIO 200LLB - Evolutionary Biology Credits: 5</li>
      </ul>
    </div>
    <div class=\"acalog-core\"><h2>Curricular Plan</h2><hr></div>
    """

    let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: "https://catalogs.buffalo.edu")
    let reqs = parsed.requirements

    guard let elective = reqs.first(where: { $0.category.lowercased().contains("general technical elective") }) else {
      XCTFail("Expected 'General Technical Elective' category. Categories: \(reqs.map { $0.category })")
      return
    }

    let codes = Set((elective.requiredCourses ?? []) + (elective.selectFrom ?? []))
    XCTAssertTrue(codes.contains("BIO 200"))

    // These should NOT appear (they are prose/ranges, not actual option lists).
    XCTAssertFalse(codes.contains("ANY 300"))
    XCTAssertFalse(codes.contains("MTH 300"))
    XCTAssertFalse(codes.contains("MTH 49"))

    // Nested excluded courses should not be surfaced as options.
    XCTAssertFalse(codes.contains("CE 304"))
    XCTAssertFalse(codes.contains("CE 317"))
  }

  func testUBTitles_doNotIncludeTrailingAndOrConnectors() throws {
    let html = """
    <div class=\"acalog-core\"><h2>Undergraduate Course Requirements</h2><hr></div>
    <div class=\"acalog-core\"><h3>Biological Sciences Core (81-82 credits)</h3><hr>
      <ul>
        <li>CHE 101LR - General Chemistry Credits: 4 AND</li>
        <li>CHE 113LAB - General Chemistry Credits: 1 OR</li>
        <li>CHE 105LLR - Chemistry: Principles and Applications Credits: 5</li>
      </ul>
    </div>
    <div class=\"acalog-core\"><h2>Curricular Plan</h2><hr></div>
    """

    let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: "https://catalogs.buffalo.edu")
    let reqs = parsed.requirements

    guard let core = reqs.first(where: { $0.category.lowercased().contains("biological sciences core") }) else {
      XCTFail("Expected core category. Categories: \(reqs.map { $0.category })")
      return
    }

    let details = (core.requiredCoursesDetailed ?? []) + (core.selectFromDetailed ?? [])
    let byCode = Dictionary(uniqueKeysWithValues: details.map { ($0.code, $0) })

    XCTAssertEqual(byCode["CHE 101"]?.title, "General Chemistry")
    XCTAssertEqual(byCode["CHE 113"]?.title, "General Chemistry")
    XCTAssertEqual(byCode["CHE 105"]?.title, "Chemistry: Principles and Applications")
  }
}
