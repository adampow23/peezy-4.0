//
//  WorkflowCardModels.swift
//  Peezy
//
//  Minimal models for workflow answer submission.
//  Used by per-task flow files and WorkflowService.
//

import Foundation

// MARK: - Workflow Answers

struct WorkflowAnswers: Equatable {
    let workflowId: String
    var answers: [String: [String]] = [:]  // questionId -> selected optionIds

    init(workflowId: String) {
        self.workflowId = workflowId
    }

    /// Get selected option IDs for a question
    func getAnswer(questionId: String) -> [String] {
        return answers[questionId] ?? []
    }

    /// Toggle selection for an option
    mutating func toggleAnswer(questionId: String, optionId: String, isExclusive: Bool, allOptions: [String]) {
        var current = Set(answers[questionId] ?? [])

        if current.contains(optionId) {
            current.remove(optionId)
        } else {
            if isExclusive {
                current = [optionId]
            } else {
                current.insert(optionId)
            }
        }

        answers[questionId] = Array(current)
    }

    /// Check if an option is selected
    func isSelected(questionId: String, optionId: String) -> Bool {
        answers[questionId]?.contains(optionId) ?? false
    }

    /// Check if question has any answer
    func hasAnswer(for questionId: String) -> Bool {
        guard let selected = answers[questionId] else { return false }
        return !selected.isEmpty
    }

    /// Convert to dictionary for submission
    func toDictionary() -> [String: Any] {
        return [
            "workflowId": workflowId,
            "answers": answers
        ]
    }
}

// MARK: - Workflow Submission Response

struct WorkflowSubmissionResponse {
    let success: Bool
    let submissionId: String
    let message: String
    let estimatedResponseTime: String
}
