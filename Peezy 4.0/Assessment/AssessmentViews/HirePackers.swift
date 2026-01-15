import SwiftUI

struct HirePackers: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options = ["Hire Packers", "Pack Myself"]
    
    let iconMap: [String: String] = [
        "Hire Packers": "shippingbox.fill",
        "Pack Myself": "hand.raised.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: AssessmentStep.HirePackers.stepNumber,
                totalSteps: AssessmentStep.HirePackers.totalSteps,
                onBack: {
                    coordinator.goBack()
                },
                onCompletion: {
                    // Not used for intermediate steps
                }
            )
            
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "Will you hire packers?",
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
                                assessmentData.HirePackers = option
                                assessmentData.saveData()
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lightHaptic.impactOccurred()
                                    coordinator.goToNext(from: .HirePackers)
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
        .navigationBarBackButtonHidden(true)
        .background(Color(.systemBackground))
        .onAppear {
            selected = assessmentData.HirePackers
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NavigationStack {
        HirePackers()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))
    }
}
