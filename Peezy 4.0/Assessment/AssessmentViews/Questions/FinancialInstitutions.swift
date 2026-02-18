import SwiftUI

struct FinancialInstitutions: View {
    @State private var selectedCategories: Set<String> = []
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false

    let categories = [
        ("Bank Account", "building.columns.fill"),
        ("Credit Card", "creditcard.fill"),
        ("Credit Union", "building.2.fill"),
        ("Investment Account", "chart.line.uptrend.xyaxis"),
        ("Retirement Account", "banknote.fill"),
        ("Student Loans", "graduationcap.fill"),
        ("Insurance", "shield.lefthalf.filled")
    ]

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Financial accounts?")
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
                assessmentData.financialInstitutions = Array(selectedCategories)
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
            selectedCategories = Set(assessmentData.financialInstitutions)
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    FinancialInstitutions()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
