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
import UIKit
import Combine
import FirebaseAuth
import FirebaseCrashlytics

// MARK: - Assessment Input Steps

/// Every input screen in the assessment.
enum AssessmentInputStep: String, Hashable {
    // Section 1: Basics
    case userName
    case moveDate
    case moveDateType

    // Section 2: Current Home
    case currentRentOrOwn
    case currentDwellingType
    case currentAddress
    // Apartment/Condo branch
    case currentFloorAccess
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
    case newBedrooms
    // Apartment/Condo
    case newSquareFootage
    // House/Townhouse
    case newFinishedSqFt

    // Storage (with home details)
    case hasStorage
    case storageSize
    case storageFullness

    // Section 4: People
    case anyKids
    case childrenInSchool
    case childrenInDaycare
    case hasVet
    case hasVehicles

    // Section 5: Services
    case servicesIntro
    case hireMovers
    case truckRental
    case hasDeclutter
    case wantToSell
    case hireCleaners

    // Section 6: Accounts
    case addressChangeIntro
    case financialInstitutions
    case healthcareProviders
    case fitnessWellness

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
    @Published var isNavigating: Bool = false
    
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

    /// Chapter-local position for the chaptered tracker. The live sequence is
    /// used so branching questions are counted only when they are reachable.
    func chapterProgress(for step: AssessmentInputStep) -> AssessmentChapterProgress {
        let chapter = PeezyQuestionVisuals.chapter(for: step)
        let chapterSteps = sequence.compactMap(\.inputStep).filter {
            PeezyQuestionVisuals.chapter(for: $0) == chapter
        }
        let position = (chapterSteps.firstIndex(of: step) ?? 0) + 1
        return AssessmentChapterProgress(
            chapter: chapter,
            position: position,
            total: max(chapterSteps.count, 1)
        )
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

            // Bounds check: if current node was removed from the new sequence
            if currentIndex >= sequence.count {
                currentIndex = max(sequence.count - 1, 0)
            }
        }
        
        // Advance to next node
        currentIndex += 1
        
        // Safety: clamp to valid range
        currentIndex = min(currentIndex, sequence.count - 1)
    }

    /// Dismiss the keyboard before navigating so only one transition runs at a time.
    func goToNextDismissingKeyboard() {
        guard !isNavigating else { return }
        isNavigating = true

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.goToNext()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isNavigating = false
            }
        }
    }
    
    /// Go back to the previous step.
    /// Does nothing if already at the first step.
    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
    
    /// Reset the entire assessment.
    /// P1-R load token: minted at creation and at every `reset()`, so a replacement load for the same UID retires the
    /// completions of the flow it replaced.
    private(set) var loadGeneration = UUID()

    /// The pure P1-R rule: a completion applies only under the UID and the load generation that started it.
    nonisolated static func completionIsCurrent(startedUID: String, currentUID: String, startedGeneration: UUID, currentGeneration: UUID) -> Bool {
        startedUID == currentUID && startedGeneration == currentGeneration
    }

    func reset() {
        loadGeneration = UUID()
        currentIndex = 0
        isComplete = false
        isSaving = false
        saveError = nil
        isCompleting = false
        isNavigating = false
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
        // Skip userName when Authentication Services already provided it (Sign in with Apple).
        // Required by App Store Guideline 4.
        if dataManager.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addStep(.userName)
        }
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
        }

        // Section 3: New Home
        addStep(.newRentOrOwn)
        addStep(.newDwellingType)
        addStep(.newAddress)

        // Branch based on new dwelling type
        let newDwelling = dataManager.newDwellingType.lowercased()
        if newDwelling == "apartment" || newDwelling == "condo" {
            addStep(.newFloorAccess)
        }

        // Section 4: People
        addStep(.anyKids)
        if dataManager.anyKids.lowercased() == "yes" {
            addStep(.childrenInSchool)
            addStep(.childrenInDaycare)
        }

        addStep(.hasVet)
        addStep(.hasVehicles)

        // Section 5: Services
        addStep(.servicesIntro)
        addStep(.hireMovers)
        if dataManager.hireMovers.lowercased() == "no" {
            addStep(.truckRental)
        }
        addStep(.hasDeclutter)
        if dataManager.hasDeclutter.lowercased() == "yes" {
            addStep(.wantToSell)
        }
        addStep(.hireCleaners)

        // Section 6: Accounts
        addStep(.addressChangeIntro)
        addStep(.financialInstitutions)
        addStep(.healthcareProviders)
        addStep(.fitnessWellness)

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
        case .currentDwellingType, .newDwellingType, .hireMovers, .anyKids,
             .hasDeclutter:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Reflect-Backs (Spec 04 Phase E — copy LOCKED)

    /// Banner rendered on the question FOLLOWING each beat — the revived
    /// inputContext pathway, mechanism (a) from the Spec 02 report. Beats
    /// resolve against the LIVE sequence (branching-safe: the banner lands
    /// on whichever step actually follows the beat) and only fire when the
    /// beat put something on the plan.
    func reflectBack(for step: AssessmentInputStep) -> String? {
        guard let index = sequence.firstIndex(of: .input(step)), index > 0,
              let previous = sequence[index - 1].inputStep else { return nil }

        switch previous {
        case .hasVet where dataManager.hasVet.lowercased() == "yes":
            return "Vet transfer just went on your plan."

        case .childrenInDaycare where dataManager.childrenInSchool.lowercased() == "yes"
            || dataManager.childrenInDaycare.lowercased() == "yes":
            return "School and daycare handling — on the plan."

        case .newAddress where !dataManager.newAddressPending
            && !dataManager.newAddress.isEmpty
            && !dataManager.currentAddress.isEmpty:
            return "Got both addresses — your plan is taking shape."

        case .hireCleaners where dataManager.hireMovers.lowercased() == "yes"
            || dataManager.hireCleaners.lowercased() == "yes":
            return "Movers, cleaning, supplies: we'll bring you options — you'll never chase quotes."

        default:
            return nil
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
                header: "Let's get to know each other. What's your first name?",
                subheader: nil
            )

        case .moveDate:
            return InputContext(
                header: "When are we moving? Not official yet? Your best guess works.",
                subheader: nil
            )

        case .moveDateType:
            return InputContext(
                header: "Is your move date flexible?",
                subheader: "We'll plan against your best guess — adjusting later takes one tap in Settings."
            )

            
        // --- SECTION 2: CURRENT HOME ---
            
        case .currentRentOrOwn:
            return InputContext(
                header: "Alright, let's talk about your current place. Are you renting or do you own?",
                subheader: "This tells us whether we're dealing with lease stuff, deposits, or listing prep."
            )
            
        case .currentDwellingType:
            return InputContext(
                header: "What kind of place is it?",
                subheader: nil
            )
            
        case .currentAddress:
            return InputContext(
                header: "What's the address?",
                subheader: "This powers your mail forwarding, utilities, address changes — all the stuff you'd normally chase down yourself."
            )
            
        case .currentFloorAccess:
            return InputContext(
                header: "What's the access like?",
                subheader: nil
            )

        case .currentBedrooms:
            return InputContext(
                header: "How many bedrooms at your current place?",
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
                subheader: "Same deal — this is how utilities, internet, and everything else get set up before you walk in."
            )
            
        case .newFloorAccess:
            return InputContext(
                header: "What's the access like?",
                subheader: nil
            )

        case .newBedrooms:
            return InputContext(
                header: "How many bedrooms at the new place?",
                subheader: nil
            )

        case .hasStorage:
            return InputContext(
                header: "Anything in a storage unit making the move too?",
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

        case .anyKids:
            return InputContext(
                header: "Any kids making the move with you?",
                subheader: nil
            )

        case .childrenInSchool:
            return InputContext(
                header: "Will any of them need to transfer schools?",
                subheader: nil
            )

        case .childrenInDaycare:
            return InputContext(
                header: "What about any in daycare?",
                subheader: nil
            )

        case .hasVet:
            return InputContext(
                header: "Got any pets that see a vet?",
                subheader: nil
            )

        case .hasVehicles:
            return InputContext(
                header: "Any vehicles coming along?",
                subheader: nil
            )

        // --- SECTION 5: SERVICES ---

        case .servicesIntro:
            return InputContext(
                header: "Now let's talk about any professional help you might need.",
                subheader: "Movers, packers, cleaners — tell us who you're hiring, or just curious about, and we'll line up the quotes."
            )

        case .hireMovers:
            return InputContext(
                header: "Would you like quotes for professional movers?",
                subheader: nil
            )
            
        case .truckRental:
            return InputContext(
                header: "Are you planning to rent a moving truck, or do you have that covered?",
                subheader: nil
            )

        case .hasDeclutter:
            return InputContext(
                header: "Any items you're planning to part with before the move?",
                subheader: "Clothes, furniture, electronics — anything you don't want making the trip."
            )

        case .wantToSell:
            return InputContext(
                header: "Are you planning to sell any of those items?",
                subheader: "We'll help you sell — with a plan B ready for anything that doesn't."
            )

        case .hireCleaners:
            return InputContext(
                header: "Want quotes for the final deep clean of your current place?",
                subheader: nil
            )
            
        // --- SECTION 6: ACCOUNTS ---

        case .addressChangeIntro:
            return InputContext(
                header: "Time to make sure everyone knows where to find you.",
                subheader: "Banks, doctors, memberships — they all need your new address. We'll handle the updates, the cancellations, and finding new ones near you."
            )

        case .financialInstitutions:
            return InputContext(
                header: "First up: the money accounts.",
                subheader: "Tap everything you have. More than one of something? Tap it once per account — we track each one separately."
            )

        case .healthcareProviders:
            return InputContext(
                header: "Now for any health-related accounts?",
                subheader: "Tap everything you have. More than one of something? Tap it once per account — we track each one separately."
            )

        case .fitnessWellness:
            return InputContext(
                header: "Last one: any gyms, studios, or wellness memberships?",
                subheader: "Tap everything you have. More than one of something? Tap it once per account — we track each one separately."
            )

        // --- WRAP-UP ---

        }
    }
    
    // MARK: - Assessment Completion
    
    func completeAssessment() async {
        guard !isCompleting else { return }
        isCompleting = true

        let userId = Auth.auth().currentUser?.uid ?? ""
        let generation = loadGeneration

        #if DEBUG
        print("🚀 COMPLETE ASSESSMENT: userId='\(userId)' auth=\(Auth.auth().currentUser != nil)")
        #endif

        // Show completion screen immediately
        isComplete = true
        isSaving = true
        AnalyticsEvents.assessmentCompleted(questionCount: sequence.count)

        // S4 (P1-R): every async completion below is applied only while the UID and the load generation that started it are still current
        func stillCurrent() -> Bool { Self.completionIsCurrent(startedUID: userId, currentUID: Auth.auth().currentUser?.uid ?? "", startedGeneration: generation, currentGeneration: loadGeneration) }
        // the deferred mutation belongs to this completion only, never to a replacement flow's
        defer { if stillCurrent() { isSaving = false } }

        // Race geocoding against a 5-second timeout so a slow network can't hang forever
        let geocodeTask = Task {
            await dataManager.computeDistanceAndInterstate()
        }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            geocodeTask.cancel()
        }
        _ = await geocodeTask.value
        timeoutTask.cancel()
        // guarded immediately after the await and before any store call
        guard stillCurrent() else { return }

        let assessmentData = dataManager.getAllAssessmentData()
        let moveDate = dataManager.moveDate

        // Save assessment to Firestore (non-blocking for task generation)
        do {
            try await dataManager.saveAssessment()
        } catch {
            Crashlytics.crashlytics().record(error: error)
            #if DEBUG
            print("⚠️ Assessment save failed: \(error) — continuing with task generation")
            #endif
            guard stillCurrent() else { return }
            saveError = error
        }
        guard stillCurrent() else { return }

        // Generate tasks independently — don't let a save failure block this
        do {
            let taskService = TaskGenerationService()
            let tasksGenerated = try await taskService.generateTasksForUser(
                userId: userId,
                assessment: assessmentData,
                moveDate: moveDate
            )

            #if DEBUG
            print("✅ ASSESSMENT COMPLETE: \(tasksGenerated) tasks generated for user \(userId)")
            #endif
        } catch {
            #if DEBUG
            print("❌ Task generation failed: \(error)")
            #endif
            guard stillCurrent() else { return }
            saveError = error
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let assessmentCompleted = Notification.Name("assessmentCompleted")
    static let retakeAssessment = Notification.Name("retakeAssessment")
}
