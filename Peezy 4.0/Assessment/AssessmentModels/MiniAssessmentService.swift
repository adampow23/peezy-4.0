import Foundation
import FirebaseFirestore

// ============================================================================
// MiniAssessmentService
// Handles mini-assessment completion and sub-task generation
//
// FLOW:
// 1. User completes a mini-assessment task (e.g., Children Mini-Assessment)
// 2. Answers are saved to Firestore (users/{userId}/miniAssessments/{taskId})
// 3. Sub-tasks with matching parentTask are generated
// 4. Sub-tasks are evaluated against COMBINED assessment data
// ============================================================================

class MiniAssessmentService {

    private let db = Firestore.firestore()

    // MARK: - Complete Mini-Assessment

    /// Called when user completes a mini-assessment
    /// - Parameters:
    ///   - taskId: The mini-assessment task ID (e.g., "CHILDREN_OPTIONS")
    ///   - answers: Dictionary of field names to values (e.g., ["SchoolAgeChildren": "2"])
    ///   - userId: The user's ID
    ///   - moveDate: User's move date (for calculating due dates)
    func completeMiniAssessment(
        taskId: String,
        answers: [String: Any],
        userId: String,
        moveDate: Date
    ) async throws {

        print("📋 Mini-assessment '\(taskId)' completed with answers: \(answers)")

        // Step 1: Save mini-assessment answers to Firestore
        try await saveMiniAssessmentAnswers(taskId: taskId, answers: answers, userId: userId)

        // Step 2: Mark the mini-assessment task as complete
        try await markTaskComplete(taskId: taskId, userId: userId)

        // Step 3: Get combined assessment data (core + all mini-assessments)
        let combinedAssessment = try await getCombinedAssessmentData(userId: userId)

        // Step 4: Generate sub-tasks for this mini-assessment
        try await generateSubTasks(
            parentTaskId: taskId,
            assessment: combinedAssessment,
            userId: userId,
            moveDate: moveDate
        )

        print("✅ Mini-assessment '\(taskId)' processing complete")
    }

    // MARK: - Save Answers

    private func saveMiniAssessmentAnswers(
        taskId: String,
        answers: [String: Any],
        userId: String
    ) async throws {

        let docRef = db.collection("users").document(userId)
            .collection("miniAssessments").document(taskId)

        var data = answers
        data["completedAt"] = FieldValue.serverTimestamp()
        data["taskId"] = taskId

        try await docRef.setData(data, merge: true)
        print("💾 Saved mini-assessment answers for '\(taskId)'")
    }

    // MARK: - Mark Task Complete

    private func markTaskComplete(taskId: String, userId: String) async throws {
        let tasksRef = db.collection("users").document(userId).collection("tasks")

        // Query for task by taskId field or document ID
        let query = tasksRef.whereField("id", isEqualTo: taskId)
        let snapshot = try await query.getDocuments()

        for doc in snapshot.documents {
            try await doc.reference.updateData([
                "status": "Completed",
                "completedAt": FieldValue.serverTimestamp()
            ])
        }

        // Also try by document ID directly
        let directRef = tasksRef.document(taskId)
        let directDoc = try await directRef.getDocument()
        if directDoc.exists {
            try await directRef.updateData([
                "status": "Completed",
                "completedAt": FieldValue.serverTimestamp()
            ])
        }

        print("✅ Marked task '\(taskId)' as complete")
    }

    // MARK: - Get Combined Assessment Data

    /// Merges core assessment with all completed mini-assessments
    func getCombinedAssessmentData(userId: String) async throws -> [String: Any] {

        // Get core assessment from userKnowledge
        let knowledgeDoc = try await db.collection("userKnowledge").document(userId).getDocument()
        var combined = knowledgeDoc.data() ?? [:]

        // Get all completed mini-assessments
        let miniAssessmentsSnapshot = try await db.collection("users").document(userId)
            .collection("miniAssessments").getDocuments()

        for doc in miniAssessmentsSnapshot.documents {
            let data = doc.data()
            // Merge each field (excluding metadata)
            for (key, value) in data {
                if key != "completedAt" && key != "taskId" {
                    combined[key] = value
                }
            }
        }

        print("📊 Combined assessment has \(combined.count) fields")
        return combined
    }

    // MARK: - Generate Sub-Tasks

    private func generateSubTasks(
        parentTaskId: String,
        assessment: [String: Any],
        userId: String,
        moveDate: Date
    ) async throws {

        print("🔍 Looking for sub-tasks with parentTask: '\(parentTaskId)'")

        // Helper: Firestore stores numbers as Double or Int64, so as? Int can silently fail
        func asInt(_ value: Any?) -> Int? {
            if let i = value as? Int { return i }
            if let d = value as? Double { return Int(d) }
            if let i64 = value as? Int64 { return Int(i64) }
            return nil
        }

        // Query taskCatalog for sub-tasks of this parent
        let catalogSnapshot = try await db.collection("taskCatalog")
            .whereField("parentTask", isEqualTo: parentTaskId)
            .getDocuments()

        print("📋 Found \(catalogSnapshot.documents.count) potential sub-tasks")

        let batch = db.batch()
        var generatedCount = 0

        for doc in catalogSnapshot.documents {
            let taskData = doc.data()
            let taskTitle = taskData["title"] as? String ?? "Unknown"

            // Evaluate conditions against combined assessment
            let conditions = taskData["conditions"] as? [String: Any]
            let conditionPassed = TaskConditionParser.evaluateConditions(conditions, against: assessment)

            if conditionPassed {
                // Generate this sub-task
                let taskId = taskData["taskId"] as? String ?? doc.documentID
                let pageKey = taskData["pageKey"] as? String ?? ""
                let docId = pageKey.isEmpty ? taskId : pageKey
                let urgency = asInt(taskData["urgencyPercentage"]) ?? 50
                let dueDate = calculateDueDate(moveDate: moveDate, urgencyPercentage: urgency)

                let taskRef = db.collection("users").document(userId)
                    .collection("tasks").document(docId)

                var newTask: [String: Any] = [
                    "id": docId,
                    "taskId": taskId,
                    "title": taskTitle,
                    "desc": taskData["desc"] as? String ?? "",
                    "category": taskData["category"] as? String ?? "general",
                    "status": "Upcoming",
                    "dueDate": Timestamp(date: dueDate),
                    "urgencyPercentage": urgency,
                    "isSubTask": true,
                    "parentTask": parentTaskId,
                    "userId": userId,
                    "createdAt": FieldValue.serverTimestamp(),
                    "generatedFrom": "mini-assessment-completion"
                ]

                // Copy optional fields if they exist
                if let estHours = taskData["estHours"] {
                    newTask["estHours"] = estHours
                }
                if let tips = taskData["tips"] {
                    newTask["tips"] = tips
                }
                if let whyNeeded = taskData["whyNeeded"] {
                    newTask["whyNeeded"] = whyNeeded
                }
                if let priority = taskData["priority"] {
                    newTask["priority"] = priority
                }

                batch.setData(newTask, forDocument: taskRef)
                generatedCount += 1
                print("  ✅ Will generate: '\(taskTitle)'")
            } else {
                print("  ⏭️ Skipped (conditions not met): '\(taskTitle)'")
            }
        }

        if generatedCount > 0 {
            try await batch.commit()
            print("💾 Generated \(generatedCount) sub-tasks for '\(parentTaskId)'")
        } else {
            print("ℹ️ No sub-tasks generated for '\(parentTaskId)' (conditions not met or none defined)")
        }
    }

    // MARK: - Due Date Calculation

    private func calculateDueDate(moveDate: Date, urgencyPercentage: Int) -> Date {
        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
        let moveDateStart = Calendar.current.startOfDay(for: moveDate)
        let totalDays = Calendar.current.dateComponents([.day], from: today, to: moveDateStart).day ?? 30

        guard totalDays > 0 else { return today }

        // HIGH urgency (90+) = do it EARLY (within first 10% of timeline)
        // LOW urgency (10) = can wait (90% into timeline)
        let daysFromNow = Int(Double(totalDays) * (1.0 - Double(urgencyPercentage) / 100.0))
        return Calendar.current.date(byAdding: .day, value: max(0, daysFromNow), to: today) ?? today
    }
}
