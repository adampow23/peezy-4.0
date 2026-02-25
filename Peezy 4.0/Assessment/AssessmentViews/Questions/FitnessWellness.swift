import SwiftUI

struct FitnessWellness: View {
    @State private var categoryCounts: [String: Int] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false

    let categories = [
        ("Gym / CrossFit", "dumbbell.fill"),
        ("Yoga / Pilates", "figure.mind.and.body"),
        ("Spin / Cycling", "figure.indoor.cycle"),
        ("Massage / Spa", "hand.raised.fill"),
        ("Country Club / Golf", "figure.golf")
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    ForEach(Array(categories.enumerated()), id: \.element.0) { index, category in
                        MultiSelectTile(
                            title: category.0,
                            icon: category.1,
                            isSelected: (categoryCounts[category.0] ?? 0) > 0,
                            onTap: {
                                categoryCounts[category.0, default: 0] += 1
                            }
                        )
                        .overlay(alignment: .topTrailing) {
                            if let count = categoryCounts[category.0], count > 0 {
                                Text("\(count)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.cyan))
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 30)
                        .animation(.easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.1), value: showContent)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }

            PeezyAssessmentButton(categoryCounts.isEmpty ? "None — Skip" : "Continue") {
                assessmentData.fitnessWellness = Array(categoryCounts.keys)
                assessmentData.fitnessCounts = categoryCounts
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            categoryCounts = assessmentData.fitnessCounts
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    FitnessWellness()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
