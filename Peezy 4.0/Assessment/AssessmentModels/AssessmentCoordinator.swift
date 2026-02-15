//
//  AssessmentCoordinator.swift
//  Peezy
//
//  Manages assessment flow navigation and completion
//

import SwiftUI
import Combine
import FirebaseAuth

enum AssessmentStep: String, CaseIterable {
    case UserName
    case MoveDate
    case MoveExperience
    case MoveConcerns
    case HowHeard
    case MoveDistance
    case CurrentRentOrOwn
    case CurrentDwellingType
    case NewRentOrOwn
    case NewDwellingType
    case WhosMoving
    case AnyPets
    case HireMovers
    case HirePackers
    case HireCleaners
    
    var stepNumber: Int {
        return AssessmentStep.allCases.firstIndex(of: self)! + 1
    }
    
    var totalSteps: Int {
        return AssessmentStep.allCases.count
    }
}

class AssessmentCoordinator: ObservableObject {
    @Published var path: [AssessmentStep] = []
    @Published var isComplete = false
    @Published var isSaving = false
    @Published var saveError: Error?
    
    private var isCompleting = false
    private let dataManager: AssessmentDataManager
    
    init(dataManager: AssessmentDataManager) {
        self.dataManager = dataManager
    }
    
    func goToNext(from current: AssessmentStep) {
        guard let currentIndex = AssessmentStep.allCases.firstIndex(of: current),
              currentIndex < AssessmentStep.allCases.count - 1 else {
            // Last step - complete the assessment
            Task {
                await completeAssessment()
            }
            return
        }
        
        let nextStep = AssessmentStep.allCases[currentIndex + 1]
        path.append(nextStep)
    }
    
    @MainActor
    func completeAssessment() async {
        guard !isCompleting else { return }
        isCompleting = true

        let userId = Auth.auth().currentUser?.uid ?? ""
        print("🚀 Starting assessment completion for user: \(userId)")

        // Show completion screen IMMEDIATELY
        isComplete = true

        // Now do the work in background
        isSaving = true

        do {
            // 1. Get assessment data
            let assessmentData = dataManager.getAllAssessmentData()
            let moveDate = dataManager.MoveDate ?? Date()

            print("⏳ ASSESSMENT: Saving to Firestore...")

            // 2. Save assessment
            try await dataManager.saveAssessment()

            print("⏳ ASSESSMENT: Generating tasks...")

            // 3. Generate tasks
            let taskService = TaskGenerationService()
            let tasksGenerated = try await taskService.generateTasksForUser(
                userId: userId,
                assessment: assessmentData,
                moveDate: moveDate
            )

            print("✅ ASSESSMENT: Complete! Generated \(tasksGenerated) tasks")

            isSaving = false

        } catch {
            print("❌ Error completing assessment: \(error.localizedDescription)")
            isSaving = false
            saveError = error
            // Don't set isComplete = false - let user proceed anyway
        }
    }
    
    func goBack() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    func reset() {
        path.removeAll()
        isComplete = false
        isSaving = false
        saveError = nil
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let assessmentCompleted = Notification.Name("assessmentCompleted")
}
