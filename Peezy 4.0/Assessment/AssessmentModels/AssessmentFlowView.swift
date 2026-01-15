//
//  AssessmentFlowView.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/9/25.
//

import SwiftUI

// MARK: - AssessmentFlowView

struct AssessmentFlowView: View {
    @StateObject private var assessmentData: AssessmentDataManager
    @StateObject private var coordinator: AssessmentCoordinator

    init() {
        // Create a single shared instance of AssessmentDataManager
        let manager = AssessmentDataManager()
        _assessmentData = StateObject(wrappedValue: manager)
        _coordinator = StateObject(wrappedValue: AssessmentCoordinator(dataManager: manager))
    }

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            UserName()
                .navigationDestination(for: AssessmentStep.self) { step in
                    destinationView(for: step)
                }
        }
        .environmentObject(coordinator)
        .environmentObject(assessmentData)
        .sheet(isPresented: $coordinator.isComplete) {
            AssessmentCompleteView()
        }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    func destinationView(for step: AssessmentStep) -> some View {
        switch step {
        case .UserName:
            UserName()
        case .MoveDate:
            MoveDate()
        case .MoveExperience:
            MoveExperience()
        case .MoveConcerns:
            MoveConcerns()
        case .HowHeard:
            HowHeard()
        case .MoveDistance:
            MoveDistance()
        case .CurrentRentOrOwn:
            CurrentRentOrOwn()
        case .CurrentDwellingType:
            CurrentDwellingType()
        case .NewRentOrOwn:
            NewRentOrOwn()
        case .NewDwellingType:
            NewDwellingType()
        case .WhosMoving:
            WhosMoving()
        case .AnyPets:
            AnyPets()
        case .HireMovers:
            HireMovers()
        case .HirePackers:
            HirePackers()
        case .HireCleaners:
            HireCleaners()
        }
    }
}

// MARK: - Preview

#Preview {
    AssessmentFlowView()
}
