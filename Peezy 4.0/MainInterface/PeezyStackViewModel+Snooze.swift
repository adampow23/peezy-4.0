//
//  PeezyStackViewModel+Snooze.swift
//  Peezy
//
//  Extension to handle snooze flow when user swipes left
//
//  INTEGRATION CHECKLIST:
//  1. Add to PeezyStackViewModel.swift:
//
//       var snoozeManager = SnoozeManager()
//       var isSnoozing: Bool { snoozeManager.isSnoozing }
//
//  2. In handleSwipe(), change .later case to use handleLaterSwipe()
//
//  3. In PeezyStackViewComplete, add snooze overlay (see that file)
//

import SwiftUI

extension PeezyStackViewModel {

    // MARK: - Later Swipe Handler

    /// Handles "Later" swipe - triggers snooze flow for valid tasks
    /// Call this from handleSwipe() when action is .later
    ///
    /// ```swift
    /// case .later:
    ///     handleLaterSwipe(for: card)
    /// ```
    func handleLaterSwipe(for card: PeezyCard) {
        // Only snoozeable cards trigger the snooze flow
        guard card.canSnooze else {
            // Non-snoozeable cards (intro, milestones, etc.) just dismiss
            dismissCard(card)
            return
        }

        guard let taskId = card.taskId else {
            // Safety check - canSnooze should already prevent this
            dismissCard(card)
            return
        }

        // Start snooze flow
        snoozeManager.startSnooze(
            taskId: taskId,
            taskTitle: card.title,
            taskDueDate: card.dueDate,
            moveDate: userMoveDate  // From user's assessment
        )

        // Set up completion callback - remove card from stack
        snoozeManager.onSnoozeComplete = { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.cards.removeAll { $0.id == card.id }
            }
        }

        // Set up cancel callback - card stays in stack
        snoozeManager.onSnoozeCancelled = { [weak self] in
            // Card stays where it is, user can try again
            // Reset any drag state if needed
            self?.resetCardPosition(card)
        }
    }

    // MARK: - Helper Methods

    /// Dismisses a card without snooze (for non-task cards)
    private func dismissCard(_ card: PeezyCard) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            cards.removeAll { $0.id == card.id }
        }
    }

    /// Resets card position after cancelled snooze
    private func resetCardPosition(_ card: PeezyCard) {
        // If using drag offset state, reset it here
        // This depends on how your card view tracks drag state
    }
}

// MARK: - Updated handleSwipe Implementation

/*

 UPDATE YOUR handleSwipe() METHOD IN PeezyStackViewModel.swift:

 func handleSwipe(card: PeezyCard, action: SwipeAction) {
     switch action {
     case .doIt:
         // Check for workflow first
         Task {
             await handleDoItSwipe(for: card)
         }

     case .later:
         // NEW: Use snooze handler
         handleLaterSwipe(for: card)

     case .skip:
         // Remove card entirely (user doesn't need this)
         withAnimation {
             cards.removeAll { $0.id == card.id }
         }
         // Optionally update Firestore status to "Skipped"
     }
 }

 */
