// TaskGenerationService.swift
// Peezy iOS - Task Generation from Catalog
//
// LAST UPDATED: 2026-02-12
//
// Generates personalized task list by reading the taskCatalog collection,
// evaluating each task's conditions against the user's assessment data,
// and writing matching tasks to users/{uid}/tasks/.
//
// CONDITION FORMAT: Conditions are stored as maps { fieldName: [acceptableValues] }
// See TaskCatalogSchema.swift for full documentation.
//
// CHANGES (2026-02-12):
//   - Removed mini-assessment task creation (consolidated into main assessment)
//   - Removed isSubTask/parentTask skip logic
//   - Removed dead fields: pageKey, isAssessmentTask, isSubTask, parentTask, priority
//   - Task document ID = taskId from catalog (e.g., "BOOK_MOVERS")
//   - Debug prints gated behind #if DEBUG

import Foundation
import FirebaseFirestore

@MainActor
protocol TaskGenerationTransactionRunning {
    func createMissingTasks(
        userId: String,
        candidates: [[String: Any]]
    ) async throws -> Int
}

nonisolated protocol TaskGenerationTransactionAccess: AnyObject, Sendable {
    func userData() throws -> [String: Any]?
    func taskExists(id: String, candidate: [String: Any]) throws -> Bool
    func createTask(id: String, data: [String: Any]) throws
}

typealias TaskGenerationTransactionBody =
    @Sendable (any TaskGenerationTransactionAccess) throws -> Int

// Firebase owns the transaction callback queue. This adapter never escapes a
// callback invocation, and its Firestore handles are only accessed by that
// callback, so the unchecked conformance records that queue confinement.
nonisolated private final class FirestoreTaskGenerationTransactionAccess:
    TaskGenerationTransactionAccess,
    @unchecked Sendable
{
    private let transaction: Transaction
    private let userRef: DocumentReference

    init(transaction: Transaction, userRef: DocumentReference) {
        self.transaction = transaction
        self.userRef = userRef
    }

    func userData() throws -> [String: Any]? {
        try transaction.getDocument(userRef).data()
    }

    func taskExists(id: String, candidate: [String: Any]) throws -> Bool {
        try transaction.getDocument(userRef.collection("tasks").document(id)).exists
    }

    func createTask(id: String, data: [String: Any]) throws {
        transaction.setData(data, forDocument: userRef.collection("tasks").document(id))
    }
}

// Candidate maps contain immutable Firestore values prepared before entering
// the retryable callback. The wrapper prevents the Sendable closure from
// capturing actor-isolated local state while preserving identical retry data.
nonisolated private struct TaskGenerationTransactionCandidate: @unchecked Sendable {
    let id: String
    let data: [String: Any]
}

@MainActor
struct FirestoreTaskGenerationTransactionRunner: TaskGenerationTransactionRunning {
    typealias Execute = (@escaping TaskGenerationTransactionBody) async throws -> Int

    private let database: Firestore?
    private let injectedExecute: Execute?

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
        self.injectedExecute = nil
    }

    init(execute: @escaping Execute) {
        self.database = nil
        self.injectedExecute = execute
    }

    func createMissingTasks(
        userId: String,
        candidates: [[String: Any]]
    ) async throws -> Int {
        let identified = try candidates.map { candidate -> TaskGenerationTransactionCandidate in
            guard let id = candidate["id"] as? String, !id.isEmpty else {
                throw TaskGenerationWriteError.missingCandidateID
            }
            return TaskGenerationTransactionCandidate(id: id, data: candidate)
        }

        let body: TaskGenerationTransactionBody = { access in
            if let marker = try access.userData()?["taskReset"] as? [String: Any],
               let state = marker["state"] as? String,
               state == "deleting" || state == "awaiting_local_reset" {
                throw TaskGenerationWriteError.resetActive
            }

            // Capture the add-only decision for every candidate before the
            // first write. The SDK may replay this whole body after contention;
            // identified data (including generated row UUIDs) is unchanged.
            var missing: [TaskGenerationTransactionCandidate] = []
            for candidate in identified {
                if try !access.taskExists(id: candidate.id, candidate: candidate.data) {
                    missing.append(candidate)
                }
            }
            for candidate in missing {
                try access.createTask(id: candidate.id, data: candidate.data)
            }
            return missing.count
        }

        if let injectedExecute {
            return try await injectedExecute(body)
        }
        guard let database else { throw TaskGenerationWriteError.missingResult }
        let userRef = database.collection("users").document(userId)
        let result = try await database.runTransaction { transaction, errorPointer in
            do {
                let access = FirestoreTaskGenerationTransactionAccess(
                    transaction: transaction,
                    userRef: userRef
                )
                return NSNumber(value: try body(access))
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        guard let number = result as? NSNumber else { throw TaskGenerationWriteError.missingResult }
        return number.intValue
    }
}

class TaskGenerationService {

    private let db = Firestore.firestore()
    private let transactionRunner: any TaskGenerationTransactionRunning

    @MainActor
    init(
        transactionRunner: (any TaskGenerationTransactionRunning)? = nil
    ) {
        self.transactionRunner = transactionRunner ?? FirestoreTaskGenerationTransactionRunner()
    }

    /// Generates tasks for a user based on their assessment
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - assessment: Dictionary containing user's assessment data
    ///   - moveDate: The user's move date
    /// - Returns: Number of tasks generated
    @MainActor
    func generateTasksForUser(
        userId: String,
        assessment: [String: Any],
        moveDate: Date
    ) async throws -> Int {
        #if DEBUG
        print("🚀 TASK GEN: Starting for user \(userId)")
        print("📅 TASK GEN: Move date is \(moveDate), today is \(DateProvider.shared.now)")
        #endif

        // 1. Fetch all tasks from taskCatalog
        let catalogSnapshot = try await db.collection("taskCatalog").getDocuments()
        let hasSuppliesKitSubmission = try await hasWorkflowResponse(
            userId: userId,
            workflowId: "supplies_kit"
        )
        #if DEBUG
        print("📚 Found \(catalogSnapshot.documents.count) tasks in catalog")
        print("🔍 ASSESSMENT DATA FOR CONDITIONS:")
        for (key, value) in assessment.sorted(by: { $0.key < $1.key }) {
            print("   • \(key): \(value) (type: \(type(of: value)))")
        }
        #endif

        var tasksToCreate: [[String: Any]] = []

        // Spec 09: nudge rows resolve their spawn target's date through this
        // per-run index — built once from the snapshot, shared by every row.
        let catalogIndex = Dictionary(
            uniqueKeysWithValues: catalogSnapshot.documents.map { ($0.documentID, $0.data()) }
        )

        // 2. Evaluate each task's conditions
        for document in catalogSnapshot.documents {
            if document.documentID == "BOX_RETURN", !hasSuppliesKitSubmission {
                continue
            }
            let taskData = document.data()
            // spawnedOnly rows exist only via the spawnTasks callable (Spec 09).
            if taskData["spawnedOnly"] as? Bool == true { continue }
            let taskTitle = taskData["title"] as? String ?? "Unknown"

            // Get conditions — stored as { fieldName: [acceptableValues] }
            let conditions = Self.evaluableConditions(taskData["conditions"] as? [String: Any])

            #if DEBUG
            print("🔍 Evaluating: '\(taskTitle)' conditions: \(conditions ?? [:])")
            #endif

            // Evaluate conditions against user's assessment
            let conditionPassed = TaskConditionParser.evaluateConditions(conditions, against: assessment)

            if conditionPassed {
                let urgencyPercentage = (taskData["urgencyPercentage"] as? NSNumber)?.intValue ?? 50

                let dueDate = resolvedDueDate(
                    for: taskData,
                    catalogIndex: catalogIndex,
                    moveDate: moveDate
                )

                #if DEBUG
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                print("✅ '\(taskTitle)' → due: \(dateFormatter.string(from: dueDate)) (urgency: \(urgencyPercentage))")
                #endif

                // Build user task document
                var userTask: [String: Any] = [
                    "id": document.documentID,              // e.g., "BOOK_MOVERS"
                    "taskId": taskData["taskId"] ?? document.documentID,
                    "title": taskData["title"] ?? "",
                    "desc": taskData["desc"] ?? "",
                    "category": taskData["category"] ?? "custom",
                    "actionCategory": taskData["actionCategory"] ?? "",
                    "actionType": taskData["actionType"] ?? "off-app",
                    "taskType": taskData["taskType"] as? String ?? "provide_info",
                    "urgencyPercentage": urgencyPercentage,
                    "estHours": taskData["estHours"] ?? 0,
                    "tips": taskData["tips"] ?? "",
                    "whyNeeded": taskData["whyNeeded"] ?? "",
                    "conditions": taskData["conditions"] ?? [:],
                    "dueDate": Timestamp(date: dueDate),
                    "status": "Upcoming",
                    "userId": userId,
                    "createdAt": Timestamp(date: Date()),
                ]

                // Copy workflowId only if present (workflow tasks only)
                if let workflowId = taskData["workflowId"] as? String {
                    userTask["workflowId"] = workflowId
                }
                if let days = taskData["surfaceAfterDaysPastMove"] as? NSNumber {
                    userTask["surfaceAfterDaysPastMove"] = days
                }

                // Copy selfServiceOnly flag (defaults to false if absent)
                userTask["selfServiceOnly"] = taskData["selfServiceOnly"] as? Bool ?? false

                stampTierAndNudgeMetadata(from: taskData, onto: &userTask)

                // Row-generation (Spec 04 Phase B): stamp per-user rows the
                // FlowEngine expands (merged flows, count-expanded providers,
                // conditional sections). Absent config or zero rows = no field.
                if let rowGen = taskData["rowGeneration"] as? [String: Any] {
                    let rows = Self.flowRows(from: rowGen, assessment: assessment)
                    if !rows.isEmpty {
                        userTask["flowRows"] = rows
                    }
                }

                tasksToCreate.append(userTask)
            } else {
                #if DEBUG
                print("❌ Skipping: '\(taskTitle)'")
                #endif
            }
        }

        #if DEBUG
        print("📋 TASK GEN: \(tasksToCreate.count) tasks matched conditions")
        #endif

        // 3. Add-only, reset-aware transaction. Reads precede writes and a
        // retry re-observes every lifecycle document before deciding to create.
        let totalTasks: Int
        do {
            totalTasks = try await Self.createMissingTasks(
                userId: userId,
                candidates: tasksToCreate,
                runner: transactionRunner
            )
            #if DEBUG
            print("✅ TASK GEN: Created \(totalTasks) missing tasks in Firestore")
            #endif
        } catch {
            #if DEBUG
            print("❌ TASK GEN FAILED: \(error)")
            #endif
            throw error
        }

        #if DEBUG
        print("✨ TASK GEN: Complete — \(totalTasks) tasks generated")
        #endif

        return totalTasks
    }

    // MARK: - Incremental Generation (Spec 04 Phase B)

    /// Add-only generation for the tier-2 dose cards (DECLUTTER_INTENT /
    /// STORAGE_NEED): after a card writes its assessment keys, this creates
    /// tasks that NOW match — and never touches existing docs (a full rerun
    /// would batch.setData over live statuses).
    @MainActor
    func generateNewlyMatchingTasks(
        userId: String,
        assessment: [String: Any],
        moveDate: Date
    ) async throws -> Int {
        let catalogSnapshot = try await db.collection("taskCatalog").getDocuments()
        let hasSuppliesKitSubmission = try await hasWorkflowResponse(
            userId: userId,
            workflowId: "supplies_kit"
        )

        var candidates: [[String: Any]] = []

        // Same per-run index as the initial loop (Spec 09 nudge date math).
        let catalogIndex = Dictionary(
            uniqueKeysWithValues: catalogSnapshot.documents.map { ($0.documentID, $0.data()) }
        )

        for document in catalogSnapshot.documents {
            if document.documentID == "BOX_RETURN", !hasSuppliesKitSubmission {
                continue
            }
            let taskData = document.data()
            // spawnedOnly rows exist only via the spawnTasks callable (Spec 09).
            if taskData["spawnedOnly"] as? Bool == true { continue }
            let conditions = Self.evaluableConditions(taskData["conditions"] as? [String: Any])
            guard TaskConditionParser.evaluateConditions(conditions, against: assessment) else { continue }

            let urgencyPercentage = (taskData["urgencyPercentage"] as? NSNumber)?.intValue ?? 50
            let dueDate = resolvedDueDate(for: taskData, catalogIndex: catalogIndex, moveDate: moveDate)

            var userTask: [String: Any] = [
                "id": document.documentID,
                "taskId": taskData["taskId"] ?? document.documentID,
                "title": taskData["title"] ?? "",
                "desc": taskData["desc"] ?? "",
                "category": taskData["category"] ?? "custom",
                "actionCategory": taskData["actionCategory"] ?? "",
                "actionType": taskData["actionType"] ?? "off-app",
                "taskType": taskData["taskType"] as? String ?? "provide_info",
                "urgencyPercentage": urgencyPercentage,
                "estHours": taskData["estHours"] ?? 0,
                "tips": taskData["tips"] ?? "",
                "whyNeeded": taskData["whyNeeded"] ?? "",
                "conditions": taskData["conditions"] ?? [:],
                "dueDate": Timestamp(date: dueDate),
                "status": "Upcoming",
                "userId": userId,
                "createdAt": Timestamp(date: Date()),
            ]
            if let workflowId = taskData["workflowId"] as? String {
                userTask["workflowId"] = workflowId
            }
            if let days = taskData["surfaceAfterDaysPastMove"] as? NSNumber {
                userTask["surfaceAfterDaysPastMove"] = days
            }
            userTask["selfServiceOnly"] = taskData["selfServiceOnly"] as? Bool ?? false
            stampTierAndNudgeMetadata(from: taskData, onto: &userTask)
            if let rowGen = taskData["rowGeneration"] as? [String: Any] {
                let rows = Self.flowRows(from: rowGen, assessment: assessment)
                if !rows.isEmpty {
                    userTask["flowRows"] = rows
                }
            }

            candidates.append(userTask)
        }
        return try await Self.createMissingTasks(
            userId: userId,
            candidates: candidates,
            runner: transactionRunner
        )
    }

    static func createMissingTasks(
        userId: String,
        candidates: [[String: Any]],
        runner: any TaskGenerationTransactionRunning
    ) async throws -> Int {
        guard candidates.count <= 499 else { throw TaskGenerationWriteError.transactionLimit }
        guard !candidates.isEmpty else { return 0 }
        return try await runner.createMissingTasks(userId: userId, candidates: candidates)
    }

    private func hasWorkflowResponse(userId: String, workflowId: String) async throws -> Bool {
        guard !userId.isEmpty else { return false }
        let snapshot = try await db.collection("users").document(userId)
            .collection("workflowResponses").document(workflowId)
            .getDocument()
        return snapshot.exists
    }

    // MARK: - Flow Rows

    /// Computes the per-user `flowRows` stamped on a task doc from the
    /// catalog's rowGeneration config. Modes:
    /// - counts: one row per selected category × its Spec-02 tap count
    ///   (missing count = 1 for pre-count assessments)
    /// - flag: a single named row when the assessment key is "Yes"
    /// - accessRows: fixed rows plus key==value conditional rows
    static func flowRows(from config: [String: Any], assessment: [String: Any]) -> [[String: Any]] {
        let mode = config["mode"] as? String ?? ""

        switch mode {
        case "counts":
            guard let categories = config["categories"] as? [String] else { return [] }
            let countsKey = config["source"] as? String ?? ""
            let selectionKey = config["selectionKey"] as? String ?? ""
            let counts = assessment[countsKey] as? [String: Any] ?? [:]
            let selected = assessment[selectionKey] as? [String] ?? []

            var rows: [[String: Any]] = []
            for category in categories where selected.contains(category) {
                let count = max((counts[category] as? NSNumber)?.intValue ?? 1, 1)
                let slug = Self.rowSlug(category)
                for ordinal in 1...count {
                    rows.append([
                        "id": "\(slug)_\(ordinal)",
                        "category": category,
                        "subjectId": UUID().uuidString
                    ])
                }
            }
            return rows

        case "flag":
            guard let rowId = config["rowId"] as? String,
                  let source = config["source"] as? String,
                  (assessment[source] as? String)?.lowercased() == "yes" else { return [] }
            return [["id": rowId, "subjectId": UUID().uuidString]]

        case "accessRows":
            var rows: [[String: Any]] = (config["always"] as? [String] ?? []).map {
                ["id": $0, "subjectId": UUID().uuidString]
            }
            for conditional in config["conditional"] as? [[String: Any]] ?? [] {
                guard let rowId = conditional["rowId"] as? String,
                      let key = conditional["key"] as? String,
                      let expected = conditional["equals"] as? String else { continue }
                if (assessment[key] as? String) == expected {
                    rows.append(["id": rowId, "subjectId": UUID().uuidString])
                }
            }
            return rows

        default:
            return []
        }
    }

    private static func rowSlug(_ category: String) -> String {
        category.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { result, char in
                if char == "_" && result.hasSuffix("_") { return }
                result.append(char)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // MARK: - Spec 09 Legacy-Client Gate

    /// The 7 _NUDGE rows carry `requiresClientV2:["true"]` so legacy clients
    /// fail-false on the unknown key and never generate them. This client
    /// understands the nudge tier — strip the gate key before evaluation
    /// (a gate-only conditions map becomes empty = auto-pass).
    static func evaluableConditions(_ conditions: [String: Any]?) -> [String: Any]? {
        guard var conditions else { return nil }
        conditions.removeValue(forKey: "requiresClientV2")
        return conditions
    }

    // MARK: - Spec 09 Tier / Nudge Metadata

    /// Stamps `tier` (when the row carries one) and nudge card metadata onto
    /// the user task doc so the mapper renders nudges without a catalog read.
    private func stampTierAndNudgeMetadata(
        from taskData: [String: Any],
        onto userTask: inout [String: Any]
    ) {
        if let tier = taskData["tier"] as? String {
            userTask["tier"] = tier
        }
        if let nudge = taskData["nudge"] as? [String: Any] {
            if let prompt = nudge["cardPrompt"] as? String {
                userTask["nudgePrompt"] = prompt
            }
            if let spawnsId = nudge["spawnsId"] as? String {
                userTask["nudgeSpawnsId"] = spawnsId
            }
        }
    }

    // MARK: - Spec 09 Due Dates

    /// One date path for BOTH generation loops: a nudge row's dueDate is its
    /// spawn target's computed date minus leadDays (default 2); every other
    /// row uses its own dateRule override or the existing urgency math.
    private func resolvedDueDate(
        for taskData: [String: Any],
        catalogIndex: [String: [String: Any]],
        moveDate: Date
    ) -> Date {
        if let nudge = taskData["nudge"] as? [String: Any] {
            let leadDays = (nudge["leadDays"] as? NSNumber)?.intValue ?? 2
            let target = (nudge["spawnsId"] as? String).flatMap { catalogIndex[$0] } ?? taskData
            let targetDate = rowDueDate(for: target, moveDate: moveDate)
            return Calendar.current.date(byAdding: .day, value: -leadDays, to: targetDate) ?? targetDate
        }
        return rowDueDate(for: taskData, moveDate: moveDate)
    }

    /// A row's own date: `dateRule` `{anchor:"moveDate", offsetDays:N}`
    /// override when present, else the urgency-timeline math.
    private func rowDueDate(for taskData: [String: Any], moveDate: Date) -> Date {
        if let dateRule = taskData["dateRule"] as? [String: Any],
           let offsetDays = (dateRule["offsetDays"] as? NSNumber)?.intValue {
            let anchor = Calendar.current.startOfDay(for: moveDate)
            return Calendar.current.date(byAdding: .day, value: offsetDays, to: anchor) ?? anchor
        }
        let urgency = (taskData["urgencyPercentage"] as? NSNumber)?.intValue ?? 50
        return calculateDueDate(moveDate: moveDate, urgencyPercentage: urgency)
    }

    // MARK: - Due Date Calculation

    /// Calculates task due date based on urgency percentage
    /// Higher percentage (90+) = MORE urgent = do it EARLY (within first 10% of timeline)
    /// Lower percentage (10) = LESS urgent = can wait (90% into timeline)
    /// - Parameters:
    ///   - moveDate: User's move date
    ///   - urgencyPercentage: Task urgency (1-99)
    /// - Returns: Calculated due date
    private func calculateDueDate(
        moveDate: Date,
        urgencyPercentage: Int
    ) -> Date {
        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
        let moveDateStart = Calendar.current.startOfDay(for: moveDate)
        let totalDays = Calendar.current.dateComponents([.day], from: today, to: moveDateStart).day ?? 0

        // Guard against past/same-day moves
        guard totalDays > 0 else { return today }

        // HIGH urgency (90+) = do it EARLY (within first 10% of timeline)
        // LOW urgency (10) = can wait (90% into timeline)
        let daysFromNow = Double(totalDays) * (1.0 - Double(urgencyPercentage) / 100.0)
        var dueDate = Calendar.current.date(byAdding: .day, value: Int(daysFromNow), to: today) ?? moveDate

        // Never schedule in the past
        if dueDate < today {
            dueDate = today
        }

        return dueDate
    }
}

enum TaskGenerationWriteError: LocalizedError {
    case transactionLimit
    case resetActive
    case missingResult
    case missingCandidateID

    var errorDescription: String? {
        switch self {
        case .transactionLimit: "Too many task candidates for one safe transaction."
        case .resetActive: "Task generation is paused while assessment reset is active."
        case .missingResult: "Task generation transaction returned no result."
        case .missingCandidateID: "Task generation candidate is missing its stable task ID."
        }
    }
}
