import FirebaseAuth
import FirebaseFirestore

/// Firestore write side of task actions (Spec 03 Phases B–C). Bodies of the
/// status/snooze/complete writes are moved VERBATIM from PeezyHomeViewModel —
/// the update payloads are load-bearing; do not change field names or shapes.
struct TaskActionService {

    /// Persists the workflow spine stage on the task doc — direct write,
    /// matching the existing status-write pattern (no callable).
    func setStage(taskId: String, stage: TaskStage) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
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
    func writeFlowProgress(taskId: String, path: [String], answerKey: String? = nil, values: [String]? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid, !taskId.isEmpty else { return }
        let db = Firestore.firestore()
        var update: [String: Any] = ["flowPath": path]
        if let answerKey, let values {
            update["flowAnswers.\(answerKey)"] = values
        }
        do {
            try await db.collection("users").document(userId).collection("tasks")
                .document(taskId).updateData(update)
        } catch {
            print("⚠️ Failed to write flow progress: \(error.localizedDescription)")
        }
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
}
