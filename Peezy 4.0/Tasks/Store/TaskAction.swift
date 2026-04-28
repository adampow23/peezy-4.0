import Foundation

enum TaskAction: Equatable {
    case open(PeezyCard)
    case markComplete(PeezyCard)
    case undo(PeezyCard)
    case resetInventory(PeezyCard)
}
