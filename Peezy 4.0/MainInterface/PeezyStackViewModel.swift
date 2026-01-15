import SwiftUI
import Observation

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

    // Workflow support
    var workflowManager = WorkflowManager()
    var isInWorkflow: Bool { workflowManager.isInWorkflow }
    var workflowTriggeredByCardId: String? = nil

    // Snooze support
    var snoozeManager = SnoozeManager()
    var isSnoozing: Bool { snoozeManager.isSnoozing }

    // Helper for workflow submission
    var currentUserId: String? {
        userState?.userId
    }

    // Helper for snooze - user's move date from assessment
    var userMoveDate: Date? {
        userState?.moveDate
    }

    // Track actions for undo
    private var actionHistory: [CardActionResult] = []
    
    // Dependencies
    private let client: PeezyClient
    
    // MARK: - Init
    init(client: PeezyClient = .shared) {
        self.client = client
    }
    
    // MARK: - Load Cards
    
    /// Load initial cards from backend (call on appear)
    func loadInitialCards() async {
        guard let userState = userState else {
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
        
        do {
            let response = try await client.getInitialCards(userState: userState)
            
            await MainActor.run {
                // Convert backend cards to UI cards
                if let cardData = response.cards, !cardData.isEmpty {
                    self.cards = cardData.map { $0.toCard() }
                } else {
                    // Backend didn't return cards - generate intro
                    self.cards = Self.introCards(for: userState)
                }
                
                // Apply any state updates
                self.applyStateUpdates(response.stateUpdates)
                
                self.isLoading = false
            }
        } catch let peezyError as PeezyError {
            await MainActor.run {
                self.error = peezyError
                self.isLoading = false
                // Show placeholder cards on error
                self.cards = Self.placeholderCards()
            }
        } catch {
            await MainActor.run {
                self.error = .networkError(error)
                self.isLoading = false
                self.cards = Self.placeholderCards()
            }
        }
    }
    
    /// Refresh cards (pull to refresh or manual)
    func refreshCards() async {
        await loadInitialCards()
    }
    
    // MARK: - Handle Swipe

    /// Handle user swiping a card
    func handleSwipe(card: PeezyCard, action: SwipeAction) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: action == .doIt ? .heavy : .light)
        generator.impactOccurred()

        switch action {
        case .doIt:
            // Track action
            actionHistory.append(CardActionResult(card: card, action: action))

            // Remove card with animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                cards.removeAll { $0.id == card.id }
            }

            // Update local state
            updateLocalState(for: card, action: action)

            // Notify backend (fire and forget, don't block UI)
            Task {
                await notifyBackendOfAction(card: card, action: action)
            }

        case .later:
            // Use snooze flow for snoozeable cards
            handleLaterSwipe(for: card)

            // Track action (card removal handled by snooze completion)
            actionHistory.append(CardActionResult(card: card, action: action))

            // Update local state
            updateLocalState(for: card, action: action)

            // Notify backend
            Task {
                await notifyBackendOfAction(card: card, action: action)
            }
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
                    // Insert new cards at bottom of stack
                    for card in newCards {
                        if !self.cards.contains(where: { $0.id == card.id }) {
                            self.cards.insert(card, at: 0)
                        }
                    }
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
    
    /// Add multiple cards
    func addCards(_ newCards: [PeezyCard]) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            for card in newCards {
                if !cards.contains(where: { $0.id == card.id }) {
                    cards.insert(card, at: 0)
                }
            }
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
        }
        
        // Intro card on top
        cards.append(PeezyCard.intro(updateCount: cards.count))
        
        return cards
    }
}
