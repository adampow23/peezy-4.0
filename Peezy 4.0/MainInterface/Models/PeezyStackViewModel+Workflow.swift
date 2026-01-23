//
//  PeezyStackViewModel+Workflow.swift
//  Peezy
//
//  Extension to handle workflow qualifying questions and mini-assessments
//
//  INTEGRATION:
//  Add these properties to PeezyStackViewModel.swift:
//
//    var workflowManager = WorkflowManager()
//    var isInWorkflow: Bool { workflowManager.isInWorkflow }
//    var workflowTriggeredByCardId: String?
//

import SwiftUI

extension PeezyStackViewModel {
    
    // MARK: - Workflow Detection
    
    /// Check if a card has an associated workflow (vendor qualifying or mini-assessment)
    func getWorkflowId(for card: PeezyCard) -> String? {
        // 1. Check if card has workflowId directly (mini-assessments)
        if let workflowId = card.workflowId, !workflowId.isEmpty {
            return workflowId
        }
        
        // 2. Check if card has a taskId that maps to a workflow
        if let taskId = card.taskId {
            // Mini-assessment IDs start with "address_change_"
            if taskId.starts(with: "address_change_") {
                return taskId
            }
        }
        
        // 3. Fall back to vendor workflow mapping by title
        return mapCardToVendorWorkflow(card)
    }
    
    /// Maps vendor task cards to their workflow IDs
    private func mapCardToVendorWorkflow(_ card: PeezyCard) -> String? {
        let title = card.title.lowercased()
        
        // Vendor workflows
        if title.contains("book") && title.contains("mover") {
            if title.contains("long") || title.contains("distance") {
                return "book_long_distance_movers"
            }
            return "book_movers"
        }
        
        if title.contains("clean") {
            return "cleaning_service"
        }
        
        if title.contains("junk") || title.contains("removal") {
            return "junk_removal"
        }
        
        if title.contains("internet") || title.contains("wifi") {
            return "internet_setup"
        }
        
        if title.contains("storage") {
            return "storage_unit"
        }
        
        if title.contains("pet") && title.contains("transport") {
            return "pet_transport"
        }
        
        if title.contains("car") && (title.contains("ship") || title.contains("transport")) {
            return "auto_transport"
        }
        
        if title.contains("pack") && title.contains("service") {
            return "packing_services"
        }
        
        return nil
    }
    
    // MARK: - Do It Swipe Handler
    
    /// Handles "Do It" swipe - checks for workflow before proceeding
    func handleDoItSwipe(for card: PeezyCard) async {
        // Check if this card has an associated workflow
        if let workflowId = getWorkflowId(for: card) {
            // Track which card triggered the workflow
            workflowTriggeredByCardId = card.id
            
            // Start the workflow
            await workflowManager.startWorkflow(
                workflowId: workflowId,
                workflowTitle: card.title
            )
            
            // Set up completion handler
            workflowManager.onWorkflowComplete = { [weak self] in
                self?.handleWorkflowComplete()
            }
            
            // Set up dismissal handler (user cancelled)
            workflowManager.onWorkflowDismissed = { [weak self] in
                self?.onWorkflowDismissed()
            }
            
            // Set up chat handler (swipe up)
            workflowManager.onOpenChat = { [weak self] in
                // Post notification or handle chat opening
                NotificationCenter.default.post(name: .openChat, object: nil)
            }
        } else {
            // No workflow - proceed with normal "do it" action
            handleSwipe(card: card, action: .doIt)
        }
    }
    
    // MARK: - Workflow Actions (called from WorkflowCardView)

    /// User tapped continue on intro or finished a question
    func handleWorkflowContinue() {
        workflowManager.progressToNext()
    }

    /// User selected an option in a question
    func handleWorkflowSelect(questionId: String, optionId: String, isExclusive: Bool) {
        workflowManager.selectOption(questionId: questionId, optionId: optionId, isExclusive: isExclusive)
    }

    // MARK: - Workflow Completion

    /// Called when user completes workflow (taps done on recap)
    func handleWorkflowComplete() {
        guard let userId = currentUserId else {
            workflowManager.error = "User not authenticated"
            return
        }

        Task {
            let success = await workflowManager.completeWorkflow(userId: userId)
            if success {
                onWorkflowCompleted()
            }
        }
    }

    /// Called after workflow submission succeeds
    func onWorkflowCompleted() {
        // Remove the card that triggered the workflow
        if let triggeredCardId = workflowTriggeredByCardId {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                cards.removeAll { $0.id == triggeredCardId }
            }
        }

        // Clear tracking
        workflowTriggeredByCardId = nil

        // Refresh cards to show any newly generated tasks
        Task {
            await refreshCards()
        }
    }

    /// Called when workflow is dismissed/cancelled by user
    func onWorkflowDismissed() {
        // Don't remove the card - user cancelled
        workflowTriggeredByCardId = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openChat = Notification.Name("openChat")
}
