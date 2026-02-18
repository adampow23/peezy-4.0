import SwiftUI

struct HasStorage: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Animation states
    @State private var showContent = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["Yes", "No"]

    let iconMap: [String: String] = [
        "Yes": "checkmark.circle.fill",
        "No": "xmark.circle.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "Do you have a storage unit with stuff that needs to move too?",
                showContent: showContent
            ) {
                // Options grid
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
                                assessmentData.hasStorage = option

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
        .background(InteractiveBackground())
        .onAppear {
            selected = assessmentData.hasStorage
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HasStorage()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
