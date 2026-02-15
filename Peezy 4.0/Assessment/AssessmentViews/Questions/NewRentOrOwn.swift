import SwiftUI

struct NewRentOrOwn: View {
    @State private var selected = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    let options = ["Rent", "Own"]
    let iconMap: [String: String] = ["Rent": "key.fill", "Own": "house.fill"]
    
    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "Rent or own?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: iconMap[option], isSelected: selected == option, onTap: {
                            selected = option
                            assessmentData.newRentOrOwn = option
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
            selected = assessmentData.newRentOrOwn
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NewRentOrOwn()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
