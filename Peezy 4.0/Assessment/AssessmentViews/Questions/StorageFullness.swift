import SwiftUI

struct StorageFullness: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Animation states
    @State private var showContent = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["1/4 Full", "1/2 Full", "3/4 Full", "Full"]

    let iconMap: [String: String] = [
        "1/4 Full": "square.dashed",
        "1/2 Full": "square.split.2x1",
        "3/4 Full": "square.split.2x2",
        "Full": "square.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "How full is it?",
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
                                assessmentData.storageFullness = option

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
            selected = assessmentData.storageFullness
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    StorageFullness()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
