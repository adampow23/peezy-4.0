import SwiftUI

struct CurrentAddress: View {
    @State private var selectedAddress = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Animation states
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
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        Text("Current address?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: geo.size.width * 0.6, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(x: showContent ? 0 : -20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                    Spacer(minLength: 0)

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
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)

                    Spacer(minLength: 0)
                }
            }

            PeezyAssessmentButton("Continue", disabled: !canContinue) {
                guard canContinue else { return }
                assessmentData.currentAddress = selectedAddress
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .background(InteractiveBackground())
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
