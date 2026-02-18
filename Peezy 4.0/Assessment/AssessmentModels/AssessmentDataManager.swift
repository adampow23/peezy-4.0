import Foundation
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import Combine

@MainActor
class AssessmentDataManager: ObservableObject {
    
    // MARK: - Identity
    @Published var userName: String = ""
    
    // MARK: - Timeline
    @Published var moveDate: Date = Date()
    @Published var moveDateType: String = ""
    
    // MARK: - Experience
    @Published var moveConcerns: [String] = []
    
    // MARK: - Current Home
    @Published var currentRentOrOwn: String = ""
    @Published var currentDwellingType: String = ""
    @Published var currentAddress: String = ""
    @Published var currentFloorAccess: String = ""
    @Published var currentBedrooms: String = ""
    @Published var currentSquareFootage: String = ""
    @Published var currentFinishedSqFt: String = ""
    
    // MARK: - New Home
    @Published var newRentOrOwn: String = ""
    @Published var newDwellingType: String = ""
    @Published var newAddress: String = ""
    @Published var newFloorAccess: String = ""
    @Published var newBedrooms: String = ""
    @Published var newSquareFootage: String = ""
    @Published var newFinishedSqFt: String = ""
    
    // MARK: - Household
    @Published var childrenInSchool: String = ""
    @Published var childrenInDaycare: String = ""
    @Published var hasVet: String = ""
    
    // MARK: - Services
    @Published var hireMovers: String = ""
    @Published var hirePackers: String = ""
    @Published var hireCleaners: String = ""
    
    // MARK: - Accounts
    @Published var financialInstitutions: [String] = []
    @Published var healthcareProviders: [String] = []
    @Published var fitnessWellness: [String] = []
    
    // MARK: - Attribution
    @Published var howHeard: String = ""
    
    // MARK: - State
    @Published var saveError: Error?

    // MARK: - Computed Distance Fields
    /// Computed from currentAddress vs newAddress via geocoding.
    /// Set by computeDistanceAndInterstate() before task generation.
    @Published var moveDistance: String = ""
    @Published var isInterstate: String = ""

    // MARK: - Get All Assessment Data
    
    /// Returns every raw answer + mapped keys in a single dictionary.
    /// This is the contract for TaskGenerationService and peezyRespond.
    func getAllAssessmentData() -> [String: Any] {
        var data: [String: Any] = [:]
        
        // --- Raw answers ---
        
        // Identity
        data["userName"] = userName
        
        // Timeline
        data["moveDate"] = Timestamp(date: moveDate)
        data["moveDateType"] = moveDateType
        
        // Experience
        data["moveConcerns"] = moveConcerns
        
        // Current home
        data["currentRentOrOwn"] = currentRentOrOwn
        data["currentDwellingType"] = currentDwellingType
        data["currentAddress"] = currentAddress
        data["currentFloorAccess"] = currentFloorAccess
        data["currentBedrooms"] = currentBedrooms
        data["currentSquareFootage"] = currentSquareFootage
        data["currentFinishedSqFt"] = currentFinishedSqFt
        
        // New home
        data["newRentOrOwn"] = newRentOrOwn
        data["newDwellingType"] = newDwellingType
        data["newAddress"] = newAddress
        data["newFloorAccess"] = newFloorAccess
        data["newBedrooms"] = newBedrooms
        data["newSquareFootage"] = newSquareFootage
        data["newFinishedSqFt"] = newFinishedSqFt
        
        // Household
        data["childrenInSchool"] = childrenInSchool
        data["childrenInDaycare"] = childrenInDaycare
        data["hasVet"] = hasVet
        
        // Services — raw labels preserved for display/Firestore, mapped to Yes/No below
        data["hireMoversDetail"] = hireMovers
        data["hirePackersDetail"] = hirePackers
        data["hireCleanersDetail"] = hireCleaners
        
        // Accounts
        data["financialInstitutions"] = financialInstitutions
        data["healthcareProviders"] = healthcareProviders
        data["fitnessWellness"] = fitnessWellness
        
        // Attribution
        data["howHeard"] = howHeard
        
        // --- Computed keys for TaskConditionParser ---
        // These keys are required by taskCatalog conditions but not collected
        // directly from UI — they are derived from raw assessment answers.

        // Distance & interstate (set by computeDistanceAndInterstate())
        data["moveDistance"] = moveDistance   // "Local" or "Long Distance"
        data["isInterstate"] = isInterstate  // "Yes" or "No"

        // Service hire mapping — UI stores descriptive labels, catalog expects "Yes"/"No"
        // "Hire Professional Movers" / "Get Me Quotes" → "Yes"
        // "Move Myself" → "No"
        // "Not Sure" → "Yes" (better to over-prepare)
        data["hireMovers"] = mapServiceToYesNo(hireMovers, yesValues: ["hire professional movers", "get me quotes", "not sure"])
        data["hirePackers"] = mapServiceToYesNo(hirePackers, yesValues: ["hire professional packers", "get me quotes", "not sure"])
        data["hireCleaners"] = mapServiceToYesNo(hireCleaners, yesValues: ["hire professional cleaners", "get me quotes", "not sure"])

        return data
    }
    
    // MARK: - Service Value Mapping

    /// Maps descriptive service labels to "Yes"/"No" for task catalog conditions.
    private func mapServiceToYesNo(_ value: String, yesValues: [String]) -> String {
        guard !value.isEmpty else { return "" }
        return yesValues.contains(value.lowercased()) ? "Yes" : "No"
    }

    // MARK: - Geocoding (Distance & Interstate)

    /// Geocodes both addresses and computes moveDistance and isInterstate.
    /// Call this before getAllAssessmentData() to populate the computed fields.
    /// Defaults to "Long Distance" / "Yes" on failure (better to over-prepare).
    func computeDistanceAndInterstate() async {
        let geocoder = CLGeocoder()

        guard !currentAddress.isEmpty, !newAddress.isEmpty else {
            moveDistance = "Long Distance"
            isInterstate = "Yes"
            return
        }

        do {
            // CLGeocoder requires sequential calls (shared internal state)
            let fromPlacemarks = try await geocoder.geocodeAddressString(currentAddress)
            let toPlacemarks = try await geocoder.geocodeAddressString(newAddress)

            guard let fromPlacemark = fromPlacemarks.first,
                  let toPlacemark = toPlacemarks.first,
                  let fromLocation = fromPlacemark.location,
                  let toLocation = toPlacemark.location else {
                moveDistance = "Long Distance"
                isInterstate = "Yes"
                return
            }

            // Distance in miles
            let distanceMeters = fromLocation.distance(from: toLocation)
            let distanceMiles = distanceMeters / 1609.34
            moveDistance = distanceMiles >= 50 ? "Long Distance" : "Local"

            // Interstate comparison
            let fromState = fromPlacemark.administrativeArea ?? ""
            let toState = toPlacemark.administrativeArea ?? ""
            if fromState.isEmpty || toState.isEmpty {
                isInterstate = "Yes"
            } else {
                isInterstate = fromState.lowercased() == toState.lowercased() ? "No" : "Yes"
            }

            #if DEBUG
            print("📍 Geocoding: \(String(format: "%.1f", distanceMiles)) miles, interstate: \(isInterstate)")
            #endif

        } catch {
            #if DEBUG
            print("⚠️ Geocoding failed: \(error.localizedDescription) — defaulting to Long Distance / Yes")
            #endif
            moveDistance = "Long Distance"
            isInterstate = "Yes"
        }
    }

    // MARK: - Save to Firestore
    
    /// Saves assessment data to both Firestore paths.
    /// Path 1: users/{uid}/user_assessments/{auto-ID}
    /// Path 2: userKnowledge/{uid}
    func saveAssessment() async throws {
        guard let userId = Auth.auth().currentUser?.uid, !userId.isEmpty else {
            throw AssessmentError.noUser
        }
        
        let assessmentData = getAllAssessmentData()
        let db = Firestore.firestore()
        
        // Write to user_assessments subcollection (auto-generated doc ID)
        try await db.collection("users")
            .document(userId)
            .collection("user_assessments")
            .addDocument(data: assessmentData)
        
        // Write to userKnowledge (keyed by uid — overwrites)
        try await db.collection("userKnowledge")
            .document(userId)
            .setData(assessmentData, merge: true)
    }
    
    // MARK: - Reset
    
    func reset() {
        userName = ""
        moveDate = Date()
        moveDateType = ""
        moveConcerns = []
        currentRentOrOwn = ""
        currentDwellingType = ""
        currentAddress = ""
        currentFloorAccess = ""
        currentBedrooms = ""
        currentSquareFootage = ""
        currentFinishedSqFt = ""
        newRentOrOwn = ""
        newDwellingType = ""
        newAddress = ""
        newFloorAccess = ""
        newBedrooms = ""
        newSquareFootage = ""
        newFinishedSqFt = ""
        childrenInSchool = ""
        childrenInDaycare = ""
        hasVet = ""
        hireMovers = ""
        hirePackers = ""
        hireCleaners = ""
        financialInstitutions = []
        healthcareProviders = []
        fitnessWellness = []
        howHeard = ""
        moveDistance = ""
        isInterstate = ""
        saveError = nil
    }
}

// MARK: - Errors

enum AssessmentError: LocalizedError {
    case noUser
    
    var errorDescription: String? {
        switch self {
        case .noUser:
            return "No authenticated user found. Please sign in and try again."
        }
    }
}
