//
//  TaskFlowRouter.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Status Action
// Used by StatusCard to communicate what the user chose.
// Router maps these to ViewModel methods.

enum TaskFlowStatusAction {
    case inProgress
    case done
    case later
}

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
        onDismiss: @escaping () -> Void,
        onStatusAction: @escaping (TaskFlowStatusAction) -> Void
    ) -> some View {
        switch flowId {

        // ── Type 1: Self-Service ──

        case "return_key_fobs_remotes":
            ReturnKeysFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "schedule_time_off_work":
            ScheduleTimeOffFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "update_employer_records":
            UpdateEmployerRecordsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "update_drivers_license":
            UpdateDriversLicenseFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "new_drivers_license":
            NewDriversLicenseFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "register_vehicle":
            RegisterVehicleFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "photograph_rental_condition":
            PhotographRentalFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "buy_packing_supplies":
            BuyPackingSuppliesFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "buy_cleaning_supplies":
            BuyCleaningSuppliesFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "defrost_freezer":
            DefrostFreezerFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "diy_deep_cleaning":
            DiyDeepCleaningFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "diy_final_cleaning":
            DiyFinalCleaningFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "forward_mail_usps":
            ForwardMailFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "coa_schools":
            UpdateSchoolFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "transfer_daycare":
            UpdateDaycareFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "update_credit_card":
            UpdateCreditCardsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "update_student_loans":
            UpdateStudentLoansFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "begin_school_transfer":
            NotifySchoolFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "new_school_enrollment":
            EnrollNewSchoolFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "setup_daycare":
            FindNewDaycareFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)

        // ── Type 2: Manage-Provider ──

        case "manage_gym":
            ManageGymFlow(
                userId: userId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )
        case "manage_doctor":
            ManageDoctorFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "manage_dentist":
            ManageDentistFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "manage_vet":
            ManageVetFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "transfer_pharmacy_records":
            TransferPharmacyFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "transfer_specialists_records":
            TransferSpecialistsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "manage_yoga":
            ManageYogaFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "manage_spin":
            ManageSpinFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "manage_massage":
            ManageMassageFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "manage_bank":
            ManageBankFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)
        case "update_investment":
            UpdateInvestmentFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)

        // ── Type 3: Decision Only ──

        case "arrange_parking_new":
            ArrangeParkingNewFlow(
                userId: userId,
                currentAddress: [userState?.destinationCity, userState?.destinationState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "arrange_parking_old":
            ArrangeParkingOldFlow(
                userId: userId,
                currentAddress: [userState?.originCity, userState?.originState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "reserve_elevators_new":
            ReserveElevatorsNewFlow(
                userId: userId,
                currentAddress: [userState?.destinationCity, userState?.destinationState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "reserve_elevators_old":
            ReserveElevatorsOldFlow(
                userId: userId,
                currentAddress: [userState?.originCity, userState?.originState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "setup_utilities":
            SetupUtilitiesFlow(
                userId: userId,
                currentAddress: [userState?.destinationCity, userState?.destinationState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "cancel_utilities":
            CancelUtilitiesFlow(
                userId: userId,
                currentAddress: [userState?.originCity, userState?.originState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "transfer_utilities":
            TransferUtilitiesFlow(
                userId: userId,
                currentAddress: [userState?.destinationCity, userState?.destinationState]
                    .compactMap { $0 }.joined(separator: ", "),
                moveDate: userState?.moveDate ?? Date(),
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        // ── Type 4: Insurance ──

        case "handle_auto_insurance", "update_auto_insurance":
            HandleAutoInsuranceFlow(
                userId: userId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case "handle_home_insurance",
             "cancel_renters_insurance", "setup_renters_insurance", "transfer_renters_insurance",
             "cancel_condo_insurance", "setup_condo_insurance", "transfer_condo_insurance",
             "cancel_homeowners_insurance", "setup_homeowners_insurance", "transfer_homeowners_insurance":
            HandleHomeInsuranceFlow(
                userId: userId,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        // ── Type 5: Survey + Submit ──

        case "rent_truck":
            RentTruckFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss, onStatusAction: onStatusAction)

        // ── Type 6: Complex-Vendor ──

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

        // All other flows temporarily removed — rebuilding from master schema
        default:
            EmptyView()
        }
    }
}
