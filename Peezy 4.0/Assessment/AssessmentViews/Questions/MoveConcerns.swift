import SwiftUI

struct MoveConcerns: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "What are you most hoping Peezy can help you with?"
    let subtext     : String? = nil
    let buttonText  = "Continue"
    let options: [(String, String)] = [
        ("Knowing what to do and when", "list.bullet.clipboard"),
        ("Finding time to actually pack", "shippingbox.fill"),
        ("Dealing with moving companies", "person.2.fill"),
        ("The fear of forgetting something important", "calendar"),
        ("Something else", "ellipsis")
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
                    selected.remove(option)
                } else {
                    selected.insert(option)
                }
            },
            onContinue: {
                data.moveConcerns = Array(selected)
                coordinator.goToNext()
            }
        )
        .onAppear {
            selected = Set(data.moveConcerns)
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    MoveConcerns().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
