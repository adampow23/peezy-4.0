import FirebaseAuth
import FirebaseFirestore

/// Firestore write side of task actions. Spec 03 Phase B: setStage only.
/// Spec 03 Phase C absorbs the status/snooze/complete writes from
/// PeezyHomeViewModel into this service.
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
}
