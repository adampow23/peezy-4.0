import SwiftUI

struct NewAddress: View {
    @State private var selectedAddress = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @StateObject private var keyboard = KeyboardObserver()
    @State private var showContent = false

    private var needsUnitField: Bool {
        let type = assessmentData.newDwellingType.lowercased()
        return type == "apartment" || type == "condo"
    }

    private var unitFieldSatisfied: Bool {
        !needsUnitField || !assessmentData.newUnitNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canContinue: Bool {
        !selectedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && unitFieldSatisfied
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 20)

                AddressAutocompleteView(
                    placeholder: "Street, City, State, ZIP",
                    onAddressSelected: { address in
                        selectedAddress = address
                    },
                    showUnitField: needsUnitField,
                    unitNumber: $assessmentData.newUnitNumber
                )
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                Spacer(minLength: 0)
            }

            PeezyAssessmentButton("Continue", disabled: !canContinue) {
                guard canContinue else { return }
                assessmentData.newAddress = selectedAddress
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
            selectedAddress = assessmentData.newAddress
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NewAddress()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
