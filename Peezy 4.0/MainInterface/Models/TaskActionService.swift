import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firestore write side of task actions (Spec 03 Phases B–C). Bodies of the
/// status/snooze/complete writes are moved VERBATIM from PeezyHomeViewModel —
/// the update payloads are load-bearing; do not change field names or shapes.
struct TaskActionService {

    /// Persists the workflow spine stage on the task doc — direct write,
    /// matching the existing status-write pattern (no callable).
    func setStage(taskId: String, stage: TaskStage) async {
        // Empty path segments raise uncatchable ObjC exceptions in Firestore —
        // guard like the sibling flow-state writes do.
        guard let userId = Auth.auth().currentUser?.uid, !taskId.isEmpty else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(taskId).updateData(["stage": stage.rawValue])
        } catch {
            print("⚠️ Failed to set stage: \(error.localizedDescription)")
        }
    }

    /// Persists FlowEngine progress on the task doc (Spec 04 Phase A):
    /// `flowPath` is the visited step-id trail (last = current step) and
    /// `flowAnswers.{key}` the per-step answer. Same direct-write pattern
    /// as setStage. Cleared on flow terminals via clearFlowState.
    func writeFlowProgress(
        userId: String,
        taskId: String,
        path: [String],
        answers: [String: [String]]
    ) async throws {
        guard !userId.isEmpty, !taskId.isEmpty else {
            throw FlowProgressPersistenceError.missingIdentity
        }
        let db = Firestore.firestore()
        try await db.collection("users").document(userId).collection("tasks")
            .document(taskId).updateData([
                "flowPath": path,
                "flowAnswers": answers
            ])
    }

    func loadFlowProgress(userId: String, taskId: String) async throws -> FlowProgressSnapshot {
        guard !userId.isEmpty, !taskId.isEmpty else {
            throw FlowProgressPersistenceError.missingIdentity
        }
        let document = try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskId)
            .getDocument()
        let data = document.data() ?? [:]
        return FlowProgressSnapshot(
            path: data["flowPath"] as? [String] ?? [],
            answers: (data["flowAnswers"] as? [String: Any])?
                .compactMapValues { $0 as? [String] } ?? [:]
        )
    }

    /// Removes persisted flow state so the next open starts fresh — fired on
    /// summary submission and status-card terminals (matches the pre-engine
    /// "reopen starts over" semantics once a flow has concluded).
    func clearFlowState(taskId: String) async {
        guard let userId = Auth.auth().currentUser?.uid, !taskId.isEmpty else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(taskId).updateData([
                    "flowPath": FieldValue.delete(),
                    "flowAnswers": FieldValue.delete()
                ])
        } catch {
            print("⚠️ Failed to clear flow state: \(error.localizedDescription)")
        }
    }

    /// Terminal nudge-lifecycle writes (Spec 09 Phase 3): "Dismissed" /
    /// "Converted". Same direct-write pattern as the sibling status writes.
    func setStatus(taskId: String, status: String) async {
        guard let userId = Auth.auth().currentUser?.uid, !taskId.isEmpty else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(taskId).updateData(["status": status])
        } catch {
            print("⚠️ Failed to set status \(status): \(error.localizedDescription)")
        }
    }

    func markTaskCompleted(_ task: PeezyCard) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(task.id).updateData(["status": "Completed", "completedAt": FieldValue.serverTimestamp()])
        } catch {
            print("⚠️ Failed to mark task completed: \(error.localizedDescription)")
        }
    }

    func markTaskInProgress(_ task: PeezyCard) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(task.id).updateData(["status": "InProgress", "inProgressAt": FieldValue.serverTimestamp()])
        } catch {
            print("⚠️ Failed to mark task in progress: \(error.localizedDescription)")
        }
    }

    func writeUserInProgress(_ task: PeezyCard, returnDate: Date) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(task.id).updateData([
                    "status": "UserInProgress",
                    "userInProgressDate": Timestamp(date: Date()),
                    "userInProgressReturnDate": Timestamp(date: returnDate)
                ])
        } catch {
            print("⚠️ Failed to mark task as user in progress: \(error.localizedDescription)")
        }
    }

    func writeSnooze(_ task: PeezyCard, snoozedUntil: Date) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(task.id).updateData([
                    "status": "Snoozed",
                    "snoozedUntil": Timestamp(date: snoozedUntil),
                    "lastSnoozedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("⚠️ Failed to snooze task: \(error.localizedDescription)")
        }
    }

    // MARK: - Packing plan

    /// Generates and atomically persists the plan plus its catalog-external
    /// task documents. Stable source keys preserve completed sessions across
    /// move-date and inventory regeneration.
    @discardableResult
    func generatePackingPlan(
        userId: String,
        rooms: [ScannedRoom],
        moveDate: Date,
        today: Date = Date()
    ) async throws -> PackingPlan {
        guard !userId.isEmpty else { throw PackingPlanPersistenceError.missingUser }
        async let previousRequest = loadPackingPlan(userId: userId)
        async let packingConfigurationRequest = loadPackingConfiguration()
        async let supplyRatesRequest = loadSupplyRates()
        let (previous, packingConfiguration, supplyRates) = try await (
            previousRequest,
            packingConfigurationRequest,
            supplyRatesRequest
        )
        let inputs = rooms.map { room in
            PackingRoomInput(
                name: room.name,
                items: room.items
                    .filter(\.shouldMove)
                    .map {
                        PackingPlanItem(
                            name: $0.name,
                            category: $0.category,
                            quantity: $0.quantity,
                            cubicFeet: $0.cubicFeet,
                            tier: $0.tier
                        )
                    }
            )
        }
        let plan = PackingPlanEngine.generate(
            rooms: inputs,
            moveDate: moveDate,
            today: today,
            configuration: packingConfiguration,
            preserving: previous
        )
        var suppliesKit = KitEstimator.estimate(
            items: rooms.flatMap { room in
                room.items.filter(\.shouldMove).map { item in
                    KitInventoryItem(
                        name: item.name,
                        category: item.category,
                        roomName: room.name,
                        tier: item.tier,
                        sizeEstimate: item.sizeEstimate,
                        quantity: item.quantity,
                        cubicFeet: item.cubicFeet,
                        isFragile: item.isFragile
                    )
                }
            },
            supplyRates: supplyRates
        )
        if let firstSessionDate = plan.sessions.map(\.scheduledDate).min() {
            suppliesKit.deliveryBy = Calendar.current.date(
                byAdding: .day,
                value: -packingConfiguration.suppliesDeliveryBufferDays,
                to: firstSessionDate
            )
        }
        try await persist(
            plan,
            suppliesKit: suppliesKit,
            userId: userId,
            packingConfiguration: packingConfiguration
        )
        if previous == nil {
            AnalyticsEvents.packingPlanCreated()
        }
        return plan
    }

    /// Move-date regeneration path used by IdentityService.update. A user can
    /// have identity before inventory; no inventory means there is no plan yet.
    @discardableResult
    func regeneratePackingPlanFromStoredInventory(
        userId: String,
        moveDate: Date,
        today: Date = Date()
    ) async throws -> PackingPlan? {
        let rooms = try await loadStoredInventory(userId: userId)
        guard !rooms.isEmpty else { return nil }
        return try await generatePackingPlan(
            userId: userId,
            rooms: rooms,
            moveDate: moveDate,
            today: today
        )
    }

    /// Home-load reconciliation: regenerate if the authoritative move date
    /// changed, otherwise silently reflow past-dated incomplete sessions.
    func syncPackingPlanForLoad(
        userId: String,
        moveDate: Date,
        today: Date = Date()
    ) async throws {
        guard let current = try await loadPackingPlan(userId: userId) else { return }
        let calendar = Calendar.current
        if calendar.startOfDay(for: current.moveDate) != calendar.startOfDay(for: moveDate) {
            _ = try await regeneratePackingPlanFromStoredInventory(
                userId: userId,
                moveDate: moveDate,
                today: today
            )
            return
        }

        let configuration = try await loadPackingConfiguration()
        let reflowed = PackingPlanEngine.reflowIfNeeded(
            current,
            today: today,
            configuration: configuration
        )
        if reflowed != current {
            try await persist(
                reflowed,
                userId: userId,
                packingConfiguration: configuration
            )
        }
    }

    func loadPackingSession(userId: String, taskId: String) async throws -> PackingSession {
        guard !userId.isEmpty, !taskId.isEmpty else { throw PackingPlanPersistenceError.sessionNotFound }
        guard let session = try await loadPackingPlan(userId: userId)?.sessions.first(where: { $0.taskId == taskId }) else {
            throw PackingPlanPersistenceError.sessionNotFound
        }
        return session
    }

    func loadSuppliesKit(userId: String, taskId: String = SuppliesKit.taskId) async throws -> SuppliesKit {
        guard !userId.isEmpty else { throw PackingPlanPersistenceError.kitNotFound }
        let currentRates = try await loadSupplyRates()
        let snapshot = try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskId)
            .getDocument()
        guard let data = snapshot.data(),
              let rawKit = data["suppliesKit"] as? [String: Any],
              let kit = decodeSuppliesKit(from: rawKit, currentRates: currentRates) else {
            throw PackingPlanPersistenceError.kitNotFound
        }
        return kit
    }

    func loadSuppliesKitState(
        userId: String,
        taskId: String = SuppliesKit.taskId
    ) async throws -> (kit: SuppliesKit, wasCustomized: Bool) {
        guard !userId.isEmpty else { throw PackingPlanPersistenceError.kitNotFound }
        let currentRates = try await loadSupplyRates()
        let snapshot = try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskId)
            .getDocument()
        guard let data = snapshot.data(),
              let rawKit = data["suppliesKit"] as? [String: Any],
              let kit = decodeSuppliesKit(from: rawKit, currentRates: currentRates) else {
            throw PackingPlanPersistenceError.kitNotFound
        }
        return (kit, data["kitCustomizedAt"] != nil)
    }

    func updateSuppliesKit(userId: String, taskId: String, kit: SuppliesKit) async throws {
        guard !userId.isEmpty, !taskId.isEmpty else { throw PackingPlanPersistenceError.kitNotFound }
        var normalizedKit = kit
        normalizedKit.clampToNonnegative()
        try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskId)
            .updateData([
                "suppliesKit": suppliesKitData(normalizedKit),
                "desc": normalizedKit.itemizedSummary,
                "kitCustomizedAt": FieldValue.serverTimestamp()
            ])
    }

    /// `No thanks` removes the one-time offer from Home permanently while
    /// retaining an explicit, reopenable row under "You're on it" in Tasks.
    func dismissSuppliesKit(userId: String, taskId: String) async throws {
        guard !userId.isEmpty, !taskId.isEmpty else { throw PackingPlanPersistenceError.kitNotFound }
        try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskId)
            .updateData([
                "status": "UserInProgress",
                "kitDismissedAt": FieldValue.serverTimestamp(),
                "userInProgressDate": FieldValue.serverTimestamp(),
                "userInProgressReturnDate": FieldValue.delete()
            ])
    }

    // MARK: - Packing readiness

    func loadReadinessGate(
        userId: String,
        taskId: String = ReadinessChecklist.taskId
    ) async throws -> ReadinessGateRecord {
        guard !userId.isEmpty, !taskId.isEmpty else {
            throw PackingPlanPersistenceError.readinessNotFound
        }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        async let taskSnapshot = userRef.collection("tasks").document(taskId).getDocument()
        async let readinessSnapshot = readinessRef(db: db, userId: userId).getDocument()
        async let plan = loadPackingPlan(userId: userId)

        let (taskDocument, readinessDocument, packingPlan) = try await (
            taskSnapshot,
            readinessSnapshot,
            plan
        )
        guard let scheduledDate = (taskDocument.data()?["dueDate"] as? Timestamp)?.dateValue() else {
            throw PackingPlanPersistenceError.readinessNotFound
        }

        if let data = readinessDocument.data(),
           let rawItems = data["items"] as? [String: Any] {
            let items = rawItems.compactMapValues { $0 as? Bool }
            let checklist = ReadinessChecklist(items: items)
            return ReadinessGateRecord(
                checklist: checklist,
                scheduledDate: scheduledDate,
                completedAt: checklist.isComplete
                    ? (data["completedAt"] as? Timestamp)?.dateValue()
                    : nil
            )
        }

        let reservationPrefill = await hasCompletedReserveAccessAnswers(
            db: db,
            userId: userId
        )
        let checklist = ReadinessChecklist(
            allSessionsComplete: packingPlan?.sessions.allSatisfy(\.isCompleted) == true,
            accessReserved: reservationPrefill
        )
        let record = ReadinessGateRecord(
            checklist: checklist,
            scheduledDate: scheduledDate,
            completedAt: nil
        )
        try await saveReadinessGate(userId: userId, record: record)
        return record
    }

    func saveReadinessGate(userId: String, record: ReadinessGateRecord) async throws {
        guard !userId.isEmpty else { throw PackingPlanPersistenceError.readinessNotFound }

        let db = Firestore.firestore()
        let batch = db.batch()
        let completedAt = record.checklist.isComplete ? (record.completedAt ?? Date()) : nil

        // LOCKED purpose: this persisted checklist is the vendor-accountability
        // evidence layer for explaining moving-day overages after the fact.
        var readinessData: [String: Any] = [
            "items": record.checklist.items,
            "scheduledDate": Timestamp(date: record.scheduledDate),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let completedAt {
            readinessData["completedAt"] = Timestamp(date: completedAt)
        } else {
            readinessData["completedAt"] = FieldValue.delete()
        }
        batch.setData(
            readinessData,
            forDocument: readinessRef(db: db, userId: userId),
            merge: true
        )

        var taskData: [String: Any] = [
            "status": record.checklist.isComplete ? "Completed" : "Upcoming"
        ]
        if let completedAt {
            taskData["completedAt"] = Timestamp(date: completedAt)
        } else {
            taskData["completedAt"] = FieldValue.delete()
        }
        batch.updateData(
            taskData,
            forDocument: db.collection("users").document(userId)
                .collection("tasks").document(ReadinessChecklist.taskId)
        )
        try await batch.commit()
    }

    /// Plan and task completion land in one batch so regeneration never loses
    /// a completion that the task row already showed.
    func completePackingSession(
        userId: String,
        taskId: String,
        completedAt: Date = Date()
    ) async throws -> PackingCompletion {
        guard !userId.isEmpty, !taskId.isEmpty else { throw PackingPlanPersistenceError.sessionNotFound }
        guard let plan = try await loadPackingPlan(userId: userId),
              let completion = PackingPlanEngine.completion(
                afterCompleting: taskId,
                in: plan,
                at: completedAt
              ) else { throw PackingPlanPersistenceError.sessionNotFound }

        let db = Firestore.firestore()
        let batch = db.batch()
        batch.setData(
            packingPlanData(completion.plan),
            forDocument: packingPlanRef(db: db, userId: userId)
        )
        batch.updateData([
            "status": "Completed",
            "completedAt": Timestamp(date: completedAt),
            "packingSession.completedAt": Timestamp(date: completedAt)
        ], forDocument: db.collection("users").document(userId).collection("tasks").document(taskId))
        try await batch.commit()
        return completion.result
    }

    func loadPackingPlan(userId: String) async throws -> PackingPlan? {
        guard !userId.isEmpty else { return nil }
        let db = Firestore.firestore()
        let snapshot = try await packingPlanRef(db: db, userId: userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return packingPlan(from: data)
    }

    func clearPackingPlan(userId: String) async throws {
        guard !userId.isEmpty else { return }
        let db = Firestore.firestore()
        let tasks = try await db.collection("users").document(userId).collection("tasks")
            .whereField("generatedBy", isEqualTo: "packingPlan")
            .getDocuments()
        let batch = db.batch()
        batch.deleteDocument(packingPlanRef(db: db, userId: userId))
        batch.deleteDocument(readinessRef(db: db, userId: userId))
        for task in tasks.documents { batch.deleteDocument(task.reference) }
        try await batch.commit()
    }

    // MARK: Packing plan persistence helpers

    private func persist(
        _ plan: PackingPlan,
        suppliesKit: SuppliesKit? = nil,
        userId: String,
        packingConfiguration: PackingConfiguration
    ) async throws {
        let db = Firestore.firestore()
        let taskCollection = db.collection("users").document(userId).collection("tasks")
        let existing = try await taskCollection
            .whereField("generatedBy", isEqualTo: "packingPlan")
            .getDocuments()
        let existingById = Dictionary(uniqueKeysWithValues: existing.documents.map { ($0.documentID, $0.data()) })
        let existingByKey = Dictionary(
            uniqueKeysWithValues: existing.documents.compactMap { document -> (String, [String: Any])? in
                guard let payload = document.data()["packingSession"] as? [String: Any],
                      let key = payload["sessionKey"] as? String else { return nil }
                return (key, document.data())
            }
        )

        let batch = db.batch()
        batch.setData(packingPlanData(plan), forDocument: packingPlanRef(db: db, userId: userId))

        let newIds = Set(plan.sessions.map(\.taskId))
        for old in existing.documents
        where old.documentID.hasPrefix("PACKING_SESSION_") && !newIds.contains(old.documentID) {
            batch.deleteDocument(old.reference)
        }
        for session in plan.sessions {
            let previousData = existingById[session.taskId] ?? existingByKey[session.sessionKey]
            batch.setData(
                packingTaskData(session, previousData: previousData),
                forDocument: taskCollection.document(session.taskId)
            )
        }

        let previousReadiness = existingById[ReadinessChecklist.taskId]
        let readinessDate = readinessScheduledDate(
            moveDate: plan.moveDate,
            configuration: packingConfiguration
        )
        batch.setData(
            readinessTaskData(
                scheduledDate: readinessDate,
                previousData: previousReadiness
            ),
            forDocument: taskCollection.document(ReadinessChecklist.taskId)
        )
        if let oldDate = (previousReadiness?["dueDate"] as? Timestamp)?.dateValue(),
           Calendar.current.startOfDay(for: oldDate) != Calendar.current.startOfDay(for: readinessDate) {
            batch.deleteDocument(readinessRef(db: db, userId: userId))
        }
        if let suppliesKit {
            let previousData = existingById[SuppliesKit.taskId]
            let resolvedKit: SuppliesKit
            if previousData?["kitCustomizedAt"] != nil,
               let rawKit = previousData?["suppliesKit"] as? [String: Any],
               var customized = decodeSuppliesKit(
                   from: rawKit,
                   currentRates: suppliesKit.supplyRates
               ) {
                customized.deliveryBy = suppliesKit.deliveryBy
                resolvedKit = customized
            } else {
                resolvedKit = suppliesKit
            }
            batch.setData(
                suppliesKitTaskData(resolvedKit, previousData: previousData),
                forDocument: taskCollection.document(SuppliesKit.taskId),
                merge: true
            )
            // TRANSFORM successor: a generated kit replaces the legacy task
            // for this user as well as retiring it from the catalog.
            batch.deleteDocument(taskCollection.document("BUY_PACKING_SUPPLIES"))
        }
        try await batch.commit()
    }

    private func loadPackingConfiguration() async throws -> PackingConfiguration {
        let snapshot = try await Firestore.firestore()
            .collection("appConfig").document("packing")
            .getDocument()
        guard let data = snapshot.data(),
              let configuration = PackingConfiguration(firestoreData: data)
        else {
            throw PackingPlanPersistenceError.configurationUnavailable("packing")
        }
        return configuration
    }

    private func loadSupplyRates() async throws -> SupplyRates {
        let snapshot = try await Firestore.firestore()
            .collection("appConfig").document("supplyRates")
            .getDocument()
        guard let data = snapshot.data(),
              let rates = SupplyRates(configData: data)
        else {
            throw PackingPlanPersistenceError.configurationUnavailable("supply rates")
        }
        return rates
    }

    private func loadStoredInventory(userId: String) async throws -> [ScannedRoom] {
        let snapshot = try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("inventory")
            .getDocuments()

        return snapshot.documents.compactMap { document in
            guard document.documentID != "_metadata" else { return nil }
            let data = document.data()
            guard let name = data["name"] as? String ?? data["roomName"] as? String else { return nil }
            let items = (data["items"] as? [[String: Any]] ?? []).compactMap(InventoryItem.from(dict:))
            return ScannedRoom(
                id: data["id"] as? String ?? document.documentID,
                name: name,
                items: items,
                scannedAt: (data["scannedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }

    private func packingPlanRef(db: Firestore, userId: String) -> DocumentReference {
        // NEEDS-CLARIFICATION: the spec's users/{uid}/packingPlan shorthand
        // needs a concrete Firestore document id. This mirrors identity/identity.
        db.collection("users").document(userId)
            .collection("packingPlan").document("current")
    }

    private func readinessRef(db: Firestore, userId: String) -> DocumentReference {
        // NEEDS-CLARIFICATION: the spec's users/{uid}/readiness shorthand
        // needs a concrete document id. This mirrors packingPlan/current.
        db.collection("users").document(userId)
            .collection("readiness").document("current")
    }

    private func readinessScheduledDate(
        moveDate: Date,
        configuration: PackingConfiguration
    ) -> Date {
        let calendar = Calendar.current
        let moveDay = calendar.startOfDay(for: moveDate)
        return calendar.date(
            byAdding: .day,
            value: -configuration.moveDayBufferDays,
            to: moveDay
        ) ?? moveDay
    }

    private func packingPlanData(_ plan: PackingPlan) -> [String: Any] {
        var data: [String: Any] = [
            "moveDate": Timestamp(date: plan.moveDate),
            "generatedAt": Timestamp(date: plan.generatedAt),
            "sessions": plan.sessions.map(packingSessionData)
        ]
        if let reflowedAt = plan.reflowedAt {
            data["reflowedAt"] = Timestamp(date: reflowedAt)
        }
        return data
    }

    private func packingSessionData(_ session: PackingSession) -> [String: Any] {
        var data: [String: Any] = [
            "taskId": session.taskId,
            "sessionKey": session.sessionKey,
            "sourceKeys": session.sourceKeys,
            "rooms": session.rooms,
            "roomLabel": session.roomLabel,
            "estMinutes": session.estMinutes,
            "scheduledDate": Timestamp(date: session.scheduledDate),
            "itemSummary": session.itemSummary,
            "isFirstNightBag": session.isFirstNightBag,
            "isBehindPace": session.isBehindPace
        ]
        if let completedAt = session.completedAt {
            data["completedAt"] = Timestamp(date: completedAt)
        }
        return data
    }

    private func packingTaskData(
        _ session: PackingSession,
        previousData: [String: Any]?
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": session.taskId,
            "taskId": session.taskId,
            "workflowId": "packing_session",
            "title": "Today: \(session.roomLabel). About \(session.estMinutes) minutes.",
            "desc": "Here's what's in it: \(session.itemSummary.joined(separator: ", "))",
            "category": "packing",
            "actionCategory": "packing",
            "actionType": "in-app",
            "taskType": "provide_info",
            "urgencyPercentage": 80,
            "estHours": Double(session.estMinutes) / 60.0,
            "tips": "Pack only this session. Peezy will reflow the rest if plans change.",
            "whyNeeded": "One focused packing session keeps moving day on pace.",
            "dueDate": Timestamp(date: session.scheduledDate),
            "status": session.isCompleted ? "Completed" : "Upcoming",
            "selfServiceOnly": true,
            "generatedBy": "packingPlan",
            "createdAt": previousData?["createdAt"] ?? FieldValue.serverTimestamp(),
            "packingSession": packingSessionData(session)
        ]

        if let completedAt = session.completedAt {
            data["completedAt"] = Timestamp(date: completedAt)
        } else if let previousData,
                  let status = previousData["status"] as? String,
                  status == "Snoozed" || status == "UserInProgress" {
            data["status"] = status
            for key in ["snoozedUntil", "lastSnoozedAt", "userInProgressDate", "userInProgressReturnDate"] {
                if let value = previousData[key] { data[key] = value }
            }
        }
        return data
    }

    private func readinessTaskData(
        scheduledDate: Date,
        previousData: [String: Any]?
    ) -> [String: Any] {
        let previousDate = (previousData?["dueDate"] as? Timestamp)?.dateValue()
        let sameDate = previousDate.map {
            Calendar.current.startOfDay(for: $0) == Calendar.current.startOfDay(for: scheduledDate)
        } ?? false
        let preservedStatus = sameDate ? previousData?["status"] as? String : nil

        var data: [String: Any] = [
            "id": ReadinessChecklist.taskId,
            "taskId": ReadinessChecklist.taskId,
            "workflowId": "packing_readiness",
            "title": "Final moving-day readiness check",
            "desc": "Confirm packing, furniture, building access, a clear path, and your first-night bag.",
            "category": "packing",
            "actionCategory": "packing",
            "actionType": "in-app",
            "taskType": "provide_info",
            "urgencyPercentage": 99,
            "estHours": 0.1,
            "tips": "Tap each item as it becomes ready. Nothing here blocks your move.",
            "whyNeeded": "This record is what keeps your estimate honest if move day runs long.",
            "dueDate": Timestamp(date: scheduledDate),
            "status": preservedStatus ?? "Upcoming",
            "selfServiceOnly": true,
            "generatedBy": "packingPlan",
            "createdAt": previousData?["createdAt"] ?? FieldValue.serverTimestamp()
        ]
        if sameDate, let completedAt = previousData?["completedAt"] {
            data["completedAt"] = completedAt
        }
        if sameDate,
           let status = previousData?["status"] as? String,
           status == "Snoozed" || status == "UserInProgress" {
            data["status"] = status
            for key in ["snoozedUntil", "lastSnoozedAt", "userInProgressDate", "userInProgressReturnDate"] {
                if let value = previousData?[key] { data[key] = value }
            }
        }
        return data
    }

    private func hasCompletedReserveAccessAnswers(
        db: Firestore,
        userId: String
    ) async -> Bool {
        let userRef = db.collection("users").document(userId)
        let pairs = [
            (taskId: "RESERVE_ACCESS_OLD", workflowId: "reserve_access_old"),
            (taskId: "RESERVE_ACCESS_NEW", workflowId: "reserve_access_new")
        ]

        var taskExists: [String: Bool] = [:]
        var responseExists: [String: Bool] = [:]
        for pair in pairs {
            let task = try? await userRef.collection("tasks").document(pair.taskId).getDocument()
            let response = try? await userRef.collection("workflowResponses")
                .document(pair.workflowId).getDocument()
            let status = task?.data()?["status"] as? String
            taskExists[pair.taskId] = task?.exists == true && status != "Skipped"
            responseExists[pair.taskId] = response?.data()?["answers"] != nil
        }

        let applicable = pairs.filter { taskExists[$0.taskId] == true }
        if !applicable.isEmpty {
            return applicable.allSatisfy { responseExists[$0.taskId] == true }
        }
        return pairs.contains { responseExists[$0.taskId] == true }
    }

    private func suppliesKitTaskData(
        _ kit: SuppliesKit,
        previousData: [String: Any]?
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": SuppliesKit.taskId,
            "taskId": SuppliesKit.taskId,
            "workflowId": "supplies_kit",
            "title": "Your packing supplies kit",
            "desc": kit.itemizedSummary,
            "category": "packing",
            "actionCategory": "purchase-get",
            "actionType": "in-app",
            "taskType": "provide_info",
            "urgencyPercentage": 86,
            "estHours": 0.1,
            "tips": "Includes a few extra — running out mid-pack is worse than spares.",
            "whyNeeded": "The right supplies arrive before packing starts, without a mid-session store run.",
            "status": previousData?["status"] as? String ?? "Upcoming",
            "selfServiceOnly": false,
            "generatedBy": "packingPlan",
            "createdAt": previousData?["createdAt"] ?? FieldValue.serverTimestamp(),
            "suppliesKit": suppliesKitData(kit)
        ]
        if let deliveryBy = kit.deliveryBy {
            data["dueDate"] = Timestamp(date: deliveryBy)
        } else {
            data["dueDate"] = FieldValue.serverTimestamp()
        }
        return data
    }

    private func suppliesKitData(_ kit: SuppliesKit) -> [String: Any] {
        var data: [String: Any] = [
            "small": kit.small,
            "medium": kit.medium,
            "large": kit.large,
            "wardrobe": kit.wardrobe,
            "dishPack": kit.dishPack,
            "tape": kit.tape,
            "paper": kit.paper,
            "wrap": kit.wrap,
            "mattressBags": kit.mattressBags,
            "headroomPercent": KitConstants.headroomPercent,
            "totalPriceCents": kit.totalPriceCents,
            "supplyRatesCents": kit.supplyRates.persistedCents
        ]
        if let deliveryBy = kit.deliveryBy {
            data["deliveryBy"] = Timestamp(date: deliveryBy)
        }
        return data
    }

    private func decodeSuppliesKit(
        from data: [String: Any],
        currentRates: SupplyRates
    ) -> SuppliesKit? {
        let keys = ["small", "medium", "large", "wardrobe", "dishPack", "tape", "paper", "wrap", "mattressBags"]
        guard keys.allSatisfy({ data[$0] is NSNumber }) else { return nil }
        let persistedRates = (data["supplyRatesCents"] as? [String: Any])
            .flatMap(SupplyRates.init(persistedCents:))
        return SuppliesKit(
            small: (data["small"] as? NSNumber)?.intValue ?? 0,
            medium: (data["medium"] as? NSNumber)?.intValue ?? 0,
            large: (data["large"] as? NSNumber)?.intValue ?? 0,
            wardrobe: (data["wardrobe"] as? NSNumber)?.intValue ?? 0,
            dishPack: (data["dishPack"] as? NSNumber)?.intValue ?? 0,
            tape: (data["tape"] as? NSNumber)?.intValue ?? 0,
            paper: (data["paper"] as? NSNumber)?.intValue ?? 0,
            wrap: (data["wrap"] as? NSNumber)?.intValue ?? 0,
            mattressBags: (data["mattressBags"] as? NSNumber)?.intValue ?? 0,
            deliveryBy: (data["deliveryBy"] as? Timestamp)?.dateValue(),
            supplyRates: persistedRates ?? currentRates
        )
    }

    private func packingPlan(from data: [String: Any]) -> PackingPlan? {
        guard let moveDate = data["moveDate"] as? Timestamp,
              let generatedAt = data["generatedAt"] as? Timestamp,
              let rawSessions = data["sessions"] as? [[String: Any]] else { return nil }
        let sessions = rawSessions.compactMap(packingSession(from:))
        guard sessions.count == rawSessions.count else { return nil }
        return PackingPlan(
            moveDate: moveDate.dateValue(),
            generatedAt: generatedAt.dateValue(),
            reflowedAt: (data["reflowedAt"] as? Timestamp)?.dateValue(),
            sessions: sessions
        )
    }

    private func packingSession(from data: [String: Any]) -> PackingSession? {
        guard let taskId = data["taskId"] as? String,
              let sessionKey = data["sessionKey"] as? String,
              let roomLabel = data["roomLabel"] as? String,
              let scheduledDate = data["scheduledDate"] as? Timestamp,
              let estMinutes = (data["estMinutes"] as? NSNumber)?.intValue
        else { return nil }
        return PackingSession(
            taskId: taskId,
            sessionKey: sessionKey,
            sourceKeys: data["sourceKeys"] as? [String] ?? [sessionKey],
            rooms: data["rooms"] as? [String] ?? [roomLabel],
            roomLabel: roomLabel,
            estMinutes: estMinutes,
            scheduledDate: scheduledDate.dateValue(),
            itemSummary: data["itemSummary"] as? [String] ?? [],
            isFirstNightBag: data["isFirstNightBag"] as? Bool ?? false,
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue(),
            isBehindPace: data["isBehindPace"] as? Bool ?? false
        )
    }
}

enum PackingPlanPersistenceError: LocalizedError {
    case missingUser
    case missingMoveDate
    case sessionNotFound
    case kitNotFound
    case readinessNotFound
    case configurationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingUser: return "A signed-in user is required to create a packing plan."
        case .missingMoveDate: return "Add a move date before creating a packing plan."
        case .sessionNotFound: return "That packing session is no longer available."
        case .kitNotFound: return "That packing supplies kit is no longer available."
        case .readinessNotFound: return "That moving-day readiness check is no longer available."
        case .configurationUnavailable(let name):
            return "The latest \(name) configuration could not be loaded. Try again when you're online."
        }
    }
}
