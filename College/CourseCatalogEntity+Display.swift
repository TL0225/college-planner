import Foundation

extension CourseCatalogEntity {
    var creditsDisplayText: String {
        let v = creditsValue
        if v > 0 {
            if abs(v.rounded() - v) < 0.0001 {
                return String(Int(v.rounded()))
            }
            return String(format: "%.1f", v)
        }

        let base = Int(credits)
        return base > 0 ? String(base) : ""
    }
}
