import Foundation

/// Daily dose math, split out of PeezyHomeViewModel (Spec 03 Phase C).
/// The buffer thresholds, target formula, and urgency sort are ported VERBATIM
/// from the pre-split view model — they are calibrated; do not tweak in passing.
struct DailyDoseEngine {

    func bufferDays(daysUntilMove: Int) -> Int {
        if daysUntilMove <= 10 { return 0 }
        if daysUntilMove <= 14 { return 3 }
        return 7
    }

    func workingDays(daysUntilMove: Int) -> Int {
        max(daysUntilMove - bufferDays(daysUntilMove: daysUntilMove), 1)
    }

    func dailyTarget(activeTaskCount: Int, daysUntilMove: Int) -> Int {
        guard activeTaskCount > 0 else { return 0 }
        return max(Int(ceil(Double(activeTaskCount) / Double(workingDays(daysUntilMove: daysUntilMove)))), 1)
    }

    /// Urgency-descending, title as tiebreak — the dose ordering.
    func urgencySorted(_ cards: [PeezyCard]) -> [PeezyCard] {
        cards.sorted { a, b in
            let ua = a.urgencyPercentage ?? 0
            let ub = b.urgencyPercentage ?? 0
            if ua != ub { return ua > ub }
            return a.title < b.title
        }
    }
}
