import SwiftUI

struct HealthcareProviders: View {
    @State private var selectedCategories: Set<String> = []
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
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Who needs your new info?")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: geo.size.width * 0.6, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Tap all that apply")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(x: showContent ? 0 : -20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        ForEach(Array(categories.enumerated()), id: \.element.0) { index, category in
                            MultiSelectTile(
                                title: category.0,
                                icon: category.1,
                                isSelected: selectedCategories.contains(category.0),
                                onTap: {
                                    if selectedCategories.contains(category.0) {
                                        selectedCategories.remove(category.0)
                                    } else {
                                        selectedCategories.insert(category.0)
                                    }
                                }
                            )
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 30)
                            .animation(.easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.1), value: showContent)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 0)
                }
            }

            PeezyAssessmentButton(selectedCategories.isEmpty ? "None — Skip" : "Continue") {
                assessmentData.healthcareProviders = Array(selectedCategories)
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .background(InteractiveBackground())
        .onAppear {
            selectedCategories = Set(assessmentData.healthcareProviders)
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
