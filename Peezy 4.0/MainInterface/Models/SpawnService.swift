import Foundation
import FirebaseFunctions

/// Thin typed client for the deployed `spawnTasks` callable (Spec 09).
/// Callable pattern only — zero client-side webhook URLs (LE-029). Shared by
/// the nudge Yes path (Phase 3) and the conversation spawn terminal (Phase 4).
struct SpawnService {

    struct Source: Equatable {
        let kind: String   // "conversation" | "nudge" | "onComplete"
        let id: String
    }

    struct Subject: Equatable {
        let kind: String
        let id: String
    }

    struct Spawn: Equatable {
        let taskId: String
        var titleParams: [String: String]? = nil
        var subject: Subject? = nil
        var institutionId: String? = nil
        var institution: String? = nil
    }

    struct SpawnedTask {
        let id: String
        let taskId: String
        let title: String
        let dueDateISO: String
    }

    struct Response {
        let created: [SpawnedTask]
    }

    func spawn(
        token: String,
        source: Source,
        spawns: [Spawn],
        answers: [String: Any]? = nil,
        expectedUserId: String? = nil
    ) async throws -> Response {
        let payload = Self.makePayload(
            requestToken: token,
            source: source,
            expectedUserId: expectedUserId,
            spawns: spawns,
            answers: answers
        )

        let result = try await Functions.functions().httpsCallable("spawnTasks").call(payload)

        guard let data = result.data as? [String: Any],
              let created = data["created"] as? [[String: Any]] else {
            throw SpawnServiceError.invalidResponse
        }

        return Response(created: created.map { entry in
            SpawnedTask(
                id: entry["id"] as? String ?? "",
                taskId: entry["taskId"] as? String ?? "",
                title: entry["title"] as? String ?? "",
                dueDateISO: entry["dueDateISO"] as? String ?? ""
            )
        })
    }

    nonisolated static func makePayload(
        requestToken: String,
        source: Source,
        expectedUserId: String?,
        spawns: [Spawn],
        answers: [String: Any]?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "token": requestToken,
            "source": ["kind": source.kind, "id": source.id],
            "spawns": spawns.map { spawn -> [String: Any] in
                var entry: [String: Any] = ["taskId": spawn.taskId]
                if let titleParams = spawn.titleParams { entry["titleParams"] = titleParams }
                if let subject = spawn.subject,
                   let institutionId = spawn.institutionId,
                   let institution = spawn.institution {
                    entry["subject"] = ["kind": subject.kind, "id": subject.id]
                    entry["institutionId"] = institutionId
                    entry["institution"] = institution
                }
                return entry
            }
        ]
        if let answers { payload["answers"] = answers }
        if let expectedUserId { payload["expectedUserId"] = expectedUserId }
        return payload
    }
}

enum SpawnServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
