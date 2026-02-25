import SwiftUI

struct PackingPreference: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options: [(label: String, value: String, icon: String)] = [
        ("No thanks", "none", "hand.raised.fill"),
        ("Yes, full service", "full", "shippingbox.fill"),
        ("Yes, kitchen only", "kitchen", "fork.knife"),
        ("Yes, both options", "both", "list.clipboard.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                        SelectionTile(
                            title: option.label,
                            icon: option.icon,
                            isSelected: selected == option.value,
                            onTap: {
                                selected = option.value
                                assessmentData.packingPreference = option.value
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
            selected = assessmentData.packingPreference
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    PackingPreference()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
