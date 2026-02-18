import SwiftUI

struct NewFloorAccess: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["First Floor", "Stairs", "Elevator", "Reservable Elevator"]
    let iconMap: [String: String] = [
        "First Floor": "1.circle.fill",
        "Stairs": "figure.stairs",
        "Elevator": "arrow.up.arrow.down.circle.fill",
        "Reservable Elevator": "checkmark.circle.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "How will you access your floor?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: iconMap[option], isSelected: selected == option, onTap: {
                            selected = option
                            assessmentData.newFloorAccess = option
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                lightHaptic.impactOccurred()
                                coordinator.goToNext()
                            }
                        })
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
            selected = assessmentData.newFloorAccess
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NewFloorAccess()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
