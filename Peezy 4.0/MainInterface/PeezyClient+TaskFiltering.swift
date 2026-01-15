//
//  PeezyClient+TaskFiltering.swift
//  Peezy
//
//  Extension to filter snoozed tasks when loading cards
//
//  ARCHITECTURE NOTE:
//  The actual snooze filtering happens in two places:
//  1. SnoozeManager.swift - writes snoozedUntil to Firestore when user snoozes
//  2. PeezyCard.shouldShow - filters cards client-side based on snooze date
//
//  For production, server-side filtering should be added to the Firebase
//  function that returns cards (to avoid loading snoozed tasks at all).
//

import Foundation

extension PeezyClient {

    // MARK: - Client-Side Task Filtering

    /// Filters a list of cards to only show non-snoozed, active tasks
    /// Use this after loading cards from backend
    static func filterVisibleCards(_ cards: [PeezyCard]) -> [PeezyCard] {
        return cards.filter { card in
            // Use the card's shouldShow computed property
            card.shouldShow
        }
    }

    /// Sorts cards by priority and due date
    static func sortCardsByUrgency(_ cards: [PeezyCard]) -> [PeezyCard] {
        return cards.sorted { lhs, rhs in
            // Higher priority first
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            // Earlier due date first
            let lhsDue = lhs.dueDate ?? .distantFuture
            let rhsDue = rhs.dueDate ?? .distantFuture
            return lhsDue < rhsDue
        }
    }
}

// MARK: - Future: Server-Side Filtering

/*

 When implementing server-side filtering in Firebase Functions,
 the query should:

 1. Filter out tasks where snoozedUntil > now
 2. Filter out tasks with status "Completed" or "Skipped"
 3. Include tasks with status "Snoozed" only if snoozedUntil <= now

 Example Firestore query approach:

 // Query 1: Active tasks (not snoozed)
 const activeTasks = await db.collection('users')
     .doc(userId)
     .collection('tasks')
     .where('status', 'in', ['Upcoming', 'InProgress'])
     .get();

 // Query 2: Snoozed tasks whose snooze time has passed
 const unsnoozedTasks = await db.collection('users')
     .doc(userId)
     .collection('tasks')
     .where('status', '==', 'Snoozed')
     .where('snoozedUntil', '<=', admin.firestore.Timestamp.now())
     .get();

 // Combine and return

*/
