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
            completer.queryFragment = query
        }
    }

    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching: Bool = false

    private let completer: MKLocalSearchCompleter

    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
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

            let coordinate: CLLocationCoordinate2D
            if #available(macOS 26.0, *) {
                coordinate = item.location.coordinate
            } else {
                coordinate = item.placemark.coordinate
            }
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
}
