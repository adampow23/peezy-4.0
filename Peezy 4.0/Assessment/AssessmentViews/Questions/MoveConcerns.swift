import SwiftUI

struct MoveConcerns: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "What are you hoping Peezy can help you with?"
    let subtext     : String? = nil
    let buttonText  = "Continue"
    let options: [(String, String)] = [
        ("Knowing what to do and when", "list.bullet.clipboard"),
        ("Finding time to actually pack", "shippingbox.fill"),
        ("Dealing with moving companies", "person.2.fill"),
        ("The fear of forgetting something important", "calendar"),
        ("Something else", "ellipsis")
    ]

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

    @State private var selected: Set<String> = []
    @State private var headerDone = false
    @State private var showControls = false
    @State private var isHero = false
    @State private var skipped = false

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {
                if isHero { Spacer() }

                // ── TEXT AREA ──
                VStack(spacing: 8) {
                    Group {
                        if skipped {
                            Text(header)
                        } else {
                            TypingText(
                                fullText: header,
                                speed: 0.04,
                                visibleColor: PeezyTheme.Colors.deepInk,
                                onComplete: {
                                    headerDone = true
                                    triggerMorph()
                                }
                            )
                        }
                    }
                    .font(.system(size: isHero ? 32 : 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(isHero ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, isHero ? 0 : 24)
                .padding(.bottom, isHero ? 0 : 32)
                .contentShape(Rectangle())
                .onTapGesture { skipToControls() }

                if isHero { Spacer() }
                if !isHero && showControls { Spacer(minLength: 16) }

                // ── BINARY TOGGLE GRID ──
                if showControls {
                    let columns = [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(options, id: \.0) { option in
                            let label = option.0
                            let icon = option.1
                            let isOn = selected.contains(label)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isOn {
                                        selected.remove(label)
                                    } else {
                                        selected.insert(label)
                                    }
                                }
                            } label: {
                                VStack(spacing: 10) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: icon)
                                            .font(.system(size: 24))
                                            .foregroundStyle(isOn ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)

                                        if isOn {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(PeezyTheme.Colors.lightBase)
                                                .offset(x: 12, y: -8)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }

                                    Text(label)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(isOn ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isOn ? PeezyTheme.Colors.deepInk : Color.white.opacity(0.001))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            isOn ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.12),
                                            lineWidth: isOn ? 2 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isHero && showControls { Spacer(minLength: 32) }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText) {
                        data.moveConcerns = Array(selected)
                        coordinator.goToNext()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selected = Set(data.moveConcerns)
        }
    }

    // ── MORPH LOGIC ──
    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }

    private func performMorph() {
        withAnimation(.easeOut(duration: 0.35)) {
            showControls = true
        }
    }

    private func skipToControls() {
        guard !showControls else { return }
        skipped = true
        headerDone = true
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = true
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    MoveConcerns()
        .environmentObject(dm)
        .environmentObject(AssessmentCoordinator(dataManager: dm))
}
