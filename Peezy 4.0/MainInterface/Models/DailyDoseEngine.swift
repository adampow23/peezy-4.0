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
    /// A stamped dose is readable only at its own root epoch; an unstamped
    /// legacy dose only while the effective root epoch is 0 (§5:545, 549).
    func loadFrozenDose(userId: String) async -> FrozenDose? {
        let db = FirestoreRuntime.firestore()
        guard let doc = try? await db.collection("users").document(userId).getDocument(),
              let data = doc.data(),
              let rootEpoch = try? TaskGenerationEpochStamp.effectiveRootEpoch(data, requireResetAbsent: false)
        else { return nil }
        return Self.frozenDose(from: data["dailyDose"], rootEpoch: rootEpoch)
    }

    static func frozenDose(from raw: Any?, rootEpoch: Int) -> FrozenDose? {
        guard let map = raw as? [String: Any],
              let date = map["date"] as? String,
              let taskIds = map["taskIds"] as? [String] else { return nil }
        if let rawStamp = map[TaskGenerationEpochStamp.fieldName] {
            guard map.count == 4,
                  TaskGenerationEpochStamp.safeInteger(map["schema_version"]) == 1,
                  let stamp = TaskGenerationEpochStamp.safeInteger(rawStamp),
                  stamp == rootEpoch else { return nil }
            return FrozenDose(date: date, taskIds: taskIds)
        }
        guard map.count == 2, rootEpoch == 0 else { return nil }
        return FrozenDose(date: date, taskIds: taskIds)
    }

    /// Persists the day's dose as the exact stamped map
    /// `{schema_version:1,task_generation_epoch,date,taskIds}` in one root
    /// transaction; refuses while `taskReset` is present (§5:540-543).
    func freeze(_ dose: FrozenDose, userId: String) async {
        let db = FirestoreRuntime.firestore()
        let ref = db.collection("users").document(userId)
        do {
            try await db.runTypedTransaction { transaction in
                let root = try transaction.getDocument(ref)
                let epoch = try TaskGenerationEpochStamp.effectiveRootEpoch(root.data(), requireResetAbsent: true)
                let map: [String: Any] = [
                    "schema_version": 1,
                    TaskGenerationEpochStamp.fieldName: epoch,
                    "date": dose.date,
                    "taskIds": dose.taskIds
                ]
                if root.exists {
                    transaction.updateData(["dailyDose": map], forDocument: ref)
                } else {
                    transaction.setData(["dailyDose": map], forDocument: ref, merge: true)
                }
            }
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

// MARK: - DailyDoseLocalStore (§5:547; C6.6 `peezy.{uid}.dailyDose.v2`)

/// Exact `{schemaVersion:1,taskGenerationEpoch,revision,completedCount,lastDate,firstLaunchDate}`.
struct DailyDoseLocalStateV1: Equatable, Sendable {
    static let schemaVersion = 1
    static let maxCanonicalBytes = 1_024
    static let maxCompletedCount = 1_000_000
    private static let keys = ["completedCount", "firstLaunchDate", "lastDate", "revision", "schemaVersion", "taskGenerationEpoch"]

    var taskGenerationEpoch: Int
    var revision: Int
    var completedCount: Int
    var lastDate: String?
    var firstLaunchDate: String?

    init(taskGenerationEpoch: Int, revision: Int, completedCount: Int, lastDate: String?, firstLaunchDate: String?) {
        self.taskGenerationEpoch = taskGenerationEpoch
        self.revision = revision
        self.completedCount = completedCount
        self.lastDate = lastDate
        self.firstLaunchDate = firstLaunchDate
    }

    var isValid: Bool {
        (0...TaskGenerationEpochStamp.maxSafeInteger).contains(taskGenerationEpoch)
            && (0...TaskGenerationEpochStamp.maxSafeInteger).contains(revision)
            && (0...Self.maxCompletedCount).contains(completedCount)
            && Self.isDate(lastDate) && Self.isDate(firstLaunchDate)
    }

    /// Canonical JSON: sorted keys, compact, explicit nulls.
    func canonicalData() -> Data? {
        guard isValid else { return nil }
        let object: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "taskGenerationEpoch": taskGenerationEpoch,
            "revision": revision,
            "completedCount": completedCount,
            "lastDate": lastDate.map { $0 as Any } ?? NSNull(),
            "firstLaunchDate": firstLaunchDate.map { $0 as Any } ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              data.count <= Self.maxCanonicalBytes else { return nil }
        return data
    }

    /// Strict decode: exact member set, exact types and ranges, cap; anything else is nil.
    static func decode(_ data: Data) -> DailyDoseLocalStateV1? {
        guard data.count <= maxCanonicalBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.keys.sorted() == keys,
              TaskGenerationEpochStamp.safeInteger(object["schemaVersion"]) == schemaVersion,
              let epoch = TaskGenerationEpochStamp.safeInteger(object["taskGenerationEpoch"]),
              let revision = TaskGenerationEpochStamp.safeInteger(object["revision"]),
              let completed = TaskGenerationEpochStamp.safeInteger(object["completedCount"]),
              let lastDate = optionalDate(object["lastDate"]),
              let firstLaunchDate = optionalDate(object["firstLaunchDate"]) else { return nil }
        let state = DailyDoseLocalStateV1(
            taskGenerationEpoch: epoch, revision: revision, completedCount: completed,
            lastDate: lastDate, firstLaunchDate: firstLaunchDate
        )
        return state.isValid ? state : nil
    }

    /// `.some(nil)` for JSON null, `.some(date)` for an exact `YYYY-MM-DD`, nil otherwise.
    private static func optionalDate(_ value: Any?) -> String?? {
        if value is NSNull { return .some(nil) }
        guard let string = value as? String, isDate(string) else { return nil }
        return .some(string)
    }

    private static func isDate(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

/// Sole process-wide accessor of `peezy.{uid}.dailyDose.v2`. Each mutation
/// CASes the exact epoch/revision and increments the revision; malformed or
/// over-cap bytes block mutation and are never silently removed. Cleanup at a
/// result epoch and the legacy 0→1 bridge belong to S3.
actor DailyDoseLocalStore {
    enum LoadResult: Equatable, Sendable {
        case absent
        case present(DailyDoseLocalStateV1)
        case malformed
    }

    enum MutationResult: Equatable, Sendable {
        case committed(DailyDoseLocalStateV1)
        case drift(current: DailyDoseLocalStateV1)
        case absent
        case malformed
    }

    static let shared = DailyDoseLocalStore(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func key(uid: String) -> String { "peezy.\(uid).dailyDose.v2" }

    func load(uid: String) -> LoadResult {
        guard let data = defaults.data(forKey: Self.key(uid: uid)) else { return .absent }
        guard let state = DailyDoseLocalStateV1.decode(data) else { return .malformed }
        return .present(state)
    }

    /// Returns the existing state, or creates the empty epoch floor when absent;
    /// nil when the stored bytes are malformed.
    func ensure(uid: String, taskGenerationEpoch: Int) -> DailyDoseLocalStateV1? {
        switch load(uid: uid) {
        case let .present(state):
            return state
        case .malformed:
            return nil
        case .absent:
            let floor = DailyDoseLocalStateV1(
                taskGenerationEpoch: taskGenerationEpoch, revision: 0, completedCount: 0,
                lastDate: nil, firstLaunchDate: nil
            )
            return write(floor, uid: uid) ? floor : nil
        }
    }

    func mutate(
        uid: String,
        expectedTaskGenerationEpoch: Int,
        expectedRevision: Int,
        _ change: @Sendable (inout DailyDoseLocalStateV1) -> Void
    ) -> MutationResult {
        switch load(uid: uid) {
        case .absent: return .absent
        case .malformed: return .malformed
        case let .present(current):
            guard current.taskGenerationEpoch == expectedTaskGenerationEpoch,
                  current.revision == expectedRevision else { return .drift(current: current) }
            var next = current
            change(&next)
            next.taskGenerationEpoch = current.taskGenerationEpoch
            next.revision = current.revision + 1
            return write(next, uid: uid) ? .committed(next) : .drift(current: current)
        }
    }

    private func write(_ state: DailyDoseLocalStateV1, uid: String) -> Bool {
        guard let data = state.canonicalData() else { return false }
        defaults.set(data, forKey: Self.key(uid: uid))
        return true
    }
}
