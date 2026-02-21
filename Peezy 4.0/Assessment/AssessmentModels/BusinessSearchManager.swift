import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class BusinessSearchManager {

    // MARK: - Output

    var suggestions: [String] = []

    // MARK: - Private

    private var debounceTask: Task<Void, Never>?
    private var cachedCoordinate: CLLocationCoordinate2D?
    private var cachedAddress: String = ""

    // US geographic center — fallback when geocoding fails
    private let usCenterCoordinate = CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)

    // MARK: - Public API

    /// Geocode the given address once and cache the result.
    /// Call this on .onAppear in the parent view.
    func primeLocation(address: String) async {
        guard !address.isEmpty, address != cachedAddress else { return }
        cachedAddress = address
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            if let location = placemarks.first?.location {
                cachedCoordinate = location.coordinate
            }
        } catch {
            cachedCoordinate = nil // will fall back to US center
        }
    }

    /// Trigger a debounced search. Pass empty string to clear suggestions.
    func search(query: String, category: String) {
        debounceTask?.cancel()
        guard query.count >= 2 else {
            suggestions = []
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
            guard !Task.isCancelled else { return }
            await performSearch(query: query, category: category)
        }
    }

    func clearSuggestions() {
        debounceTask?.cancel()
        suggestions = []
    }

    // MARK: - Private

    private func performSearch(query: String, category: String) async {
        let naturalQuery = "\(query) \(category)"
        let coordinate = cachedCoordinate ?? usCenterCoordinate
        let spanDelta: CLLocationDegrees = cachedCoordinate != nil ? 0.5 : 60.0

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = naturalQuery
        request.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            // Deduplicate by name, take first 5
            var seen = Set<String>()
            var names: [String] = []
            for item in response.mapItems {
                guard let name = item.name, !name.isEmpty else { continue }
                if seen.insert(name).inserted {
                    names.append(name)
                    if names.count == 5 { break }
                }
            }
            suggestions = names
        } catch {
            suggestions = []
        }
    }
}
