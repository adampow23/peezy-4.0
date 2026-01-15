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
    private func completeAssessment() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No user ID - cannot save assessment")
            saveError = NSError(
                domain: "AssessmentCoordinator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
            )
            // Still mark complete so user isn't stuck
            isComplete = true
            return
        }
        
        isSaving = true
        print("🚀 Starting assessment completion for user: \(userId)")
        
        do {
            // 1. Get assessment data
            let assessmentData = dataManager.getAllAssessmentData()
            let moveDate = dataManager.MoveDate
            
            // 2. Save assessment to Firestore (both locations)
            try await dataManager.saveAssessment()
            print("✅ Assessment saved to Firestore")
            
            // 3. Generate personalized tasks
            let taskService = TaskGenerationService()
            let tasksGenerated = try await taskService.generateTasksForUser(
                userId: userId,
                assessment: assessmentData,
                moveDate: moveDate
            )
            print("✅ Generated \(tasksGenerated) tasks")
            
            isSaving = false
            isComplete = true
            
            // Notify AppRootView to transition to main app
            NotificationCenter.default.post(
                name: .assessmentCompleted,
                object: nil
            )
            
        } catch {
            print("❌ Error completing assessment: \(error.localizedDescription)")
            isSaving = false
            saveError = error
            
            // Still mark complete so user can proceed
            // They can retry or data will sync later
            isComplete = true
            
            NotificationCenter.default.post(
                name: .assessmentCompleted,
                object: nil
            )
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
