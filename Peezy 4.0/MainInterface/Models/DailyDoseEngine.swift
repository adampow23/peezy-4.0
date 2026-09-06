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

// MARK: - S3: epoch-r cleanup and the exact 0→1 bridge (§5:547; C6.6)

extension DailyDoseLocalStore {
    enum CleanupResult: Equatable, Sendable {
        /// Older epoch replaced by the empty epoch-r state (revision + 1), or an absent store given the epoch-r floor.
        case cleaned(DailyDoseLocalStateV1)
        /// The store already sits at the result epoch; preserved.
        case preserved(DailyDoseLocalStateV1)
        /// The store is at a newer epoch; preserved and reported.
        case drift(current: DailyDoseLocalStateV1)
        case malformed
    }

    enum BridgeResult: Equatable, Sendable {
        /// v2 was absent and legacy v0 keys existed: v2 written at epoch 0 from them, then the keys removed.
        case bridged(DailyDoseLocalStateV1)
        /// v2 already present; any leftover legacy keys were removed (crash after the v2 write).
        case present
        /// Neither v2 nor any legacy key existed.
        case none
        /// v2 bytes are malformed; they and every legacy key are preserved.
        case malformed
    }

    /// The three shipped v0 keys under `peezy.{uid}.dailyDose.`.
    static func legacyKeys(uid: String) -> [String] {
        ["completedCount", "lastDate", "firstLaunchDate"].map { "peezy.\(uid).dailyDose.\($0)" }
    }

    /// Removes the three legacy v0 keys; the v2 state is untouched.
    func removeLegacyKeys(uid: String) {
        Self.legacyKeys(uid: uid).forEach { defaults.removeObject(forKey: $0) }
    }

    /// Cleanup at the result epoch: the state becomes the empty floor at
    /// `taskGenerationEpoch` with revision 0, so any writer holding the previous
    /// epoch drifts on its next CAS. Malformed bytes are preserved, never replaced.
    func cleanup(uid: String, taskGenerationEpoch: Int) -> CleanupResult {
        switch load(uid: uid) {
        case .malformed:
            return .malformed
        case .absent:
            let floor = DailyDoseLocalStateV1(taskGenerationEpoch: taskGenerationEpoch, revision: 0, completedCount: 0, lastDate: nil, firstLaunchDate: nil)
            return write(floor, uid: uid) ? .cleaned(floor) : .malformed
        case let .present(current):
            if current.taskGenerationEpoch == taskGenerationEpoch { return .preserved(current) }
            if current.taskGenerationEpoch > taskGenerationEpoch { return .drift(current: current) }
            let next = DailyDoseLocalStateV1(taskGenerationEpoch: taskGenerationEpoch, revision: current.revision + 1, completedCount: 0, lastDate: nil, firstLaunchDate: nil)
            return write(next, uid: uid) ? .cleaned(next) : .malformed
        }
    }

    /// Exact 0→1 bridge order: read the legacy values, write v2 at epoch 0,
    /// then remove the legacy keys. A crash between the two steps leaves both;
    /// the next call finds v2 present and removes the keys.
    func bridgeLegacy(uid: String) -> BridgeResult {
        let keys = Self.legacyKeys(uid: uid)
        switch load(uid: uid) {
        case .malformed:
            return .malformed
        case .present:
            removeLegacyKeys(uid: uid)
            return .present
        case .absent:
            guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return .none }
            let completed = min(max(defaults.integer(forKey: keys[0]), 0), DailyDoseLocalStateV1.maxCompletedCount)
            let state = DailyDoseLocalStateV1(
                taskGenerationEpoch: 0, revision: 0, completedCount: completed,
                lastDate: Self.legacyDate(defaults.string(forKey: keys[1])),
                firstLaunchDate: Self.legacyDate(defaults.string(forKey: keys[2]))
            )
            guard write(state, uid: uid) else { return .malformed }
            removeLegacyKeys(uid: uid)
            return .bridged(state)
        }
    }

    /// Only an exact `YYYY-MM-DD` legacy value carries over.
    private static func legacyDate(_ value: String?) -> String? {
        guard let value, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
}

extension DailyDoseEngine {
    /// Authority-taking dose reset (S3): one root transaction requires the exact
    /// awaiting marker for `authority` and removes the frozen dose; then the local
    /// store is cleaned at the result epoch and the legacy v0 keys are removed.
    func resetForRetake(authority: ResetLocalCleanupAuthorityV1, localStore: DailyDoseLocalStore = .shared) async throws {
        let firestore = try await FirestoreRuntime.provider.acquire().firestore
        let ref = firestore.collection("users").document(authority.accountUid)
        try await firestore.runTypedTransaction { transaction in
            let root = try transaction.getDocument(ref)
            guard ResetMarkerV1.matchesAwaiting(root.data(), authority: authority) else { throw ResetCleanupError.markerMismatch }
            if root.data()?["dailyDose"] != nil {
                transaction.updateData(["dailyDose": FieldValue.delete()], forDocument: ref)
            }
        }
        _ = await localStore.cleanup(uid: authority.accountUid, taskGenerationEpoch: authority.taskGenerationEpoch)
        await localStore.removeLegacyKeys(uid: authority.accountUid)
    }
}
