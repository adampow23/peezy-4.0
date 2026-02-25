import SwiftUI

struct TruckRental: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Animation states
    @State private var showContent = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["Yes, get me quotes", "No, I'm covered"]

    let iconMap: [String: String] = [
        "Yes, get me quotes": "truck.box.fill",
        "No, I'm covered": "checkmark.circle.fill"
    ]

    let valueMap: [String: String] = [
        "Yes, get me quotes": "yes",
        "No, I'm covered": "no"
    ]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(
                            title: option,
                            icon: iconMap[option],
                            isSelected: selected == option,
                            onTap: {
                                selected = option
                                assessmentData.truckRental = valueMap[option] ?? "no"

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lightHaptic.impactOccurred()
                                    coordinator.goToNext()
                                }
                            }
                        )
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 30)
                        .animation(.easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.1), value: showContent)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            // Reverse-map stored value back to display label
            if let label = valueMap.first(where: { $0.value == assessmentData.truckRental })?.key {
                selected = label
            }
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    TruckRental()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
