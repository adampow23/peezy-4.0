import SwiftUI
import FirebaseFirestore

// MARK: - Task Status

enum TaskStatus: String, Codable {
    case upcoming = "Upcoming"
    case inProgress = "InProgress"
    case completed = "Completed"
    case snoozed = "Snoozed"
    case skipped = "Skipped"
}

// MARK: - PeezyCard Model
/// Enhanced card model that connects to Firebase backend and task system
struct PeezyCard: Identifiable, Equatable, Codable {
    let id: String
    let type: CardType
    let title: String
    let subtitle: String
    let colorName: String // Codable-friendly color storage

    // Task connection (optional - not all cards link to tasks)
    var taskId: String?
    var workflowId: String?

    // Vendor connection (for vendor recommendation cards)
    var vendorCategory: String?
    var vendorId: String?

    // Action tracking
    var createdAt: Date
    var priority: Priority

    // Task status and snooze support
    var status: TaskStatus
    var dueDate: Date?
    var snoozedUntil: Date?
    var lastSnoozedAt: Date?
    
    // MARK: - Card Types
    enum CardType: String, Codable {
        case intro          // "Good morning, 3 updates ready"
        case task           // Standard task decision
        case vendor         // Vendor recommendation
        case update         // Status update / notification
        case milestone      // Celebration / progress marker
        case question       // Peezy asking for info
    }
    
    enum Priority: Int, Codable, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Computed Properties
    var color: Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .white
        }
    }
    
    var icon: String {
        switch type {
        case .intro: return "sparkles"
        case .task: return "circle.grid.2x2.fill"
        case .vendor: return "building.2.fill"
        case .update: return "bell.fill"
        case .milestone: return "star.fill"
        case .question: return "questionmark.circle.fill"
        }
    }
    
    var headerLabel: String {
        switch type {
        case .intro: return "UPDATES"
        case .task: return "DECISION"
        case .vendor: return "RECOMMENDATION"
        case .update: return "UPDATE"
        case .milestone: return "MILESTONE"
        case .question: return "QUESTION"
        }
    }
    
    // What happens on swipe right
    var doItLabel: String {
        switch type {
        case .intro: return "Start"
        case .task: return "Do It"
        case .vendor: return "Book"
        case .update: return "Got It"
        case .milestone: return "Nice!"
        case .question: return "Yes"
        }
    }
    
    // What happens on swipe left
    var laterLabel: String {
        switch type {
        case .intro: return "Skip"
        case .task: return "Later"
        case .vendor: return "Skip"
        case .update: return "Dismiss"
        case .milestone: return "Dismiss"
        case .question: return "No"
        }
    }
    
    // MARK: - Snooze Support

    /// Whether this card can be snoozed (must have taskId and be a task type)
    var canSnooze: Bool {
        guard taskId != nil else { return false }
        guard status != .completed else { return false }
        switch type {
        case .task, .vendor:
            return true
        case .intro, .milestone, .update, .question:
            return false
        }
    }

    /// Whether this card is currently snoozed
    var isSnoozed: Bool {
        guard let snoozedUntil = snoozedUntil else { return false }
        return snoozedUntil > Date()
    }

    /// Whether this card should be shown in the stack
    var shouldShow: Bool {
        // If snoozed, only show if snooze date has passed
        if isSnoozed {
            return false
        }
        // Don't show completed or skipped tasks
        if status == .completed || status == .skipped {
            return false
        }
        return true
    }

    // MARK: - Initializers
    init(
        id: String = UUID().uuidString,
        type: CardType,
        title: String,
        subtitle: String,
        colorName: String = "white",
        taskId: String? = nil,
        workflowId: String? = nil,
        vendorCategory: String? = nil,
        vendorId: String? = nil,
        priority: Priority = .normal,
        createdAt: Date = Date(),
        status: TaskStatus = .upcoming,
        dueDate: Date? = nil,
        snoozedUntil: Date? = nil,
        lastSnoozedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.colorName = colorName
        self.taskId = taskId
        self.workflowId = workflowId
        self.vendorCategory = vendorCategory
        self.vendorId = vendorId
        self.priority = priority
        self.createdAt = createdAt
        self.status = status
        self.dueDate = dueDate
        self.snoozedUntil = snoozedUntil
        self.lastSnoozedAt = lastSnoozedAt
    }
    
    // MARK: - Factory Methods
    
    /// Create intro card for daily greeting
    static func intro(updateCount: Int) -> PeezyCard {
        let greeting = greetingForTimeOfDay()
        let subtitle = updateCount == 0
            ? "You're all caught up!"
            : "\(updateCount) update\(updateCount == 1 ? "" : "s") ready for you."
        
        return PeezyCard(
            type: .intro,
            title: greeting,
            subtitle: subtitle,
            colorName: "white",
            priority: .high
        )
    }
    
    /// Create task decision card from MovingTask
    static func fromTask(
        taskId: String,
        title: String,
        subtitle: String,
        workflowId: String? = nil,
        priority: Priority = .normal
    ) -> PeezyCard {
        return PeezyCard(
            type: .task,
            title: title,
            subtitle: subtitle,
            colorName: colorForPriority(priority),
            taskId: taskId,
            workflowId: workflowId,
            priority: priority
        )
    }
    
    /// Create vendor recommendation card
    static func vendorRecommendation(
        title: String,
        subtitle: String,
        vendorCategory: String,
        vendorId: String? = nil
    ) -> PeezyCard {
        return PeezyCard(
            type: .vendor,
            title: title,
            subtitle: subtitle,
            colorName: "blue",
            vendorCategory: vendorCategory,
            vendorId: vendorId,
            priority: .normal
        )
    }
    
    /// Create milestone celebration card
    static func milestone(title: String, subtitle: String) -> PeezyCard {
        return PeezyCard(
            type: .milestone,
            title: title,
            subtitle: subtitle,
            colorName: "purple",
            priority: .low
        )
    }
    
    /// Create question card (Peezy needs input)
    static func question(title: String, subtitle: String, taskId: String? = nil) -> PeezyCard {
        return PeezyCard(
            type: .question,
            title: title,
            subtitle: subtitle,
            colorName: "orange",
            taskId: taskId,
            priority: .high
        )
    }
    
    // MARK: - Helpers
    
    private static func greetingForTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Hey There"
        }
    }
    
    private static func colorForPriority(_ priority: Priority) -> String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .normal: return "green"
        case .low: return "gray"
        }
    }
    
    // MARK: - Equatable
    static func == (lhs: PeezyCard, rhs: PeezyCard) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Card Action Result
/// Tracks what happened when user swiped a card
struct CardActionResult {
    let card: PeezyCard
    let action: SwipeAction
    let timestamp: Date
    
    init(card: PeezyCard, action: SwipeAction) {
        self.card = card
        self.action = action
        self.timestamp = Date()
    }
}

// MARK: - Swipe Action
enum SwipeAction: String, Codable {
    case doIt = "do_it"
    case later = "later"
}
