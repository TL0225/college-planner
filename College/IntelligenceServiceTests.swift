import Foundation

/// Test the IntelligenceService with real prerequisite examples
func testIntelligenceService() {
    print("🧪 Testing IntelligenceService\n")
    
    let intelligenceService = IntelligenceService()
    
    // Test cases
    let testCases = [
        ("Simple", "Prerequisite: CS 1110", "CS 2110"),
        ("AND", "Prerequisites: CS 1110 and MATH 1920", "CS 2802"),
        ("OR", "Prerequisite: CS 1110 or CS 1112", "CS 2110"),
        ("Complex", "Prerequisite: (CS 1110 or CS 1112) AND MATH 1920", "CS 2110"),
        ("With Grade", "Prerequisite: CS 1110 with a grade of B or better", "CS 3110"),
        ("Multiple AND", "Prerequisites: CS 2110 and CS 2800 and MATH 2940", "CS 4820"),
        ("Nested", "Prerequisites: (CS 2110 and CS 2800) or CS 2802", "CS 4410"),
    ]
    
    var regexCount = 0
    var llmCount = 0
    
    for (name, text, courseCode) in testCases {
        print("Test: \(name)")
        print("Input: \"\(text)\"")
        
        let (rule, needsLLM, confidence) = intelligenceService.parsePrerequisite(text, courseCode: courseCode)
        
        if let rule = rule {
            print("✅ Parsed with \(needsLLM ? "LLM" : "REGEX")")
            print("Confidence: \(confidence)")
            print("Rule: \(rule)")
            
            if !needsLLM {
                regexCount += 1
            }
        } else if needsLLM {
            print("⏳ Queued for LLM processing")
            llmCount += 1
        } else {
            print("❌ Failed to parse")
        }
        
        print()
    }
    
    print("\n📊 Results:")
    print("Regex parsed: \(regexCount)/\(testCases.count)")
    print("Needs LLM: \(llmCount)/\(testCases.count)")
    print("Success rate: \(regexCount * 100 / testCases.count)%")
}

// Uncomment to run tests:
// testIntelligenceService()
