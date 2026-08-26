import Foundation
import FirebaseFunctions

/// Thin typed client for the deployed `spawnTasks` callable (Spec 09).
/// Callable pattern only — zero client-side webhook URLs (LE-029). Shared by
/// the nudge Yes path (Phase 3) and the conversation spawn terminal (Phase 4).
struct SpawnService {

    struct Source {
        let kind: String   // "conversation" | "nudge" | "onComplete"
        let id: String
    }

    struct Spawn {
        let taskId: String
        var titleParams: [String: String]? = nil
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
        var payload: [String: Any] = [
            "token": token,
            "source": ["kind": source.kind, "id": source.id],
            "spawns": spawns.map { spawn -> [String: Any] in
                var entry: [String: Any] = ["taskId": spawn.taskId]
                if let titleParams = spawn.titleParams {
                    entry["titleParams"] = titleParams
                }
                return entry
            }
        ]
        if let answers {
            payload["answers"] = answers
        }
        if let expectedUserId {
            payload["expectedUserId"] = expectedUserId
        }

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
