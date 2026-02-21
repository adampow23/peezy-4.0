import SwiftUI

struct HireCleaners: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    // Options match coordinator tile label contract
    let options = ["Get me quotes", "I'll handle it myself"]

    let iconMap: [String: String] = [
        "Get me quotes": "doc.text.magnifyingglass",
        "I'll handle it myself": "hand.raised.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "Would you like quotes for a professional move-out cleaning, or are you going to handle that yourself?",
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
                                assessmentData.hireCleaners = option
                                
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
            selected = assessmentData.hireCleaners
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HireCleaners()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
