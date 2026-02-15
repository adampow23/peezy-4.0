//
//  AssessmentFlowView.swift
//  Peezy
//
//  The container view that hosts the entire assessment flow.
//  Renders the correct view based on the coordinator's current node:
//  - Interstitial nodes → ConversationalInterstitialView (comment only, tap to dismiss)
//  - Input nodes → AssessmentInputWrapper (context typewriter + reveal) wrapping the question view
//
//  Progress bar visible throughout. Completion sheet on finish.
//

import SwiftUI

struct AssessmentFlowView: View {
    
    @Binding var showAssessment: Bool
    @StateObject private var coordinator: AssessmentCoordinator
    @StateObject private var dataManager: AssessmentDataManager
    
    init(showAssessment: Binding<Bool>) {
        _showAssessment = showAssessment
        let dm = AssessmentDataManager()
        _dataManager = StateObject(wrappedValue: dm)
        _coordinator = StateObject(wrappedValue: AssessmentCoordinator(dataManager: dm))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress bar — visible on input screens, hidden on interstitials
                if let node = coordinator.currentNode, !node.isInterstitial {
                    assessmentProgressBar
                        .transition(.opacity)
                }
                
                // Main content area
                if let node = coordinator.currentNode {
                    nodeView(for: node)
                        .id(coordinator.currentIndex) // Force fresh view on navigation
                }
            }
        }
        .environmentObject(coordinator)
        .environmentObject(dataManager)
        .sheet(isPresented: $coordinator.isComplete) {
            AssessmentCompleteView()
                .environmentObject(coordinator)
                .environmentObject(dataManager)
        }
    }
    
    // MARK: - Progress Bar
    
    private var assessmentProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                // Back button
                if coordinator.currentInputStepNumber > 1 {
                    Button {
                        coordinator.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Step counter
                Text("\(coordinator.currentInputStepNumber) of \(coordinator.totalInputSteps)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: geo.size.width * coordinator.progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: coordinator.progress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Node Routing
    
    @ViewBuilder
    private func nodeView(for node: AssessmentNode) -> some View {
        switch node {
        case .interstitial(let afterStep):
            let comment = coordinator.interstitialComment(after: afterStep)
            ConversationalInterstitialView(commentText: comment.text) {
                coordinator.goToNext()
            }
            
        case .input(let step):
            AssessmentInputWrapper(step: step, coordinator: coordinator) {
                questionView(for: step)
            }
        }
    }
    
    // MARK: - Question View Switch
    
    /// Returns the raw question view for a given step.
    /// These views contain ONLY input controls (tiles, text fields, pickers, etc.)
    /// Context header/subheader is handled by AssessmentInputWrapper.
    @ViewBuilder
    private func questionView(for step: AssessmentInputStep) -> some View {
        switch step {
        // --- Section 1: Basics ---
        case .userName:              UserName()
        case .moveExperience:        MoveExperience()
        case .moveConcerns:          MoveConcerns()
        case .moveOutDate:           MoveOutDate()
        case .moveInDate:            MoveInDate()
        case .moveFlexibility:       MoveFlexibility()
            
        // --- Section 2: Current Home ---
        case .currentRentOrOwn:      CurrentRentOrOwn()
        case .currentDwellingType:   CurrentDwellingType()
        case .currentAddress:        CurrentAddress()
        case .currentFloor:          CurrentFloor()
        case .currentElevatorAccess: CurrentElevatorAccess()
        case .currentBedrooms:       CurrentBedrooms()
        case .currentSquareFootage:  CurrentSquareFootage()
        case .currentFinishedSqFt:   CurrentFinishedSqFt()
        case .currentUnfinishedSqFt: CurrentUnfinishedSqFt()
            
        // --- Section 3: New Home ---
        case .newRentOrOwn:          NewRentOrOwn()
        case .newDwellingType:       NewDwellingType()
        case .newAddress:            NewAddress()
        case .newFloor:              NewFloor()
        case .newElevatorAccess:     NewElevatorAccess()
        case .newBedrooms:           NewBedrooms()
        case .newSquareFootage:      NewSquareFootage()
        case .newFinishedSqFt:       NewFinishedSqFt()
        case .newUnfinishedSqFt:     NewUnfinishedSqFt()
            
        // --- Section 4: People ---
        case .anyChildren:           AnyChildren()
        case .childrenAges:          ChildrenAges()
        case .anyPets:               AnyPets()
        case .petSelection:          PetSelection()
            
        // --- Section 5: Services ---
        case .hireMovers:            HireMovers()
        case .hirePackers:           HirePackers()
        case .hireCleaners:          HireCleaners()
            
        // --- Section 6: Accounts ---
        case .financialInstitutions: FinancialInstitutions()
        case .healthcareProviders:   HealthcareProviders()
        case .fitnessWellness:       FitnessWellness()
            
        // --- Wrap-up ---
        case .howHeard:              HowHeard()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AssessmentFlowView(showAssessment: .constant(true))
}
#endif
