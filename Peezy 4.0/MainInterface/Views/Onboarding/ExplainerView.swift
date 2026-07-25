import SwiftUI

/// Five-card tap-through shown once, post-auth, pre-assessment.
/// Copy is locked per peezy-v1-architecture.md §9. Do not edit strings.
struct ExplainerView: View {
    let onFinished: () -> Void
    @State private var index = 0

    private let cards: [ExplainerCard] = [
        .init(
            kicker: "LET'S BE HONEST",
            title: "Moving is a nightmare.",
            body: "You've done it before. The endless list, the calls, the things you find out too late. Nobody enjoys this."
        ),
        .init(
            kicker: "HOW PEEZY WORKS",
            title: "One thing at a time.",
            body: "Peezy tells you exactly what to do and when. No giant checklist staring at you. Open the app, do the thing, done."
        ),
        .init(
            kicker: "ON PURPOSE",
            title: "No feeds. No badges. No fluff.",
            body: "Peezy is plain by design. Every screen exists to get you through this move — not to keep you scrolling."
        ),
        .init(
            kicker: "THE REAL DIFFERENCE",
            title: "We do the parts you hate.",
            body: "Internet setup. Finding movers you can trust. Changing your address everywhere. Peezy handles it — you just approve."
        ),
        .init(
            kicker: "FIRST THINGS FIRST",
            title: "A few questions.",
            body: "They're how Peezy knows what's coming for your move — not someone else's. The more you tell us, the more we can take off your plate."
        )
    ]

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ExplainerProgressDots(count: cards.count, index: index)
                    .padding(.top, 24)
                    .accessibilityIdentifier("explainer.progress")
                Spacer()
                ExplainerCardView(card: cards[index])
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .accessibilityIdentifier("explainer.card.\(index)")
                Spacer()
                Button(action: advance) {
                    Text(index == cards.count - 1 ? "Let's go" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PeezyTheme.Colors.deepInk)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .accessibilityIdentifier("explainer.next")
            }
        }
        .onTapGesture(perform: advance)
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func advance() {
        PeezyHaptics.light()
        if index < cards.count - 1 {
            index += 1
        } else {
            UserDefaults.standard.set(true, forKey: "peezy.explainer.seen")
            onFinished()
        }
    }
}

struct ExplainerCard: Identifiable {
    let id = UUID()
    let kicker: String
    let title: String
    let body: String
}

private struct ExplainerCardView: View {
    let card: ExplainerCard
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(card.kicker)
                .font(.caption.weight(.bold))
                .kerning(1.5)
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
            Text(card.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.body)
                .font(.body)
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }
}

private struct ExplainerProgressDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.15))
                    .frame(width: i == index ? 24 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
    }
}
