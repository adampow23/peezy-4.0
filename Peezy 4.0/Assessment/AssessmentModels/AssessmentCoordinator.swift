//
//  AssessmentCoordinator.swift
//  Peezy
//
//  Manages assessment flow: navigation, branching, and completion.
//  Architecture: sequence-based state machine with dynamic branching.
//
//  Flow: input → input → input → ... → complete
//
//  UX Model:
//  - Input screen: Context header typewriters in at top, then input controls slide/fade in below.
//

import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Assessment Input Steps

/// Every input screen in the assessment.
enum AssessmentInputStep: String, Hashable {
    // Section 1: Basics
    case userName
    case moveConcerns
    case moveDate
    case moveDateType
    
    // Section 2: Current Home
    case currentRentOrOwn
    case currentDwellingType
    case currentAddress
    // Apartment/Condo branch
    case currentFloorAccess
    // Shared (both paths)
    case currentBedrooms
    // Apartment/Condo
    case currentSquareFootage
    // House/Townhouse
    case currentFinishedSqFt
    
    // Section 3: New Home
    case newRentOrOwn
    case newDwellingType
    case newAddress
    // Apartment/Condo branch
    case newFloorAccess
    // Shared
    case newBedrooms
    // Apartment/Condo
    case newSquareFootage
    // House/Townhouse
    case newFinishedSqFt
    
    // Section 4: People
    case childrenInSchool
    case childrenInDaycare
    case hasVet
    case hasVehicles
    case hasStorage
    case storageSize
    case storageFullness

    // Section 5: Services
    case hireMovers
    case hirePackers
    case hireCleaners
    
    // Section 6: Accounts
    case financialInstitutions
    case financialDetails
    case healthcareProviders
    case healthcareDetails
    case fitnessWellness
    case fitnessDetails
    
    // Wrap-up
    case howHeard
}

// MARK: - Assessment Node

/// A single node in the assessment sequence — an input screen.
enum AssessmentNode: Hashable {
    /// Input screen with built-in context animation.
    case input(AssessmentInputStep)

    var inputStep: AssessmentInputStep? {
        switch self {
        case .input(let step): return step
        }
    }
}

// MARK: - Input Context

/// Context that appears at the top of an input screen before controls are revealed.
struct InputContext {
    /// Header text — the question or setup for the input.
    let header: String
    /// Optional subheader — additional guidance, fun facts, or explanation.
    let subheader: String?
}

// MARK: - Assessment Coordinator

@MainActor
class AssessmentCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentIndex: Int = 0
    @Published var sequence: [AssessmentNode] = []
    @Published var isComplete: Bool = false
    @Published var isSaving: Bool = false
    @Published var saveError: Error?
    
    // MARK: - Private State
    
    private var isCompleting: Bool = false
    let dataManager: AssessmentDataManager
    
    // MARK: - Computed Properties
    
    /// The current node in the sequence.
    var currentNode: AssessmentNode? {
        guard currentIndex >= 0 && currentIndex < sequence.count else { return nil }
        return sequence[currentIndex]
    }
    
    /// Highest step count seen — ensures progress bar denominator never decreases.
    @Published private var maxInputStepsSeen: Int = 0

    /// Total number of steps for progress bar.
    /// Uses a watermark so the denominator only ever increases, never decreases.
    /// This prevents the progress bar from jumping backward when branches change.
    var totalInputSteps: Int {
        return maxInputStepsSeen
    }

    /// Current step number (1-based) — for progress bar.
    var currentInputStepNumber: Int {
        return max(currentIndex + 1, 1)
    }

    /// Progress fraction for the progress bar (0.0 to 1.0).
    var progress: Double {
        guard totalInputSteps > 0 else { return 0 }
        return Double(currentInputStepNumber) / Double(totalInputSteps)
    }
    
    // MARK: - Init
    
    init(dataManager: AssessmentDataManager) {
        self.dataManager = dataManager
        buildSequence()
    }
    
    // MARK: - Navigation
    
    /// Advance to the next node in the sequence.
    func goToNext() {
        // If we're at the last node, complete the assessment
        guard currentIndex < sequence.count - 1 else {
            Task {
                await completeAssessment()
            }
            return
        }
        
        // If the current node is an input that affects branching, rebuild sequence.
        // Rebuild repositions currentIndex to the same node in the new sequence.
        if let currentInput = currentNode?.inputStep, isBranchingStep(currentInput) {
            let nodeBeforeRebuild = currentNode
            buildSequence()
            
            // Find this same node in the rebuilt sequence
            if let nodeBeforeRebuild,
               let repositioned = sequence.firstIndex(of: nodeBeforeRebuild) {
                currentIndex = repositioned
            }
        }
        
        // Advance to next node
        currentIndex += 1
        
        // Safety: clamp to valid range
        currentIndex = min(currentIndex, sequence.count - 1)
    }
    
    /// Go back to the previous step.
    /// Does nothing if already at the first step.
    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
    
    /// Reset the entire assessment.
    func reset() {
        currentIndex = 0
        isComplete = false
        isSaving = false
        saveError = nil
        isCompleting = false
        maxInputStepsSeen = 0
        buildSequence()
    }
    
    // MARK: - Sequence Building
    
    /// Build the full assessment sequence based on current data.
    /// Called on init and when branching answers change.
    func buildSequence() {
        var nodes: [AssessmentNode] = []

        // Helper to add an input step
        func addStep(_ step: AssessmentInputStep) {
            nodes.append(.input(step))
        }

        // Section 1: Basics
        addStep(.userName)
        addStep(.moveConcerns)
        addStep(.moveDate)
        addStep(.moveDateType)
        
        // Section 2: Current Home
        addStep(.currentRentOrOwn)
        addStep(.currentDwellingType)
        addStep(.currentAddress)
        
        // Branch based on current dwelling type
        let currentDwelling = dataManager.currentDwellingType.lowercased()
        if currentDwelling == "apartment" || currentDwelling == "condo" {
            addStep(.currentFloorAccess)
            addStep(.currentBedrooms)
            addStep(.currentSquareFootage)
        } else {
            // House / Townhouse (also default if not yet answered)
            addStep(.currentBedrooms)
            addStep(.currentFinishedSqFt)
        }
        
        // Section 3: New Home
        addStep(.newRentOrOwn)
        addStep(.newDwellingType)
        addStep(.newAddress)
        
        // Branch based on new dwelling type
        let newDwelling = dataManager.newDwellingType.lowercased()
        if newDwelling == "apartment" || newDwelling == "condo" {
            addStep(.newFloorAccess)
            addStep(.newBedrooms)
            addStep(.newSquareFootage)
        } else {
            addStep(.newBedrooms)
            addStep(.newFinishedSqFt)
        }

        // Storage — belongs with home details
        addStep(.hasStorage)
        if dataManager.hasStorage.lowercased() == "yes" {
            addStep(.storageSize)
            addStep(.storageFullness)
        }

        // Section 4: People
        addStep(.childrenInSchool)
        addStep(.childrenInDaycare)

        addStep(.hasVet)

        addStep(.hasVehicles)

        // Section 5: Services
        addStep(.hireMovers)
        addStep(.hirePackers)
        addStep(.hireCleaners)
        
        // Section 6: Accounts
        addStep(.financialInstitutions)
        if !dataManager.financialInstitutions.isEmpty {
            addStep(.financialDetails)
        }
        addStep(.healthcareProviders)
        if !dataManager.healthcareProviders.isEmpty {
            addStep(.healthcareDetails)
        }
        addStep(.fitnessWellness)
        if !dataManager.fitnessWellness.isEmpty {
            addStep(.fitnessDetails)
        }
        
        // Wrap-up
        addStep(.howHeard)
        
        sequence = nodes

        // Update watermark for progress bar stability
        let inputCount = nodes.count
        if inputCount > maxInputStepsSeen {
            maxInputStepsSeen = inputCount
        }
    }
    
    /// Steps that affect branching — trigger a sequence rebuild when answered.
    private func isBranchingStep(_ step: AssessmentInputStep) -> Bool {
        switch step {
        case .currentDwellingType, .newDwellingType,
             .hasStorage,
             .financialInstitutions, .healthcareProviders, .fitnessWellness:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Input Context (Header + Subheader for Input Screens)
    
    /// Returns the context that appears at the top of an input screen.
    /// This typewriters in, then the input controls are revealed below.
    func inputContext(for step: AssessmentInputStep) -> InputContext {
        switch step {
            
        // --- SECTION 1: BASICS ---
            
        case .userName:
            return InputContext(
                header: "Love it. Let's get to know each other. What's your first name?",
                subheader: nil
            )

        case .moveConcerns:
            return InputContext(
                header: "Nice to meet you, \(dataManager.userName). I'm Peezy! I'll be handling the entire move so you don't have to, but I want to know where your head is at. What's taking up the most mental energy right now?",
                subheader: "Pick your biggest headaches below."
            )
            
        case .moveDate:
            let firstLine: String
            if dataManager.moveConcerns.isEmpty {
                firstLine = "No major stress? I like your style, \(dataManager.userName). Let's keep it that way."
            } else {
                firstLine = "Say no more. That is exactly the stuff I'm built to take off your plate. Take a deep breath—I've got it from here."
            }
            return InputContext(
                header: firstLine,
                subheader: "Next up: when are we moving? If it's not 100% official yet, just drop your best guess below!"
            )

        case .moveDateType:
            let days = Calendar.current.dateComponents([.day], from: Date(), to: dataManager.moveDate).day ?? 0
            let firstLine: String
            if days < 7 {
                firstLine = "Less than a week? No sweat. This is exactly why I'm here. Let's put this into high gear."
            } else if days <= 14 {
                firstLine = "Two weeks out! That's the perfect amount of time for me to get everything locked in without a scramble."
            } else if days <= 30 {
                firstLine = "A month away! I love it. We're going to have this whole thing handled with plenty of time to spare."
            } else {
                firstLine = "Awesome, we've got loads of time. Getting this sorted early means zero stress as the big day gets closer."
            }
            return InputContext(
                header: firstLine,
                subheader: "Now, how set in stone is that date?"
            )
            
        // --- SECTION 2: CURRENT HOME ---
            
        case .currentRentOrOwn:
            return InputContext(
                header: "Alright, let's talk about your current place. Are you renting or do you own?",
                subheader: "This helps me figure out things like lease breaks, security deposits, or listing prep."
            )
            
        case .currentDwellingType:
            return InputContext(
                header: "What kind of place is it?",
                subheader: nil
            )
            
        case .currentAddress:
            return InputContext(
                header: "What's the address?",
                subheader: "I'll use this for mail forwarding, utilities, change of address—all the stuff you'd normally have to chase down yourself."
            )
            
        case .currentFloorAccess:
            return InputContext(
                header: "What floor are you on?",
                subheader: "This helps me plan the move-out logistics."
            )
            
        case .currentBedrooms:
            return InputContext(
                header: "How many bedrooms?",
                subheader: nil
            )
            
        case .currentSquareFootage:
            return InputContext(
                header: "Roughly how big is the place?",
                subheader: "Don't overthink it—a ballpark is perfect."
            )
            
        case .currentFinishedSqFt:
            return InputContext(
                header: "How much finished living space are we working with?",
                subheader: "Ballpark is totally fine."
            )
            
        // --- SECTION 3: NEW HOME ---
            
        case .newRentOrOwn:
            return InputContext(
                header: "Now let's talk about where you're headed. Renting or buying?",
                subheader: nil
            )
            
        case .newDwellingType:
            return InputContext(
                header: "What kind of place is the new one?",
                subheader: nil
            )
            
        case .newAddress:
            return InputContext(
                header: "What's the new address?",
                subheader: "Same deal—I'll use it to get utilities, internet, and everything else set up before you even walk in the door."
            )
            
        case .newFloorAccess:
            return InputContext(
                header: "What floor is the new place?",
                subheader: "Helps me plan the move-in side."
            )
            
        case .newBedrooms:
            return InputContext(
                header: "How many bedrooms at the new place?",
                subheader: nil
            )
            
        case .newSquareFootage:
            return InputContext(
                header: "Roughly how big is the new place?",
                subheader: nil
            )
            
        case .newFinishedSqFt:
            return InputContext(
                header: "How much finished living space at the new place?",
                subheader: nil
            )
            
        // --- SECTION 4: PEOPLE ---
            
        case .childrenInSchool:
            return InputContext(
                header: "Any kids in school?",
                subheader: "I'll handle the enrollment transfers and records requests so you don't have to sit on hold."
            )

        case .childrenInDaycare:
            return InputContext(
                header: "Any little ones in daycare?",
                subheader: "I'll help with the provider search at the new place."
            )
            
        case .hasVet:
            return InputContext(
                header: "Got any pets that see a vet?",
                subheader: "I'll transfer records and find a new vet near the new place if you need one."
            )

        case .hasVehicles:
            return InputContext(
                header: "Any vehicles that need registration or title updates?",
                subheader: "State lines mean paperwork—I'll handle it."
            )

        case .hasStorage:
            return InputContext(
                header: "Do you have a storage unit that needs to be dealt with?",
                subheader: nil
            )

        case .storageSize:
            return InputContext(
                header: "How big is the unit?",
                subheader: nil
            )

        case .storageFullness:
            return InputContext(
                header: "How full is it?",
                subheader: nil
            )

        // --- SECTION 5: SERVICES ---
            
        case .hireMovers:
            return InputContext(
                header: "Are you interested in getting quotes for professional movers, or are you planning to handle the move yourself?",
                subheader: "Either way works—I'll build the plan around your choice."
            )
            
        case .hirePackers:
            return InputContext(
                header: "Would you like quotes for professional packing help, or are you planning to pack everything yourself?",
                subheader: "Pro tip: packers can do a full house in a day. Just saying."
            )
            
        case .hireCleaners:
            return InputContext(
                header: "Would you like quotes for a professional move-out cleaning, or are you going to handle that yourself?",
                subheader: "A good deep clean can be the difference between getting your deposit back and leaving money on the table."
            )
            
        // --- SECTION 6: ACCOUNTS ---
            
        case .financialInstitutions:
            return InputContext(
                header: "Let's make sure your money follows you. Which of these do you need to update your address with?",
                subheader: "Tap all that apply."
            )

        case .financialDetails:
            return InputContext(
                header: "Which ones specifically?",
                subheader: "Start typing and I'll help you find them."
            )

        case .healthcareProviders:
            return InputContext(
                header: "What about healthcare? Who needs your new info?",
                subheader: "Tap all that apply."
            )

        case .healthcareDetails:
            return InputContext(
                header: "Which ones specifically?",
                subheader: nil
            )

        case .fitnessWellness:
            return InputContext(
                header: "Any memberships or subscriptions we should cancel or transfer?",
                subheader: "Gyms love to keep charging after you leave. Tap all that apply."
            )

        case .fitnessDetails:
            return InputContext(
                header: "Which ones specifically?",
                subheader: nil
            )
            
        // --- WRAP-UP ---
            
        case .howHeard:
            return InputContext(
                header: "Last one, \(dataManager.userName)—how'd you find us?",
                subheader: nil
            )
        }
    }
    
    // MARK: - Assessment Completion
    
    func completeAssessment() async {
        guard !isCompleting else { return }
        isCompleting = true
        
        let userId = Auth.auth().currentUser?.uid ?? ""
        
        // Show completion screen immediately
        isComplete = true
        isSaving = true
        
        do {
            // Compute distance & interstate from addresses before building the dictionary
            await dataManager.computeDistanceAndInterstate()

            let assessmentData = dataManager.getAllAssessmentData()
            let moveDate = dataManager.moveDate
            
            // Save assessment to Firestore
            try await dataManager.saveAssessment()
            
            // Generate tasks
            let taskService = TaskGenerationService()
            let tasksGenerated = try await taskService.generateTasksForUser(
                userId: userId,
                assessment: assessmentData,
                moveDate: moveDate
            )
            
            #if DEBUG
            print("✅ Assessment complete. Generated \(tasksGenerated) tasks.")
            #endif
            isSaving = false
            
        } catch {
            #if DEBUG
            print("❌ Error completing assessment: \(error.localizedDescription)")
            #endif
            isSaving = false
            saveError = error
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let assessmentCompleted = Notification.Name("assessmentCompleted")
}
