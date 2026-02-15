// TaskGenerationService.swift
// Peezy iOS - Task Generation from Catalog
// Generates personalized task list based on user assessment

import Foundation
import FirebaseFirestore

class TaskGenerationService {
    
    private let db = Firestore.firestore()
    
    /// Generates tasks for a user based on their assessment
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - assessment: Dictionary containing user's assessment data
    ///   - moveDate: The user's move date
    /// - Returns: Number of tasks generated
    @MainActor
    func generateTasksForUser(
        userId: String,
        assessment: [String: Any],
        moveDate: Date
    ) async throws -> Int {
        print("🚀 TASK GEN: Starting for user \(userId)")
        print("📅 TASK GEN: Move date is \(moveDate), today is \(DateProvider.shared.now)")

        // 0. Create special "Complete Assessment" task FIRST
        try await createAssessmentCompletionTask(userId: userId, moveDate: moveDate)
        
        // 1. Create mini-assessment tasks (address change lists)
        let miniAssessmentCount = try await createMiniAssessmentTasks(userId: userId, moveDate: moveDate)
        print("📋 Created \(miniAssessmentCount) mini-assessment tasks")

        // 2. Fetch all tasks from taskCatalog
        let catalogSnapshot = try await db.collection("taskCatalog").getDocuments()
        print("📚 Found \(catalogSnapshot.documents.count) tasks in catalog")

        // 🔍 DEBUG: Print assessment data being used for condition evaluation
        print("🔍 ASSESSMENT DATA FOR CONDITIONS:")
        for (key, value) in assessment.sorted(by: { $0.key < $1.key }) {
            print("   • \(key): \(value) (type: \(type(of: value)))")
        }

        var tasksToCreate: [[String: Any]] = []
        
        // 3. Evaluate each task's conditions
        for document in catalogSnapshot.documents {
            let taskData = document.data()
            let taskTitle = taskData["title"] as? String ?? "Unknown"

            // Skip sub-tasks during initial generation
            // Sub-tasks are generated when their parent mini-assessment completes
            if let isSubTask = taskData["isSubTask"] as? Bool, isSubTask == true {
                let parentTask = taskData["parentTask"] as? String ?? "unknown"
                print("⏭️ Skipping sub-task '\(taskTitle)' - will generate when '\(parentTask)' completes")
                continue
            }

            // Get conditions - Firestore stores as [String: [String]] dictionary
            let conditions = taskData["conditions"] as? [String: Any]

            // Debug logging
            print("🔍 Evaluating conditions for '\(taskTitle)': \(conditions ?? [:])")

            // Evaluate conditions against user's assessment
            let conditionPassed = TaskConditionParser.evaluateConditions(conditions, against: assessment)

            if conditionPassed {
                print("✅ Condition PASSED for '\(taskTitle)'")

                // Calculate due date based on urgency and optional bounds
                let urgencyPercentage = taskData["urgencyPercentage"] as? Int ?? 50
                let earliestDays = taskData["earliestDaysBeforeMove"] as? Int
                let latestDays = taskData["latestDaysBeforeMove"] as? Int

                // 📊 Debug: Log urgency distribution from catalog
                print("📊 Task '\(taskData["title"] as? String ?? "Unknown")' urgency: \(urgencyPercentage), earliest: \(earliestDays ?? -1), latest: \(latestDays ?? -1)")

                let dueDate = calculateDueDate(
                    moveDate: moveDate,
                    urgencyPercentage: urgencyPercentage,
                    earliestDaysBeforeMove: earliestDays,
                    latestDaysBeforeMove: latestDays
                )

                // 📅 DEBUG: Log calculated due date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                print("📅 Task '\(taskData["title"] as? String ?? "")' → dueDate: \(dateFormatter.string(from: dueDate)) (urgency: \(urgencyPercentage))")

                // Create task document data in MovingTask-compatible format
                var userTask: [String: Any] = [:]
                
                // Copy all fields from catalog
                // Use pageKey if non-empty, otherwise fall back to document ID
                let pageKey = taskData["pageKey"] as? String ?? ""
                userTask["id"] = pageKey.isEmpty ? document.documentID : pageKey
                userTask["taskId"] = taskData["taskId"]
                userTask["urgencyPercentage"] = urgencyPercentage
                userTask["title"] = taskData["title"] ?? ""
                userTask["desc"] = taskData["desc"] ?? ""
                userTask["estHours"] = taskData["estHours"] ?? 0
                userTask["tips"] = taskData["tips"] ?? ""
                userTask["category"] = taskData["category"] ?? "custom"
                userTask["whyNeeded"] = taskData["whyNeeded"] ?? ""
                userTask["priority"] = taskData["priority"] ?? ""
                userTask["isAssessmentTask"] = false
                userTask["isSubTask"] = taskData["isSubTask"] ?? false
                userTask["parentTask"] = taskData["parentTask"] ?? ""
                userTask["conditions"] = taskData["conditions"] ?? ""
                
                // Add user-specific fields
                userTask["dueDate"] = Timestamp(date: dueDate)
                userTask["status"] = "Upcoming"  // ✅ Matches TaskStatus enum rawValue
                userTask["userId"] = userId
                userTask["createdAt"] = Timestamp(date: Date())
                
                tasksToCreate.append(userTask)
                
                print("✅ Including: \(taskTitle)")
            } else {
                print("❌ Condition FAILED for '\(taskTitle)' - skipping")
            }
        }
        
        print("📋 TASK GEN: Created \(tasksToCreate.count) catalog tasks")

        // 4. Batch write tasks to user's collection
        let batch = db.batch()
        let userTasksRef = db.collection("users").document(userId).collection("tasks")

        for taskData in tasksToCreate {
            // Use pageKey as document ID if available, otherwise auto-generate
            // IMPORTANT: Skip empty IDs - Firestore requires non-empty document paths
            let rawId = taskData["id"] as? String ?? ""
            let docId = rawId.isEmpty ? UUID().uuidString : rawId

            guard !docId.isEmpty else {
                print("⚠️ TASK GEN: Skipping task with empty ID: \(taskData["title"] ?? "unknown")")
                continue
            }

            let taskRef = userTasksRef.document(docId)
            batch.setData(taskData, forDocument: taskRef)
        }

        // 5. Commit batch
        let totalTasks = tasksToCreate.count + miniAssessmentCount + 1 // +1 for assessment complete
        print("💾 TASK GEN: Committing \(tasksToCreate.count) tasks to Firestore...")

        do {
            try await batch.commit()
            print("✅ TASK GEN: Successfully wrote \(tasksToCreate.count) tasks")
        } catch {
            print("❌ TASK GEN FAILED: \(error)")
            throw error
        }

        print("✨ TASK GEN: Total tasks generated: \(totalTasks)")
        
        return totalTasks
    }
    
    // MARK: - Due Date Calculation

    /// Calculates task due date based on urgency percentage with optional bounds
    /// Higher percentage (90+) = MORE urgent = do it EARLY (within first 10% of timeline)
    /// Lower percentage (10) = LESS urgent = can wait (90% into timeline)
    /// - Parameters:
    ///   - moveDate: User's move date
    ///   - urgencyPercentage: Task urgency (1-99)
    ///   - earliestDaysBeforeMove: Optional - can't start before this many days before move
    ///   - latestDaysBeforeMove: Optional - must be done by this many days before move
    /// - Returns: Calculated due date
    private func calculateDueDate(
        moveDate: Date,
        urgencyPercentage: Int,
        earliestDaysBeforeMove: Int? = nil,
        latestDaysBeforeMove: Int? = nil
    ) -> Date {
        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
        let moveDateStart = Calendar.current.startOfDay(for: moveDate)
        let totalDays = Calendar.current.dateComponents([.day], from: today, to: moveDateStart).day ?? 0

        // Guard against past/same-day moves
        guard totalDays > 0 else { return today }

        // Calculate ideal date from urgency
        // HIGH urgency (90+) = do it EARLY (within first 10% of timeline)
        // LOW urgency (10) = can wait (90% into timeline)
        let daysFromNow = Double(totalDays) * (1.0 - Double(urgencyPercentage) / 100.0)
        var dueDate = Calendar.current.date(byAdding: .day, value: Int(daysFromNow), to: today) ?? moveDate

        // Apply earliest bound (can't start before this many days before move)
        if let earliest = earliestDaysBeforeMove {
            let earliestDate = Calendar.current.date(byAdding: .day, value: -earliest, to: moveDateStart)!
            if dueDate < earliestDate && earliestDate > today {
                dueDate = earliestDate
            }
        }

        // Apply latest bound (must be done by this many days before move)
        if let latest = latestDaysBeforeMove {
            let latestDate = Calendar.current.date(byAdding: .day, value: -latest, to: moveDateStart)!
            if dueDate > latestDate {
                dueDate = latestDate
            }
        }

        // Never schedule in the past
        if dueDate < today {
            dueDate = today
        }

        return dueDate
    }

    // MARK: - Assessment Completion Task

    /// Creates the special "Complete Assessment" task
    /// This is the user's first task and introduces them to the checkmark tracing ritual
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - moveDate: The user's move date
    private func createAssessmentCompletionTask(userId: String, moveDate: Date) async throws {
        print("🎯 Creating special 'Complete Assessment' task")

        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)

        // Create the assessment completion task
        let assessmentTask: [String: Any] = [
            "id": "assessment_complete",
            "taskId": 0,
            "urgencyPercentage": 100, // Most urgent - do it now!
            "title": "Complete Moving Assessment",
            "desc": "Congratulations! You've completed your moving assessment. Now it's time to mark this task as complete to experience how task completion works in Peezy. Simply tap and hold on this task card to trace the checkmark and watch your progress grow!",
            "estHours": 0,
            "tips": "This is your first task! Long-press to trace the checkmark and see the magic happen.",
            "category": "assessment",
            "whyNeeded": "This introduces you to Peezy's satisfying task completion ritual and kicks off your moving journey.",
            "priority": "High",
            "isAssessmentTask": true,
            "isSubTask": false,
            "parentTask": "",
            "conditions": "",
            "dueDate": Timestamp(date: today),
            "status": "Upcoming",
            "userId": userId,
            "createdAt": Timestamp(date: Date())
        ]

        // Save to Firestore
        let taskRef = db.collection("users")
            .document(userId)
            .collection("tasks")
            .document("assessment_complete")

        try await taskRef.setData(assessmentTask)

        print("✅ Assessment completion task created successfully")
    }
    
    // MARK: - Mini-Assessment Tasks (Address Change Lists)
    
    /// Creates mini-assessment tasks for address change lists
    /// These help users identify all places they need to update their address
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - moveDate: The user's move date
    /// - Returns: Number of mini-assessment tasks created
    private func createMiniAssessmentTasks(userId: String, moveDate: Date) async throws -> Int {
        print("📋 Creating mini-assessment tasks")
        
        // Calculate due dates - these should be done early in the process
        // Urgency 85% = early in timeline (important to do soon)
        let dueDate = calculateDueDate(moveDate: moveDate, urgencyPercentage: 85)
        
        // Define all mini-assessment tasks
        let miniAssessments: [(id: String, title: String, desc: String, icon: String)] = [
            (
                id: "address_change_financial",
                title: "Create financial address list",
                desc: "Let's identify all your financial accounts that need your new address - banks, credit cards, investments, and more.",
                icon: "dollarsign.circle.fill"
            ),
            (
                id: "address_change_health",
                title: "Create healthcare address list",
                desc: "Update your healthcare providers with your new address - doctors, dentists, insurance, and pharmacies.",
                icon: "heart.fill"
            ),
            (
                id: "address_change_insurance",
                title: "Create insurance address list",
                desc: "Your insurance rates can change with your address! Let's make sure all policies are updated.",
                icon: "shield.fill"
            ),
            (
                id: "address_change_fitness",
                title: "Create fitness membership list",
                desc: "Identify gym memberships and fitness subscriptions to transfer or cancel.",
                icon: "figure.run"
            ),
            (
                id: "address_change_memberships",
                title: "Create membership address list",
                desc: "Warehouse clubs, AAA, library cards - let's catch all memberships that need updating.",
                icon: "person.2.fill"
            ),
            (
                id: "address_change_subscriptions",
                title: "Create subscription address list",
                desc: "Don't let deliveries go to your old address! Update meal kits, pet food, and other subscriptions.",
                icon: "shippingbox.fill"
            )
        ]
        
        let batch = db.batch()
        let userTasksRef = db.collection("users").document(userId).collection("tasks")
        
        for (index, assessment) in miniAssessments.enumerated() {
            let taskData: [String: Any] = [
                "id": assessment.id,
                "taskId": 1000 + index,  // Use 1000+ range for mini-assessments
                "urgencyPercentage": 85,
                "title": assessment.title,
                "desc": assessment.desc,
                "estHours": 0.25,  // About 15 minutes each
                "tips": "Swipe right to start. We'll help you think of everything!",
                "category": "address_change",
                "whyNeeded": "Updating your address everywhere prevents missed bills, lost mail, and service interruptions.",
                "priority": "Medium",
                "isAssessmentTask": false,
                "isSubTask": false,
                "parentTask": "",
                "conditions": "",
                "workflowId": assessment.id,  // Links to mini-assessment workflow
                "icon": assessment.icon,
                "dueDate": Timestamp(date: dueDate),
                "status": "Upcoming",
                "userId": userId,
                "createdAt": Timestamp(date: Date())
            ]
            
            let taskRef = userTasksRef.document(assessment.id)
            batch.setData(taskData, forDocument: taskRef)
        }

        do {
            try await batch.commit()
            print("✅ TASK GEN: Created \(miniAssessments.count) mini-assessment tasks")
        } catch {
            print("❌ TASK GEN FAILED (mini-assessments): \(error)")
            throw error
        }
        return miniAssessments.count
    }
}
