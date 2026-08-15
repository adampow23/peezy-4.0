import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
@Observable
final class SupportChatService {

    var messages: [SupportMessage] = []
    var unreadCount: Int = 0
    var error: String?
    private(set) var adminSeenAt: Date?
    private(set) var sendingMessageIds: Set<String> = []

    private var messageListener: ListenerRegistration?
    private var metaListener: ListenerRegistration?
    private var listeningUserId: String?
    private let db = Firestore.firestore()

    private func chatCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("supportChat")
    }

    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            stopListening()
            return
        }
        guard listeningUserId != userId || messageListener == nil else { return }

        removeListeners()
        listeningUserId = userId
        messages = []
        unreadCount = 0
        adminSeenAt = nil
        sendingMessageIds = []
        error = nil

        messageListener = chatCollection(userId: userId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.listeningUserId == userId else { return }

                if let error {
                    self.error = error.localizedDescription
                    return
                }

                guard let documents = snapshot?.documents else { return }

                let fetchedMessages = documents.compactMap { doc in
                    SupportMessage(documentId: doc.documentID, data: doc.data())
                }
                let fetchedIds = Set(fetchedMessages.map(\.id))
                let pendingMessages = self.messages.filter {
                    self.sendingMessageIds.contains($0.id) && !fetchedIds.contains($0.id)
                }

                self.messages = (fetchedMessages + pendingMessages).sorted {
                    $0.timestamp < $1.timestamp
                }

                self.unreadCount = self.messages.filter { $0.sender == .support && !$0.read }.count
                self.error = nil
            }

        metaListener = chatCollection(userId: userId).document("_meta")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, self.listeningUserId == userId else { return }
                self.adminSeenAt = (snapshot?.data()?["adminSeenAt"] as? Timestamp)?.dateValue()
            }
    }

    func stopListening() {
        removeListeners()
        listeningUserId = nil
        messages = []
        unreadCount = 0
        adminSeenAt = nil
        sendingMessageIds = []
        error = nil
    }

    /// Structured send result (plan v7 GOAL B). `persisted` and `adminQueued`
    /// are SEPARATE facts: the message doc write proves persisted, while only
    /// an awaited, successful `submitSupportMessage` callable — the thing that
    /// updates `supportThreads` for the admin inbox — proves adminQueued.
    struct SendResult {
        let persisted: Bool
        let adminQueued: Bool
        let wasFirstUserMessage: Bool
        let messageId: String?

        static let notPersisted = SendResult(
            persisted: false,
            adminQueued: false,
            wasFirstUserMessage: false,
            messageId: nil
        )
    }

    /// Expert-review durable marker target: when provided, the message doc and
    /// the task doc's `expertReview {messageId, adminQueued:false}` marker are
    /// committed in ONE batch, and `adminQueued` flips true only after the
    /// callable succeeds.
    struct TaskMarker {
        let userId: String
        let taskDocumentId: String
    }

    @discardableResult
    func sendMessage(
        _ text: String,
        taskContext: SupportTaskContext? = nil,
        atomicTaskMarker: TaskMarker? = nil
    ) async -> SendResult {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Not signed in"
            return .notPersisted
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notPersisted }
        let isFirstUserMessage = !messages.contains { $0.sender == .user }

        let message = SupportMessage(
            text: trimmed,
            sender: .user,
            taskContext: taskContext
        )
        sendingMessageIds.insert(message.id)
        messages.append(message)
        messages.sort { $0.timestamp < $1.timestamp }
        error = nil

        do {
            let messageRef = chatCollection(userId: userId).document(message.id)
            if let atomicTaskMarker, !atomicTaskMarker.taskDocumentId.isEmpty {
                let batch = db.batch()
                batch.setData(message.toFirestoreData(), forDocument: messageRef)
                batch.updateData(
                    ["expertReview": ["messageId": message.id, "adminQueued": false]],
                    forDocument: taskReference(atomicTaskMarker)
                )
                try await batch.commit()
            } else {
                try await messageRef.setData(message.toFirestoreData())
            }
            sendingMessageIds.remove(message.id)
        } catch {
            sendingMessageIds.remove(message.id)
            messages.removeAll { $0.id == message.id }
            self.error = "Failed to send: \(error.localizedDescription)"
            return .notPersisted
        }

        // Awaited (not detached): this callable is what reaches the admin
        // inbox. It is NOT idempotent, so it is never retried here — a
        // failure surfaces as adminQueued=false with the marker left false.
        var adminQueued = false
        do {
            let callable = Functions.functions().httpsCallable("submitSupportMessage")
            var payload: [String: Any] = [
                "messageId": message.id,
                "text": trimmed
            ]
            if let taskContext {
                payload["taskContext"] = taskContext.toFirestoreData()
            }
            _ = try await callable.call(payload)
            adminQueued = true
        } catch {
            print("⚠️ submitSupportMessage not confirmed: \(error.localizedDescription)")
        }

        if adminQueued, let atomicTaskMarker, !atomicTaskMarker.taskDocumentId.isEmpty {
            try? await taskReference(atomicTaskMarker).updateData([
                "expertReview": ["messageId": message.id, "adminQueued": true]
            ])
        }

        return SendResult(
            persisted: true,
            adminQueued: adminQueued,
            wasFirstUserMessage: isFirstUserMessage,
            messageId: message.id
        )
    }

    private func taskReference(_ marker: TaskMarker) -> DocumentReference {
        db.collection("users").document(marker.userId)
            .collection("tasks").document(marker.taskDocumentId)
    }

    func receipt(for message: SupportMessage) -> SupportMessageReceipt {
        if sendingMessageIds.contains(message.id) {
            return .sending
        }
        if let adminSeenAt, adminSeenAt > message.timestamp {
            return .seen
        }
        return .delivered
    }

    func markSupportMessagesRead() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let unread = messages.filter { $0.sender == .support && !$0.read }
        guard !unread.isEmpty else { return }

        let batch = db.batch()
        for message in unread {
            let ref = chatCollection(userId: userId).document(message.id)
            batch.updateData(["read": true], forDocument: ref)
        }

        Task {
            try? await batch.commit()
        }
    }

    private func removeListeners() {
        messageListener?.remove()
        messageListener = nil
        metaListener?.remove()
        metaListener = nil
    }
}
