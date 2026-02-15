import SwiftUI

struct CurrentElevatorAccess: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    // Options match coordinator tile label contract
    let options = ["No Elevator", "Shared Elevator", "Reservable Elevator"]
    
    let iconMap: [String: String] = [
        "No Elevator": "figure.stairs",
        "Shared Elevator": "arrow.up.arrow.down.circle.fill",
        "Reservable Elevator": "checkmark.circle.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(
                questionText: "Elevator situation?",
                showContent: showContent
            ) {
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
                                assessmentData.currentElevatorAccess = option
                                
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
            selected = assessmentData.currentElevatorAccess
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    CurrentElevatorAccess()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
