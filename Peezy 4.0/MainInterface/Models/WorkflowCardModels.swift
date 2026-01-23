//
//  WorkflowCardModels.swift
//  Peezy
//
//  Models for workflow qualifying questions
//
//  Card Types:
//  - intro: Explains the workflow
//  - question: Multi-choice question
//  - recap: Summary before submission
//

import Foundation

// MARK: - Workflow Qualifying Data (from backend)

struct WorkflowQualifying: Codable, Equatable {
    let workflowId: String
    let intro: WorkflowIntro
    let questions: [WorkflowQuestion]
    let recap: WorkflowRecap?
    let questionCount: Int

    // Custom init for decoding (questionCount may come from backend or be computed)
    init(workflowId: String, intro: WorkflowIntro, questions: [WorkflowQuestion], recap: WorkflowRecap?, questionCount: Int? = nil) {
        self.workflowId = workflowId
        self.intro = intro
        self.questions = questions
        self.recap = recap
        self.questionCount = questionCount ?? questions.count
    }

    // Default recap for workflows that don't have one
    var recapOrDefault: WorkflowRecap {
        return recap ?? WorkflowRecap(
            title: "Ready to submit",
            closing: "We'll get back to you soon.",
            button: "Submit"
        )
    }
}

struct WorkflowIntro: Codable, Equatable {
    let title: String
    let subtitle: String
}

struct WorkflowQuestion: Codable, Equatable, Identifiable {
    let id: String
    let question: String
    let subtitle: String?
    let options: [QuestionOption]
    let type: QuestionType

    enum QuestionType: String, Codable {
        case single_select
        case multi_select
    }

    init(id: String, question: String, subtitle: String? = nil, options: [QuestionOption], type: QuestionType = .single_select) {
        self.id = id
        self.question = question
        self.subtitle = subtitle
        self.options = options
        self.type = type
    }
}

struct QuestionOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let icon: String
    let subtitle: String?
    let exclusive: Bool?

    init(id: String, label: String, icon: String, subtitle: String? = nil, exclusive: Bool? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.subtitle = subtitle
        self.exclusive = exclusive
    }
}

struct WorkflowRecap: Codable, Equatable {
    let title: String
    let closing: String
    let button: String
}

// MARK: - Workflow Card (UI State)

enum WorkflowCardType: Equatable {
    case intro
    case question
    case recap
}

struct WorkflowCard: Identifiable, Equatable {
    let id: String
    let workflowId: String
    let workflowTitle: String
    let cardType: WorkflowCardType
    let qualifying: WorkflowQualifying

    // For question cards
    var questionIndex: Int?

    // MARK: - Computed Properties

    var progressText: String? {
        switch cardType {
        case .intro:
            return nil
        case .question:
            guard let index = questionIndex else { return nil }
            return "\(index + 1) of \(qualifying.questionCount)"
        case .recap:
            return "Review"
        }
    }

    var currentQuestion: WorkflowQuestion? {
        guard cardType == .question, let index = questionIndex else { return nil }
        guard index < qualifying.questions.count else { return nil }
        return qualifying.questions[index]
    }

    // MARK: - Equatable
    static func == (lhs: WorkflowCard, rhs: WorkflowCard) -> Bool {
        lhs.id == rhs.id
    }
}

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
    mutating func toggleAnswer(questionId: String, optionId: String, isExclusive: Bool, allOptions: [QuestionOption]) {
        var current = Set(answers[questionId] ?? [])

        if current.contains(optionId) {
            current.remove(optionId)
        } else {
            if isExclusive {
                // Exclusive option - clear others and select only this
                current = [optionId]
            } else {
                // Non-exclusive - remove any exclusive options first
                let exclusiveIds = Set(allOptions.filter { $0.exclusive == true }.map { $0.id })
                current.subtract(exclusiveIds)
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
