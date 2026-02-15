import SwiftUI

// MARK: - AssessmentFlowView
// Container view for the assessment flow.
// Creates the DataManager and Coordinator, reads the current node,
// and renders either an interstitial or the appropriate question view.
// All child views receive dataManager and coordinator via .environmentObject().

struct AssessmentFlowView: View {
    
    @StateObject private var dataManager: AssessmentDataManager
    @StateObject private var coordinator: AssessmentCoordinator
    
    @Binding var showAssessment: Bool
    
    // MARK: - Init
    
    init(showAssessment: Binding<Bool>) {
        self._showAssessment = showAssessment
        let dm = AssessmentDataManager()
        _dataManager = StateObject(wrappedValue: dm)
        _coordinator = StateObject(wrappedValue: AssessmentCoordinator(dataManager: dm))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let node = coordinator.currentNode {
                nodeContent(for: node)
                    .environmentObject(dataManager)
                    .environmentObject(coordinator)
                    .id(coordinator.currentIndex)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(.easeInOut(duration: 0.3), value: coordinator.currentIndex)
            }
            
            // Progress bar — only visible on input nodes
            if let node = coordinator.currentNode, !node.isInterstitial {
                VStack {
                    progressHeader
                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: $coordinator.isComplete) {
            AssessmentCompleteView()
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        HStack(spacing: 16) {
            // Back button — hidden on first input
            Button {
                coordinator.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(coordinator.currentInputStepNumber > 1 ? 1 : 0)
            .disabled(coordinator.currentInputStepNumber <= 1)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * coordinator.progress, height: 6)
                        .animation(.easeInOut(duration: 0.4), value: coordinator.progress)
                }
            }
            .frame(height: 6)
            
            // Step counter
            Text("\(coordinator.currentInputStepNumber)/\(coordinator.totalInputSteps)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    // MARK: - Node Content Router
    
    @ViewBuilder
    private func nodeContent(for node: AssessmentNode) -> some View {
        switch node {
        case .interstitial(let beforeStep):
            let content = coordinator.interstitialContent(before: beforeStep)
            ConversationalInterstitialView(
                commentText: content.comment,
                contextHeader: content.contextHeader,
                contextSubheader: content.contextSubheader,
                onContinue: { coordinator.goToNext() }
            )
            
        case .input(let step):
            inputView(for: step)
        }
    }
    
    // MARK: - Input View Router
    
    @ViewBuilder
    private func inputView(for step: AssessmentInputStep) -> some View {
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
