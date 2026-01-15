import SwiftUI

struct WhosMoving: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    // Animation states
    @State private var showContent = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["Just Me", "Partner", "Family", "Roommate"]

    let iconMap: [String: String] = [
        "Just Me": "person.fill",
        "Partner": "heart.fill",
        "Family": "figure.2.and.child.holdinghands",
        "Roommate": "person.3.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: AssessmentStep.WhosMoving.stepNumber,
                totalSteps: AssessmentStep.WhosMoving.totalSteps,
                onBack: {
                    coordinator.goBack()
                },
                onCompletion: {
                    // Not used for intermediate steps
                }
            )

            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "Who's moving with you?",
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
                                assessmentData.WhosMoving = option
                                assessmentData.saveData()

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lightHaptic.impactOccurred()
                                    coordinator.goToNext(from: .WhosMoving)
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
            selected = assessmentData.WhosMoving
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NavigationStack {
        WhosMoving()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))
    }
}//
//  WhosMoving.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 1/12/26.
//

