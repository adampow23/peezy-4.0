//
//  TaskFlowRouter.swift
//  Peezy 4.0
//
//  Thin resolver (Spec 04 Phase C — replaces the closed 47-case switch).
//  Resolution order:
//  1. Capture registry (scan_inventory keeps its bespoke path)
//  2. Catalog-v2 in-app tasks (explicit, no server definitions)
//  3. Swift custom flows (die in Specs 05–06 as the verticals rebuild
//     on the spine)
//  4. Routed ids not matched above: flowDefinitions lookup → FlowEngineView;
//     unresolvable ids render the coming-right-up card (the permanent spinner
//     is dead).
//

import SwiftUI

enum TaskFlowStatusAction {
    case inProgress
    case done
    case later
    /// The flow already persisted a permanent Home dismissal.
    case dismissedPermanently
    /// Legacy callback name retained for existing call sites. Submitted work
    /// is complete once the user has their action details.
    case submittedToPeezy
    /// Movers chain (plan v7): the flow already performed its own awaited,
    /// throwing completion write. Home does local accounting only — no write.
    case completedAlreadyPersisted
    /// Movers chain (plan v7): the flow already performed its own awaited,
    /// throwing two-day snooze write. Home does local accounting only.
    case laterAlreadyPersisted
}

struct TaskFlowRouter {

    /// A task is routable when the catalog supplied a workflow id or its
    /// lowercased task id resolves to one of the router's explicit mappings.
    static func flowId(for card: PeezyCard) -> String? {
        if let workflowId = card.workflowId, !workflowId.isEmpty {
            return workflowId
        }

        let candidate = (card.taskId ?? card.id).lowercased()
        guard hasMappedFlow(for: candidate) else { return nil }
        return candidate
    }

    private static func hasMappedFlow(for flowId: String) -> Bool {
        if CaptureRegistry.registration(flowId: flowId) != nil {
            return true
        }

        switch flowId {
        case "add_new_address", "confirm_move_date", "declutter_intent", "storage_need",
             "packing_session", "supplies_kit", "packing_readiness", "move_checkin", "box_return",
             "rent_truck", "book_movers", "compare_moving_quotes", "book_your_movers",
             "book_cleaners", "setup_internet", "sell_items", "remove_items",
             "handle_auto_insurance", "update_auto_insurance",
             "handle_home_insurance",
             "cancel_renters_insurance", "setup_renters_insurance", "transfer_renters_insurance",
             "cancel_condo_insurance", "setup_condo_insurance", "transfer_condo_insurance",
             "cancel_homeowners_insurance", "setup_homeowners_insurance", "transfer_homeowners_insurance":
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    static func flow(
        for flowId: String,
        userId: String,
        taskId: String? = nil,
        userState: UserState? = nil,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onStatusAction: @escaping (TaskFlowStatusAction) -> Void
    ) -> some View {
        let resolvedTaskId = taskId ?? ""
        if CaptureRegistry.registration(flowId: flowId)?.kind == .videoInventory {
            ScanInventoryRouteGate(
                userId: userId,
                taskId: resolvedTaskId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        } else if flowId == "packing_session" {
            PackingSessionRouteGate(
                userId: userId,
                taskId: resolvedTaskId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        } else {
            OutermostTaskFlowContainer(
                userId: userId,
                taskId: resolvedTaskId,
                onDismiss: onDismiss
            ) { requestExit in
                routedFlow(
                    for: flowId,
                    userId: userId,
                    taskId: resolvedTaskId,
                    userState: userState,
                    onComplete: onComplete,
                    onDismiss: requestExit,
                    onStatusAction: onStatusAction
                )
            }
        }
    }

    @ViewBuilder
    static func detail(
        userId: String,
        taskId: String,
        fallbackFlowId: String,
        onComplete: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        TaskDetailView(
            userId: userId,
            taskDocumentId: taskId,
            fallbackFlowId: fallbackFlowId,
            onComplete: onComplete,
            onSnooze: onSnooze,
            onDismiss: onDismiss
        )
    }

    @ViewBuilder
    private static func routedFlow(
        for flowId: String,
        userId: String,
        taskId: String,
        userState: UserState?,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onStatusAction: @escaping (TaskFlowStatusAction) -> Void
    ) -> some View {
        // ── Capture registry (bespoke path; parameterization in Spec 05) ──
        if CaptureRegistry.registration(flowId: flowId)?.kind == .videoInventory {
            ScanInventoryRouteGate(
                userId: userId,
                taskId: taskId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        } else {
            switch flowId {

        // ── Catalog-v2 in-app tasks ──

        case "add_new_address":
            AddNewAddressFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss)
        case "confirm_move_date":
            ConfirmMoveDateFlow(userId: userId, taskId: taskId, currentDate: userState?.moveDate ?? Date(), onComplete: onComplete, onDismiss: onDismiss)
        case "declutter_intent":
            DeclutterIntentFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss)
        case "storage_need":
            StorageNeedFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss)
        case "supplies_kit":
            SuppliesKitView(
                userId: userId,
                taskId: taskId.isEmpty ? SuppliesKit.taskId : taskId,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        case "packing_readiness":
            PackingReadinessView(
                userId: userId,
                taskId: taskId.isEmpty ? ReadinessChecklist.taskId : taskId,
                onComplete: onComplete,
                onDismiss: onDismiss
            )
        case "move_checkin":
            MoveCheckInView(
                userId: userId,
                taskId: taskId,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        case "box_return":
            BoxReturnView(
                userId: userId,
                taskId: taskId,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        // ── Swift custom flows (Types 4–6; superseded in Specs 05–06) ──

        case "rent_truck":
            RentTruckFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        // Movers chain (plan v7): role is derived from the flowId matched here,
        // NEVER from taskId — spawned task documents carry random ids.
        case "book_movers":
            FindMoversFlow(
                role: .getQuotes,
                userId: userId,
                taskDocumentId: taskId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        case "compare_moving_quotes":
            FindMoversFlow(
                role: .compareQuotes,
                userId: userId,
                taskDocumentId: taskId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        case "book_your_movers":
            BookYourMoversView(
                userId: userId,
                taskDocumentId: taskId,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        case "book_cleaners":
            FindCleanersFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "setup_internet":
            SetupInternetFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "sell_items":
            SellItemsFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "remove_items":
            RemoveItemsFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "handle_auto_insurance", "update_auto_insurance":
            HandleAutoInsuranceFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "handle_home_insurance",
             "cancel_renters_insurance", "setup_renters_insurance", "transfer_renters_insurance",
             "cancel_condo_insurance", "setup_condo_insurance", "transfer_condo_insurance",
             "cancel_homeowners_insurance", "setup_homeowners_insurance", "transfer_homeowners_insurance":
            HandleHomeInsuranceFlow(userId: userId, taskId: taskId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)

        // ── Data-driven: flowDefinitions → FlowEngineView ──

        default:
            FlowEngineLoaderView(
                workflowId: flowId,
                userId: userId,
                taskId: taskId,
                inputs: FlowInputs(
                    currentAddress: userState?.currentFullAddress ?? "",
                    newAddress: userState?.newFullAddress ?? "",
                    moveDate: userState?.moveDate ?? Date(),
                    isLongDistance: userState?.isLongDistance ?? false
                ),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
            }
        }
    }
}

private struct ScanInventoryRouteGate: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @ViewBuilder
    var body: some View {
        Group {
            if PaywallPolicy.requiresMovePass(for: .scanner),
               !subscriptionManager.isSubscribed {
                PaywallGateSheet(surface: .scanner) { subscribed in
                    if !subscribed {
                        onDismiss()
                    }
                }
            } else {
                OutermostTaskFlowContainer(
                    userId: userId,
                    taskId: taskId,
                    waitsForExternalAnswerState: true,
                    onDismiss: onDismiss
                ) { requestExit in
                    ScanInventoryFlow(
                        userId: userId,
                        taskId: taskId,
                        onComplete: onComplete,
                        onDismiss: requestExit,
                        onStatusAction: onStatusAction
                    )
                }
            }
        }
        .accessibilityIdentifier("scanner.route_gate")
    }
}

private struct PackingSessionRouteGate: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @ViewBuilder
    var body: some View {
        Group {
            if PaywallPolicy.requiresMovePass(for: .packing),
               !subscriptionManager.isSubscribed {
                PaywallGateSheet(surface: .packing) { subscribed in
                    if !subscribed {
                        onDismiss()
                    }
                }
            } else {
                OutermostTaskFlowContainer(
                    userId: userId,
                    taskId: taskId,
                    onDismiss: onDismiss
                ) { requestExit in
                    PackingSessionView(
                        userId: userId,
                        taskId: taskId,
                        onComplete: onComplete,
                        onDismiss: requestExit,
                        onStatusAction: onStatusAction
                    )
                }
            }
        }
        .accessibilityIdentifier("packing.route_gate")
    }
}
