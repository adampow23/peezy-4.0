import SwiftUI

struct NewDwellingType: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    var options: [String] {
        assessmentData.newRentOrOwn == "Own"
            ? ["House", "Condo", "Townhouse"]
            : ["House", "Apartment", "Condo", "Townhouse"]
    }

    let iconMap: [String: String] = [
        "House": "house.fill",
        "Apartment": "building.2.fill",
        "Condo": "building.fill",
        "Townhouse": "house.and.flag.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "Type of place?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: iconMap[option], isSelected: selected == option, onTap: {
                            selected = option
                            assessmentData.newDwellingType = option
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
            if assessmentData.newRentOrOwn == "Own" && assessmentData.newDwellingType == "Apartment" {
                assessmentData.newDwellingType = ""
            }
            selected = assessmentData.newDwellingType
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NewDwellingType()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
