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

        print("🚀 Starting task generation for user: \(userId)")

        // 0. Create special "Complete Assessment" task FIRST
        try await createAssessmentCompletionTask(userId: userId, moveDate: moveDate)
        
        // 1. Create mini-assessment tasks (address change lists)
        let miniAssessmentCount = try await createMiniAssessmentTasks(userId: userId, moveDate: moveDate)
        print("📋 Created \(miniAssessmentCount) mini-assessment tasks")

        // 2. Fetch all tasks from taskCatalog
        let catalogSnapshot = try await db.collection("taskCatalog").getDocuments()
        print("📚 Found \(catalogSnapshot.documents.count) tasks in catalog")

        var tasksToCreate: [[String: Any]] = []
        
        // 3. Evaluate each task's conditions
        for document in catalogSnapshot.documents {
            let taskData = document.data()
            
            // Get conditions
            let conditions = taskData["conditions"] as? String
            
            // Evaluate if this task should be generated for this user
            if TaskConditionParser.evaluateConditions(conditions, against: assessment) {
                
                // Calculate due date based on urgency
                let urgencyPercentage = taskData["urgencyPercentage"] as? Int ?? 50
                let dueDate = calculateDueDate(moveDate: moveDate, urgencyPercentage: urgencyPercentage)
                
                // Create task document data in MovingTask-compatible format
                var userTask: [String: Any] = [:]
                
                // Copy all fields from catalog
                userTask["id"] = taskData["pageKey"] as? String ?? document.documentID
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
                
                print("✅ Including: \(taskData["title"] as? String ?? "Unknown")")
            } else {
                print("⏭️ Skipping: \(taskData["title"] as? String ?? "Unknown") (conditions not met)")
            }
        }
        
        print("📝 Generating \(tasksToCreate.count) tasks for user")
        
        // 4. Batch write tasks to user's collection
        let batch = db.batch()
        let userTasksRef = db.collection("users").document(userId).collection("tasks")
        
        for taskData in tasksToCreate {
            // Use pageKey as document ID if available, otherwise auto-generate
            let docId = taskData["id"] as? String ?? UUID().uuidString
            let taskRef = userTasksRef.document(docId)
            batch.setData(taskData, forDocument: taskRef)
        }
        
        // 5. Commit batch
        try await batch.commit()
        
        let totalTasks = tasksToCreate.count + miniAssessmentCount + 1 // +1 for assessment complete
        print("✨ Successfully generated \(totalTasks) total tasks!")
        
        return totalTasks
    }
    
    // MARK: - Due Date Calculation
    
    /// Calculates task due date based on urgency percentage
    /// Higher percentage (94%) = MORE urgent = do it SOONER (early in timeline, few days from now)
    /// Lower percentage (1%) = LESS urgent = do it LATER (near move date)
    /// - Parameters:
    ///   - moveDate: User's move date
    ///   - urgencyPercentage: Task urgency (1-99)
    /// - Returns: Calculated due date
    private func calculateDueDate(moveDate: Date, urgencyPercentage: Int) -> Date {
        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
        let moveDateStart = Calendar.current.startOfDay(for: moveDate)
        
        // Calculate total days between today and move date
        let totalDays = Calendar.current.dateComponents([.day], from: today, to: moveDateStart).day ?? 0
        
        // Calculate days from now based on urgency percentage
        // HIGH urgency (94%) = do it EARLY = 6% of timeline (3 days from now if move is in 54 days)
        // LOW urgency (1%) = do it LATE = 99% of timeline (53 days from now, near move day)
        let daysFromNow = Double(totalDays) * (1.0 - Double(urgencyPercentage) / 100.0)
        
        // Calculate due date
        let dueDate = Calendar.current.date(
            byAdding: .day,
            value: Int(daysFromNow),
            to: today
        ) ?? moveDate
        
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
        
        try await batch.commit()
        
        print("✅ Created \(miniAssessments.count) mini-assessment tasks")
        return miniAssessments.count
    }
}
