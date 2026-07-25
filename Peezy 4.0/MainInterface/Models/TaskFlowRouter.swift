//
//  TaskFlowRouter.swift
//  Peezy 4.0
//
//  Thin resolver (Spec 04 Phase C — replaces the closed 47-case switch).
//  Resolution order:
//  1. Capture registry (scan_inventory keeps its bespoke path)
//  2. Admin-pushed flows (quote_selection / admin_memo)
//  3. Catalog-v2 in-app tasks (explicit, no server definitions)
//  4. Swift custom flows (die in Specs 05–06 as the verticals rebuild
//     on the spine)
//  5. Everything else: flowDefinitions lookup → FlowEngineView; unresolvable
//     ids render the coming-right-up card (the permanent spinner is dead).
//

import SwiftUI

enum TaskFlowStatusAction {
    case inProgress
    case done
    case later
}

struct TaskFlowRouter {

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
        // ── Capture registry (bespoke path; parameterization in Spec 05) ──
        if CaptureRegistry.registration(flowId: flowId)?.kind == .videoInventory {
            ScanInventoryFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        } else {
            switch flowId {

        // ── Admin-pushed ──

        case "quote_selection":
            QuoteSelectionFlow(taskId: taskId ?? "", userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "admin_memo":
            AdminMemoFlow(taskId: taskId ?? "", userId: userId, onComplete: onComplete, onDismiss: onDismiss)

        // ── Catalog-v2 in-app tasks ──

        case "add_new_address":
            AddNewAddressFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "confirm_move_date":
            ConfirmMoveDateFlow(userId: userId, currentDate: userState?.moveDate ?? Date(), onComplete: onComplete, onDismiss: onDismiss)
        case "declutter_intent":
            DeclutterIntentFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "storage_need":
            StorageNeedFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)

        // ── Swift custom flows (Types 4–6; superseded in Specs 05–06) ──

        case "rent_truck":
            RentTruckFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "book_movers":
            FindMoversFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "book_cleaners":
            FindCleanersFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "setup_internet":
            SetupInternetFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "sell_items":
            SellItemsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "remove_items":
            RemoveItemsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "handle_auto_insurance", "update_auto_insurance":
            HandleAutoInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "handle_home_insurance",
             "cancel_renters_insurance", "setup_renters_insurance", "transfer_renters_insurance",
             "cancel_condo_insurance", "setup_condo_insurance", "transfer_condo_insurance",
             "cancel_homeowners_insurance", "setup_homeowners_insurance", "transfer_homeowners_insurance":
            HandleHomeInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)

        // ── Data-driven: flowDefinitions → FlowEngineView ──

        default:
            FlowEngineLoaderView(
                workflowId: flowId,
                userId: userId,
                taskId: taskId ?? "",
                inputs: FlowInputs(
                    currentAddress: userState?.currentFullAddress ?? "",
                    newAddress: userState?.newFullAddress ?? "",
                    moveDate: userState?.moveDate ?? Date()
                ),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
            }
        }
    }
}
