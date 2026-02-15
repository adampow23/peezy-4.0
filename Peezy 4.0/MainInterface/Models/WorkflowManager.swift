//
//  WorkflowManager.swift
//  Peezy
//
//  Manages workflow state and coordinates with WorkflowService
//

import Foundation
import SwiftUI

@Observable
class WorkflowManager {

    // MARK: - State

    private(set) var isInWorkflow = false
    private(set) var currentWorkflowId: String?
    private(set) var currentWorkflowTitle: String?
    private(set) var workflowCards: [WorkflowCard] = []
    private(set) var answers = WorkflowAnswers(workflowId: "")

    var isLoading = false
    var error: String?

    // MARK: - Callbacks

    /// Called when workflow completes successfully (user submitted)
    var onWorkflowComplete: (() -> Void)?

    /// Called when workflow is dismissed/cancelled by user
    var onWorkflowDismissed: (() -> Void)?

    /// Called when user swipes up to open chat from within workflow
    var onOpenChat: (() -> Void)?

    // Track current question index
    private var currentQuestionIndex = 0
    private var qualifying: WorkflowQualifying?

    // Service
    private let service = WorkflowService()

    // Double-submit guard
    private var isSubmitting = false

    // MARK: - Start Workflow

    /// Start a workflow with optional display title
    /// - Parameters:
    ///   - workflowId: The workflow identifier (e.g., "book_movers")
    ///   - workflowTitle: Optional display title (falls back to formatted workflowId)
    func startWorkflow(workflowId: String, workflowTitle: String? = nil) async {
        guard !isInWorkflow else { return }

        isLoading = true
        error = nil

        // Store the title (use provided or format from ID)
        let displayTitle = workflowTitle ?? formatWorkflowTitle(workflowId)

        do {
            // Fetch qualifying questions
            let qualifying = try await service.getQualifying(for: workflowId)
            self.qualifying = qualifying

            await MainActor.run {
                // Initialize state
                self.isInWorkflow = true
                self.currentWorkflowId = workflowId
                self.currentWorkflowTitle = displayTitle
                self.currentQuestionIndex = 0
                self.answers = WorkflowAnswers(workflowId: workflowId)

                // Create intro card
                let introCard = WorkflowCard(
                    id: "\(workflowId)-intro",
                    workflowId: workflowId,
                    workflowTitle: displayTitle,
                    cardType: .intro,
                    qualifying: qualifying
                )

                self.workflowCards = [introCard]
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Progress to Next Card

    func progressToNext() {
        guard let qualifying = qualifying,
              let workflowId = currentWorkflowId,
              let title = currentWorkflowTitle else { return }

        // Determine what's next
        if currentQuestionIndex < qualifying.questions.count {
            // Show next question
            var questionCard = WorkflowCard(
                id: "\(workflowId)-q\(currentQuestionIndex)",
                workflowId: workflowId,
                workflowTitle: title,
                cardType: .question,
                qualifying: qualifying
            )
            questionCard.questionIndex = currentQuestionIndex

            currentQuestionIndex += 1

            withAnimation(.spring(response: 0.3)) {
                workflowCards = [questionCard]
            }
        } else {
            // Show recap
            let recapCard = WorkflowCard(
                id: "\(workflowId)-recap",
                workflowId: workflowId,
                workflowTitle: title,
                cardType: .recap,
                qualifying: qualifying
            )

            withAnimation(.spring(response: 0.3)) {
                workflowCards = [recapCard]
            }
        }
    }

    // MARK: - Handle Selection

    func selectOption(questionId: String, optionId: String, isExclusive: Bool) {
        guard let qualifying = qualifying else { return }

        // Find all options for this question to handle exclusive logic
        if let question = qualifying.questions.first(where: { $0.id == questionId }) {
            let allOptions = question.options
            answers.toggleAnswer(
                questionId: questionId,
                optionId: optionId,
                isExclusive: isExclusive,
                allOptions: allOptions
            )
        }
    }

    // MARK: - Complete Workflow

    func completeWorkflow(userId: String) async -> Bool {
        // Double-submit guard
        guard !isSubmitting else { return false }
        isSubmitting = true

        defer { isSubmitting = false }

        guard let workflowId = currentWorkflowId else { return false }

        isLoading = true

        do {
            let response = try await service.submitAnswers(
                workflowId: workflowId,
                answers: answers,
                userId: userId
            )

            await MainActor.run {
                self.isLoading = false

                if response.success {
                    // Capture callback before reset (reset clears it)
                    let completionCallback = self.onWorkflowComplete
                    self.resetWorkflow()
                    // Call completion callback after reset
                    completionCallback?()
                } else {
                    self.error = "Submission failed"
                }
            }

            return response.success
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
            return false
        }
    }

    // MARK: - Cancel/Reset

    func cancelWorkflow() {
        // Capture callback before reset (reset clears it)
        let dismissCallback = onWorkflowDismissed
        resetWorkflow()
        // Call dismissal callback after reset
        dismissCallback?()
    }

    private func resetWorkflow() {
        isInWorkflow = false
        currentWorkflowId = nil
        currentWorkflowTitle = nil
        workflowCards = []
        answers = WorkflowAnswers(workflowId: "")
        currentQuestionIndex = 0
        qualifying = nil
        error = nil
        // Clear callbacks
        onWorkflowComplete = nil
        onWorkflowDismissed = nil
        onOpenChat = nil
    }

    // MARK: - Demo Workflow (No Firebase)

    /// Start a workflow with pre-loaded data (no Firebase fetch).
    /// Used for walkthrough demo workflows.
    func startDemoWorkflow(workflowId: String, workflowTitle: String, qualifying: WorkflowQualifying) {
        guard !isInWorkflow else { return }

        self.qualifying = qualifying
        self.isInWorkflow = true
        self.currentWorkflowId = workflowId
        self.currentWorkflowTitle = workflowTitle
        self.currentQuestionIndex = 0
        self.answers = WorkflowAnswers(workflowId: workflowId)
        self.isLoading = false
        self.error = nil

        let introCard = WorkflowCard(
            id: "\(workflowId)-intro",
            workflowId: workflowId,
            workflowTitle: workflowTitle,
            cardType: .intro,
            qualifying: qualifying
        )
        self.workflowCards = [introCard]
    }

    // MARK: - Helpers

    private func formatWorkflowTitle(_ workflowId: String) -> String {
        workflowId
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
