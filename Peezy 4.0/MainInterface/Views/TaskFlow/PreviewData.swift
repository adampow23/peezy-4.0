import SwiftUI

// MARK: - Preview Helpers

extension PeezyCard {
    static let previewResearch = PeezyCard(
        id: "preview-research",
        type: .task,
        title: "Reserve parking for unloading",
        subtitle: "Secure a designated parking space at your new building for moving day.",
        taskId: "ARRANGE_PARKING_NEW",
        status: .upcoming,
        taskCategory: "moving",
        urgencyPercentage: 72,
        selfServiceOnly: false,
        actionType: "workflow",
        taskType: "research"
    )

    static let previewSurvey = PeezyCard(
        id: "preview-survey",
        type: .task,
        title: "Book movers",
        subtitle: "Research and reserve a moving company to handle your relocation safely and efficiently.",
        taskId: "BOOK_MOVERS",
        workflowId: "book_movers",
        status: .upcoming,
        taskCategory: "moving",
        urgencyPercentage: 94,
        selfServiceOnly: false,
        actionType: "workflow",
        taskType: "survey"
    )

    static let previewTransfer = PeezyCard(
        id: "preview-transfer",
        type: .task,
        title: "Bank / Credit Union",
        subtitle: "Decide how to handle your bank account for the move — update your address, close and open a new one, or let us know it's covered.",
        taskId: "MANAGE_BANK",
        workflowId: "manage_bank",
        status: .upcoming,
        taskCategory: "finance",
        urgencyPercentage: 84,
        selfServiceOnly: false,
        actionType: "workflow",
        taskType: "transfer_cancel"
    )

    static let previewTransferGym = PeezyCard(
        id: "preview-transfer-gym",
        type: .task,
        title: "Gym / CrossFit Membership",
        subtitle: "Decide how to handle your gym membership.",
        taskId: "MANAGE_GYM",
        status: .upcoming,
        taskCategory: "fitness",
        urgencyPercentage: 86,
        selfServiceOnly: false,
        actionType: "workflow",
        taskType: "transfer_cancel"
    )

    static let previewProvideInfo = PeezyCard(
        id: "preview-provide-info",
        type: .task,
        title: "Forward mail",
        subtitle: "File a change of address with the postal service so your mail is forwarded from your old address to your new one.",
        taskId: "FORWARD_MAIL_USPS",
        status: .upcoming,
        taskCategory: "administrative",
        urgencyPercentage: 79,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info"
    )
}

extension UserState {
    static let preview: UserState = {
        var state = UserState(userId: "preview", name: "Adam")
        state.originCity = "Austin"
        state.originState = "TX"
        state.destinationCity = "Denver"
        state.destinationState = "CO"
        state.moveDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        state.moveDistance = .crossState
        return state
    }()
}
