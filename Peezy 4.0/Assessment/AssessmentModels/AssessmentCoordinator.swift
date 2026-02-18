//
//  AssessmentCoordinator.swift
//  Peezy
//
//  Manages assessment flow: navigation, branching, interstitials, and completion.
//  Architecture: sequence-based state machine with dynamic branching.
//
//  Flow: interstitial (post-comment) → input (context + controls) → interstitial → input → ... → complete
//
//  UX Model:
//  - Interstitial: Single typewriter comment reacting to the previous answer. Tap to dismiss.
//  - Input screen: Context header typewriters in at top, then input controls slide/fade in below.
//  - The first interstitial is Peezy's intro (no previous answer to react to).
//

import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Assessment Input Steps

/// Every input screen in the assessment. No interstitials here — those are managed by the coordinator.
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
    case anyPets
    case petSelection
    
    // Section 5: Services
    case hireMovers
    case hirePackers
    case hireCleaners
    
    // Section 6: Accounts
    case financialInstitutions
    case healthcareProviders
    case fitnessWellness
    
    // Wrap-up
    case howHeard
}

// MARK: - Assessment Node

/// A single node in the assessment sequence — either an interstitial or an input screen.
enum AssessmentNode: Hashable {
    /// Post-comment interstitial. `after` is the step whose answer we're reacting to.
    /// For the very first interstitial (Peezy's intro), `after` is nil.
    case interstitial(after: AssessmentInputStep?)
    /// Input screen with built-in context animation.
    case input(AssessmentInputStep)
    
    var inputStep: AssessmentInputStep? {
        switch self {
        case .input(let step): return step
        case .interstitial: return nil
        }
    }
    
    var isInterstitial: Bool {
        if case .interstitial = self { return true }
        return false
    }
}

// MARK: - Interstitial Comment

/// Content for a post-comment interstitial — a single reaction to the previous answer.
struct InterstitialComment {
    /// Peezy's reaction to the user's previous answer (or intro for the first one).
    let text: String
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
    
    /// Highest input step count seen — ensures progress bar denominator never decreases.
    @Published private var maxInputStepsSeen: Int = 0
    
    /// Total number of INPUT steps for progress bar.
    /// Uses a watermark so the denominator only ever increases, never decreases.
    /// This prevents the progress bar from jumping backward when branches change.
    var totalInputSteps: Int {
        return maxInputStepsSeen
    }
    
    /// Current input step number (1-based) — for progress bar.
    var currentInputStepNumber: Int {
        let inputNodesBeforeCurrent = sequence.prefix(currentIndex + 1).filter { !$0.isInterstitial }.count
        return max(inputNodesBeforeCurrent, 1)
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
    
    /// Go back to the previous INPUT step (skipping interstitials).
    /// Does nothing if already at or before the first input step.
    func goBack() {
        guard currentIndex > 0 else { return }
        
        // Walk backward from one before current position
        var targetIndex = currentIndex - 1
        
        // Skip interstitials — land on the previous input node
        while targetIndex >= 0 && sequence[targetIndex].isInterstitial {
            targetIndex -= 1
        }
        
        // If no previous input exists, we're at the first question — do nothing
        guard targetIndex >= 0 else { return }
        
        currentIndex = targetIndex
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
        
        /// Track the previous input step so interstitials know what they're reacting to.
        var previousStep: AssessmentInputStep? = nil
        
        // Helper to add an interstitial (reacting to previous) + input pair
        func addStep(_ step: AssessmentInputStep) {
            nodes.append(.interstitial(after: previousStep))
            nodes.append(.input(step))
            previousStep = step
        }
        
        // Section 1: Basics
        addStep(.userName)          // First interstitial: after: nil → Peezy intro
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
        
        // Section 4: People
        addStep(.childrenInSchool)
        addStep(.childrenInDaycare)

        addStep(.anyPets)
        if dataManager.anyPets.lowercased() == "yes" {
            addStep(.petSelection)
        }
        
        // Section 5: Services
        addStep(.hireMovers)
        addStep(.hirePackers)
        addStep(.hireCleaners)
        
        // Section 6: Accounts
        addStep(.financialInstitutions)
        addStep(.healthcareProviders)
        addStep(.fitnessWellness)
        
        // Wrap-up
        addStep(.howHeard)
        
        sequence = nodes
        
        // Update watermark for progress bar stability
        let inputCount = nodes.filter { !$0.isInterstitial }.count
        if inputCount > maxInputStepsSeen {
            maxInputStepsSeen = inputCount
        }
    }
    
    /// Steps that affect branching — trigger a sequence rebuild when answered.
    private func isBranchingStep(_ step: AssessmentInputStep) -> Bool {
        switch step {
        case .currentDwellingType, .newDwellingType, .anyPets:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Interstitial Comments (Post-Answer Reactions)
    
    // TILE LABEL CONTRACT — question views MUST use these exact strings:
    //
    // moveDateType:         "Same Day" | "Out Before In" | "In Before Out"
    // currentRentOrOwn:     "Rent" | "Own"
    // newRentOrOwn:         "Rent" | "Own"
    // currentFloorAccess:   "First Floor" | "Stairs" | "Elevator" | "Reservable Elevator"
    // newFloorAccess:       (same as above)
    // hireMovers:           "Hire Professional Movers" | "Move Myself" | "Not Sure" | "Get Me Quotes"
    // hirePackers:          "Hire Professional Packers" | "Pack Myself" | "Not Sure" | "Get Me Quotes"
    // hireCleaners:         "Hire Professional Cleaners" | "Clean Myself" | "Not Sure" | "Get Me Quotes"
    // childrenInSchool:     "Yes" | "No"
    // childrenInDaycare:    "Yes" | "No"
    // anyPets:              "Yes" | "No"
    //
    // All comparisons use .lowercased() so casing doesn't matter, but spelling must match.
    
    /// Returns the post-comment for an interstitial that reacts to the given step's answer.
    /// If `afterStep` is nil, this is the first interstitial (Peezy's intro).
    func interstitialComment(after afterStep: AssessmentInputStep?) -> InterstitialComment {
        guard let step = afterStep else {
            // First interstitial — Peezy's introduction
            return InterstitialComment(
                text: "Hey there 👋 I'm Peezy, your moving concierge. I'm going to ask you some questions about your move so I can start handling things for you. The more you tell me, the more I can take off your plate."
            )
        }
        
        switch step {
            
        // --- SECTION 1: BASICS ---
            
        case .userName:
            return InterstitialComment(
                text: "Great to meet you, \(dataManager.userName). We're going to make this the smoothest move you've ever had."
            )

        case .moveConcerns:
            let concerns = dataManager.moveConcerns
            let text: String
            if concerns.isEmpty {
                text = "No worries at all? We love the confidence. Let's keep that energy going."
            } else if concerns.count == 1 {
                text = "Just \(concerns.first ?? "that")? We've got you covered. That's one of the biggest reasons people come to us."
            } else {
                text = "\(concerns.joined(separator: ", "))? Totally normal. Every one of those is something we handle every day. You're in good hands."
            }
            return InterstitialComment(text: text)
            
        case .moveDate:
            let weeksOut = weeksUntilDate(dataManager.moveDate)
            let text: String
            if weeksOut <= 2 {
                text = "\(weeksOut) weeks out — that's tight, but we've done tighter. Let's make every day count."
            } else if weeksOut <= 4 {
                text = "\(weeksOut) weeks — solid timeline. Plenty of room to get everything handled right."
            } else {
                text = "\(weeksOut) weeks out — you're ahead of the game. Most people don't start planning until 2 weeks before."
            }
            return InterstitialComment(text: text)

        case .moveDateType:
            let text: String
            switch dataManager.moveDateType.lowercased() {
            case "same day":
                text = "Same-day move — tight but totally doable. We'll make sure everything lines up."
            case "out before in":
                text = "Out first, then in — we'll plan for the gap so nothing falls through the cracks."
            case "in before out":
                text = "Nice — overlap means you can move things gradually if you want."
            default:
                text = "Got it. We'll work with your timeline."
            }
            return InterstitialComment(text: text)
            
        // --- SECTION 2: CURRENT HOME ---
            
        case .currentRentOrOwn:
            let text = dataManager.currentRentOrOwn.lowercased() == "own"
                ? "Homeowner — nice. We'll make sure things like closing details and property prep are on the list."
                : "Renting — got it. We'll handle things like lease notifications, security deposit recovery, and move-out requirements."
            return InterstitialComment(text: text)
            
        case .currentDwellingType:
            return InterstitialComment(
                text: "Got it — \(dataManager.currentDwellingType.lowercased()) it is."
            )
            
        case .currentAddress:
            return InterstitialComment(
                text: "Perfect. A few more details about your place so we can plan logistics."
            )
            
        case .currentFloorAccess:
            let text: String
            switch dataManager.currentFloorAccess.lowercased() {
            case "first floor":
                text = "First floor — nice and easy for the movers."
            case "stairs":
                text = "Stairs — we'll factor in extra time and make sure the movers know what they're getting into."
            case "elevator":
                text = "Elevator — we'll plan around peak times and make sure everything goes smooth."
            case "reservable elevator":
                text = "Reservable elevator — perfect. We'll remind you to book it ahead of time."
            default:
                text = "Got it."
            }
            return InterstitialComment(text: text)
            
        case .currentBedrooms:
            return InterstitialComment(
                text: "\(dataManager.currentBedrooms) bedroom\(dataManager.currentBedrooms == "1" ? "" : "s") — got it."
            )
            
        case .currentSquareFootage:
            return generatePackingBallparkComment()
            
        case .currentFinishedSqFt:
            return generatePackingBallparkComment()
            
        // --- SECTION 3: NEW HOME ---
            
        case .newRentOrOwn:
            let text = dataManager.newRentOrOwn.lowercased() == "own"
                ? "Congrats on the new place! We'll make sure utilities, insurance, and everything else is set up before you get there."
                : "Got it — renting at the new spot. We'll make sure you've got everything lined up with the new landlord."
            return InterstitialComment(text: text)
            
        case .newDwellingType:
            return InterstitialComment(
                text: "A \(dataManager.newDwellingType.lowercased()) — nice."
            )
            
        case .newAddress:
            return InterstitialComment(
                text: "Perfect. Same drill — a few details about the new place."
            )
            
        case .newFloorAccess:
            return InterstitialComment(text: "Got it.")
            
        case .newBedrooms:
            return InterstitialComment(text: "Nice.")
            
        case .newSquareFootage:
            return InterstitialComment(text: "Got it.")
            
        case .newFinishedSqFt:
            // Distance comment — both addresses now collected
            return InterstitialComment(text: generateDistanceComment())
            
        // --- SECTION 4: PEOPLE ---
            
        case .childrenInSchool:
            if dataManager.childrenInSchool.lowercased() == "yes" {
                return InterstitialComment(text: "Got it — we'll make sure school transfers and enrollment are on the list.")
            } else {
                return InterstitialComment(text: "Got it.")
            }

        case .childrenInDaycare:
            if dataManager.childrenInDaycare.lowercased() == "yes" {
                return InterstitialComment(text: "We'll help you find daycare options near the new place.")
            } else {
                return InterstitialComment(text: "Got it.")
            }
            
        case .anyPets:
            if dataManager.anyPets.lowercased() == "yes" {
                return InterstitialComment(text: "We've moved plenty of pets — they're in good hands.")
            } else {
                return InterstitialComment(text: generateHouseholdComment())
            }
            
        case .petSelection:
            return InterstitialComment(text: generateHouseholdComment())
            
        // --- SECTION 5: SERVICES ---
            
        case .hireMovers:
            let text: String
            switch dataManager.hireMovers.lowercased() {
            case "hire professional movers":
                text = "Smart move. We'll make sure you get matched with top-rated, vetted movers — and they know they're accountable to us."
            case "move myself":
                text = "Respect the hustle. We'll make sure you've got the right truck size, equipment, and a solid game plan."
            case "not sure":
                text = "No pressure. We'll get you some quotes so you can decide with real numbers."
            case "get me quotes":
                text = "On it. We'll get you 3 competitive quotes from vetted pros so you can compare without the hassle."
            default:
                text = "Got it."
            }
            return InterstitialComment(text: text)
            
        case .hirePackers:
            let text: String
            switch dataManager.hirePackers.lowercased() {
            case "hire professional packers":
                text = "Professional packing is honestly one of the best investments in a move. We'll find the right crew."
            case "pack myself":
                text = "We'll build you a packing schedule so it doesn't all pile up on the last day."
            case "not sure", "get me quotes":
                text = "We'll get you options so you can decide."
            default:
                text = "Got it."
            }
            return InterstitialComment(text: text)
            
        case .hireCleaners:
            return InterstitialComment(text: generateServicesSummary())
            
        // --- SECTION 6: ACCOUNTS ---
            
        case .financialInstitutions:
            let count = dataManager.financialInstitutions.count
            let text = count > 0
                ? "\(count) financial account\(count == 1 ? "" : "s") — we'll make sure every one gets updated."
                : "No financial accounts to update? Nice and simple."
            return InterstitialComment(text: text)
            
        case .healthcareProviders:
            let count = dataManager.healthcareProviders.count
            let text = count > 0
                ? "We'll handle those healthcare updates for you."
                : "No healthcare updates needed — easy."
            return InterstitialComment(text: text)
            
        case .fitnessWellness:
            return InterstitialComment(
                text: "That's everything I need, \(dataManager.userName). Give me just a second to build your plan..."
            )
            
        // --- WRAP-UP ---
            
        case .howHeard:
            return InterstitialComment(
                text: "Thanks! Alright, your plan is ready. Let me show you what we've got."
            )
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
                header: "Let's get on a first-name basis.",
                subheader: "First name, nickname, your old AIM screen name — whatever feels right. We're going to be talking a lot."
            )

        case .moveConcerns:
            return InputContext(
                header: "What's on your mind?",
                subheader: "What's weighing on you most about this move? Pick as many as apply — this is how we know where to focus your plan."
            )
            
        case .moveDate:
            return InputContext(
                header: "Let's figure out your timeline.",
                subheader: "When's the big day? If you don't know the exact date, a best guess works — you can always update it later."
            )

        case .moveDateType:
            return InputContext(
                header: "One more thing on timing.",
                subheader: "Are you moving out and in on the same day, or is there a gap? This helps us plan logistics and figure out if you'll need storage."
            )
            
        // --- SECTION 2: CURRENT HOME ---
            
        case .currentRentOrOwn:
            return InputContext(
                header: "Let's start with where you're living now.",
                subheader: "Are you renting or do you own? This affects things like security deposits, lease termination, and what needs to happen before you leave."
            )
            
        case .currentDwellingType:
            return InputContext(
                header: "What type of place is it?",
                subheader: nil
            )
            
        case .currentAddress:
            return InputContext(
                header: "What's the address?",
                subheader: "We need this for mail forwarding, change of address, and researching local utilities and services. Everything stays private."
            )
            
        case .currentFloorAccess:
            return InputContext(
                header: "How do you access your floor?",
                subheader: "This helps us estimate move time and plan logistics."
            )
            
        case .currentBedrooms:
            return InputContext(
                header: "How many bedrooms?",
                subheader: nil
            )
            
        case .currentSquareFootage:
            return InputContext(
                header: "Roughly how big is the place?",
                subheader: "Square footage helps us estimate packing time and how much moving capacity you'll need. A rough guess is fine."
            )
            
        case .currentFinishedSqFt:
            return InputContext(
                header: "How much finished living space?",
                subheader: "The main living area — bedrooms, kitchen, living room. A rough estimate works."
            )
            
        // --- SECTION 3: NEW HOME ---
            
        case .newRentOrOwn:
            return InputContext(
                header: "Now let's talk about where you're headed.",
                subheader: "Renting or buying at the new place?"
            )
            
        case .newDwellingType:
            return InputContext(
                header: "What kind of place?",
                subheader: nil
            )
            
        case .newAddress:
            return InputContext(
                header: "What's the new address?",
                subheader: "Same reason as before — utilities, internet, everything we need to get set up before you arrive."
            )
            
        case .newFloorAccess:
            return InputContext(
                header: "How will you access your floor at the new place?",
                subheader: nil
            )
            
        case .newBedrooms:
            return InputContext(
                header: "How many bedrooms at the new place?",
                subheader: nil
            )
            
        case .newSquareFootage:
            return InputContext(
                header: "Roughly how big is the new place?",
                subheader: "This helps us figure out if everything will fit and what kind of setup you'll need."
            )
            
        case .newFinishedSqFt:
            return InputContext(
                header: "How much finished living space at the new place?",
                subheader: nil
            )
            
        // --- SECTION 4: PEOPLE ---
            
        case .childrenInSchool:
            return InputContext(
                header: "Who's coming with you?",
                subheader: "Any school-age kids? This affects school transfers, enrollment, and how we plan the transition."
            )

        case .childrenInDaycare:
            return InputContext(
                header: "What about little ones?",
                subheader: "Any kids in daycare? We'll help you find options near the new place."
            )
            
        case .anyPets:
            return InputContext(
                header: "Any pets coming along?",
                subheader: "Dogs, cats, goldfish — they all change the plan a little. Vet records, pet-friendly arrangements, the works."
            )
            
        case .petSelection:
            return InputContext(
                header: "Which ones and how many?",
                subheader: "Select each type and how many you have. We'll make sure every one of them is accounted for."
            )
            
        // --- SECTION 5: SERVICES ---
            
        case .hireMovers:
            return InputContext(
                header: "Professional movers?",
                subheader: "Are you thinking about hiring pros to handle the heavy lifting, or going the DIY route? If you're not sure, we can get you quotes to compare."
            )
            
        case .hirePackers:
            return InputContext(
                header: "What about packing?",
                subheader: "Want pros to handle it, or are you more of a 'I know where everything is if I pack it myself' person?"
            )
            
        case .hireCleaners:
            return InputContext(
                header: "Last one on services — cleaning.",
                subheader: "Want a professional move-out clean, or handling that yourself? A good clean can make a big difference for security deposit recovery."
            )
            
        // --- SECTION 6: ACCOUNTS ---
            
        case .financialInstitutions:
            return InputContext(
                header: "Now let's make sure your accounts follow you.",
                subheader: "Which financial institutions need your new address? Select each type and we'll ask for the specific names."
            )
            
        case .healthcareProviders:
            return InputContext(
                header: "What about healthcare?",
                subheader: "Any doctors, dentists, or insurance providers that need your new info?"
            )
            
        case .fitnessWellness:
            return InputContext(
                header: "Any fitness or wellness memberships?",
                subheader: "Gym, studio, country club — we want to make sure you cancel in time and don't get hit with extra charges."
            )
            
        // --- WRAP-UP ---
            
        case .howHeard:
            return InputContext(
                header: "One last quick one.",
                subheader: "How'd you find us? This just helps us know what's working."
            )
        }
    }
    
    // MARK: - Dynamic Comment Helpers
    
    private func weeksUntilDate(_ date: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return max(days / 7, 0)
    }
    
    private func generatePackingBallparkComment() -> InterstitialComment {
        let bedrooms = dataManager.currentBedrooms
        let sqft = dataManager.currentSquareFootage.isEmpty
            ? dataManager.currentFinishedSqFt
            : dataManager.currentSquareFootage
        
        if !bedrooms.isEmpty && !sqft.isEmpty {
            return InterstitialComment(
                text: "\(bedrooms) bedroom\(bedrooms == "1" ? "" : "s"), \(sqft) sq ft — for a place that size, most people need about 3-5 days to pack if they do a couple hours a day. We'll build that into your timeline."
            )
        } else if !bedrooms.isEmpty {
            return InterstitialComment(
                text: "\(bedrooms) bedroom\(bedrooms == "1" ? "" : "s") — we've got a good picture of what we're working with."
            )
        } else {
            return InterstitialComment(
                text: "Good — we've got a solid picture of your current place."
            )
        }
    }
    
    private func generateDistanceComment() -> String {
        let currentAddr = dataManager.currentAddress
        let newAddr = dataManager.newAddress
        
        if !currentAddr.isEmpty && !newAddr.isEmpty {
            return "Alright — we've got both addresses locked in. We'll use those to handle mail forwarding, utilities, and everything that needs to switch over."
        } else {
            return "Let's talk about who's making this move with you."
        }
    }
    
    private func generateHouseholdComment() -> String {
        var parts: [String] = []

        if dataManager.childrenInSchool.lowercased() == "yes" || dataManager.childrenInDaycare.lowercased() == "yes" {
            parts.append("kids")
        }

        if dataManager.anyPets.lowercased() == "yes" && !dataManager.petSelection.isEmpty {
            let petTypes = dataManager.petSelection.joined(separator: ", ").lowercased()
            parts.append(petTypes)
        }

        if parts.isEmpty {
            return "Alright — let's talk about the move itself."
        } else {
            return "You, \(parts.joined(separator: ", and ")) — we've got the full picture. Now let's talk about the move itself."
        }
    }
    
    private func generateServicesSummary() -> String {
        var choices: [String] = []
        
        if dataManager.hireMovers.lowercased().contains("hire") || dataManager.hireMovers.lowercased().contains("quotes") {
            choices.append("movers")
        }
        if dataManager.hirePackers.lowercased().contains("hire") || dataManager.hirePackers.lowercased().contains("quotes") {
            choices.append("packers")
        }
        if dataManager.hireCleaners.lowercased().contains("hire") || dataManager.hireCleaners.lowercased().contains("quotes") {
            choices.append("cleaners")
        }
        
        if choices.isEmpty {
            return "DIY across the board — we respect that. Let's make sure your accounts are all set."
        } else if choices.count == 3 {
            return "Full service — movers, packers, and cleaners. We'll get you matched with the best. Now let's handle your accounts."
        } else {
            return "We'll get you set up with \(choices.joined(separator: " and ")). Now let's make sure your accounts follow you to the new place."
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
