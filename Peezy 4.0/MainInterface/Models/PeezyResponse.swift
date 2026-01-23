import Foundation

// MARK: - PeezyResponse
/// Response from the peezyRespond Firebase function
struct PeezyResponse: Codable {
    let text: String
    let suggestedActions: [SuggestedAction]?
    let stateUpdates: StateUpdates?
    let internalNotes: InternalNotes?
    let cards: [CardData]?  // Cards to add to the stack
    
    // MARK: - Suggested Actions
    struct SuggestedAction: Codable {
        let type: String        // "book_vendor", "complete_task", "open_link", etc.
        let label: String       // Button text
        let data: ActionData?
        
        struct ActionData: Codable {
            let vendorCategory: String?
            let vendorId: String?
            let taskId: String?
            let url: String?
            let workflowId: String?
        }
    }
    
    // MARK: - State Updates
    /// Updates to apply to UserState after this response
    struct StateUpdates: Codable {
        let heardAccountabilityPitch: Bool?
        let vendorsSurfaced: [String]?
        let tasksCompleted: [String]?
        let tasksSuggested: [String]?
    }
    
    // MARK: - Internal Notes
    /// Metadata about the response (for debugging/analytics)
    struct InternalNotes: Codable {
        let vendorsSurfaced: [String]?
        let contextFactorsApplied: [String]?
        let workflowTriggered: String?
        let urgencyLevel: String?
    }
    
    // MARK: - Card Data
    /// Card to add to the stack (from backend)
    struct CardData: Codable {
        let type: String        // "task", "vendor", "update", etc.
        let title: String
        let subtitle: String
        let colorName: String?
        let taskId: String?
        let workflowId: String?
        let vendorCategory: String?
        let vendorId: String?
        let priority: Int?      // 0=low, 1=normal, 2=high, 3=urgent
        
        /// Convert to PeezyCard
        func toCard() -> PeezyCard {
            let cardType: PeezyCard.CardType
            switch type.lowercased() {
            case "intro": cardType = .intro
            case "task": cardType = .task
            case "vendor": cardType = .vendor
            case "update": cardType = .update
            case "milestone": cardType = .milestone
            case "question": cardType = .question
            default: cardType = .task
            }
            
            let cardPriority: PeezyCard.Priority
            switch priority ?? 1 {
            case 0: cardPriority = .low
            case 2: cardPriority = .high
            case 3: cardPriority = .urgent
            default: cardPriority = .normal
            }
            
            return PeezyCard(
                type: cardType,
                title: title,
                subtitle: subtitle,
                colorName: colorName ?? "white",
                taskId: taskId,
                workflowId: workflowId,
                vendorCategory: vendorCategory,
                vendorId: vendorId,
                priority: cardPriority
            )
        }
    }
}

// MARK: - Chat Message
/// A single message in a conversation
struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: Role
    let content: String
    let timestamp: Date
    
    enum Role: String, Codable {
        case user = "user"
        case assistant = "assistant"
    }
    
    init(id: String = UUID().uuidString, role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Peezy Request
/// Request body sent to peezyRespond function
struct PeezyRequest: Codable {
    let message: String
    let userState: [String: AnyCodable]
    let conversationHistory: [ChatMessage]
    let currentTaskId: String?
    let requestType: String?  // "chat", "card_action", "initial_load"
    
    init(
        message: String,
        userState: UserState,
        conversationHistory: [ChatMessage] = [],
        currentTaskId: String? = nil,
        requestType: String? = nil
    ) {
        self.message = message
        self.userState = userState.toDictionary().mapValues { AnyCodable($0) }
        self.conversationHistory = conversationHistory
        self.currentTaskId = currentTaskId
        self.requestType = requestType
    }
}

// MARK: - AnyCodable Helper
/// Wrapper to encode Any values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
