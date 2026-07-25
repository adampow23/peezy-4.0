import Foundation

// MARK: - Task Stage
/// Universal workflow spine position, persisted on the task doc as `stage: String`
/// (raw value). Absent field = notStarted for workflow tasks, irrelevant for off-app.
/// Spec 03 Phase B writes it; Spec 04 renders resume-at-stage. No UI consumes it yet.
enum TaskStage: String, Codable, Equatable {
    case notStarted
    case capture
    case measure
    case scope
    case price
    case compare
    case book
    case verify
    case complete
}
