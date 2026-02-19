import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class AddressSearchManager: NSObject {

    // MARK: - Published State

    var queryFragment: String = "" {
        didSet {
            if queryFragment != oldValue {
                updateCompleter()
            }
        }
    }

    var suggestions: [MKLocalSearchCompletion] = []
    var selectedAddress: String = ""

    // MARK: - Private

    private let completer: MKLocalSearchCompleter

    // MARK: - Init

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Bias results toward the US
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
        )
    }

    // MARK: - Search

    private func updateCompleter() {
        if queryFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            suggestions = []
            completer.cancel()
        } else {
            completer.queryFragment = queryFragment
        }
    }

    func selectSuggestion(_ completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            if let item = response.mapItems.first {
                selectedAddress = formatAddress(from: item.placemark)
                queryFragment = selectedAddress
                suggestions = []
            }
        } catch {
            // Fallback: compose from the completion strings directly
            let combined = [completion.title, completion.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            selectedAddress = combined
            queryFragment = combined
            suggestions = []
        }
    }

    func clearSelection() {
        selectedAddress = ""
        queryFragment = ""
        suggestions = []
    }

    // MARK: - Helpers

    private func formatAddress(from placemark: MKPlacemark) -> String {
        var parts: [String] = []

        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            parts.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            parts.append(thoroughfare)
        }

        if let locality = placemark.locality {
            parts.append(locality)
        }

        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }

        if let postalCode = placemark.postalCode {
            parts.append(postalCode)
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension AddressSearchManager: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(5))
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}
