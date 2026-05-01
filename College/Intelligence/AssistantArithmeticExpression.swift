import Foundation

enum AssistantArithmeticExpressionError: Error, Equatable {
    case empty
    case tooLong
    case invalidCharacters
    case parseFailed
    case nonFiniteResult
}

/// Safe, tiny arithmetic evaluator for the assistant `computeArithmetic` tool (+ − × ÷, parentheses, decimals).
enum AssistantArithmeticExpression {
    private static let maxLength = 120
    private static let allowedScalars: Set<UnicodeScalar> = {
        var s = Set<UnicodeScalar>()
        for ch in "0123456789+-*/.() " {
            s.insert(ch.unicodeScalars.first!)
        }
        return s
    }()

    static func evaluate(_ raw: String) throws -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AssistantArithmeticExpressionError.empty }
        guard trimmed.count <= maxLength else { throw AssistantArithmeticExpressionError.tooLong }
        guard trimmed.unicodeScalars.allSatisfy({ allowedScalars.contains($0) }) else {
            throw AssistantArithmeticExpressionError.invalidCharacters
        }

        let expr = NSExpression(format: trimmed)
        guard let value = expr.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw AssistantArithmeticExpressionError.parseFailed
        }
        let d = value.doubleValue
        guard d.isFinite else { throw AssistantArithmeticExpressionError.nonFiniteResult }
        return d
    }

    static func formatResult(_ value: Double) -> String {
        if value.rounded() == value, abs(value) <= Double(Int.max) {
            return String(Int(value.rounded()))
        }
        return String(format: "%.6g", value)
    }
}
