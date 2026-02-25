import SwiftUI

struct HealthcareProviders: View {
    @State private var categoryCounts: [String: Int] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false

    let categories = [
        ("Doctor", "stethoscope"),
        ("Dentist", "mouth.fill"),
        ("Specialists", "cross.case.fill"),
        ("Pharmacy", "pills.fill")
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
                assessmentData.healthcareProviders = Array(categoryCounts.keys)
                assessmentData.healthcareCounts = categoryCounts
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            categoryCounts = assessmentData.healthcareCounts
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HealthcareProviders()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
