import SwiftUI

/// One-shot, Peezy-voiced offer shown on the idle camera view after camera
/// permission is granted. Mirrors the push primer pattern: in-app card first,
/// system dialogs only after an affirmative tap.
struct NarrationOfferCard: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    private let deepInk = PeezyTheme.Colors.deepInk

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Want an even better scan?")
                .font(PeezyTheme.Typography.body.weight(.semibold))
                .foregroundStyle(deepInk)

            Text("Talk while you scan — what's staying, what's full, what's not yours. Peezy listens on your phone and sends only the words, never your voice. Not required, but your estimate gets noticeably sharper.")
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(deepInk.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    declineButton
                    acceptButton
                }

                VStack(spacing: 10) {
                    declineButton
                    acceptButton
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory.narration.offer")
    }

    private var declineButton: some View {
        Button(action: onDecline) {
            Text("Scan without it")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(deepInk)
        .accessibilityIdentifier("inventory.narration.decline")
    }

    private var acceptButton: some View {
        Button(action: onAccept) {
            Text("Turn it on")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(deepInk)
        .accessibilityIdentifier("inventory.narration.accept")
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .fill(.regularMaterial)

            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .fill(Color.white.opacity(0.15))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        NarrationOfferCard(onAccept: {}, onDecline: {})
    }
}
#endif
