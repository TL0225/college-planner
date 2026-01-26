import Foundation
import CoreData

/// Intelligent service that automatically fetches and parses course catalogs from any university
class CourseCatalogService {
    private let coreDataManager: CoreDataManager
    private let apiKey: String // Store your Claude/OpenAI API key securely
    
    init(coreDataManager: CoreDataManager, apiKey: String = "") {
        self.coreDataManager = coreDataManager
        self.apiKey = apiKey
    }
    
    // MARK: - Main Entry Point
    
    /// Automatically discover and import course catalog for any university
    func importCourseCatalog(universityName: String) async throws {
        let toastID = await MainActor.run {
            AppNotificationCenter.shared.post(
                kind: .progress,
                title: "Importing Catalog",
                message: "Starting \(universityName)…",
                progress: 0.05,
                isDismissible: true
            )
        }

        do {
            print("🔍 Starting automatic course catalog import for: \(universityName)")

            // Step 1: Find or create university entity
            await MainActor.run {
                AppNotificationCenter.shared.update(id: toastID, message: "Preparing workspace…", progress: 0.1)
            }
            let university = try await findOrCreateUniversity(name: universityName)

            // Step 2: Use AI to discover catalog URL
            await MainActor.run {
                AppNotificationCenter.shared.update(id: toastID, message: "Discovering catalog URL…", progress: 0.2)
            }
            let catalogURL = try await discoverCatalogURL(universityName: universityName)
            university.catalogURL = catalogURL

            // Step 3: Fetch catalog content
            await MainActor.run {
                AppNotificationCenter.shared.update(id: toastID, message: "Fetching catalog content…", progress: 0.35)
            }
            let catalogContent = try await fetchCatalogContent(url: catalogURL)

            // Step 4: Use AI to parse courses from the content
            await MainActor.run {
                AppNotificationCenter.shared.update(id: toastID, message: "Parsing courses…", progress: 0.55)
            }
            let courses = try await parseCoursesWithAI(content: catalogContent, universityName: universityName)

            // Step 5: Store courses in Core Data
            await MainActor.run {
                AppNotificationCenter.shared.update(id: toastID, message: "Saving \(courses.count) courses…", progress: 0.8)
            }
            try await storeCourses(courses, for: university)

            // Step 6: Extract and store degree requirements
            await MainActor.run {
                AppNotificationCenter.shared.update(id: toastID, message: "Extracting degree requirements…", progress: 0.92)
            }
            try await extractDegreeRequirements(from: catalogContent, for: university)

            university.lastCatalogSync = Date()
            coreDataManager.save()

            await MainActor.run {
                AppNotificationCenter.shared.complete(
                    id: toastID,
                    kind: .success,
                    title: "Catalog Imported",
                    message: "Imported \(courses.count) courses for \(universityName).",
                    autoDismissAfter: 4
                )
            }

            print("✅ Successfully imported \(courses.count) courses for \(universityName)")
        } catch {
            await MainActor.run {
                AppNotificationCenter.shared.dismiss(id: toastID)
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Catalog Import Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
            throw error
        }
    }
    
    // MARK: - AI-Powered Discovery
    
    private func discoverCatalogURL(universityName: String) async throws -> String {
        // Use AI to find the course catalog URL
        let prompt = """
        Find the official course catalog URL for \(universityName).
        Return ONLY the URL, nothing else.
        Common patterns:
        - catalog.university.edu
        - university.edu/academics/courses
        - university.edu/registrar/catalog
        
        University: \(universityName)
        """
        
        let url = try await callAI(prompt: prompt)
        return url.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseCoursesWithAI(content: String, universityName: String) async throws -> [ParsedCourse] {
        let prompt = """
        Extract ALL courses from this university course catalog.
        Return ONLY a JSON array with this exact structure:
        [
            {
                "code": "CS 101",
                "title": "Introduction to Computer Science",
                "description": "Fundamentals of programming...",
                "credits": 3,
                "prerequisites": ["MATH 110"],
                "department": "Computer Science",
                "typically_offered": ["Fall", "Spring"]
            }
        ]
        
        Rules:
        - Extract EVERY course you find
        - Parse prerequisite strings carefully (look for "Prerequisite:", "Prereq:", etc.)
        - Handle various formats: "CS101", "CS 101", "CSCI-101"
        - If credits not specified, use 3 as default
        
        Catalog content (may be HTML, text, or mixed):
        \(content.prefix(100000)) // Limit content size
        """
        
        let jsonResponse = try await callAI(prompt: prompt)
        let courses = try parseCourseJSON(jsonResponse)
        return courses
    }
    
    // MARK: - Data Fetching
    
    private func fetchCatalogContent(url: String) async throws -> String {
        guard let catalogURL = URL(string: url) else {
            throw CatalogError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: catalogURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CatalogError.fetchFailed
        }
        
        // Handle PDF catalogs
        if url.hasSuffix(".pdf") {
            // For PDF, you'd use PDFKit to extract text
            return try extractTextFromPDF(data: data)
        }
        
        // Handle HTML catalogs
        guard let html = String(data: data, encoding: .utf8) else {
            throw CatalogError.encodingFailed
        }
        
        return html
    }
    
    // MARK: - AI Integration
    
    private func callAI(prompt: String) async throws -> String {
        // This is a simplified example - you'd integrate with Claude or OpenAI API
        // For now, return a placeholder that can be replaced with actual API call
        
        guard !apiKey.isEmpty else {
            throw CatalogError.missingAPIKey
        }
        
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        
        let body: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        
        return response.content.first?.text ?? ""
    }
    
    // MARK: - Core Data Operations
    
    private func findOrCreateUniversity(name: String) async throws -> UniversityEntity {
        let context = coreDataManager.viewContext
        
        let fetchRequest: NSFetchRequest<UniversityEntity> = UniversityEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        
        if let existing = try context.fetch(fetchRequest).first {
            await MainActor.run {
                coreDataManager.setActiveUniversity(existing)
            }
            return existing
        }
        
        let university = UniversityEntity(context: context)
        university.id = UUID()
        university.name = name
        await MainActor.run {
            coreDataManager.setActiveUniversity(university)
        }
        return university
    }
    
    private func storeCourses(_ courses: [ParsedCourse], for university: UniversityEntity) async throws {
        let context = coreDataManager.viewContext
        
        for parsedCourse in courses {
            let course = CourseCatalogEntity(context: context)
            course.id = UUID()
            course.courseCode = parsedCourse.code
            course.title = parsedCourse.title
            course.descriptionText = parsedCourse.description
            course.credits = Int16(parsedCourse.credits)
            course.department = parsedCourse.department
            course.prerequisiteCodes = parsedCourse.prerequisites.joined(separator: ",")
            course.typicallyOffered = parsedCourse.typicallyOffered.joined(separator: ",")
            course.lastUpdated = Date()
            course.university = university
        }
        
        try context.save()
    }
    
    private func extractDegreeRequirements(from content: String, for university: UniversityEntity) async throws {
        let prompt = """
        Extract degree requirements from this catalog.
        Focus on: Computer Science, Engineering, Business, Mathematics majors.
        Return JSON array:
        [
            {
                "degree_type": "Bachelor of Science",
                "major": "Computer Science",
                "category": "Core Requirements",
                "required_courses": ["CS 101", "CS 102", "CS 201"],
                "credits_required": 36,
                "description": "All CS majors must complete these core courses"
            }
        ]
        
        Content:
        \(content.prefix(50000))
        """
        
        let jsonResponse = try await callAI(prompt: prompt)
        let requirements = try parseRequirementsJSON(jsonResponse)
        
        let context = coreDataManager.viewContext
        for req in requirements {
            let requirement = DegreeRequirementEntity(context: context)
            requirement.id = UUID()
            requirement.degreeType = req.degreeType
            requirement.major = req.major
            requirement.requirementCategory = req.category
            requirement.requiredCourses = req.requiredCourses.joined(separator: ",")
            requirement.creditsRequired = Int16(req.creditsRequired)
            requirement.descriptionText = req.description
            requirement.lastUpdated = Date()
            requirement.university = university
        }
        
        try context.save()
    }
    
    // MARK: - Helper Methods
    
    private func extractTextFromPDF(data: Data) throws -> String {
        // Implement PDF text extraction using PDFKit
        // For now, throw error as placeholder
        throw CatalogError.pdfNotSupported
    }
    
    private func parseCourseJSON(_ json: String) throws -> [ParsedCourse] {
        // Extract JSON from potential markdown code blocks
        let cleanJSON = json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let data = cleanJSON.data(using: .utf8)!
        return try JSONDecoder().decode([ParsedCourse].self, from: data)
    }
    
    private func parseRequirementsJSON(_ json: String) throws -> [ParsedRequirement] {
        let cleanJSON = json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let data = cleanJSON.data(using: .utf8)!
        return try JSONDecoder().decode([ParsedRequirement].self, from: data)
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

// MARK: - Data Models

struct ParsedCourse: Codable {
    let code: String
    let title: String
    let description: String
    let credits: Int
    let prerequisites: [String]
    let department: String
    let typicallyOffered: [String]
    
    enum CodingKeys: String, CodingKey {
        case code, title, description, credits, prerequisites, department
        case typicallyOffered = "typically_offered"
    }
}

struct ParsedRequirement: Codable {
    let degreeType: String
    let major: String
    let category: String
    let requiredCourses: [String]
    let creditsRequired: Int
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case degreeType = "degree_type"
        case major, category
        case requiredCourses = "required_courses"
        case creditsRequired = "credits_required"
        case description
    }
}

struct ClaudeResponse: Codable {
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let text: String
}

// MARK: - Errors

enum CatalogError: Error {
    case invalidURL
    case fetchFailed
    case encodingFailed
    case missingAPIKey
    case pdfNotSupported
    case parsingFailed
    
    var localizedDescription: String {
        switch self {
        case .invalidURL: return "Invalid catalog URL"
        case .fetchFailed: return "Failed to fetch catalog"
        case .encodingFailed: return "Failed to decode catalog content"
        case .missingAPIKey: return "AI API key not configured"
        case .pdfNotSupported: return "PDF catalogs require additional setup"
        case .parsingFailed: return "Failed to parse course data"
        }
    }
}
