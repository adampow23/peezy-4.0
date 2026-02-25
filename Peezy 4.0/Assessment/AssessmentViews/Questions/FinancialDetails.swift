import SwiftUI

private let creditCardSuggestions = [
    "Chase", "American Express", "Capital One", "Citi", "Discover",
    "Bank of America", "Wells Fargo", "Barclays", "US Bank", "Synchrony"
]

private let investmentSuggestions = [
    "Fidelity", "Charles Schwab", "Vanguard", "E*TRADE", "TD Ameritrade",
    "Merrill Lynch", "Morgan Stanley", "Edward Jones", "Robinhood",
    "Wealthfront", "Betterment", "Northwestern Mutual", "Raymond James"
]

private let studentLoanSuggestions = [
    "Navient", "Nelnet", "Great Lakes", "FedLoan", "SoFi", "Earnest",
    "CommonBond", "Mohela", "Aidvantage", "EdFinancial"
]

struct FinancialDetails: View {
    @State private var details: [String: String] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @FocusState private var focusedKey: String?
    @State private var showContent = false

    /// Builds the list of (detailKey, label, category) for all fields.
    private var fieldEntries: [(key: String, label: String, category: String)] {
        var entries: [(String, String, String)] = []
        for category in assessmentData.financialInstitutions {
            let count = assessmentData.financialCounts[category] ?? 1
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
                assessmentData.financialDetails = details
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            details = assessmentData.financialDetails
            if let first = fieldEntries.first {
                focusedKey = first.key
            }
            withAnimation { showContent = true }
        }
    }

    private func placeholderText(for category: String) -> String {
        switch category {
        case "Bank / Credit Union":
            return "e.g. Chase, Bank of America, Wells Fargo"
        case "Credit Card":
            return "e.g. Amex, Capital One, Discover"
        case "Investment Account":
            return "e.g. Fidelity, Schwab, Vanguard"
        case "Student Loans":
            return "e.g. Navient, SoFi, Nelnet"
        default:
            return "e.g. enter provider name"
        }
    }

    private func suggestionSource(for category: String) -> SuggestionSource {
        switch category {
        case "Bank / Credit Union":
            return .mapSearch(category: "bank", nearAddress: assessmentData.currentAddress)
        case "Credit Card":
            return .local(creditCardSuggestions)
        case "Investment Account":
            return .local(investmentSuggestions)
        case "Student Loans":
            return .local(studentLoanSuggestions)
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
    manager.financialInstitutions = ["Bank / Credit Union", "Credit Card"]
    manager.financialCounts = ["Bank / Credit Union": 2, "Credit Card": 1]
    return FinancialDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
