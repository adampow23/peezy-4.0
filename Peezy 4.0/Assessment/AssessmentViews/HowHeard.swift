import SwiftUI

struct HowHeard: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options = ["Google/Search", "Social Media", "Friend/Family", "Moving Company", "Other"]
    
    let iconMap: [String: String] = [
        "Google/Search": "magnifyingglass",
        "Social Media": "at.circle.fill",
        "Friend/Family": "person.2.fill",
        "Moving Company": "truck.box.fill",
        "Other": "ellipsis"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: AssessmentStep.HowHeard.stepNumber,
                totalSteps: AssessmentStep.HowHeard.totalSteps,
                onBack: {
                    coordinator.goBack()
                },
                onCompletion: {
                    // Not used for intermediate steps
                }
            )
            
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "How did you hear about Peezy?",
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
                                assessmentData.HowHeard = option
                                assessmentData.saveData()
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lightHaptic.impactOccurred()
                                    coordinator.goToNext(from: .HowHeard)
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
            selected = assessmentData.HowHeard
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NavigationStack {
        HowHeard()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))
    }
}
