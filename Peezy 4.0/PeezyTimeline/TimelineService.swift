// TimelineService.swift
// Peezy iOS - Timeline Data Service
// Fetches tasks directly from Firestore for timeline display

import Foundation
import FirebaseFirestore
import FirebaseAuth

class TimelineService {
    private let db = Firestore.firestore()

    /// Fetches all active tasks for the current user from Firestore
    /// - Returns: Array of PeezyCards sorted by due date
    func fetchUserTasks() async throws -> [PeezyCard] {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "TimelineService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
            )
        }

        print("📅 TimelineService: Fetching tasks for user \(userId)")

        // Fetch tasks with active statuses
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .whereField("status", in: ["Upcoming", "InProgress", "pending", "Snoozed"])
            .getDocuments()

        print("📅 TimelineService: Found \(snapshot.documents.count) documents")

        var cards: [PeezyCard] = []

        for document in snapshot.documents {
            let data = document.data()

            // Parse status
            let statusString = data["status"] as? String ?? "Upcoming"
            let status = TaskStatus(rawValue: statusString) ?? .upcoming

            // Parse priority
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

            // Parse due date
            let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()

            // Parse snooze data
            let snoozedUntil = (data["snoozedUntil"] as? Timestamp)?.dateValue()
            let lastSnoozedAt = (data["lastSnoozedAt"] as? Timestamp)?.dateValue()

            // Determine card type based on task properties
            let isVendorTask = (data["category"] as? String)?.lowercased().contains("vendor") ?? false
            let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task

            // Create the card
            let card = PeezyCard(
                id: document.documentID,
                type: cardType,
                title: data["title"] as? String ?? "Untitled Task",
                subtitle: data["desc"] as? String ?? "",
                colorName: colorNameForPriority(priority),
                taskId: data["id"] as? String ?? document.documentID,
                workflowId: data["workflowId"] as? String ?? data["id"] as? String,
                vendorCategory: isVendorTask ? (data["category"] as? String) : nil,
                vendorId: nil,
                priority: priority,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                status: status,
                dueDate: dueDate,
                snoozedUntil: snoozedUntil,
                lastSnoozedAt: lastSnoozedAt
            )

            // 📅 DEBUG: Log dueDate from Firestore before filtering
            let dueDateFormatter = DateFormatter()
            dueDateFormatter.dateFormat = "MMM d, yyyy"
            print("📅 TimelineService: '\(card.title)' dueDate from Firestore: \(dueDate.map { dueDateFormatter.string(from: $0) } ?? "nil")")

            // Only include cards that should be shown (not completed, not actively snoozed)
            if card.shouldShow {
                cards.append(card)
            }
        }

        // Sort by due date (earliest first)
        cards.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        print("📅 TimelineService: Returning \(cards.count) active tasks")
        return cards
    }

    private func colorNameForPriority(_ priority: PeezyCard.Priority) -> String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .normal: return "green"
        case .low: return "gray"
        }
    }
}
