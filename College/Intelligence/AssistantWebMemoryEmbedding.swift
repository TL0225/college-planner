import Foundation
import Accelerate

/// Compact, deterministic vectors for on-device hybrid retrieval.
/// These are **not** neural transformer embeddings; they are lexical sketches (hashed n-grams)
/// so hybrid search works offline without a second model. When a dedicated MLX embedding model
/// is added later, replace ``vector(for:)`` while keeping the same ``dimension`` and on-disk format.
enum AssistantWebMemoryEmbedding {
    static let dimension: Int = 256

    /// L2-normalized float vector derived from word / character n-gram features.
    static func vector(for text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 }
        for w in words.prefix(96) {
            addToken(w, into: &v, weight: 1)
            if w.count >= 4 {
                let idx = w.index(w.startIndex, offsetBy: 2)
                addToken(String(w[..<idx]), into: &v, weight: 0.35)
                addToken(String(w[idx...]), into: &v, weight: 0.35)
            }
        }
        let utf8 = Array(lower.utf8)
        for i in 0..<(max(0, utf8.count - 2)) {
            let tri = UInt32(utf8[i]) | (UInt32(utf8[i + 1]) << 8) | (UInt32(utf8[i + 2]) << 16)
            mix(tri, into: &v, weight: 0.15)
        }
        normalizeL2(&v)
        return v
    }

    static func data(from vector: [Float]) -> Data {
        precondition(vector.count == dimension)
        var dimLE = UInt32(dimension).littleEndian
        var data = Data()
        withUnsafeBytes(of: &dimLE) { data.append(contentsOf: $0) }
        vector.withUnsafeBufferPointer { buf in
            data.append(UnsafeBufferPointer(start: buf.baseAddress, count: dimension))
        }
        return data
    }

    static func vector(fromStored data: Data?) -> [Float]? {
        guard let data, data.count >= MemoryLayout<UInt32>.size + dimension * MemoryLayout<Float>.size else {
            return nil
        }
        let expected = MemoryLayout<UInt32>.size + dimension * MemoryLayout<Float>.size
        guard data.count == expected else { return nil }
        var dimLE: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &dimLE) { dst in
            data.copyBytes(to: dst.bindMemory(to: UInt8.self), count: MemoryLayout<UInt32>.size)
        }
        guard Int(dimLE.littleEndian) == dimension else { return nil }
        let floatOffset = MemoryLayout<UInt32>.size
        return data.withUnsafeBytes { raw -> [Float] in
            let ptr = raw.baseAddress!.advanced(by: floatOffset).assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: ptr, count: dimension))
        }
    }

    /// Dot product assuming L2-normalized vectors of ``dimension``; mismatched or legacy blobs return 0 (no match).
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count == dimension else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(dimension))
        return dot
    }

    // MARK: - Internals

    private static func addToken(_ token: String, into v: inout [Float], weight: Float) {
        var h = fnv1a64(token)
        for _ in 0..<3 {
            let idx = Int(h % UInt64(dimension))
            v[idx] += weight
            h = h &* 0x100000001B3 &+ 0x9E3779B97F4A7C15
        }
    }

    private static func mix(_ seed: UInt32, into v: inout [Float], weight: Float) {
        var h = UInt64(seed)
        for _ in 0..<3 {
            let idx = Int(h % UInt64(dimension))
            v[idx] += weight
            h = h &* 0x100000001B3 &+ 0x9E3779B97F4A7C15
        }
    }

    private static func fnv1a64(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        let prime: UInt64 = 0x100000001B3
        for b in s.utf8 {
            hash ^= UInt64(b)
            hash &*= prime
        }
        return hash == 0 ? 1 : hash
    }

    private static func normalizeL2(_ v: inout [Float]) {
        var sum: Float = 0
        vDSP_svesq(v, 1, &sum, vDSP_Length(dimension))
        let inv = 1 / (sqrt(sum) + 1e-8)
        vDSP_vsmul(v, 1, [inv], &v, 1, vDSP_Length(dimension))
    }
}
