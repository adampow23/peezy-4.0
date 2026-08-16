import Foundation
import Testing
@testable import Peezy_4_0

struct Build24RegressionTests {
    @Test func movePassClassifierUsesMachineReadableReason() {
        let error = NSError(
            domain: "com.firebase.functions",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey: "A localized message that may change",
                "details": ["reason": "move-pass-required"]
            ]
        )

        #expect(FunctionsErrorClassifier.classify(error) == .movePassRequired)
    }

    @Test func movePassClassifierSupportsLegacyMessageFallback() {
        let error = NSError(
            domain: "com.firebase.functions",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Move Pass required"]
        )

        #expect(FunctionsErrorClassifier.classify(error) == .movePassRequired)
    }

    @Test func genericPermissionDenialIsNotClassifiedAsMovePass() {
        let error = NSError(
            domain: "com.firebase.functions",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )

        #expect(FunctionsErrorClassifier.classify(error) == nil)
    }

    @Test func taskContentDecodesNestedCatalogPresentationFields() {
        let content = TaskContent(data: [
            "notesEnabled": true,
            "content": [
                "walkthrough": ["First guided step"],
                "tripKit": ["docs": ["Photo ID"]]
            ]
        ])

        #expect(content.notesEnabled)
        #expect(content.walkthrough == ["First guided step"])
        #expect(content.tripKit?.docs == ["Photo ID"])
        #expect(TaskContentHeader.walkthrough == "Guided next steps")
        #expect(TaskContentHeader.tripKit == "What to bring")
    }

    @MainActor
    @Test func scannerRetryReusesRetainedUploadedSessionRequest() async {
        let client = AlwaysDenyingInventoryClient()
        let manager = InventorySessionManager(
            coverageConfirmationStore: NoopCoverageConfirmationStore(),
            userIDProvider: { "test-user" },
            apiClient: client
        )
        let request = InventoryProcessingRequest(
            userId: "test-user",
            sessionId: "uploaded-session",
            roomName: "Kitchen",
            frameCount: 12
        )

        await manager.processUploadedSession(request)

        #expect(manager.movePassRequired)
        #expect(manager.hasRetainedProcessingRequest)
        #expect(manager.stateDescription == "roomList")
        #expect(manager.error == nil)
        #expect(!manager.isProcessing)
        #expect(client.requests == [request])

        await manager.retryRetainedProcessingRequest()

        #expect(manager.movePassRequired)
        #expect(manager.hasRetainedProcessingRequest)
        #expect(client.requests == [request, request])
    }
}

@MainActor
private final class AlwaysDenyingInventoryClient: InventoryProcessingCalling {
    private(set) var requests: [InventoryProcessingRequest] = []

    func processInventory(_ request: InventoryProcessingRequest) async throws {
        requests.append(request)
        throw InventoryError.movePassRequired
    }
}

@MainActor
private struct NoopCoverageConfirmationStore: CoverageConfirmationPersisting {
    func insertConfirmedRoomID(_ roomID: String, userID: String) async throws -> Set<String> {
        [roomID]
    }
}
