import SwiftUI

/// Transient overlays rendered on top of the Tasks tab: confetti + inventory-reset spinner.
struct TasksOverlayLayer: View {
    @State private var confetti = ConfettiBus.shared
    let isResetting: Bool

    var body: some View {
        ZStack {
            if confetti.isFiring {
                ConfettiView(
                    isActive: Binding(
                        get: { confetti.isFiring },
                        set: { _ in }
                    ),
                    intensity: .high
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }

            if isResetting {
                ResetInventoryOverlay()
            }
        }
    }
}
