import Foundation
import MapKit
import Combine

struct ResolvedLocation: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? subtitle : trimmed
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class MapLocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            completer.queryFragment = canonicalQueryForAutocomplete(from: query)
        }
    }

    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching: Bool = false

    private let completer: MKLocalSearchCompleter
    private let ubBuildingAliases: [String: [String]] = [
        "clemens": ["Clemens Hall", "Clemens"],
        "capen": ["Capen Hall", "Capen"],
        "knox": ["Knox Hall", "Knox"],
        "nsc": ["Natural Sciences Complex", "Natural Sciences Complex Buffalo"],
        "natural sciences": ["Natural Sciences Complex"],
        "baldy": ["Baldy Hall", "Baldy"],
        "furnas": ["Furnas Hall", "Furnas"],
        "davis": ["Davis Hall", "Davis"],
        "hoch": ["Hochstetter Hall", "Hochstetter"],
        "obrian": ["O'Brian Hall", "OBrien Hall"],
        "o'brien": ["O'Brian Hall", "OBrien Hall"],
        "o brien": ["O'Brian Hall", "OBrien Hall"],
        "alf": ["Alfiero Center", "Alfiero"],
        "alumni": ["Alumni Arena"],
        "student union": ["Student Union Buffalo"],
        "slee": ["Slee Hall", "Slee"],
        "goodyear": ["Goodyear Hall", "Goodyear"],
    ]

    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func applyLocationBias(from location: CLLocation?, radiusMeters: CLLocationDistance = 7_500) {
        guard let location else { return }
        completer.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedLocation? {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }

            let coordinate = item.location.coordinate
            let title = item.name ?? completion.title
            let subtitle = completion.subtitle
            return ResolvedLocation(
                id: UUID(),
                title: title,
                subtitle: subtitle,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            return nil
        }
    }

    func resolveTopCompletions(limit: Int = 6, near location: CLLocation?) async -> [ResolvedLocation] {
        let top = Array(completions.prefix(limit))
        var resolved: [ResolvedLocation] = []
        resolved.reserveCapacity(max(limit, top.count))

        for completion in top {
            if let item = await resolve(completion) {
                resolved.append(item)
            }
        }

        let normalizedQueries = queryVariants(for: query)
        let primaryQuery = normalizedQueries.first ?? query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let location, !primaryQuery.isEmpty {
            let nearbyQueries = Array(normalizedQueries.prefix(2))
            for candidate in nearbyQueries {
                let nearby = await searchNearby(query: candidate, near: location, limit: limit)
                resolved.append(contentsOf: nearby)
            }
        }

        guard !resolved.isEmpty else { return [] }

        var deduped: [ResolvedLocation] = []
        deduped.reserveCapacity(resolved.count)
        var seenKeys = Set<String>()

        for item in resolved {
            let titleKey = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let latKey = Int((item.latitude * 10_000).rounded())
            let lonKey = Int((item.longitude * 10_000).rounded())
            let key = "\(titleKey)|\(latKey)|\(lonKey)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            deduped.append(item)
        }

        guard let location else {
            return Array(deduped.prefix(limit))
        }

        let queryLower = primaryQuery.lowercased()
        return deduped.sorted { lhs, rhs in
            let lhsDistance = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: location)
            let rhsDistance = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude).distance(from: location)
            let lhsPrefix = lhs.displayName.lowercased().hasPrefix(queryLower)
            let rhsPrefix = rhs.displayName.lowercased().hasPrefix(queryLower)
            if lhsPrefix != rhsPrefix {
                return lhsPrefix && !rhsPrefix
            }
            if abs(lhsDistance - rhsDistance) > 25 {
                return lhsDistance < rhsDistance
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    private func searchNearby(query: String, near location: CLLocation, limit: Int) async -> [ResolvedLocation] {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 10_000,
            longitudinalMeters: 10_000
        )
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return response.mapItems.prefix(limit).map { item in
                let coordinate = item.location.coordinate
                return ResolvedLocation(
                    id: UUID(),
                    title: item.name ?? query,
                    subtitle: "",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } catch {
            return []
        }
    }

    private func canonicalQueryForAutocomplete(from raw: String) -> String {
        queryVariants(for: raw).first ?? raw
    }

    private func queryVariants(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var variants: [String] = []
        variants.reserveCapacity(6)
        variants.append(trimmed)

        let compact = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if compact != trimmed {
            variants.append(compact)
        }

        let roomless = removingLikelyRoomSuffix(from: compact)
        if let roomless, !roomless.isEmpty, roomless.caseInsensitiveCompare(compact) != .orderedSame {
            variants.append(roomless)
        }

        variants.append(contentsOf: expandedAliasVariants(from: compact))
        if let roomless {
            variants.append(contentsOf: expandedAliasVariants(from: roomless))
        }

        var deduped: [String] = []
        var seen = Set<String>()
        deduped.reserveCapacity(variants.count)
        for value in variants {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(value)
        }
        return deduped
    }

    private func expandedAliasVariants(from query: String) -> [String] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let roomSuffix = extractRoomSuffix(from: query)
        var expanded: [String] = []

        for (alias, canonicalNames) in ubBuildingAliases {
            guard normalizedQuery.contains(alias) else { continue }
            for canonical in canonicalNames {
                if let roomSuffix, !roomSuffix.isEmpty {
                    expanded.append("\(canonical) \(roomSuffix)")
                }
                expanded.append(canonical)
            }
        }

        return expanded
    }

    private func extractRoomSuffix(from query: String) -> String? {
        let tokens = query.split(separator: " ").map(String.init)
        guard let last = tokens.last else { return nil }
        let hasDigit = last.rangeOfCharacter(from: .decimalDigits) != nil
        guard hasDigit else { return nil }
        return last
    }

    private func removingLikelyRoomSuffix(from value: String) -> String? {
        let tokens = value.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return nil }
        guard let last = tokens.last else { return nil }

        let hasDigit = last.rangeOfCharacter(from: .decimalDigits) != nil
        guard hasDigit else { return nil }

        let base = tokens.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? nil : base
    }
}
