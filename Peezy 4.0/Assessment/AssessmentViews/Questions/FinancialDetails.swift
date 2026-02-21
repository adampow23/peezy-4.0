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

    @FocusState private var focusedCategory: String?
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        Text("Which ones?")
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
                            ForEach(assessmentData.financialInstitutions, id: \.self) { category in
                                SuggestiveTextField(
                                    label: category,
                                    placeholder: "e.g. Chase, Amex...",
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
                assessmentData.financialDetails = details
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
            details = assessmentData.financialDetails
            if let first = assessmentData.financialInstitutions.first {
                focusedCategory = first
            }
            withAnimation { showContent = true }
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

    private func binding(for category: String) -> Binding<String> {
        Binding(
            get: { details[category] ?? "" },
            set: { details[category] = $0 }
        )
    }
}

#Preview {
    let manager = AssessmentDataManager()
    manager.financialInstitutions = ["Bank / Credit Union", "Credit Card"]
    return FinancialDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
