//
//  assessmentDataManager.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/9/25.
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

class AssessmentDataManager: ObservableObject {
    // Question responses
    @Published var UserName: String = ""
    @Published var MoveDate: Date = Date()
    @Published var MoveExperience: String = ""
    @Published var MoveConcerns: [String] = []
    @Published var HowHeard: String = ""
    @Published var MoveDistance: String = ""
    @Published var CurrentRentOrOwn: String = ""
    @Published var CurrentDwellingType: String = ""
    @Published var NewRentOrOwn: String = ""
    @Published var NewDwellingType: String = ""
    @Published var WhosMoving: String = ""
    @Published var AnyPets: String = ""
    @Published var HireMovers: String = ""
    @Published var HirePackers: String = ""
    @Published var HireCleaners: String = ""
    
    // Save to backend (Firebase, UserDefaults, etc.)
    func saveData() {
        // TODO: Implement your backend save logic
        print("💾 Saving assessment data...")
    }
    
    // Check if all required questions are answered
    func isComplete() -> Bool {
        return !UserName.isEmpty &&
               !CurrentDwellingType.isEmpty &&
               !NewDwellingType.isEmpty &&
               !WhosMoving.isEmpty
    }

    // Returns all assessment data as dictionary for task generation
    // Keys MUST match Firestore condition field names exactly (case-sensitive)
    // Reference: Schema/TaskCatalogSchema.swift
    func getAllAssessmentData() -> [String: Any] {
        let data: [String: Any] = [
            // User info
            "userName": UserName,
            "moveDate": MoveDate,
            "moveExperience": MoveExperience,
            "moveConcerns": MoveConcerns,
            "howHeard": HowHeard,

            // Moving basics
            "moveDistance": MoveDistance,
            "currentRentOrOwn": CurrentRentOrOwn,
            "currentDwellingType": CurrentDwellingType,
            "newRentOrOwn": NewRentOrOwn,
            "newDwellingType": NewDwellingType,

            // Household
            "whosMoving": WhosMoving,
            "anyPets": AnyPets,

            // Services
            "hireMovers": HireMovers,
            "hirePackers": HirePackers,
            "hireCleaners": HireCleaners,

            // System flag
            "selectedMoveDate": "true",

            // Mapped keys for condition matching
            "hasPets": AnyPets.lowercased() == "yes",
            "hasKids": WhosMoving.lowercased().contains("kids"),
            "destinationOwnership": NewRentOrOwn.lowercased(),
            "originOwnership": CurrentRentOrOwn.lowercased(),
            "destinationPropertyType": NewDwellingType.lowercased(),
            "originPropertyType": CurrentDwellingType.lowercased()
        ]
        return data
    }

    // Save assessment to Firestore
    func saveAssessment() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AssessmentDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user ID"])
        }

        let db = Firestore.firestore()
        let assessmentData = getAllAssessmentData()

        // 1. Save to user_assessments (legacy location)
        try await db.collection("users")
            .document(userId)
            .collection("user_assessments")
            .addDocument(data: assessmentData)

        // 2. Save to userKnowledge (for V2 Brain)
        // Convert to the format the Brain expects
        let userKnowledgeData = buildUserKnowledgeData(userId: userId)
        try await db.collection("userKnowledge")
            .document(userId)
            .setData(userKnowledgeData, merge: true)

        print("✅ Assessment saved to Firestore (both locations)")
    }

    // Build userKnowledge format for V2 Brain
    private func buildUserKnowledgeData(userId: String) -> [String: Any] {
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()

        // Helper to create an entry
        func entry(_ value: Any) -> [String: Any] {
            return [
                "value": value,
                "source": "userStated",
                "confidence": 1.0,
                "collectedAt": isoFormatter.string(from: now),
                "updatedAt": isoFormatter.string(from: now),
                "confirmationCount": 1
            ]
        }

        var entries: [String: Any] = [:]

        // Map assessment fields to userKnowledge entries
        // IMPORTANT: Keys must match AssessmentField.stableKey (snake_case)
        if !UserName.isEmpty {
            entries["user_name"] = entry(UserName)
        }

        entries["move_date"] = entry(isoFormatter.string(from: MoveDate))

        if !MoveExperience.isEmpty {
            entries["move_experience"] = entry(MoveExperience)
        }

        if !MoveConcerns.isEmpty {
            entries["biggest_concern"] = entry(MoveConcerns.joined(separator: ", "))
        }

        if !MoveDistance.isEmpty {
            entries["move_distance"] = entry(MoveDistance)
        }

        if !CurrentDwellingType.isEmpty {
            entries["current_home_type"] = entry(CurrentDwellingType)
        }

        if !NewDwellingType.isEmpty {
            entries["destination_home_type"] = entry(NewDwellingType)
        }

        if !WhosMoving.isEmpty {
            entries["household_size"] = entry(WhosMoving)
        }

        if !AnyPets.isEmpty {
            entries["has_pets"] = entry(AnyPets.lowercased() == "yes")
        }

        if !HireMovers.isEmpty {
            entries["moving_help"] = entry(HireMovers)
        }

        if !HirePackers.isEmpty {
            entries["packing_help"] = entry(HirePackers)
        }

        if !HireCleaners.isEmpty {
            entries["cleaning_help"] = entry(HireCleaners.lowercased() == "yes")
        }

        return [
            "userId": userId,
            "entries": entries,
            "createdAt": isoFormatter.string(from: now),
            "lastUpdatedAt": isoFormatter.string(from: now)
        ]
    }
}
