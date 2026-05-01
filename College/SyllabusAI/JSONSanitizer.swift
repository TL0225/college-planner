import Foundation

enum JSONSanitizer {
    /// Attempts to recover a strict JSON object/array from LLM output.
    /// Strategy:
    /// 1) Strip Markdown fences.
    /// 2) Find first '{' or '['.
    /// 3) Scan forward until braces/brackets balance (string-aware).
    static func extractJSONPayload(from raw: String) -> String? {
        let unfenced = stripCodeFences(raw)
        guard let startIndex = unfenced.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }

        let openChar = unfenced[startIndex]
        let closeChar: Character = (openChar == "{") ? "}" : "]"

        var depth = 0
        var inString = false
        var escape = false

        var i = startIndex
        while i < unfenced.endIndex {
            let c = unfenced[i]

            if inString {
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == "\"" {
                    inString = false
                }
                i = unfenced.index(after: i)
                continue
            }

            if c == "\"" {
                inString = true
                i = unfenced.index(after: i)
                continue
            }

            if c == openChar {
                depth += 1
            } else if c == closeChar {
                depth -= 1
                if depth == 0 {
                    let end = unfenced.index(after: i)
                    return String(unfenced[startIndex..<end])
                }
            }

            i = unfenced.index(after: i)
        }

        // Fallback: between first open and last close
        if let lastClose = unfenced.lastIndex(of: closeChar) {
            return String(unfenced[startIndex...lastClose])
        }

        return nil
    }

    static func stripCodeFences(_ s: String) -> String {
        var t = s
        // Common patterns: ```json ... ``` or ``` ... ```
        t = t.replacingOccurrences(of: "```json", with: "")
        t = t.replacingOccurrences(of: "```", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
