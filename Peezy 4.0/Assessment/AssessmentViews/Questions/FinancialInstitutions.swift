import SwiftUI

struct FinancialInstitutions: View {

    let header      = "First up: the money accounts."
    let subtext     : String? = "Tap everything you have. More than one of something? Tap it once per account — we track each one separately."
    let buttonText  = "Continue"

    // OPTIONS — must match taskCatalogData.json condition values EXACTLY
    let options: [(String, String)] = [
        ("Bank / Credit Union", "building.columns.fill"),
        ("Credit Card", "creditcard.fill"),
        ("Investment Account", "chart.line.uptrend.xyaxis"),
        ("Student Loans", "graduationcap.fill")
    ]

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
                if !selected.contains(option) {
                    selected.insert(option)
                    data.financialCounts[option] = 1
                }
            },
            onContinue: {
                data.financialInstitutions = Array(selected)
                coordinator.goToNext()
            },
            counts: data.financialCounts,
            onIncrement: { option in
                let current = data.financialCounts[option] ?? 1
                data.financialCounts[option] = current + 1
            },
            onDecrement: { option in
                let current = data.financialCounts[option] ?? 1
                if current <= 1 {
                    selected.remove(option)
                    data.financialCounts.removeValue(forKey: option)
                } else {
                    data.financialCounts[option] = current - 1
                }
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
