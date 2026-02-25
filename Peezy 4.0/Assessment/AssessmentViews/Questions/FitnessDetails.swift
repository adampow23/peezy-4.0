import SwiftUI

struct FitnessDetails: View {
    @State private var details: [String: String] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @FocusState private var focusedKey: String?
    @State private var showContent = false

    private var fieldEntries: [(key: String, label: String, category: String)] {
        var entries: [(String, String, String)] = []
        for category in assessmentData.fitnessWellness {
            let count = assessmentData.fitnessCounts[category] ?? 1
            if count <= 1 {
                entries.append((category, category, category))
            } else {
                for i in 1...count {
                    let key = "\(category) \(i)"
                    entries.append((key, "\(category) \(i)", category))
                }
            }
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(fieldEntries, id: \.key) { entry in
                            SuggestiveTextField(
                                label: entry.label,
                                placeholder: placeholderText(for: entry.category),
                                text: binding(for: entry.key),
                                source: suggestionSource(for: entry.category),
                                isFocused: focusedKey == entry.key
                            )
                            .onTapGesture {
                                focusedKey = entry.key
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                Spacer(minLength: 0)
            }
            .onTapGesture { focusedKey = nil }

            PeezyAssessmentButton("Continue") {
                assessmentData.fitnessDetails = details
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            details = assessmentData.fitnessDetails
            if let first = fieldEntries.first {
                focusedKey = first.key
            }
            withAnimation { showContent = true }
        }
    }

    private func placeholderText(for category: String) -> String {
        switch category {
        case "Gym / CrossFit":
            return "e.g. Planet Fitness, Equinox, LA Fitness"
        case "Yoga / Pilates":
            return "e.g. CorePower, local studio name"
        case "Spin / Cycling":
            return "e.g. SoulCycle, Peloton studio"
        case "Massage / Spa":
            return "e.g. Massage Envy, Hand & Stone"
        case "Country Club / Golf":
            return "e.g. local country club, TopGolf"
        default:
            return "e.g. enter membership name"
        }
    }

    private func suggestionSource(for category: String) -> SuggestionSource {
        switch category {
        case "Gym / CrossFit":
            return .mapSearch(category: "gym crossfit", nearAddress: assessmentData.currentAddress)
        case "Yoga / Pilates":
            return .mapSearch(category: "yoga pilates studio", nearAddress: assessmentData.currentAddress)
        case "Spin / Cycling":
            return .mapSearch(category: "cycling spin studio", nearAddress: assessmentData.currentAddress)
        case "Massage / Spa":
            return .mapSearch(category: "spa massage", nearAddress: assessmentData.currentAddress)
        case "Country Club / Golf":
            return .mapSearch(category: "golf country club", nearAddress: assessmentData.currentAddress)
        default:
            return .local([])
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { details[key] ?? "" },
            set: { details[key] = $0 }
        )
    }
}

#Preview {
    let manager = AssessmentDataManager()
    manager.fitnessWellness = ["Gym / CrossFit", "Yoga / Pilates"]
    manager.fitnessCounts = ["Gym / CrossFit": 2, "Yoga / Pilates": 1]
    return FitnessDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
