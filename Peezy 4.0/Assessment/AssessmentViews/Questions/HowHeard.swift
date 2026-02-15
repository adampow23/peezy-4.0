import SwiftUI

struct HowHeard: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options = ["Social Media", "Friend/Family", "Search Engine", "Other"]
    let iconMap: [String: String] = [
        "Social Media": "iphone",
        "Friend/Family": "person.2.fill",
        "Search Engine": "magnifyingglass",
        "Other": "ellipsis.circle.fill"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "How'd you find us?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: iconMap[option], isSelected: selected == option, onTap: {
                            selected = option
                            assessmentData.howHeard = option
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
            selected = assessmentData.howHeard
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HowHeard()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
