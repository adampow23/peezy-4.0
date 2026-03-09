import SwiftUI

struct CurrentAddress: View {
    @State private var selectedAddress = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Animation states
    @StateObject private var keyboard = KeyboardObserver()
    @State private var showContent = false

    private var needsUnitField: Bool {
        let type = assessmentData.currentDwellingType.lowercased()
        return type == "apartment" || type == "condo"
    }

    private var unitFieldSatisfied: Bool {
        !needsUnitField || !assessmentData.currentUnitNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canContinue: Bool {
        !selectedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && unitFieldSatisfied
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if !keyboard.isVisible {
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                        .frame(maxHeight: 40)
                }

                AddressAutocompleteView(
                    placeholder: "Street, City, State, ZIP",
                    onAddressSelected: { address in
                        selectedAddress = address
                    },
                    showUnitField: needsUnitField,
                    unitNumber: $assessmentData.currentUnitNumber
                )
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                Spacer(minLength: 0)
            }

            PeezyAssessmentButton("Continue", disabled: !canContinue) {
                guard canContinue else { return }
                assessmentData.currentAddress = selectedAddress
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, keyboard.isVisible ? 12 : 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .padding(.bottom, keyboard.isVisible ? keyboard.height : 0)
        .onAppear {
            selectedAddress = assessmentData.currentAddress
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    CurrentAddress()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
