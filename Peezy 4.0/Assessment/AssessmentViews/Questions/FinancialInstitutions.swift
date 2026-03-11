import SwiftUI

struct FinancialInstitutions: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "Let's start with finance related accounts you might have."
    let subtext     : String? = "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    let buttonText  = "Continue"
    let options: [(String, String)] = [
        ("Bank/Credit Union", "building.columns.fill"),
        ("Credit Card", "creditcard.fill"),
        ("Investment/Brokerage", "chart.line.uptrend.xyaxis"),
        ("401k/IRA", "banknote.fill"),
        ("Student Loans", "graduationcap.fill"),
        ("Mortgage", "house.fill"),
        ("HSA/FSA", "cross.case.fill")
    ]

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

    @State private var selected: Set<String> = []
    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        MultiSelectTemplate(
            header: header, subtext: subtext,
            options: options,
            selected: selected,
            buttonText: buttonText,
            onToggle: { option in
                if selected.contains(option) {
                    // Already selected — increment count
                    let current = data.financialCounts[option] ?? 1
                    data.financialCounts[option] = current + 1
                } else {
                    // First tap — add to selection
                    selected.insert(option)
                    data.financialCounts[option] = 1
                }
            },
            onContinue: {
                data.financialInstitutions = Array(selected)
                coordinator.goToNext()
            }
        )
        .onAppear {
            selected = Set(data.financialInstitutions)
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    FinancialInstitutions().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
