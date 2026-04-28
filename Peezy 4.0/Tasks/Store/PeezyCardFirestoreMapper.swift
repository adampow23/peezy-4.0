import FirebaseFirestore
import Foundation

enum PeezyCardFirestoreMapper {
    /// Converts a Firestore document to a PeezyCard, or nil if parsing fails.
    /// Ported from TimelineService.fetchUserTasks().
    static func card(from document: QueryDocumentSnapshot) -> PeezyCard? {
        let data = document.data()

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
        let userInProgressDate = (data["userInProgressDate"] as? Timestamp)?.dateValue()
        let userInProgressReturnDate = (data["userInProgressReturnDate"] as? Timestamp)?.dateValue()

        let categoryRaw = data["category"] as? String
        let isVendorTask = categoryRaw?.lowercased().contains("vendor") ?? false
        let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task

        return PeezyCard(
            id: document.documentID,
            type: cardType,
            title: data["title"] as? String ?? "Untitled Task",
            subtitle: data["desc"] as? String ?? "",
            colorName: colorNameForPriority(priority),
            taskId: data["id"] as? String ?? document.documentID,
            workflowId: data["workflowId"] as? String,
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
            userInProgressDate: userInProgressDate,
            userInProgressReturnDate: userInProgressReturnDate,
            completedAt: completedAt,
            selfServiceOnly: (data["selfServiceOnly"] as? Bool) ?? false,
            actionType: data["actionType"] as? String,
            taskType: data["taskType"] as? String,
            tips: data["tips"] as? String,
            whyNeeded: data["whyNeeded"] as? String,
            estPeezy: data["estPeezy"] as? String,
            estHours: (data["estHours"] as? NSNumber)?.doubleValue
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
