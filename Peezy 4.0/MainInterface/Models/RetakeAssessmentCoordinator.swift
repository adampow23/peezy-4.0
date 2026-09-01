import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol RetakeOperationStore {
    func load(userId: String) async -> String?
    func save(_ operationId: String, userId: String) async
    func clear(userId: String) async
}

final class UserDefaultsRetakeOperationStore: RetakeOperationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ userId: String) -> String { "phase1.pendingRetakeOperation.\(userId)" }
    func load(userId: String) async -> String? { defaults.string(forKey: key(userId)) }
    func save(_ operationId: String, userId: String) async { defaults.set(operationId, forKey: key(userId)) }
    func clear(userId: String) async { defaults.removeObject(forKey: key(userId)) }
}

struct RetakeAssessmentCoordinator {
    enum TaskPlanAction { case reset, finalize }
    enum Error: LocalizedError {
        case missingUser
        var errorDescription: String? { "Please sign in again before resetting your assessment." }
    }

    typealias TaskPlan = (_ action: TaskPlanAction, _ operationId: String) async throws -> Void

    private let currentUser: () -> String?
    private let taskPlan: TaskPlan
    private let deleteAssessments: (String) async throws -> Void
    private let deleteUserKnowledge: (String) async throws -> Void
    private let resetDose: (String) async throws -> Void
    private let operationStore: any RetakeOperationStore
    private let postNotification: () async -> Void

    init(
        currentUser: @escaping () -> String?,
        taskPlan: @escaping TaskPlan,
        deleteAssessments: @escaping (String) async throws -> Void,
        deleteUserKnowledge: @escaping (String) async throws -> Void,
        resetDose: @escaping (String) async throws -> Void,
        operationStore: any RetakeOperationStore,
        postNotification: @escaping () async -> Void
    ) {
        self.currentUser = currentUser
        self.taskPlan = taskPlan
        self.deleteAssessments = deleteAssessments
        self.deleteUserKnowledge = deleteUserKnowledge
        self.resetDose = resetDose
        self.operationStore = operationStore
        self.postNotification = postNotification
    }

    func retake() async throws {
        guard let userId = currentUser(), !userId.isEmpty else { throw Error.missingUser }
        let operationId: String
        if let saved = await operationStore.load(userId: userId), !saved.isEmpty {
            operationId = saved
        } else {
            operationId = UUID().uuidString
            await operationStore.save(operationId, userId: userId)
        }

        // Every local operation is idempotent. If any step is ambiguous or
        // fails, the durable operation ID remains and the exact sequence replays.
        try await taskPlan(.reset, operationId)
        try await deleteAssessments(userId)
        try await deleteUserKnowledge(userId)
        try await resetDose(userId)
        try await taskPlan(.finalize, operationId)
        await operationStore.clear(userId: userId)
        await postNotification()
    }

    static func production() -> RetakeAssessmentCoordinator {
        let store = UserDefaultsRetakeOperationStore()
        return RetakeAssessmentCoordinator(
            currentUser: { Auth.auth().currentUser?.uid },
            taskPlan: { action, operationId in
                let service = TaskPlanService()
                switch action {
                case .reset:
                    _ = try await service.resetAllTasks(operationId: operationId)
                case .finalize:
                    _ = try await service.finalizeTaskReset(operationId: operationId)
                }
            },
            deleteAssessments: { userId in
                let documents = try await Firestore.firestore().collection("users").document(userId)
                    .collection("user_assessments").getDocuments().documents
                for document in documents { try await document.reference.delete() }
            },
            deleteUserKnowledge: { userId in
                try await Firestore.firestore().collection("userKnowledge").document(userId).delete()
            },
            resetDose: { userId in
                try await DailyDoseEngine().resetForRetake(userId: userId)
            },
            operationStore: store,
            postNotification: {
                await MainActor.run {
                    NotificationCenter.default.post(name: .retakeAssessment, object: nil)
                }
            }
        )
    }
}
