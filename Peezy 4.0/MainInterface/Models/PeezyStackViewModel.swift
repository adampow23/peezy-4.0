import SwiftUI
import Observation
import FirebaseFirestore
import FirebaseAuth

// MARK: - PeezyStackViewModel
@Observable
final class PeezyStackViewModel {
    
    // MARK: - State
    var cards: [PeezyCard] = []
    var isLoading: Bool = false
    var error: PeezyError?
    var showChat: Bool = false
    
    // User context
    var userState: UserState?

    // NOTE: Workflow, snooze, and mini-assessment logic moved to PeezyHomeViewModel.
    // PeezyStackViewModel now serves Timeline only (data loading + card array).

    // Track actions for undo
    private var actionHistory: [CardActionResult] = []

    // MARK: - Computed Counts (for intro card display)

    /// Count of update cards in the stack (excludes intro card)
    var updateCount: Int {
        cards.filter { $0.type == .update }.count
    }

    /// Count of task/vendor cards in the stack (excludes intro card)
    var taskCount: Int {
        cards.filter { $0.type == .task || $0.type == .vendor }.count
    }

    // Dependencies
    private let client: PeezyClient
    
    // MARK: - Init
    init(client: PeezyClient = .shared) {
        self.client = client
    }
    
    // MARK: - Load Cards

    /// Load initial cards directly from Firestore (same source as Timeline)
    func loadInitialCards() async {
        guard userState != nil else {
            // No user state - show placeholder cards
            await MainActor.run {
                self.cards = Self.placeholderCards()
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }

        // Load directly from Firestore (same source as Timeline)
        await loadCardsFromFirestore()
    }
    
    /// Refresh cards (pull to refresh or manual)
    func refreshCards() async {
        await loadCardsFromFirestore()
    }

    // MARK: - Direct Firestore Loading (matches TimelineService)

    /// Loads cards directly from Firestore - same source as Timeline
    /// This ensures card stack and timeline show identical data
    private func loadCardsFromFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ PeezyStackViewModel: No user ID for Firestore load")
            await MainActor.run {
                self.isLoading = false
                self.cards = Self.placeholderCards()
            }
            return
        }

        do {
            let db = Firestore.firestore()

            // Query active tasks - same filter as TimelineService
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .whereField("status", in: ["Upcoming", "InProgress", "pending", "Snoozed"])
                .getDocuments()

            print("🃏 PeezyStackViewModel: Found \(snapshot.documents.count) documents in Firestore")

            var loadedCards: [PeezyCard] = []
            let now = Date()

            for document in snapshot.documents {
                let data = document.data()

                // Parse status
                let statusString = data["status"] as? String ?? "Upcoming"
                let status = TaskStatus(rawValue: statusString) ?? .upcoming

                // Skip completed/skipped
                if status == .completed || status == .skipped {
                    continue
                }

                // Parse priority (same logic as TimelineService)
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

                // Parse due date from Firestore Timestamp
                let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()

                // Parse snooze data
                let snoozedUntil = (data["snoozedUntil"] as? Timestamp)?.dateValue()
                let lastSnoozedAt = (data["lastSnoozedAt"] as? Timestamp)?.dateValue()

                // Skip if currently snoozed
                if let snoozedUntil = snoozedUntil, snoozedUntil > now {
                    continue
                }

                // Determine card type based on task properties
                let isVendorTask = (data["category"] as? String)?.lowercased().contains("vendor") ?? false
                let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task

                let card = PeezyCard(
                    id: document.documentID,
                    type: cardType,
                    title: data["title"] as? String ?? "Untitled Task",
                    subtitle: data["desc"] as? String ?? "",
                    colorName: colorNameForPriority(priority),
                    taskId: data["id"] as? String ?? document.documentID,
                    workflowId: data["workflowId"] as? String,
                    vendorCategory: isVendorTask ? (data["category"] as? String) : nil,
                    vendorId: nil,
                    priority: priority,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    status: status,
                    dueDate: dueDate,
                    snoozedUntil: snoozedUntil,
                    lastSnoozedAt: lastSnoozedAt
                )

                // Only include cards that should be shown
                if card.shouldShow {
                    loadedCards.append(card)
                }
            }

            // Sort and update on main thread
            await MainActor.run {
                // Add intro card if we have user state
                var allCards = loadedCards
                if let userState = self.userState {
                    let introCard = PeezyCard(
                        type: .intro,
                        title: Self.greeting(for: userState),
                        subtitle: Self.subtitle(for: userState),
                        colorName: "white"
                    )
                    allCards.append(introCard)
                }

                self.cards = Self.sortCardsForStack(allCards)
                self.isLoading = false
                print("✅ PeezyStackViewModel: Loaded \(self.cards.count) cards from Firestore (same source as Timeline)")
            }

        } catch {
            print("❌ PeezyStackViewModel Firestore load error: \(error)")
            await MainActor.run {
                self.error = .networkError(error)
                self.isLoading = false
                // Fall back to intro cards
                if let userState = self.userState {
                    self.cards = Self.sortCardsForStack(Self.introCards(for: userState))
                }
            }
        }
    }

    /// Color name for priority (matches TimelineService)
    private func colorNameForPriority(_ priority: PeezyCard.Priority) -> String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .normal: return "green"
        case .low: return "gray"
        }
    }

    /// Generate greeting for intro card
    static func greeting(for userState: UserState) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = userState.name.isEmpty ? "" : ", \(userState.name)"

        switch hour {
        case 5..<12:
            return "Good morning\(name)"
        case 12..<17:
            return "Good afternoon\(name)"
        case 17..<22:
            return "Good evening\(name)"
        default:
            return "Hey\(name)"
        }
    }

    /// Generate subtitle for intro card
    static func subtitle(for userState: UserState) -> String {
        if let days = userState.daysUntilMove {
            if days == 0 {
                return "Moving day is here! Let's make it smooth."
            } else if days == 1 {
                return "Just 1 day until your move!"
            } else if days <= 7 {
                return "\(days) days until your move. Let's stay on track."
            } else {
                return "Here's what's on your plate today."
            }
        }
        return "Here's what's on your plate today."
    }

    // MARK: - Handle Swipe (simplified — timeline doesn't use swipe actions)

    /// Handle user swiping a card (retained for backward compatibility)
    func handleSwipe(card: PeezyCard, action: SwipeAction) {
        let generator = UIImpactFeedbackGenerator(style: action == .doIt ? .heavy : .light)
        generator.impactOccurred()

        switch action {
        case .doIt:
            completeCardDirectly(card: card)
        case .later:
            // Simple dismiss — snooze logic is in PeezyHomeViewModel now
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                cards.removeAll { $0.id == card.id }
            }
        }
    }
    
    /// Directly complete a card (remove + notify backend).
    func completeCardDirectly(card: PeezyCard) {
        // Track action
        actionHistory.append(CardActionResult(card: card, action: .doIt))

        // Remove card with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            cards.removeAll { $0.id == card.id }
        }

        // Update local state
        updateLocalState(for: card, action: .doIt)

        // Notify backend (fire and forget, don't block UI)
        Task {
            await notifyBackendOfAction(card: card, action: .doIt)
        }
    }

    /// Update local UserState based on swipe
    private func updateLocalState(for card: PeezyCard, action: SwipeAction) {
        guard var state = userState else { return }
        
        switch action {
        case .doIt:
            // Mark task as pending action / in progress
            if let taskId = card.taskId {
                state.pendingTasks.append(taskId)
            }
            if let vendorCategory = card.vendorCategory {
                state.vendorsContacted.append(vendorCategory)
            }
        case .later:
            // Track deferred tasks
            if let taskId = card.taskId {
                state.deferredTasks.append(taskId)
            }
        }
        
        state.lastInteractionAt = Date()
        self.userState = state
    }
    
    /// Notify backend of card action (may return new cards)
    private func notifyBackendOfAction(card: PeezyCard, action: SwipeAction) async {
        guard let userState = userState else { return }
        
        do {
            let response = try await client.recordCardAction(
                card: card,
                action: action,
                userState: userState
            )
            
            await MainActor.run {
                // Add any new cards from response
                if let newCards = response.cards?.map({ $0.toCard() }), !newCards.isEmpty {
                    // Add new cards and re-sort to maintain correct order
                    var updatedCards = self.cards
                    for card in newCards {
                        if !updatedCards.contains(where: { $0.id == card.id }) {
                            updatedCards.append(card)
                        }
                    }
                    self.cards = Self.sortCardsForStack(updatedCards)
                }

                // Apply state updates
                self.applyStateUpdates(response.stateUpdates)
            }
        } catch {
            // Log but don't show error - action was already processed locally
            print("⚠️ Failed to notify backend: \(error.localizedDescription)")
        }
    }
    
    // MARK: - State Updates
    
    private func applyStateUpdates(_ updates: PeezyResponse.StateUpdates?) {
        guard let updates = updates, var state = userState else { return }
        
        if let heard = updates.heardAccountabilityPitch {
            state.heardAccountabilityPitch = heard
        }
        
        if let completed = updates.tasksCompleted {
            state.completedTasks.append(contentsOf: completed)
        }
        
        self.userState = state
    }
    
    // MARK: - Undo
    
    /// Undo last swipe action
    func undoLastAction() {
        guard let lastAction = actionHistory.popLast() else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            // Re-add the card to top of stack
            cards.append(lastAction.card)
        }
        
        // Remove from local state tracking
        if var state = userState {
            if let taskId = lastAction.card.taskId {
                state.pendingTasks.removeAll { $0 == taskId }
                state.deferredTasks.removeAll { $0 == taskId }
            }
            userState = state
        }
    }
    
    var canUndo: Bool {
        !actionHistory.isEmpty
    }
    
    // MARK: - Add Cards
    
    /// Add a card to the stack (from chat or other source)
    func addCard(_ card: PeezyCard, atTop: Bool = false) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            if atTop {
                cards.append(card)
            } else {
                cards.insert(card, at: 0)
            }
        }
    }
    
    /// Add multiple cards and re-sort to maintain correct order
    func addCards(_ newCards: [PeezyCard]) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            var updatedCards = cards
            for card in newCards {
                if !updatedCards.contains(where: { $0.id == card.id }) {
                    updatedCards.append(card)
                }
            }
            cards = Self.sortCardsForStack(updatedCards)
        }
    }
    
    // MARK: - Placeholder Cards
    
    /// Placeholder cards when loading or no backend
    static func placeholderCards() -> [PeezyCard] {
        [
            PeezyCard(
                type: .task,
                title: "Internet",
                subtitle: "Let's get your WiFi sorted for the new place.",
                colorName: "blue"
            ),
            PeezyCard(
                type: .task,
                title: "Movers",
                subtitle: "Time to book your moving crew.",
                colorName: "green"
            ),
            PeezyCard.intro(updateCount: 2)
        ]
    }
    
    /// Generate intro cards based on user state
    static func introCards(for userState: UserState) -> [PeezyCard] {
        var cards: [PeezyCard] = []

        // Track what tasks we're adding for the briefing
        var hasMovers = false
        var hasInternet = false
        var moversUrgent = false

        // Add contextual task cards based on urgency
        if let days = userState.daysUntilMove {
            if days <= 14 && !userState.vendorsBooked.contains("movers") {
                cards.append(PeezyCard.fromTask(
                    taskId: "book_movers",
                    title: "Movers",
                    subtitle: days <= 7 ? "Getting urgent - let's lock this in." : "Time to book your moving crew.",
                    workflowId: "book_movers",
                    priority: days <= 7 ? .urgent : .high
                ))
                hasMovers = true
                moversUrgent = days <= 7
            }
        }

        // Internet is always relevant
        if !userState.vendorsBooked.contains("internet") {
            cards.append(PeezyCard.fromTask(
                taskId: "internet_setup",
                title: "Internet",
                subtitle: "Let's get your WiFi sorted for the new place.",
                workflowId: "internet_setup",
                priority: .normal
            ))
            hasInternet = true
        }

        // Build warm, user-centric briefing message
        let briefing = buildBriefingMessage(
            hasMovers: hasMovers,
            hasInternet: hasInternet,
            moversUrgent: moversUrgent,
            totalTasks: cards.count
        )

        // Intro card on top with user's name and briefing
        cards.append(PeezyCard.intro(
            userName: userState.name.isEmpty ? nil : userState.name,
            briefing: briefing
        ))

        return cards
    }

    /// Build a warm, eager assistant briefing message
    /// Should feel like a happy assistant who genuinely wants to help
    private static func buildBriefingMessage(
        hasMovers: Bool,
        hasInternet: Bool,
        moversUrgent: Bool,
        totalTasks: Int
    ) -> String {
        // No tasks - all caught up
        if totalTasks == 0 {
            return "All clear! I'll let you know when something comes up."
        }

        // Single task - eager, helpful tone
        if totalTasks == 1 {
            if hasInternet {
                return "Just one thing today - I need your input on a few details so I can get the internet set up for you."
            }
            if hasMovers {
                if moversUrgent {
                    return "I found some great mover options - wanted to get these in front of you before they book up."
                }
                return "I put together some mover options for you to check out whenever you're ready."
            }
        }

        // Multiple tasks - still warm and eager
        if hasMovers && hasInternet {
            if moversUrgent {
                return "Got a couple things for you - some mover options to review, and a few quick details so I can schedule your internet."
            }
            return "I've got mover quotes ready for you, plus a few questions so I can get your internet sorted."
        }

        // Generic fallback
        if totalTasks == 2 {
            return "Couple things for you today - shouldn't take long!"
        }

        return "Got a few things ready for you."
    }

    // MARK: - Card Sorting

    /// Sort cards for stack display: most urgent (earliest due date) on TOP
    /// In a card stack, the LAST item in the array is shown on TOP (visible to user).
    /// So we sort: latest due date first, earliest due date last (end of array = top of stack).
    /// Intro cards always go on top (end of array).
    /// Filters out cards that are currently snoozed (snoozedUntil is in the future).
    static func sortCardsForStack(_ cards: [PeezyCard]) -> [PeezyCard] {
        // Separate intro cards from other cards
        let introCards = cards.filter { $0.type == .intro }

        // Filter out snoozed cards (those with snoozedUntil in the future)
        // and separate task cards
        let now = Date()
        let activeCards = cards.filter { card in
            guard card.type != .intro else { return false }

            // If card has snoozedUntil in the future, filter it out
            if let snoozedUntil = card.snoozedUntil, snoozedUntil > now {
                return false
            }
            return true
        }

        // Sort non-intro cards: latest due date first, earliest last
        // This puts earliest due date at END of array (top of stack)
        let sortedOther = activeCards.sorted { card1, card2 in
            // Primary sort: by due date (descending - latest first)
            let date1 = card1.dueDate ?? Date.distantFuture
            let date2 = card2.dueDate ?? Date.distantFuture

            if date1 != date2 {
                return date1 > date2  // Later dates first in array
            }

            // Secondary sort: by priority (lower priority first, higher priority at end/top)
            return card1.priority < card2.priority
        }

        // Combine: sorted tasks first, then intro cards on top (end of array)
        return sortedOther + introCards
    }
}
