// Peezy 4.0/Assessment/AssessmentViews/Questions/AnyKids.swift
import SwiftUI

struct AnyKids: View {
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["Yes", "No"]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: nil, isSelected: assessmentData.anyKids == option, onTap: {
                            assessmentData.anyKids = option
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
        .onAppear {
            withAnimation { showContent = true }
        }
    }
}
