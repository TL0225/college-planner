import Foundation

extension String {
    /// Normalizes common catalog text issues (NBSP, stray newlines/tabs, multiple spaces).
    nonisolated func normalizedCatalogText() -> String {
        let withoutNBSP = replacingOccurrences(of: "\u{00A0}", with: " ")
        let collapsed = withoutNBSP.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
