import SwiftUI

struct HireMovers: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    // Options match coordinator tile label contract
    let options = ["I'd like quotes", "I'll handle it myself", "Not Sure", "Get Me Quotes"]
    let iconMap: [String: String] = [
        "I'd like quotes": "truck.box.fill",
        "I'll handle it myself": "figure.walk",
        "Not Sure": "questionmark.circle.fill",
        "Get Me Quotes": "doc.text.magnifyingglass"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "Professional movers?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: iconMap[option], isSelected: selected == option, onTap: {
                            selected = option
                            assessmentData.hireMovers = option
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
            selected = assessmentData.hireMovers
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HireMovers()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
