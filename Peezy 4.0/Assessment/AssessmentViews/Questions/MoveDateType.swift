import SwiftUI

// Restored from eab4193^ (Spec 02 Phase B): the flexible-date escape hatch.
// "Flexible" persists moveDatePending=true while MoveDate still captures a
// best-guess date (the dose math needs a denominator). Subtext copy is
// LOCKED per spec 02; it renders pre-choice because the tile auto-advances.
struct MoveDateType: View {
    let header      = "Is your move date flexible?"
    let subtext     : String? = "We'll plan against your best guess — adjusting later takes one tap in Settings."
    let options     = ["Strict", "Flexible"]
    let icons       = ["arrow.left.arrow.right", "checkmark.circle"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.moveDateType
        ) { value in
            data.moveDateType = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
        .accessibilityIdentifier("assessment.moveDateType")
    }
}

#Preview {
    let dm = AssessmentDataManager()
    MoveDateType().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
