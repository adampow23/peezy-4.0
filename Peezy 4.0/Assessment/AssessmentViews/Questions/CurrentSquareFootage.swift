import SwiftUI

struct CurrentSquareFootage: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = [
        "Under 500 sq ft",
        "500–800 sq ft",
        "800–1,200 sq ft",
        "1,200–1,800 sq ft",
        "1,800+ sq ft"
    ]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(
                questionText: "Roughly how big is the place?",
                showContent: showContent
            ) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(
                            title: option,
                            icon: nil,
                            isSelected: selected == option,
                            onTap: {
                                selected = option
                                assessmentData.currentSquareFootage = option

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
            selected = assessmentData.currentSquareFootage
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    CurrentSquareFootage()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
