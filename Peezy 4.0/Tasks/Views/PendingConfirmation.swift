import Foundation

enum PendingConfirmation: Identifiable, Equatable {
    case resetInventory(PeezyCard)

    var id: String {
        switch self {
        case .resetInventory(let card): return "reset-\(card.id)"
        }
    }

    var title: String {
        "Reset your inventory?"
    }

    var message: String {
        "This deletes every room scan and item you've submitted. You'll need to scan your home again from scratch. This can't be undone."
    }

    var confirmLabel: String { "Yes, reset everything" }
    var cancelLabel: String { "Keep my inventory" }
}
