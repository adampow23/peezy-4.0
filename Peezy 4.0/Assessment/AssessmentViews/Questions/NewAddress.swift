import SwiftUI

struct NewAddress: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "What's the new address?"
    let subtext     : String? = "I'll use this to get utilities, internet, and everything else set up before you walk in."
    let placeholder = "Start typing your address"
    let buttonText  = "Continue"

    // ═══════════════════════════════════════════
    //  CONTROL BOARD
    // ═══════════════════════════════════════════
    var heroFontSize: CGFloat = 32
    var heroSubtextSize: CGFloat = 16
    var morphedFontSize: CGFloat = 22
    var morphedSubtextSize: CGFloat = 14
    var morphTopPad: CGFloat = 24
    var morphBottomPad: CGFloat = 40
    var textSidePad: CGFloat = 24
    var buttonPadH: CGFloat = 24
    var buttonPadBottom: CGFloat = 32
    var morphDelay: Double = 0.4

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    @State private var isHero = false
    @State private var showControls = false
    @State private var selectedAddress = ""

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                if isHero { Spacer() }

                // ── TEXT AREA ──
                VStack(spacing: 8) {
                    Text(header)
                        .font(.system(size: isHero ? heroFontSize : morphedFontSize, weight: .semibold))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineSpacing(4)
                        .multilineTextAlignment(isHero ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)

                    if let sub = subtext {
                        Text(sub)
                            .font(.system(size: isHero ? heroSubtextSize : morphedSubtextSize))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(3)
                            .multilineTextAlignment(isHero ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, isHero ? 0 : morphTopPad)
                .padding(.bottom, isHero ? 0 : morphBottomPad)

                if isHero { Spacer() }

                if !isHero && showControls { Spacer() }

                // ── ADDRESS AUTOCOMPLETE ──
                if showControls {
                    AddressAutocompleteView(
                        placeholder: placeholder,
                        onAddressSelected: { address in
                            selectedAddress = address
                        },
                        showUnitField: data.newDwellingType == "Apartment" || data.newDwellingType == "Condo",
                        unitNumber: $data.newUnitNumber
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isHero && showControls { Spacer() }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText, disabled: selectedAddress.isEmpty) {
                        data.newAddress = selectedAddress
                        coordinator.goToNext()
                    }
                    .padding(.horizontal, buttonPadH)
                    .padding(.bottom, buttonPadBottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedAddress = data.newAddress
            triggerMorph()
        }
    }

    // ── MORPH LOGIC ─────────────────────────────────────────────

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    NewAddress().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
