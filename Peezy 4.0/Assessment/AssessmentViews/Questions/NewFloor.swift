import SwiftUI

struct NewFloor: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options: [(label: String, value: String)] = [
        ("1st Floor", "1"), ("2nd Floor", "2"), ("3rd Floor", "3"),
        ("4th-6th", "5"), ("7th+", "8")
    ]
    let iconMap: [String: String] = [
        "1st Floor": "1.circle.fill", "2nd Floor": "2.circle.fill", "3rd Floor": "3.circle.fill",
        "4th-6th": "arrow.up.circle.fill", "7th+": "arrow.up.to.line.circle.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "What floor?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element.label) { index, option in
                        SelectionTile(title: option.label, icon: iconMap[option.label], isSelected: selected == option.value, onTap: {
                            selected = option.value
                            assessmentData.newFloor = option.value
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
            selected = assessmentData.newFloor
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NewFloor()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  NewFloor.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

