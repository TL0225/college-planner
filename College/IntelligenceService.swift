import Foundation
import MLX

/// Intelligence Service: Hybrid prerequisite parsing (Regex + LLM)
/// Strategy: Parse 80% with fast regex, use LLM only for complex cases
class IntelligenceService {

    // MARK: - Precompiled regexes (performance)

    private static let singleCourseRegex: NSRegularExpression = {
        // Match "DEPT 1234" or "DEPT1234" (case-insensitive)
        // Captures: (1) dept letters, (2) number+optional suffix
        return try! NSRegularExpression(
            pattern: #"\b([A-Z]{2,4})\s*(\d{3,4}[A-Z]?)\b"#,
            options: [.caseInsensitive]
        )
    }()

    private static let minGradeRegex: NSRegularExpression = {
        // Examples: "grade of B", "B or better", "minimum grade: C+"
        return try! NSRegularExpression(
            pattern: #"(?:grade of|grade:|minimum grade:?|with a)\s*([A-D][+-]?|[ABCDF])"#,
            options: [.caseInsensitive]
        )
    }()
    
    // MARK: - LLM Model (Lazy Loading)
    // TODO: Re-enable when MLXLLM package is properly configured
    // private var model: LLMModel?
    private var isModelLoaded = false
    private let modelQueue = DispatchQueue(label: "com.college.intelligence", qos: .utility)
    
    // MARK: - Statistics
    struct ParsingStats {
        var totalParsed: Int = 0
        var regexParsed: Int = 0
        var llmParsed: Int = 0
        var failed: Int = 0
        var needsManualReview: Int = 0
    }
    
    private(set) var stats = ParsingStats()
    
    // MARK: - Main Entry Point
    
    /// Parse prerequisite text using hybrid strategy
    /// - Returns: (rule, needsLLM) - If needsLLM is true, mark for background processing
    func parsePrerequisite(
        _ text: String,
        courseCode: String
    ) -> (rule: PrerequisiteRule?, needsLLM: Bool, confidence: ParsingConfidence) {
        
        guard !text.isEmpty else {
            return (nil, false, .none)
        }
        
        // Step 1: Try regex parsing (Fast Lane - 80% of cases)
        if let simpleRule = tryRegexParsing(text) {
            stats.regexParsed += 1
            stats.totalParsed += 1
            return (simpleRule, false, .high)
        }
        
        // Step 2: Mark as needs LLM processing (Slow Lane - 20% of cases)
        stats.totalParsed += 1
        return (nil, true, .needsLLM)
    }
    
    /// Background processing for complex prerequisites
    func parseComplexPrerequisites(
        _ batch: [(text: String, courseCode: String, courseID: UUID)],
        progressCallback: @escaping (Int, Int) -> Void,
        completion: @escaping ([UUID: PrerequisiteRule]) -> Void
    ) {
        modelQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Lazy load model only when needed
            if !self.isModelLoaded {
                self.loadModel()
            }
            
            var results: [UUID: PrerequisiteRule] = [:]
            
            for (index, item) in batch.enumerated() {
                // Parse using LLM
                if let rule = try? self.parseSingleWithLLM(item.text, courseCode: item.courseCode) {
                    results[item.courseID] = rule
                    self.stats.llmParsed += 1
                } else {
                    self.stats.failed += 1
                }
                
                // Report progress
                DispatchQueue.main.async {
                    progressCallback(index + 1, batch.count)
                }
            }
            
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
    
    // MARK: - Step 1: Regex Parsing (Fast Lane)
    
    private func tryRegexParsing(_ text: String) -> PrerequisiteRule? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Pattern 1: Single course "MATH 1920" or "Prerequisite: CS 1110"
        if let single = parseSingleCourse(cleanText) {
            return single
        }
        
        // Pattern 2: Simple AND "CS 1110 and MATH 1920"
        if cleanText.contains(" and ") && !cleanText.contains("(") {
            return parseSimpleAND(cleanText)
        }
        
        // Pattern 3: Simple OR "CS 1110 or CS 1112"
        if cleanText.contains(" or ") && !cleanText.contains("(") {
            return parseSimpleOR(cleanText)
        }
        
        // If we get here, it's complex (nested logic, parentheses, etc.)
        return nil
    }
    
    private func parseSingleCourse(_ text: String) -> PrerequisiteRule? {
        let matches = Self.singleCourseRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        // If exactly one course code found, it's a simple prerequisite
        guard matches.count == 1,
              let match = matches.first,
              let deptRange = Range(match.range(at: 1), in: text),
              let numRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        
        let dept = String(text[deptRange]).uppercased()
        let number = String(text[numRange]).uppercased()
        let courseCode = "\(dept) \(number)"
        
        // Check for grade requirement
        let minGrade = extractMinGrade(from: text)
        
        return .course(CourseRequirement(courseCode: courseCode, minGrade: minGrade))
    }
    
    private func parseSimpleAND(_ text: String) -> PrerequisiteRule? {
        let parts = text.components(separatedBy: " and ")
        guard parts.count >= 2 else { return nil }
        
        var rules: [PrerequisiteRule] = []
        
        for part in parts {
            guard let rule = parseSingleCourse(part) else {
                return nil // Complex, needs LLM
            }
            rules.append(rule)
        }
        
        return .and(rules)
    }
    
    private func parseSimpleOR(_ text: String) -> PrerequisiteRule? {
        let parts = text.components(separatedBy: " or ")
        guard parts.count >= 2 else { return nil }
        
        var rules: [PrerequisiteRule] = []
        
        for part in parts {
            guard let rule = parseSingleCourse(part) else {
                return nil // Complex, needs LLM
            }
            rules.append(rule)
        }
        
        return .or(rules)
    }
    
    private func extractMinGrade(from text: String) -> String? {
        guard let match = Self.minGradeRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let gradeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        return String(text[gradeRange]).uppercased()
    }
    
    // MARK: - Step 2: LLM Parsing (Slow Lane)
    
    private func loadModel() {
        guard !isModelLoaded else { return }
        
        // TODO: Re-enable when MLXLLM package is properly configured
        print("[Intelligence] ⚠️ MLX model loading disabled - MLXLLM package not available")
        print("[Intelligence] Regex parsing will work, but LLM parsing is temporarily disabled")
        print("[Intelligence] Prerequisites marked for LLM will remain in 'pending_llm' status")
        
        /*
        modelQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                print("[Intelligence] Loading Llama 3.2 3B model...")
                
                // Get model path from Documents or bundle
                let modelPath = self.getModelPath()
                
                // Load configuration
                let modelConfig = ModelConfiguration(
                    id: modelPath,
                    tokenizerId: modelPath
                )
                
                // Load model (this takes 2-5 seconds)
                self.model = try LLMModel.load(configuration: modelConfig)
                self.isModelLoaded = true
                
                print("[Intelligence] ✅ Model loaded successfully")
            } catch {
                print("[Intelligence] ❌ Failed to load model: \(error)")
                print("[Intelligence] Make sure model is downloaded to Models/llama-3.2-3b-4bit/")
            }
        }
        */
    }
    
    private func getModelPath() -> String {
        // Try Documents directory first (for downloaded models)
        if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelDir = documentsDir.appendingPathComponent("Models/llama-3.2-3b-4bit")
            if FileManager.default.fileExists(atPath: modelDir.path) {
                return modelDir.path
            }
        }
        
        // Fall back to bundle (if model is included in app)
        if let bundlePath = Bundle.main.path(forResource: "llama-3.2-3b-4bit", ofType: nil, inDirectory: "Models") {
            return bundlePath
        }
        
        // Default: use relative path from project
        let projectPath = "/Users/timothy/Desktop/College/Models/llama-3.2-3b-4bit"
        return projectPath
    }
    
    private func parseSingleWithLLM(_ text: String, courseCode: String) throws -> PrerequisiteRule? {
        // TODO: Re-enable when MLXLLM package is properly configured
        throw IntelligenceError.modelNotLoaded
        
        /*
        guard let model = self.model else {
            throw IntelligenceError.modelNotLoaded
        }
        
        let prompt = """
        You are a course prerequisite parser. Convert this prerequisite text into structured JSON.
        
        Prerequisite text: "\(text)"
        For course: \(courseCode)
        
        Output ONLY valid JSON in this exact format:
        {
          "type": "course|and|or",
          "course": {"course_code": "DEPT 1234", "min_grade": "B"},
          "rules": [...]
        }
        
        Rules:
        - "course" type has a "course" object
        - "and"/"or" types have a "rules" array
        - Nested logic uses nested objects
        - Extract minimum grade if mentioned (e.g., "B or better" -> "B")
        - If text says "permission of instructor" or "department approval", use type "permission"
        
        Example inputs:
        1. "CS 1110" -> {"type": "course", "course": {"course_code": "CS 1110"}}
        2. "CS 1110 and MATH 1920" -> {"type": "and", "rules": [...]}
        3. "(CS 1110 or CS 1112) AND MATH 1920" -> {"type": "and", "rules": [{"type": "or", ...}, ...]}
        
        JSON:
        """
        
        // Generate response using MLX Swift
        let generateParameters = GenerateParameters(
            temperature: 0.1,       // Low temperature for deterministic output
            topP: 0.9,
            maxTokens: 200
        )
        
        let result = try model.generate(
            prompt: .init(prompt: prompt),
            parameters: generateParameters
        )
        
        // Extract text from result
        let responseText = result.output
        
        // Extract JSON from response
        guard let jsonString = extractJSON(from: responseText) else {
            throw IntelligenceError.invalidResponse
        }
        
        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw IntelligenceError.invalidResponse
        }
        
        return try JSONDecoder().decode(PrerequisiteRule.self, from: jsonData)
        */
    }
    
    private func extractJSON(from text: String) -> String? {
        // Find JSON block (between first { and last })
        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}") else {
            return nil
        }
        
        return String(text[startIndex...endIndex])
    }
    
    // MARK: - Confidence Levels
    
    enum ParsingConfidence {
        case none           // No prerequisite
        case high           // Regex parsed successfully
        case medium         // LLM parsed successfully
        case low            // LLM parsed but uncertain
        case needsLLM       // Queued for LLM processing
        case failed         // Parsing failed
        case needsManualReview  // Invalid course codes detected
    }
}

// MARK: - Errors

enum IntelligenceError: LocalizedError {
    case modelNotLoaded
    case invalidResponse
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "LLM model not loaded"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .parsingFailed:
            return "Failed to parse prerequisite"
        }
    }
}
