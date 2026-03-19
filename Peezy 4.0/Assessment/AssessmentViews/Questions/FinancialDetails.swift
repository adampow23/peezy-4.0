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

    @State private var currentEntryIndex: Int = 0
    @State private var showContent = true

    // Morph state — only morphs on first entry
    @State private var headerDone = false
    @State private var isHero = true
    @State private var skipped = false
    @State private var showControls = false

    private let speed: Double = 0.04

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

    private var currentEntry: (key: String, label: String, category: String)? {
        guard currentEntryIndex < fieldEntries.count else { return nil }
        return fieldEntries[currentEntryIndex]
    }

    private var headerText: String {
        guard let entry = currentEntry else { return "" }
        return "What \(entry.category.lowercased()) do you have an account with?"
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                if isHero { Spacer() }

                // ── TEXT AREA ──
                VStack(spacing: 8) {
                    Group {
                        if skipped || !isHero {
                            Text(headerText)
                        } else {
                            TypingText(
                                fullText: headerText,
                                speed: speed,
                                visibleColor: PeezyTheme.Colors.deepInk,
                                onComplete: {
                                    headerDone = true
                                    triggerMorph()
                                }
                            )
                        }
                    }
                    .font(.system(size: isHero ? 32 : 22, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(4)
                    .multilineTextAlignment(isHero ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)

                    // Counter
                    if !isHero && fieldEntries.count > 1 {
                        Text("\(currentEntryIndex + 1) of \(fieldEntries.count)")
                            .font(.caption)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, isHero ? 0 : 24)
                .padding(.bottom, isHero ? 0 : 40)

                if isHero { Spacer() }

                // Center field between header and button
                if !isHero && showControls { Spacer() }

                // ── TEXT FIELD ──
                if showControls, let entry = currentEntry {
                    SuggestiveTextField(
                        label: entry.label,
                        placeholder: placeholderText(for: entry.category),
                        text: binding(for: entry.key),
                        source: suggestionSource(for: entry.category),
                        isFocused: true,
                        autoFocus: true
                    )
                    .id(entry.key)
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: showContent)
                }

                if !isHero && showControls { Spacer() }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton("Continue") {
                        if currentEntryIndex < fieldEntries.count - 1 {
                            showContent = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                currentEntryIndex += 1
                                showContent = true
                            }
                        } else {
                            assessmentData.financialDetails = details
                            coordinator.goToNext()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isHero { skipToControls() }
        }
        .onAppear {
            details = assessmentData.financialDetails
        }
    }

    // ── MORPH LOGIC ─────────────────────────────────────────────

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard isHero else { return }
            performMorph()
        }
    }

    private func performMorph() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isHero = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }

    private func skipToControls() {
        skipped = true
        headerDone = true
        performMorph()
    }

    // ── HELPERS ─────────────────────────────────────────────────

    private func placeholderText(for category: String) -> String {
        switch category {
        case "Bank/Credit Union":       return "e.g. Chase, Bank of America, Wells Fargo"
        case "Credit Card":             return "e.g. Amex, Capital One, Discover"
        case "Investment/Brokerage":    return "e.g. Fidelity, Schwab, Vanguard"
        case "401k/IRA":                return "e.g. Fidelity, Vanguard, T. Rowe Price"
        case "Student Loans":           return "e.g. Navient, SoFi, Nelnet"
        case "Mortgage":                return "e.g. Wells Fargo, Rocket Mortgage"
        case "HSA/FSA":                 return "e.g. Optum, HealthEquity, Fidelity"
        default:                        return "e.g. enter provider name"
        }
    }

    private func suggestionSource(for category: String) -> SuggestionSource {
        switch category {
        case "Bank/Credit Union":
            return .mapSearch(category: "bank", nearAddress: assessmentData.currentAddress)
        case "Credit Card":
            return .local(creditCardSuggestions)
        case "Investment/Brokerage":
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
    manager.financialInstitutions = ["Bank/Credit Union", "Credit Card"]
    manager.financialCounts = ["Bank/Credit Union": 2, "Credit Card": 1]
    return FinancialDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
