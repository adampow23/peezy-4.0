import Foundation
import FirebaseFirestore

struct SupportMessage: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let sender: Sender
    let timestamp: Date
    var read: Bool

    enum Sender: String, Codable {
        case user = "user"
        case support = "support"
    }

    var isFromUser: Bool { sender == .user }

    init(id: String = UUID().uuidString, text: String, sender: Sender, timestamp: Date = Date(), read: Bool = false) {
        self.id = id
        self.text = text
        self.sender = sender
        self.timestamp = timestamp
        self.read = read
    }

    init?(documentId: String, data: [String: Any]) {
        guard let text = data["text"] as? String,
              let senderRaw = data["sender"] as? String,
              let sender = Sender(rawValue: senderRaw),
              let timestamp = data["timestamp"] as? Timestamp else {
            return nil
        }
        self.id = documentId
        self.text = text
        self.sender = sender
        self.timestamp = timestamp.dateValue()
        self.read = data["read"] as? Bool ?? false
    }

    func toFirestoreData() -> [String: Any] {
        return [
            "text": text,
            "sender": sender.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "read": read
        ]
    }
}
