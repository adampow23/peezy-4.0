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
