// CareerResumeWordDiff.swift
// Feature: Career
// Purpose: Word-token Myers diff for resume tailoring before/after views.

import Foundation

enum CareerResumeWordDiff {
    enum SegmentKind: Equatable {
        case unchanged
        case removed
        case added
    }

    struct Segment: Equatable {
        var text: String
        var kind: SegmentKind
    }

    static func diff(original: String, revised: String) -> [Segment] {
        let a = tokenize(original)
        let b = tokenize(revised)
        let ops = myers(a: a, b: b)
        var segments: [Segment] = []
        var i = 0
        var j = 0
        for op in ops {
            switch op {
            case .equal(let count):
                let words = a[i..<(i + count)]
                append(&segments, words.joined(separator: " "), kind: .unchanged)
                i += count
                j += count
            case .delete(let count):
                let words = a[i..<(i + count)]
                append(&segments, words.joined(separator: " "), kind: .removed)
                i += count
            case .insert(let count):
                let words = b[j..<(j + count)]
                append(&segments, words.joined(separator: " "), kind: .added)
                j += count
            }
        }
        return segments
    }

    private static func append(_ segments: inout [Segment], _ text: String, kind: SegmentKind) {
        guard !text.isEmpty else { return }
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1].text += " " + text
        } else {
            segments.append(Segment(text: text, kind: kind))
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private enum Op {
        case equal(Int)
        case delete(Int)
        case insert(Int)
    }

    private static func myers(a: [String], b: [String]) -> [Op] {
        let n = a.count
        let m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var ops: [Op] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                if case .equal(let count)? = ops.last {
                    ops[ops.count - 1] = .equal(count + 1)
                } else {
                    ops.append(.equal(1))
                }
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                if case .insert(let count)? = ops.last {
                    ops[ops.count - 1] = .insert(count + 1)
                } else {
                    ops.append(.insert(1))
                }
                j -= 1
            } else {
                if case .delete(let count)? = ops.last {
                    ops[ops.count - 1] = .delete(count + 1)
                } else {
                    ops.append(.delete(1))
                }
                i -= 1
            }
        }
        return ops.reversed()
    }
}
