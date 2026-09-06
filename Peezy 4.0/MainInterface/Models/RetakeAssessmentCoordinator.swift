import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Retake orchestration (PHASE2_CONTRACT.md C9.4.6, C9.5.12–C9.5.17): the
/// registry reserve is the first async operation; every server call and every
/// cleanup callback runs inside `ResetOperationRegistry.drive`; the coordinator
/// holds no operation identity of its own.
struct RetakeAssessmentCoordinator {
    enum Error: LocalizedError {
        case missingUser
        case migrationPending(ResetMigrationPending)
        case legacyRetryRequired(LegacyResetRetryRequired)

        var errorDescription: String? {
            switch self {
            case .missingUser:
                return "Please sign in again before resetting your assessment."
            case .migrationPending:
                return "Your reset is safely queued. Reopen Settings to continue when you're online."
            case .legacyRetryRequired:
                return "No prior reset was committed. Start Reset Assessment again to begin a new reset."
            }
        }
    }

    private let currentUser: () -> String?
    private let remote: any ResetRemoteProviding
    private let registry: ResetOperationRegistry
    private let gestureId: @Sendable () -> String
    private let cleanup: ResetCleanupCallbacks
    private let postNotification: () async -> Void

    init(
        currentUser: @escaping () -> String?,
        remote: any ResetRemoteProviding,
        registry: ResetOperationRegistry,
        gestureId: @escaping @Sendable () -> String = { "rsg1_" + UUID().uuidString.lowercased() },
        cleanup: ResetCleanupCallbacks,
        postNotification: @escaping () async -> Void
    ) {
        self.currentUser = currentUser
        self.remote = remote
        self.registry = registry
        self.gestureId = gestureId
        self.cleanup = cleanup
        self.postNotification = postNotification
    }

    func retake() async throws {
        guard let userId = currentUser(), !userId.isEmpty else { throw Error.missingUser }

        let handle: ResetOperationHandle
        switch try await registry.reserve(gestureId: gestureId()) {
        case let .binding(reservation):
            handle = try await registry.bind(reservation: reservation)
        case let .operation(existing):
            handle = existing
        case .legacyCompleted:
            return
        case let .migrationPending(payload):
            throw Error.migrationPending(payload)
        case let .legacyRetryRequired(payload):
            throw Error.legacyRetryRequired(payload)
        }

        // resetDispatch,inspect,deleteAssessments,inspect,deleteUserKnowledge,inspect,resetDose,inspect,finalize
        let outcome = try await registry.drive(handle: handle, remote: remote, cleanup: cleanup)
        // notification: only the invocation that stored the first fresh final receipt.
        if outcome.notify { await postNotification() }
    }

    static func production() -> RetakeAssessmentCoordinator {
        RetakeAssessmentCoordinator(
            currentUser: { Auth.auth().currentUser?.uid },
            remote: TaskPlanService.ResetTransport(),
            registry: .production,
            cleanup: ResetCleanupCallbacks(
                deleteAssessments: { authority in try await ResetLocalCleanupV1.deleteAssessments(authority: authority) },
                deleteUserKnowledge: { authority in try await ResetLocalCleanupV1.deleteUserKnowledge(authority: authority) },
                resetDose: { authority in try await DailyDoseEngine().resetForRetake(authority: authority) }
            ),
            postNotification: {
                await MainActor.run {
                    NotificationCenter.default.post(name: .retakeAssessment, object: nil)
                }
            }
        )
    }
}
