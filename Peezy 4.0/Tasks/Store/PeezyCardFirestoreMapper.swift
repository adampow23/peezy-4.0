import FirebaseFirestore
import Foundation

enum PeezyCardFirestoreMapper {
    /// THE single Firestore→PeezyCard decode path (successor to the LE-025/031
    /// parity rule). Home (PeezyHomeViewModel.loadTasks) and the Tasks tab
    /// (TasksStore listener) BOTH decode through this function — do not add a
    /// second path or re-inline field decoding at a call site.
    static func card(from document: QueryDocumentSnapshot) -> PeezyCard? {
        card(from: document.data(), documentID: document.documentID)
    }

    /// Data-shaped entry so unit fixtures can decode without a live snapshot.
    /// Still the one path — the snapshot overload above delegates here.
    static func card(from data: [String: Any], documentID: String) -> PeezyCard? {
        let statusString = data["status"] as? String ?? "Upcoming"
        let status = TaskStatus(rawValue: statusString) ?? .upcoming

        let priorityString = data["priority"] as? String ?? "Medium"
        let priority: PeezyCard.Priority
        switch priorityString.lowercased() {
        case "high", "urgent":
            priority = .high
        case "low":
            priority = .low
        default:
            priority = .normal
        }

        let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
        let snoozedUntil = (data["snoozedUntil"] as? Timestamp)?.dateValue()
        let lastSnoozedAt = (data["lastSnoozedAt"] as? Timestamp)?.dateValue()
        let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        let urgencyPercentage = (data["urgencyPercentage"] as? NSNumber)?.intValue
        let surfaceAfterDaysPastMove = (data["surfaceAfterDaysPastMove"] as? NSNumber)?.intValue
        let userInProgressDate = (data["userInProgressDate"] as? Timestamp)?.dateValue()
        let userInProgressReturnDate = (data["userInProgressReturnDate"] as? Timestamp)?.dateValue()

        let categoryRaw = data["category"] as? String
        let isVendorTask = categoryRaw?.lowercased().contains("vendor") ?? false
        let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task
        let taskId = data["taskId"] as? String ?? data["id"] as? String ?? documentID
        let packingSession = packingSession(from: data, fallbackTaskId: taskId)
        let workflowId = data["workflowId"] as? String
            ?? (taskId.hasPrefix("PACKING_SESSION_") ? "packing_session" : nil)

        // Spawn metadata (Spec 09) — NSNumber-safe numerics, defaults on absence.
        let spawnedFrom = (data["spawnedFrom"] as? [String: Any]).flatMap { raw -> PeezyCard.SpawnedFrom? in
            guard let kind = raw["kind"] as? String, let id = raw["id"] as? String else { return nil }
            return PeezyCard.SpawnedFrom(kind: kind, id: id)
        }
        let onCompleteSpawns = (data["onCompleteSpawns"] as? [[String: Any]] ?? [])
            .compactMap { raw -> PeezyCard.CompletionSpawn? in
                guard let id = raw["id"] as? String else { return nil }
                let dateRule = (raw["dateRule"] as? [String: Any]).flatMap { rule -> PeezyCard.SpawnDateRule? in
                    guard let offsetDays = (rule["offsetDays"] as? NSNumber)?.intValue else { return nil }
                    return PeezyCard.SpawnDateRule(
                        anchor: rule["anchor"] as? String ?? "moveDate",
                        offsetDays: offsetDays
                    )
                }
                return PeezyCard.CompletionSpawn(id: id, dateRule: dateRule)
            }
        let dispositionContract = (data["dispositionContract"] as? [String: Any])
            .map(dispositionContract(from:))

        return PeezyCard(
            id: documentID,
            type: cardType,
            title: data["title"] as? String ?? "Untitled Task",
            // Retained for the gated task-detail renderer; free list rows do
            // not render this catalog description.
            subtitle: data["desc"] as? String ?? "",
            colorName: colorNameForPriority(priority),
            taskId: taskId,
            workflowId: workflowId,
            vendorCategory: isVendorTask ? categoryRaw : nil,
            vendorId: nil,
            priority: priority,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            status: status,
            dueDate: dueDate,
            snoozedUntil: snoozedUntil,
            lastSnoozedAt: lastSnoozedAt,
            taskCategory: categoryRaw,
            urgencyPercentage: urgencyPercentage,
            surfaceAfterDaysPastMove: surfaceAfterDaysPastMove,
            userInProgressDate: userInProgressDate,
            userInProgressReturnDate: userInProgressReturnDate,
            completedAt: completedAt,
            selfServiceOnly: (data["selfServiceOnly"] as? Bool) ?? false,
            actionType: data["actionType"] as? String,
            taskType: data["taskType"] as? String,
            tips: data["tips"] as? String,
            whyNeeded: data["whyNeeded"] as? String,
            estPeezy: data["estPeezy"] as? String,
            estHours: (data["estHours"] as? NSNumber)?.doubleValue,
            // Nil-tolerant: absent/unknown stage = nil (notStarted for workflow tasks)
            stage: (data["stage"] as? String).flatMap(TaskStage.init(rawValue:)),
            payload: packingSession.map(CardPayload.packing),
            tier: data["tier"] as? String ?? "task",
            nudgePrompt: data["nudgePrompt"] as? String,
            nudgeSpawnsId: data["nudgeSpawnsId"] as? String,
            spawnedFrom: spawnedFrom,
            onCompleteSpawns: onCompleteSpawns,
            notesEnabled: data["notesEnabled"] as? Bool ?? false,
            quoteTracker: data["quoteTracker"] as? String ?? "none",
            dispositionContract: dispositionContract
        )
    }

    private static func dispositionContract(from raw: [String: Any]) -> PeezyCard.DispositionContract {
        let trigger = (raw["next_trigger"] as? [String: Any]).flatMap { value -> PeezyCard.DispositionContract.Trigger? in
            guard let kindRaw = value["kind"] as? String,
                  let kind = PeezyCard.DispositionContract.Trigger.Kind(rawValue: kindRaw) else { return nil }
            let payload = (value["payload"] as? [String: Any])?.compactMapValues(firestoreValue(from:))
            return .init(
                kind: kind,
                at: date(from: value["at"]),
                eventName: value["event_name"] as? String,
                canonicalKey: value["canonical_key"] as? String,
                afterSourceVersion: (value["after_source_version"] as? NSNumber)?.intValue,
                payload: payload?.isEmpty == true ? nil : payload,
                fired: value["fired"] as? Bool ?? false
            )
        }
        return .init(
            disposition: (raw["disposition"] as? String).flatMap(PeezyCard.DispositionContract.Disposition.init(rawValue:)),
            terminalKind: (raw["terminal_kind"] as? String).flatMap(PeezyCard.DispositionContract.TerminalKind.init(rawValue:)),
            owner: raw["owner"] as? String,
            nextAction: raw["next_action"] as? String,
            nextTrigger: trigger,
            resumeDestination: raw["resume_destination"] as? String,
            visibleStatusCopy: raw["visible_status_copy"] as? String,
            profileVersion: (raw["profile_version"] as? NSNumber)?.intValue,
            externalSubmission: raw["external_submission"] as? Bool ?? false,
            supersededBy: raw["superseded_by"] as? String
        )
    }

    private static func date(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    private static func firestoreValue(from raw: Any) -> PeezyCard.FirestoreValue? {
        if raw is NSNull { return .null }
        if let timestamp = raw as? Timestamp { return .date(timestamp.dateValue()) }
        if let date = raw as? Date { return .date(date) }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let decimal = number.doubleValue
            if decimal.rounded() == decimal,
               decimal >= Double(Int64.min), decimal <= Double(Int64.max) {
                return .int(number.int64Value)
            }
            return .double(decimal)
        }
        if let string = raw as? String { return .string(string) }
        if let array = raw as? [Any] {
            return .array(array.compactMap(firestoreValue(from:)))
        }
        if let map = raw as? [String: Any] {
            return .map(map.compactMapValues(firestoreValue(from:)))
        }
        return nil
    }

    private static func packingSession(
        from data: [String: Any],
        fallbackTaskId: String
    ) -> PackingSession? {
        guard let payload = data["packingSession"] as? [String: Any],
              let sessionKey = payload["sessionKey"] as? String,
              let roomLabel = payload["roomLabel"] as? String,
              let scheduledAt = payload["scheduledDate"] as? Timestamp else { return nil }

        return PackingSession(
            taskId: payload["taskId"] as? String ?? fallbackTaskId,
            sessionKey: sessionKey,
            sourceKeys: payload["sourceKeys"] as? [String] ?? [sessionKey],
            rooms: payload["rooms"] as? [String] ?? [roomLabel],
            roomLabel: roomLabel,
            estMinutes: (payload["estMinutes"] as? NSNumber)?.intValue ?? PackingConstants.targetSessionMinutes,
            scheduledDate: scheduledAt.dateValue(),
            itemSummary: payload["itemSummary"] as? [String] ?? [],
            isFirstNightBag: payload["isFirstNightBag"] as? Bool ?? false,
            completedAt: (payload["completedAt"] as? Timestamp)?.dateValue(),
            isBehindPace: payload["isBehindPace"] as? Bool ?? false
        )
    }

    private static func colorNameForPriority(_ priority: PeezyCard.Priority) -> String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .normal: return "green"
        case .low: return "gray"
        }
    }
}
