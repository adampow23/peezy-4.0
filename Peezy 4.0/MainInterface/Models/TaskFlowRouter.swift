import SwiftUI

// MARK: - Task Flow Router
// Maps workflowId/taskId to standalone flow views.
// Used by PeezyHomeView to present flows via fullScreenCover.

struct TaskFlowRouter {

    @ViewBuilder
    static func flow(
        for flowId: String,
        userId: String,
        userState: UserState? = nil,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        // All flows temporarily removed — rebuilding from master schema
        EmptyView()
    }
}
