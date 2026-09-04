import Foundation
import FirebaseFirestore

/// Daily dose math, split out of PeezyHomeViewModel (Spec 03 Phase C).
/// The buffer thresholds, target formula, and urgency sort are ported VERBATIM
/// from the pre-split view model — they are calibrated; do not tweak in passing.
///
/// Spec 04 Phase E adds the FREEZE: the dose is computed once per calendar
/// day and persisted as {date, taskIds} on the user doc. The frozen set is
/// served for the rest of the day — mid-day generations join tomorrow, and
/// the announced target can no longer shrink as tasks complete.
struct DailyDoseEngine {

    /// The persisted daily dose — users/{uid}.dailyDose {date, taskIds}.
    struct FrozenDose: Equatable {
        let date: String        // "YYYY-MM-DD"
        let taskIds: [String]
    }

    /// Reads today's frozen dose from the user doc; nil when absent or malformed.
    func loadFrozenDose(userId: String) async -> FrozenDose? {
        let db = FirestoreRuntime.firestore()
        guard let doc = try? await db.collection("users").document(userId).getDocument(),
              let raw = doc.data()?["dailyDose"] as? [String: Any],
              let date = raw["date"] as? String,
              let taskIds = raw["taskIds"] as? [String] else { return nil }
        return FrozenDose(date: date, taskIds: taskIds)
    }

    /// Persists the day's dose. setData(merge:) — the user doc also carries
    /// profile fields owned elsewhere.
    func freeze(_ dose: FrozenDose, userId: String) async {
        let db = FirestoreRuntime.firestore()
        do {
            try await db.collection("users").document(userId).setData([
                "dailyDose": ["date": dose.date, "taskIds": dose.taskIds]
            ], merge: true)
        } catch {
            print("⚠️ Failed to freeze daily dose: \(error.localizedDescription)")
        }
    }

    /// Removes the old plan's frozen dose and its local progress counters so a
    /// retake starts with the regenerated plan rather than same-day residue.
    func resetForRetake(userId: String) async throws {
        guard !userId.isEmpty else { return }

        try await FirestoreRuntime.provider.acquire().firestore
            .collection("users")
            .document(userId)
            .updateData(["dailyDose": FieldValue.delete()])

        let defaults = UserDefaults.standard
        let prefix = "peezy.\(userId).dailyDose."
        defaults.removeObject(forKey: "\(prefix)completedCount")
        defaults.removeObject(forKey: "\(prefix)lastDate")
        defaults.removeObject(forKey: "\(prefix)firstLaunchDate")
    }

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

    /// Builds a new day's frozen ids. Packing work is scheduled-date-driven:
    /// it does not inflate the regular task target, and at most one due packing
    /// session joins (and is counted in) today's frozen dose. The stable T−1
    /// readiness gate follows any packing session when it becomes due.
    func taskIdsForNewDose(
        from sortedCards: [PeezyCard],
        daysUntilMove: Int,
        moveDate: Date? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let surfacedCards = sortedCards.filter {
            isEligibleForDose(
                $0,
                moveDate: moveDate,
                today: today,
                calendar: calendar
            )
        }
        let regularCards = surfacedCards.filter { !$0.isPackingSession && !$0.isPackingReadiness }
        let regularTarget = dailyTarget(
            activeTaskCount: regularCards.count,
            daysUntilMove: daysUntilMove
        )
        let startToday = calendar.startOfDay(for: today)
        let duePacking = surfacedCards
            .compactMap { card -> (PeezyCard, PackingSession)? in
                guard let session = card.packingSession,
                      calendar.startOfDay(for: session.scheduledDate) <= startToday else { return nil }
                return (card, session)
            }
            .sorted {
                if $0.1.scheduledDate != $1.1.scheduledDate {
                    return $0.1.scheduledDate < $1.1.scheduledDate
                }
                return $0.1.taskId < $1.1.taskId
            }
            .first

        let dueReadiness = surfacedCards.first { card in
            guard card.isPackingReadiness, let dueDate = card.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) <= startToday
        }

        let scheduledCount = (duePacking == nil ? 0 : 1) + (dueReadiness == nil ? 0 : 1)
        let regularSlots = max(regularTarget - scheduledCount, 0)
        var ids = regularCards.prefix(regularSlots).map(\.id)
        if let duePacking { ids.append(duePacking.0.id) }
        if let dueReadiness { ids.append(dueReadiness.id) }
        return ids
    }

    /// Date-gated catalog tasks join the normal dose only on or after the
    /// configured post-move day. A missing move date cannot satisfy the gate.
    func isEligibleForDose(
        _ card: PeezyCard,
        moveDate: Date?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let daysPastMove = card.surfaceAfterDaysPastMove else { return true }
        guard let moveDate,
              let surfaceDate = calendar.date(
                byAdding: .day,
                value: daysPastMove,
                to: calendar.startOfDay(for: moveDate)
              )
        else { return false }
        return calendar.startOfDay(for: today) >= surfaceDate
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
