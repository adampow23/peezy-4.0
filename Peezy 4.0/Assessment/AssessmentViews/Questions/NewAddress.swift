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
    var morphedFontSize: CGFloat = 24
    var morphedSubtextSize: CGFloat = 14
    var morphTopPad: CGFloat = 24
    var morphBottomPad: CGFloat = 40
    var textSidePad: CGFloat = 24
    var buttonPadH: CGFloat = 24
    var buttonPadBottom: CGFloat = 24

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    @State private var showControls = false
    @State private var selectedAddress = ""
    // Escape hatch (Spec 02 Phase B): no address yet — persist the pending
    // flag and an optional coarse city/state/ZIP for a rough geocode.
    @State private var noAddressYet = false
    @State private var coarseLocation = ""

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Copy LOCKED per spec 02 Phase B.
    private let pendingCopy = "No address yet? No problem — most people start planning before they've signed. We'll build your plan and you can drop it in later."

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                // ── TEXT AREA ──
                VStack(spacing: 8) {
                    Text(header)
                        .font(.system(size: morphedFontSize, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let sub = subtext {
                        Text(sub)
                            .font(.system(size: morphedSubtextSize, weight: .medium))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, morphTopPad)
                .padding(.bottom, morphBottomPad)

                if showControls { Spacer() }

                // ── ADDRESS AUTOCOMPLETE / PENDING PATH ──
                if showControls {
                    if noAddressYet {
                        pendingSection
                            .transition(.opacity)
                    } else {
                        AddressAutocompleteView(
                            placeholder: placeholder,
                            onAddressSelected: { address in
                                selectedAddress = address
                            },
                            showUnitField: data.newDwellingType == "Apartment" || data.newDwellingType == "Condo",
                            unitNumber: $data.newUnitNumber
                        )
                        .transition(.opacity)
                    }
                }

                if showControls { Spacer() }

                // ── ESCAPE HATCH TOGGLE ──
                if showControls {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { noAddressYet.toggle() }
                    } label: {
                        Text(noAddressYet ? "Actually, I have the address" : "I don't have it yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .underline()
                    }
                    .accessibilityIdentifier("assessment.newAddress.noAddressYet")
                    .padding(.bottom, 12)
                }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText, disabled: noAddressYet ? false : selectedAddress.isEmpty) {
                        if noAddressYet {
                            data.newAddress = coarseLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                            data.newAddressPending = true
                        } else {
                            data.newAddress = selectedAddress
                            data.newAddressPending = false
                        }
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

    // ── PENDING SECTION ─────────────────────────────────────────

    private var pendingSection: some View {
        VStack(spacing: 16) {
            Text(pendingCopy)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.7))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("assessment.newAddress.pendingCopy")

            TextField(
                "",
                text: $coarseLocation,
                prompt: Text("City, state, or ZIP (optional)").foregroundColor(Color.gray.opacity(0.5))
            )
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(PeezyTheme.Colors.deepInk)
            .tint(PeezyTheme.Colors.accentBlue)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .accessibilityIdentifier("assessment.newAddress.coarseLocation")
        }
        .padding(.horizontal, 24)
    }

    // ── MORPH LOGIC ─────────────────────────────────────────────

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.3)) {
                showControls = true
            }
        }
    }
}

#if DEBUG
#Preview {
    let dm = AssessmentDataManager()
    NewAddress().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
#endif
