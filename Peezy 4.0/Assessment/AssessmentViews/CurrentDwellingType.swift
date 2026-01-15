import SwiftUI

struct CurrentDwellingType: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options = ["House", "Apartment", "Condo", "Townhouse"]
    
    let iconMap: [String: String] = [
        "House": "house.fill",
        "Apartment": "building.2.fill",
        "Condo": "building.fill",
        "Townhouse": "house.and.flag.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: AssessmentStep.CurrentDwellingType.stepNumber,
                totalSteps: AssessmentStep.CurrentDwellingType.totalSteps,
                onBack: {
                    coordinator.goBack()
                },
                onCompletion: {
                    // Not used for intermediate steps
                }
            )
            
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "What type of home are you moving from?",
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
                                assessmentData.CurrentDwellingType = option
                                assessmentData.saveData()
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lightHaptic.impactOccurred()
                                    coordinator.goToNext(from: .CurrentDwellingType)
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
            selected = assessmentData.CurrentDwellingType
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NavigationStack {
        CurrentDwellingType()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))
    }
}
