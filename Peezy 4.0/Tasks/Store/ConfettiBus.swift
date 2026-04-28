import Observation
import SwiftUI

@Observable
@MainActor
final class ConfettiBus {
    static let shared = ConfettiBus()
    private init() {}

    var isFiring: Bool = false

    func fire() {
        guard !isFiring else { return }
        isFiring = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.isFiring = false
        }
    }
}
