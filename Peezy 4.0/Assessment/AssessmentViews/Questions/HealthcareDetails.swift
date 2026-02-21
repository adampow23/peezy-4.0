import SwiftUI

struct HealthcareDetails: View {
    @State private var details: [String: String] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @FocusState private var focusedCategory: String?
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        Text("Which ones specifically?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: geo.size.width * 0.6, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(x: showContent ? 0 : -20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                    Spacer(minLength: 0)

                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(assessmentData.healthcareProviders, id: \.self) { category in
                                SuggestiveTextField(
                                    label: category,
                                    placeholder: "e.g. Dr. Smith, Aetna...",
                                    text: binding(for: category),
                                    source: suggestionSource(for: category),
                                    isFocused: focusedCategory == category
                                )
                                .onTapGesture {
                                    focusedCategory = category
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)

                    Spacer(minLength: 0)
                }
            }
            .onTapGesture { focusedCategory = nil }

            PeezyAssessmentButton("Continue") {
                assessmentData.healthcareDetails = details
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
            details = assessmentData.healthcareDetails
            if let first = assessmentData.healthcareProviders.first {
                focusedCategory = first
            }
            withAnimation { showContent = true }
        }
    }

    private func suggestionSource(for category: String) -> SuggestionSource {
        switch category {
        case "Doctor":
            return .mapSearch(category: "doctor", nearAddress: assessmentData.currentAddress)
        case "Dentist":
            return .mapSearch(category: "dentist", nearAddress: assessmentData.currentAddress)
        case "Specialists":
            return .mapSearch(category: "medical specialist", nearAddress: assessmentData.currentAddress)
        case "Pharmacy":
            return .mapSearch(category: "pharmacy", nearAddress: assessmentData.currentAddress)
        default:
            return .local([])
        }
    }

    private func binding(for category: String) -> Binding<String> {
        Binding(
            get: { details[category] ?? "" },
            set: { details[category] = $0 }
        )
    }
}

#Preview {
    let manager = AssessmentDataManager()
    manager.healthcareProviders = ["Doctor", "Dentist"]
    return HealthcareDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
