import SwiftUI

// MARK: - Task Flow Router
// Maps workflowId/taskId to standalone flow views.
// Used by PeezyHomeView to present flows via fullScreenCover.

struct TaskFlowRouter {

    @ViewBuilder
    static func flow(
        for flowId: String,
        userId: String,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        switch flowId {

        // ── Pattern A — Self-service (no userId) ──

        case "return_key_fobs_remotes":
            ReturnKeysFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "schedule_time_off_work":
            ScheduleTimeOffFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "update_employer_records":
            UpdateEmployerRecordsFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "update_drivers_license":
            UpdateDriversLicenseFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "new_drivers_license":
            NewDriversLicenseFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "register_vehicle":
            RegisterVehicleFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "photograph_rental_condition":
            PhotographRentalFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "buy_packing_supplies":
            BuyPackingSuppliesFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "buy_cleaning_supplies":
            BuyCleaningSuppliesFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "defrost_freezer":
            DefrostFreezerFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "diy_deep_cleaning":
            DiyDeepCleaningFlow(onComplete: onComplete, onDismiss: onDismiss)
        case "diy_final_cleaning":
            DiyFinalCleaningFlow(onComplete: onComplete, onDismiss: onDismiss)

        // ── Pattern B — Simple survey (with userId) ──

        case "manage_bank":
            ManageBankFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_doctor":
            ManageDoctorFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_dentist":
            ManageDentistFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_vet":
            ManageVetFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_gym":
            ManageGymFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_yoga":
            ManageYogaFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_spin":
            ManageSpinFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_massage":
            ManageMassageFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "manage_golf":
            ManageGolfFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "update_credit_card":
            UpdateCreditCardFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "update_investment":
            UpdateInvestmentFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "update_student_loans":
            UpdateStudentLoansFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_pharmacy_records":
            TransferPharmacyFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_specialists_records":
            TransferSpecialistsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "update_auto_insurance":
            UpdateAutoInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "cancel_renters_insurance":
            CancelRentersInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "setup_renters_insurance":
            SetupRentersInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_renters_insurance":
            TransferRentersInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "cancel_condo_insurance":
            CancelCondoInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "setup_condo_insurance":
            SetupCondoInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_condo_insurance":
            TransferCondoInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "cancel_homeowners_insurance":
            CancelHomeownersInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "setup_homeowners_insurance":
            SetupHomeownersInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_homeowners_insurance":
            TransferHomeownersInsuranceFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "forward_mail_usps":
            ForwardMailFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "cancel_utilities":
            CancelUtilitiesFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "setup_utilities":
            SetupUtilitiesFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_utilities":
            TransferUtilitiesFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "begin_school_transfer":
            BeginSchoolTransferFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "new_school_enrollment":
            NewSchoolEnrollmentFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "coa_schools":
            CoaSchoolsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "setup_daycare":
            SetupDaycareFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "transfer_daycare":
            TransferDaycareFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "arrange_parking_new":
            ArrangeParkingNewFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "arrange_parking_old":
            ArrangeParkingOldFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "reserve_elevators_new":
            ReserveElevatorsNewFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "reserve_elevators_old":
            ReserveElevatorsOldFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "rent_truck":
            RentTruckFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)

        // ── Pattern C — Complex survey (with userId) ──

        case "book_movers":
            BookMoversFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "book_cleaners":
            BookCleanersFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "setup_internet":
            SetupInternetFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "sell_items":
            SellItemsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)
        case "remove_items":
            RemoveItemsFlow(userId: userId, onComplete: onComplete, onDismiss: onDismiss)

        // ── Fallback ──

        default:
            Text("Flow not found: \(flowId)")
        }
    }
}
