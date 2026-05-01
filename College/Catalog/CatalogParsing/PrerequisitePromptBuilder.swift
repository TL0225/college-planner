import Foundation

/// Builds the LLM prompt used for prerequisite parsing.
///
/// Lives in CatalogParsing/ because it belongs to the scraper/catalog pipeline,
/// not the syllabus AI pipeline.
enum PrerequisitePromptBuilder {

    // MARK: - Complexity Classification

    /// Returns true when the prerequisite text is complex enough to warrant
    /// Qwen 3's thinking mode (`/think`).
    ///
    /// Complex inputs include:
    /// - Parenthesized groups: `"(A or B) and C"`
    /// - Mixed AND+OR: `"A and B or C and D"`
    /// - Grade qualifiers inside a multi-course expression: `"A with grade of B or C"`
    /// - Multi-sentence text: more than one sentence boundary detected
    static func requiresThinkingMode(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("(") { return true }
        let hasAnd = lower.contains(" and ")
        let hasOr  = lower.contains(" or ")
        if hasAnd && hasOr { return true }
        let hasGrade = lower.range(of: "grade of|minimum grade|or better|with a [abcdf]", options: .regularExpression) != nil
        if hasGrade && (hasAnd || hasOr) { return true }
        // Multiple sentence boundaries suggest prose-heavy text
        let sentenceCount = text.components(separatedBy: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if sentenceCount > 2 { return true }
        return false
    }

    // MARK: - Prompt Construction

    /// Returns a focused, token-efficient prompt for the given prerequisite text.
    ///
    /// Embeds the full `PrerequisiteRule` tagged-union schema and several few-shot
    /// examples. For Qwen 3 models, prepend `/think` or `/no_think` to the user
    /// turn using `requiresThinkingMode(_:)` before calling `generateJSON`.
    static func makePrompt(text: String, courseCode: String) -> String {
        return """
You are a precise course prerequisite parser for university catalogs.
Convert the prerequisite text into structured JSON using only the schema below.

Schema:
- Single course:
  { "type": "course", "course": { "course_code": "DEPT 1234", "min_grade": "B" } }
  (min_grade is optional — omit the key when no grade requirement is stated)
- AND (all required):
  { "type": "and", "rules": [ <rule>, <rule>, ... ] }
- OR (any one required):
  { "type": "or",  "rules": [ <rule>, <rule>, ... ] }
- Not representable as course rules: null

Parsing rules:
1. Normalize course codes to "DEPT NUMBER" format (e.g. "MTH141" → "MTH 141", "CSE115LEC" → "CSE 115").
2. Respect parentheses: "(A or B) and C" → and([or([A,B]), C]).
3. "and" conjunctions between courses → AND group.
4. "or" conjunctions between courses → OR group. If the word "or" appears inside a course title or discipline abbreviation (e.g. "Operations Research", "OR 150") rather than between two course requirements, treat the whole text as a single course or null.
5. Comma-separated lists without "or" are AND groups.
6. "or equivalent" / "or permission of instructor" — include the course part; drop the non-course qualifier.
7. If the text contains ONLY non-course conditions (e.g. "junior standing", "permission of instructor", "department approval") → null.
8. Output ONLY the JSON value. No prose, no markdown fences, no extra keys.

Examples:

Input: "MTH 141 or MTH 153"
Output: {"type":"or","rules":[{"type":"course","course":{"course_code":"MTH 141"}},{"type":"course","course":{"course_code":"MTH 153"}}]}

Input: "CSE 115 and MTH 141"
Output: {"type":"and","rules":[{"type":"course","course":{"course_code":"CSE 115"}},{"type":"course","course":{"course_code":"MTH 141"}}]}

Input: "CSE 115, MTH 141, and PHY 107"
Output: {"type":"and","rules":[{"type":"course","course":{"course_code":"CSE 115"}},{"type":"course","course":{"course_code":"MTH 141"}},{"type":"course","course":{"course_code":"PHY 107"}}]}

Input: "(MTH 141 or MTH 153) and CSE 115"
Output: {"type":"and","rules":[{"type":"or","rules":[{"type":"course","course":{"course_code":"MTH 141"}},{"type":"course","course":{"course_code":"MTH 153"}}]},{"type":"course","course":{"course_code":"CSE 115"}}]}

Input: "CSE 191 with a grade of C or better"
Output: {"type":"course","course":{"course_code":"CSE 191","min_grade":"C"}}

Input: "CSE 115 and (MTH 141 or MTH 153) and PHY 101"
Output: {"type":"and","rules":[{"type":"course","course":{"course_code":"CSE 115"}},{"type":"or","rules":[{"type":"course","course":{"course_code":"MTH 141"}},{"type":"course","course":{"course_code":"MTH 153"}}]},{"type":"course","course":{"course_code":"PHY 101"}}]}

Input: "CSE 115 or equivalent"
Output: {"type":"course","course":{"course_code":"CSE 115"}}

Input: "permission of instructor"
Output: null

Input: "junior standing or above"
Output: null

Input: "Introduction to Operations Research (OR 150)"
Output: {"type":"course","course":{"course_code":"OR 150"}}

Input: "(CSE 115 or CSE 116) and MTH 141 with a grade of B or better"
Output: {"type":"and","rules":[{"type":"or","rules":[{"type":"course","course":{"course_code":"CSE 115"}},{"type":"course","course":{"course_code":"CSE 116"}}]},{"type":"course","course":{"course_code":"MTH 141","min_grade":"B"}}]}

Input: "Completion of ENG 101 with a minimum grade of C and either BIO 200 or BIO 201"
Output: {"type":"and","rules":[{"type":"course","course":{"course_code":"ENG 101","min_grade":"C"}},{"type":"or","rules":[{"type":"course","course":{"course_code":"BIO 200"}},{"type":"course","course":{"course_code":"BIO 201"}}]}]}

Input: "(CHEM 101 or CHEM 105) and (PHY 107 or PHY 117) and MATH 122"
Output: {"type":"and","rules":[{"type":"or","rules":[{"type":"course","course":{"course_code":"CHEM 101"}},{"type":"course","course":{"course_code":"CHEM 105"}}]},{"type":"or","rules":[{"type":"course","course":{"course_code":"PHY 107"}},{"type":"course","course":{"course_code":"PHY 117"}}]},{"type":"course","course":{"course_code":"MATH 122"}}]}

Now parse:
Course: \(courseCode)
Prerequisite text: "\(text)"
Output:
"""
    }

    // MARK: - Dynamic Token Budget

    /// Computes a token budget appropriate for the given input text.
    ///
    /// Prerequisite JSON output is compact — even a deeply nested AND/OR tree
    /// rarely exceeds 300 tokens. The formula:
    ///   • Estimate input tokens as `text.count / 4` (3–4 chars per token is typical)
    ///   • Budget 3× the estimated input tokens for the output (the JSON representation
    ///     of the tree is roughly proportional to the number of course codes in the input)
    ///   • Floor at 150 (enough for a complex 3-branch tree)
    ///   • Cap at 1024 (hard ceiling; avoids wasting inference cycles on pathological inputs)
    static func recommendedMaxTokens(for text: String) -> Int {
        let estimatedInputTokens = max(1, text.count / 4)
        let outputBudget = estimatedInputTokens * 3 + 80
        return max(150, min(1024, outputBudget))
    }
}
