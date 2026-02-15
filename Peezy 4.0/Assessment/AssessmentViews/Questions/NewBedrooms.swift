import SwiftUI

struct NewBedrooms: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options: [(label: String, value: String)] = [
        ("Studio", "Studio"), ("1 Bedroom", "1"), ("2 Bedrooms", "2"),
        ("3 Bedrooms", "3"), ("4 Bedrooms", "4"), ("5+", "5+")
    ]
    let iconMap: [String: String] = [
        "Studio": "square.fill", "1 Bedroom": "1.circle.fill", "2 Bedrooms": "2.circle.fill",
        "3 Bedrooms": "3.circle.fill", "4 Bedrooms": "4.circle.fill", "5+": "plus.circle.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "How many bedrooms?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element.label) { index, option in
                        SelectionTile(title: option.label, icon: iconMap[option.label], isSelected: selected == option.value, onTap: {
                            selected = option.value
                            assessmentData.newBedrooms = option.value
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
            selected = assessmentData.newBedrooms
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NewBedrooms()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  NewBedrooms.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

