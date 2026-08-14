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

    func sendMessage(_ text: String, taskContext: SupportTaskContext? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Not signed in"
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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
            try await chatCollection(userId: userId)
                .document(message.id)
                .setData(message.toFirestoreData())
            sendingMessageIds.remove(message.id)

            Task {
                let callable = Functions.functions().httpsCallable("submitSupportMessage")
                var payload: [String: Any] = [
                    "messageId": message.id,
                    "text": trimmed
                ]
                if let taskContext {
                    payload["taskContext"] = taskContext.toFirestoreData()
                }
                _ = try? await callable.call(payload)
            }
        } catch {
            sendingMessageIds.remove(message.id)
            messages.removeAll { $0.id == message.id }
            self.error = "Failed to send: \(error.localizedDescription)"
        }
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
