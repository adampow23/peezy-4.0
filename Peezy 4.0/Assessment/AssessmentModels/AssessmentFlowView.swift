//
//  AssessmentFlowView.swift
//  Peezy
//
//  Hosts the entire assessment flow.
//  Each question view owns its full page (typewriter, morph, tiles, everything).
//  This view only provides the progress bar and routes to the right question.
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
            // Background ignores keyboard so it doesn't squish
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)
            
            // Content VStack — SwiftUI shrinks this naturally when keyboard appears
            VStack(spacing: 0) {
                // Progress bar — stays pinned at top
                if coordinator.currentNode != nil {
                    progressBar
                        .transition(.opacity)
                }
                
                // Question — each one owns its full layout
                if let node = coordinator.currentNode {
                    questionView(for: node)
                        .id(coordinator.currentIndex)
                }
            }
        }
        .environmentObject(coordinator)
        .environmentObject(dataManager)
        .fullScreenCover(isPresented: $coordinator.isComplete) {
            CompletionFlowView(coordinator: coordinator)
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack {
                if coordinator.currentInputStepNumber > 1 {
                    Button {
                        coordinator.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                }
                
                Spacer()
                
                Text("\(coordinator.currentInputStepNumber) of \(coordinator.totalInputSteps)")
                    .font(.caption)
                    .foregroundColor(Color.gray)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PeezyTheme.Colors.deepInk.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(PeezyTheme.Colors.deepInk.opacity(0.4))
                        .frame(width: geo.size.width * coordinator.progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: coordinator.progress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Question Routing
    
    @ViewBuilder
    private func questionView(for node: AssessmentNode) -> some View {
        switch node {
        case .input(let step):
            questionContent(for: step)
        }
    }
    
    @ViewBuilder
    private func questionContent(for step: AssessmentInputStep) -> some View {
        switch step {
        // --- Section 1: Basics ---
        case .userName:              UserName()
        case .moveConcerns:          MoveConcerns()
        case .moveDate:              MoveDate()
        case .moveDateType:          MoveDateType()
            
        // --- Section 2: Current Home ---
        case .currentRentOrOwn:      CurrentRentOrOwn()
        case .currentDwellingType:   CurrentDwellingType()
        case .currentAddress:        CurrentAddress()
        case .currentFloorAccess:    CurrentFloorAccess()
        case .currentBedrooms:       CurrentBedrooms()
            
        // --- Section 3: New Home ---
        case .newRentOrOwn:          NewRentOrOwn()
        case .newDwellingType:       NewDwellingType()
        case .newAddress:            NewAddress()
        case .newFloorAccess:        NewFloorAccess()
        case .newBedrooms:           NewBedrooms()
            
        // --- Section 4: People ---
        case .anyKids:               AnyKids()
        case .childrenInSchool:      ChildrenInSchool()
        case .childrenInDaycare:     ChildrenInDaycare()
        case .hasVet:                HasVet()
        case .hasVehicles:           HasVehicles()
        case .hasStorage:            HasStorage()
        case .storageSize:           StorageSize()
        case .storageFullness:       StorageFullness()

        // --- Section 5: Services ---
        case .servicesIntro:         ServicesIntro()
        case .hireMovers:            HireMovers()
        case .hirePackers:     HirePackers()
        case .truckRental:           TruckRental()
        case .hasDeclutter:          HasDeclutter()
        case .wantToSell:            WantToSell()
        case .hireCleaners:          HireCleaners()
            
        // --- Section 6: Accounts ---
        case .addressChangeIntro:    AddressChangeIntro()
        case .financialInstitutions: FinancialInstitutions()
        case .financialDetails:      FinancialDetails()
        case .healthcareProviders:   HealthcareProviders()
        case .healthcareDetails:     HealthcareDetails()
        case .fitnessWellness:       FitnessWellness()
        case .fitnessDetails:        FitnessDetails()
            
        // --- Wrap-up ---
        case .howHeard:              HowHeard()
            
        default:                     EmptyView()
        }
    }
}

#if DEBUG
#Preview {
    AssessmentFlowView(showAssessment: .constant(true))
}
#endif
