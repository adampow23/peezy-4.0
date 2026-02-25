import SwiftUI

struct HealthcareDetails: View {
    @State private var details: [String: String] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @FocusState private var focusedKey: String?
    @State private var showContent = false

    private var fieldEntries: [(key: String, label: String, category: String)] {
        var entries: [(String, String, String)] = []
        for category in assessmentData.healthcareProviders {
            let count = assessmentData.healthcareCounts[category] ?? 1
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
                assessmentData.healthcareDetails = details
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            details = assessmentData.healthcareDetails
            if let first = fieldEntries.first {
                focusedKey = first.key
            }
            withAnimation { showContent = true }
        }
    }

    private func placeholderText(for category: String) -> String {
        switch category {
        case "Doctor":
            return "e.g. Dr. Smith, One Medical"
        case "Dentist":
            return "e.g. Aspen Dental, your dentist's name"
        case "Specialists":
            return "e.g. dermatologist, allergist, therapist"
        case "Pharmacy":
            return "e.g. CVS, Walgreens, Rite Aid"
        default:
            return "e.g. enter provider name"
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

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { details[key] ?? "" },
            set: { details[key] = $0 }
        )
    }
}

#Preview {
    let manager = AssessmentDataManager()
    manager.healthcareProviders = ["Doctor", "Dentist"]
    manager.healthcareCounts = ["Doctor": 2, "Dentist": 1]
    return HealthcareDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
