import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Observation
import SwiftUI

@Observable
@MainActor
final class TasksStore {
    static let shared = TasksStore()

    private(set) var tasks: [PeezyCard] = []
    private(set) var loadState: LoadState = .idle
    private(set) var pendingResetTaskIds: Set<String> = []

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var listener: ListenerRegistration?
    private var currentUserId: String?
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Lifecycle

    func start(userId: String) {
        if currentUserId == userId, listener != nil { return }

        stop()

        currentUserId = userId
        loadState = .loading

        listener = db.collection("users").document(userId).collection("tasks")
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snap, err in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let err {
                        self.loadState = .failed(err.localizedDescription)
                        return
                    }

                    guard let snap else { return }

                    self.tasks = snap.documents.compactMap { PeezyCardFirestoreMapper.card(from: $0) }
                    self.loadState = .loaded
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        currentUserId = nil
        tasks = []
        loadState = .idle
    }

    // MARK: - Dispatch

    func dispatch(_ action: TaskAction, onNavigate: @MainActor @escaping (PeezyCard) -> Void) async {
        switch action {
        case .open(let card):
            PeezyHaptics.light()
            onNavigate(card)

        case .markComplete(let card):
            await performWrite(
                taskId: card.id,
                optimistic: { $0.status = .completed; $0.completedAt = Date() },
                revertStatus: card.status,
                revertCompletedAt: card.completedAt,
                firestoreUpdate: [
                    "status": "Completed",
                    "completedAt": FieldValue.serverTimestamp()
                ],
                onSuccess: {
                    ConfettiBus.shared.fire()
                    PeezyHaptics.success()
                },
                onFailure: {
                    ToastManager.shared.show("Couldn't mark complete", style: .error)
                }
            )

        case .undo(let card):
            await performWrite(
                taskId: card.id,
                optimistic: { $0.status = .upcoming; $0.completedAt = nil },
                revertStatus: card.status,
                revertCompletedAt: card.completedAt,
                firestoreUpdate: [
                    "status": "Upcoming",
                    "completedAt": FieldValue.delete()
                ],
                onSuccess: {
                    PeezyHaptics.light()
                    ToastManager.shared.show("\(card.title) moved back to active")
                },
                onFailure: {
                    ToastManager.shared.show("Couldn't undo — please try again", style: .error)
                }
            )

        case .resetInventory(let card):
            await performInventoryReset(card)
        }
    }

    private func performWrite(
        taskId: String,
        optimistic: (inout PeezyCard) -> Void,
        revertStatus: TaskStatus,
        revertCompletedAt: Date?,
        firestoreUpdate: [String: Any],
        onSuccess: () -> Void,
        onFailure: () -> Void
    ) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let idx = tasks.firstIndex(where: { $0.id == taskId })
        else {
            onFailure()
            return
        }

        optimistic(&tasks[idx])

        do {
            try await db.collection("users").document(uid)
                .collection("tasks").document(taskId)
                .updateData(firestoreUpdate)
            onSuccess()
        } catch {
            if let i = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[i].status = revertStatus
                tasks[i].completedAt = revertCompletedAt
            }
            onFailure()
        }
    }

    private func performInventoryReset(_ card: PeezyCard) async {
        guard card.isScanInventory else { return }
        pendingResetTaskIds.insert(card.id)
        defer { pendingResetTaskIds.remove(card.id) }

        let priorStatus = card.status
        let priorCompletedAt = card.completedAt

        if let i = tasks.firstIndex(where: { $0.id == card.id }) {
            tasks[i].status = .upcoming
            tasks[i].completedAt = nil
        }

        do {
            let manager = InventorySessionManager()
            try await manager.resetInventory()
            ToastManager.shared.show("Inventory reset — ready to scan again", style: .success)
            PeezyHaptics.success()
            // No refetch. Listener reconciles.
        } catch {
            if let i = tasks.firstIndex(where: { $0.id == card.id }) {
                tasks[i].status = priorStatus
                tasks[i].completedAt = priorCompletedAt
            }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                ToastManager.shared.show("Inventory reset needs a connection", style: .error)
            } else {
                ToastManager.shared.show("Couldn't reset inventory — please try again", style: .error)
            }
        }
    }
}
