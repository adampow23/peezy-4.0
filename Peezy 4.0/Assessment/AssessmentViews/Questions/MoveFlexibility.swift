import SwiftUI

struct MoveFlexibility: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    // Options match coordinator tile label contract
    let options = ["Firm Dates", "Some Flexibility", "Very Flexible"]
    
    let iconMap: [String: String] = [
        "Firm Dates": "lock.fill",
        "Some Flexibility": "arrow.left.arrow.right",
        "Very Flexible": "wind"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area with equal spacing
            AssessmentContentArea(
                questionText: "Any wiggle room?",
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
                                assessmentData.moveFlexibility = option
                                
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
            selected = assessmentData.moveFlexibility
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    MoveFlexibility()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  MoveFlexibility.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

