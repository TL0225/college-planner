// VectorMath.swift
// Feature: Core
// Purpose: Core module — VectorMath.
// Data: CollegePersistence / repositories when applicable.

import Accelerate
import Foundation

enum VectorMath {
    /// Cosine similarity for equal-length float vectors using Accelerate (`vDSP`).
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        a.withUnsafeBufferPointer { ba in
            b.withUnsafeBufferPointer { bb in
                guard let ap = ba.baseAddress, let bp = bb.baseAddress else { return }
                let n = vDSP_Length(a.count)
                vDSP_dotpr(ap, 1, bp, 1, &dot, n)
                vDSP_svesq(ap, 1, &na, n)
                vDSP_svesq(bp, 1, &nb, n)
            }
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 0 else { return nil }
        return dot / denom
    }
}
