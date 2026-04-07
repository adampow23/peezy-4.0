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

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    private func chatCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("supportChat")
    }

    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        listener?.remove()

        listener = chatCollection(userId: userId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    self.error = error.localizedDescription
                    return
                }

                guard let documents = snapshot?.documents else { return }

                self.messages = documents.compactMap { doc in
                    SupportMessage(documentId: doc.documentID, data: doc.data())
                }

                self.unreadCount = self.messages.filter { $0.sender == .support && !$0.read }.count
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func sendMessage(_ text: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Not signed in"
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = SupportMessage(text: trimmed, sender: .user)

        do {
            try await chatCollection(userId: userId)
                .document(message.id)
                .setData(message.toFirestoreData())

            Task {
                let callable = Functions.functions().httpsCallable("submitSupportMessage")
                let payload: [String: Any] = [
                    "userId": userId,
                    "userName": Auth.auth().currentUser?.displayName ?? "",
                    "messageId": message.id,
                    "text": trimmed
                ]
                _ = try? await callable.call(payload)
            }
        } catch {
            self.error = "Failed to send: \(error.localizedDescription)"
        }
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
}
