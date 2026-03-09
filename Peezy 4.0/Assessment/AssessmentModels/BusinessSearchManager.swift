import Foundation
import MapKit
import Observation

@Observable
final class BusinessSearchManager: NSObject, MKLocalSearchCompleterDelegate {

    // MARK: - Output

    var suggestions: [String] = []

    // MARK: - Private

    private let completer = MKLocalSearchCompleter()
    private var cachedCoordinate: CLLocationCoordinate2D?
    private var cachedAddress: String = ""
    private let usCenterCoordinate = CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
    }

    // MARK: - Public API

    func primeLocation(address: String) async {
        guard !address.isEmpty, address != cachedAddress else { return }
        cachedAddress = address
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            if let location = placemarks.first?.location {
                cachedCoordinate = location.coordinate
                updateCompleterRegion()
            }
        } catch {
            cachedCoordinate = nil
            updateCompleterRegion()
        }
    }

    func search(query: String, category: String) {
        guard query.count >= 2 else {
            clearSuggestions()
            return
        }
        let naturalQuery = category.isEmpty ? query : "\(query) \(category)"
        completer.queryFragment = naturalQuery
    }

    func clearSuggestions() {
        completer.queryFragment = ""
        suggestions = []
    }

    // MARK: - Private Helpers

    private func updateCompleterRegion() {
        let coordinate = cachedCoordinate ?? usCenterCoordinate
        let spanDelta: CLLocationDegrees = cachedCoordinate != nil ? 0.5 : 60.0
        completer.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var seen = Set<String>()
        var names: [String] = []
        for result in completer.results {
            let name = result.title
            if !name.isEmpty, seen.insert(name).inserted {
                names.append(name)
                if names.count == 5 { break }
            }
        }
        self.suggestions = names
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        self.suggestions = []
    }
}
