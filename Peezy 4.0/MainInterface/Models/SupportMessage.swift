import Foundation
import FirebaseFirestore

struct SupportTaskContext: Codable, Equatable {
    let userTaskId: String
    let catalogTaskId: String
    let title: String

    init(userTaskId: String, catalogTaskId: String, title: String) {
        self.userTaskId = userTaskId
        self.catalogTaskId = catalogTaskId
        self.title = title
    }

    nonisolated init?(data: [String: Any]) {
        guard let userTaskId = data["userTaskId"] as? String,
              let catalogTaskId = data["catalogTaskId"] as? String,
              let title = data["title"] as? String else { return nil }

        self.userTaskId = userTaskId
        self.catalogTaskId = catalogTaskId
        self.title = title
    }

    func toFirestoreData() -> [String: Any] {
        [
            "userTaskId": userTaskId,
            "catalogTaskId": catalogTaskId,
            "title": title
        ]
    }
}

enum SupportMessageReceipt {
    case sending
    case delivered
    case seen

    var caption: String {
        switch self {
        case .sending:
            "Sending…"
        case .delivered:
            "Delivered"
        case .seen:
            "Seen"
        }
    }
}

struct SupportMessage: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let sender: Sender
    let timestamp: Date
    var read: Bool
    let taskContext: SupportTaskContext?

    enum Sender: String, Codable {
        case user = "user"
        case support = "support"
    }

    var isFromUser: Bool { sender == .user }

    init(
        id: String = UUID().uuidString,
        text: String,
        sender: Sender,
        timestamp: Date = Date(),
        read: Bool = false,
        taskContext: SupportTaskContext? = nil
    ) {
        self.id = id
        self.text = text
        self.sender = sender
        self.timestamp = timestamp
        self.read = read
        self.taskContext = taskContext
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
        self.taskContext = (data["taskContext"] as? [String: Any])
            .flatMap(SupportTaskContext.init(data:))
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "text": text,
            "sender": sender.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "read": read
        ]

        if let taskContext {
            data["taskContext"] = taskContext.toFirestoreData()
        }

        return data
    }
}
