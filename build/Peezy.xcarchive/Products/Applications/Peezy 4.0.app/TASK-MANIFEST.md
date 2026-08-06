# Task Flow Manifest
# Each task lists: pattern, file name, content, and qualifying reference.
# Claude Code reads this + TASKFLOW-SKILL.md + reference flows to generate each file.
# Question text and options come from the qualifying data in TaskPreviewData.swift.

---

## PATTERN A — Self-Service (No Firebase submission)
## Reference: ReturnKeysFlow.swift
## Structure: TitleCard → InfoCard("Good to Know") → SummaryCard("You're all set!")

### A1: ReturnKeysFlow.swift ✅ DONE
- taskTitle: "Return all access devices"
- workflowId: "return_key_fobs_remotes"
- description: "Hand-deliver every key, fob, garage remote, mailbox key, and parking tag — and get a written receipt listing exactly what you returned."
- goodToKnow: "A missing $5 fob can cost $200 in lock-change charges. Photograph everything you're returning the moment you hand it over."

### A2: ScheduleTimeOffFlow.swift
- taskTitle: "Request your time off"
- workflowId: "schedule_time_off_work"
- description: "Request 2-3 days minimum: one for packing, moving day, and one to recover. Submit at least four weeks ahead."
- goodToKnow: "Block the day after move day — unpacking always runs longer than expected. Without time off, you'll be answering Slack with a couch on your back."

### A3: UpdateEmployerRecordsFlow.swift
- taskTitle: "Update employer records"
- workflowId: "update_employer_records"
- description: "Update your home address with HR. If you crossed state lines, also update your work-state W-4 — addresses and taxes are tracked separately."
- goodToKnow: "Confirm payroll updated 'work state for taxes' — addresses don't sync. Wrong state withholding turns next April into a W-2 nightmare."

### A4: UpdateDriversLicenseFlow.swift
- taskTitle: "Update your license address"
- workflowId: "update_drivers_license"
- description: "Bring your current license and two proofs of new address to the DMV. Most states require updates within 30 days."
- goodToKnow: "Check your state — many let you update online without an appointment. An outdated address can void traffic ticket service and jury duty notices."

### A5: NewDriversLicenseFlow.swift
- taskTitle: "Get your new state license"
- workflowId: "new_drivers_license"
- description: "Surrender your old license at the new state's DMV. Bring proof of residency, your current license, and Social Security card."
- goodToKnow: "Request REAL ID — TSA needs a new one in your new state. Driving past the deadline on an out-of-state license is a moving violation."

### A6: RegisterVehicleFlow.swift
- taskTitle: "Register your vehicles"
- workflowId: "register_vehicle"
- description: "Most states require registration within 30 days of moving. You'll need a new auto insurance policy that meets state minimums first."
- goodToKnow: "Update auto insurance first — DMV won't register without it. Outdated tags risk tickets, towing, and insurance denial in a crash."

### A7: PhotographRentalFlow.swift
- taskTitle: "Document the empty unit"
- workflowId: "photograph_rental_condition"
- description: "After cleaning, take time-stamped photos and video of every wall, floor, fixture, and appliance — inside and out, every angle."
- goodToKnow: "Film a slow walkthrough video — judges weigh it heavier than photos. Without photos, the landlord's word is the only evidence in deposit disputes."

### A8: BuyPackingSuppliesFlow.swift
- taskTitle: "Buy packing supplies"
- workflowId: "buy_packing_supplies"
- description: "A one-bedroom needs roughly 30 small, 40 medium, and 20 large boxes, plus tape, paper, and markers. Budget $100-200 total."
- goodToKnow: "Liquor stores give away sturdy small boxes — perfect for books. Running out mid-pack means a last-minute store run during peak chaos."

### A9: BuyCleaningSuppliesFlow.swift
- taskTitle: "Buy cleaning supplies"
- workflowId: "buy_cleaning_supplies"
- description: "Pick up degreaser, glass cleaner, magic erasers, mop, broom, gloves, and microfiber cloths 3-5 days before move-out."
- goodToKnow: "Pack a 'last bag' with cleaning supplies — load it onto the truck last. Once boxes are sealed, finding a sponge becomes a 30-minute hunt."

### A10: DefrostFreezerFlow.swift
- taskTitle: "Defrost your freezer"
- workflowId: "defrost_freezer"
- description: "Empty the contents, unplug it, prop the doors open, and lay towels underneath. Plan 24-48 hours before move day."
- goodToKnow: "After moving, let it sit upright for 4 hours before plugging back in. Movers won't load a wet or leaking fridge — full stop."

### A11: DiyDeepCleaningFlow.swift
- taskTitle: "Deep clean the place"
- workflowId: "diy_deep_cleaning"
- description: "Plan 6+ hours with two people. Hit appliances, baseboards, walls, windows, vents, and cabinets — landlords inspect every one."
- goodToKnow: "Clean inside the oven and fridge first — they're the top deduction trigger. One missed area can cost you hundreds in deposit deductions."

### A12: DiyFinalCleaningFlow.swift
- taskTitle: "Do the final touch-up"
- workflowId: "diy_final_cleaning"
- description: "After everything is out, walk every room, closet, and cabinet. Wipe baseboards, sweep floors, and confirm nothing is left behind."
- goodToKnow: "Bring a flashlight — corners and closets hide more than you think. A forgotten item or dusty corner is exactly what landlords cite."

### A13: ScanInventoryFlow.swift ⚠️ SPECIAL
- taskTitle: "Scan your home"
- workflowId: "scan_inventory"
- description: "Pan your camera slowly across each room. Peezy's AI identifies furniture, appliances, and large items in about 20 seconds per room."
- goodToKnow: "Open closets and cabinets — Peezy catches what you'd forget to mention. An accurate inventory unlocks precise quotes and protects you against damage claims."
- NOTE: This task opens the in-app inventory scanner. Title card primary button should trigger the scanner via onComplete callback, not advance to info card. Build as Pattern A but with primaryLabel "Start Scan" and the parent handles opening the scanner.

---

## PATTERN B — Simple Survey (Firebase submission)
## Reference: ManageBankFlow.swift
## Structure: TitleCard → 0-2 TilesCard questions → SummaryCard with Submit
## Questions come from qualifying data in TaskPreviewData.swift

### B1: ManageBankFlow.swift ✅ DONE
- taskTitle: "Handle your bank account"
- workflowId: "manage_bank"
- qualifying ref: manage_bankQualifying
- questions: 1 (action: update/close/already handled)
- summary: "We're on it" / "We'll take it from here." / "Submit"

### B2: ManageDoctorFlow.swift
- taskTitle: "Handle your primary doctor"
- workflowId: "manage_doctor"
- qualifying ref: manage_doctorQualifying
- questions: 1 (action: transfer records/update address/already handled)
- summary: "We're on it" / "We'll take it from here." / "Submit"

### B3: ManageDentistFlow.swift
- taskTitle: "Handle your dentist"
- workflowId: "manage_dentist"
- qualifying ref: manage_dentistQualifying
- questions: 1
- summary: "We're on it" / "We'll take it from here." / "Submit"

### B4: ManageVetFlow.swift
- taskTitle: "Handle your vet"
- workflowId: "manage_vet"
- qualifying ref: manage_vetQualifying
- questions: 1
- summary: "We're on it" / "We'll take it from here." / "Submit"

### B5: ManageGymFlow.swift
- taskTitle: "Handle your gym membership"
- workflowId: "manage_gym"
- qualifying ref: manage_gymQualifying
- questions: 1 (transfer/cancel/update address/already handled)
- summary: "We're on it" / "We'll take it from here." / "Submit"

### B6: ManageYogaFlow.swift
- taskTitle: "Handle your yoga membership"
- workflowId: "manage_yoga"
- qualifying ref: manage_yogaQualifying
- questions: 1
- summary: same

### B7: ManageSpinFlow.swift
- taskTitle: "Handle your cycling membership"
- workflowId: "manage_spin"
- qualifying ref: manage_spinQualifying
- questions: 1
- summary: same

### B8: ManageMassageFlow.swift
- taskTitle: "Handle your spa membership"
- workflowId: "manage_massage"
- qualifying ref: manage_massageQualifying
- questions: 1
- summary: same

### B9: ManageGolfFlow.swift
- taskTitle: "Handle your club membership"
- workflowId: "manage_golf"
- qualifying ref: manage_golfQualifying
- questions: 1
- summary: same

### B10: UpdateCreditCardFlow.swift
- taskTitle: "Update credit card addresses"
- workflowId: "update_credit_card"
- qualifying ref: update_credit_cardQualifying
- questions: 1
- summary: same

### B11: UpdateInvestmentFlow.swift
- taskTitle: "Update investment accounts"
- workflowId: "update_investment"
- qualifying ref: update_investmentQualifying
- questions: 1
- summary: same

### B12: UpdateStudentLoansFlow.swift
- taskTitle: "Update student loan accounts"
- workflowId: "update_student_loans"
- qualifying ref: update_student_loansQualifying
- questions: 1
- summary: same

### B13: TransferPharmacyFlow.swift
- taskTitle: "Transfer your pharmacy"
- workflowId: "transfer_pharmacy_records"
- qualifying ref: transfer_pharmacy_recordsQualifying
- questions: 1
- summary: same

### B14: TransferSpecialistsFlow.swift
- taskTitle: "Transfer specialist records"
- workflowId: "transfer_specialists_records"
- qualifying ref: transfer_specialists_recordsQualifying
- questions: 1
- summary: same

### B15: UpdateAutoInsuranceFlow.swift
- taskTitle: "Update your auto insurance"
- workflowId: "update_auto_insurance"
- qualifying ref: update_auto_insuranceQualifying
- questions: 2 (help preference + current provider, provider conditional on help_me)
- skip logic: current_provider shows only if help_preference = "help_me"
- summary: "We're on it" / "We'll reach out and get this updated for you." / "Submit"

### B16: CancelRentersInsuranceFlow.swift
- taskTitle: "Cancel your renter's insurance"
- workflowId: "cancel_renters_insurance"
- qualifying ref: cancel_renters_insuranceQualifying
- questions: 2 (help preference + current provider, conditional)
- skip logic: same as B15
- summary: similar

### B17: SetupRentersInsuranceFlow.swift
- taskTitle: "Set up renter's insurance"
- workflowId: "setup_renters_insurance"
- qualifying ref: setup_renters_insuranceQualifying
- questions: 1
- summary: similar

### B18: TransferRentersInsuranceFlow.swift
- taskTitle: "Transfer renter's insurance"
- workflowId: "transfer_renters_insurance"
- qualifying ref: transfer_renters_insuranceQualifying
- questions: 2 (conditional)
- skip logic: same as B15

### B19: CancelCondoInsuranceFlow.swift
- taskTitle: "Cancel your condo insurance"
- workflowId: "cancel_condo_insurance"
- qualifying ref: cancel_condo_insuranceQualifying
- questions: 2 (conditional)
- skip logic: same as B15

### B20: SetupCondoInsuranceFlow.swift
- taskTitle: "Set up condo insurance"
- workflowId: "setup_condo_insurance"
- qualifying ref: setup_condo_insuranceQualifying
- questions: 1
- summary: similar

### B21: TransferCondoInsuranceFlow.swift
- taskTitle: "Transfer your condo insurance"
- workflowId: "transfer_condo_insurance"
- qualifying ref: transfer_condo_insuranceQualifying
- questions: 2 (conditional)
- skip logic: same as B15

### B22: CancelHomeownersInsuranceFlow.swift
- taskTitle: "Cancel homeowner's insurance"
- workflowId: "cancel_homeowners_insurance"
- qualifying ref: cancel_homeowners_insuranceQualifying
- questions: 2 (conditional)
- skip logic: same as B15

### B23: SetupHomeownersInsuranceFlow.swift
- taskTitle: "Set up homeowner's insurance"
- workflowId: "setup_homeowners_insurance"
- qualifying ref: setup_homeowners_insuranceQualifying
- questions: 1
- summary: similar

### B24: TransferHomeownersInsuranceFlow.swift
- taskTitle: "Transfer homeowner's insurance"
- workflowId: "transfer_homeowners_insurance"
- qualifying ref: transfer_homeowners_insuranceQualifying
- questions: 2 (conditional)
- skip logic: same as B15

### B25: ForwardMailFlow.swift
- taskTitle: "Forward your mail"
- workflowId: "forward_mail_usps"
- qualifying ref: forward_mail_uspsQualifying
- questions: 0 (guidance only — title + info + summary, no tiles)
- summary: "Here's how to forward your mail" / closing text / "Got it"

### B26: CancelUtilitiesFlow.swift
- taskTitle: "Cancel your utilities"
- workflowId: "cancel_utilities"
- qualifying ref: cancel_utilitiesQualifying
- questions: 0
- summary: guidance recap / "Got it"

### B27: SetupUtilitiesFlow.swift
- taskTitle: "Set up new utilities"
- workflowId: "setup_utilities"
- qualifying ref: setup_utilitiesQualifying
- questions: 1

### B28: TransferUtilitiesFlow.swift
- taskTitle: "Transfer your utilities"
- workflowId: "transfer_utilities"
- qualifying ref: transfer_utilitiesQualifying
- questions: 0
- summary: guidance recap / "Got it"

### B29: BeginSchoolTransferFlow.swift
- taskTitle: "Notify the current school"
- workflowId: "begin_school_transfer"
- qualifying ref: begin_school_transferQualifying
- questions: 2

### B30: NewSchoolEnrollmentFlow.swift
- taskTitle: "Enroll in the new school"
- workflowId: "new_school_enrollment"
- qualifying ref: new_school_enrollmentQualifying
- questions: 1

### B31: CoaSchoolsFlow.swift
- taskTitle: "Update your child's school"
- workflowId: "coa_schools"
- qualifying ref: coa_schoolsQualifying
- questions: 0
- summary: guidance recap / "Got it"

### B32: SetupDaycareFlow.swift
- taskTitle: "Find your new daycare"
- workflowId: "setup_daycare"
- qualifying ref: setup_daycareQualifying
- questions: 2

### B33: TransferDaycareFlow.swift
- taskTitle: "Update your daycare"
- workflowId: "transfer_daycare"
- qualifying ref: transfer_daycareQualifying
- questions: 0
- summary: guidance recap / "Got it"

### B34: ArrangeParkingNewFlow.swift
- taskTitle: "Reserve unloading parking"
- workflowId: "arrange_parking_new"
- qualifying ref: arrange_parking_newQualifying
- questions: 1

### B35: ArrangeParkingOldFlow.swift
- taskTitle: "Reserve loading parking"
- workflowId: "arrange_parking_old"
- qualifying ref: arrange_parking_oldQualifying
- questions: 1

### B36: ReserveElevatorsNewFlow.swift
- taskTitle: "Reserve unloading elevator"
- workflowId: "reserve_elevators_new"
- qualifying ref: reserve_elevators_newQualifying
- questions: 1

### B37: ReserveElevatorsOldFlow.swift
- taskTitle: "Reserve loading elevator"
- workflowId: "reserve_elevators_old"
- qualifying ref: reserve_elevators_oldQualifying
- questions: 1

### B38: RentTruckFlow.swift
- taskTitle: "Rent your moving truck"
- workflowId: "rent_truck"
- qualifying ref: rent_truckQualifying
- questions: 1

---

## PATTERN C — Complex Survey (Firebase submission, 3+ questions)
## Reference: BookMoversFlow.swift
## Structure: TitleCard → multiple mixed card types → SummaryCard with Submit

### C1: BookMoversFlow.swift ✅ DONE
- taskTitle: "Book your movers"
- workflowId: "book_movers"
- questions: 8 (heavy items, delicate items, packing, storage yes/no, storage size, storage fullness, insurance warning, insurance preference)
- skip logic: storage_size and storage_fullness conditional on storage_needed = yes
- special cards: CompactTilesCard (storage yes/no), FillBarCard (fullness), InfoCard with caution icon (insurance warning)

### C2: BookCleanersFlow.swift
- taskTitle: "Book your cleaners"
- workflowId: "book_cleaners"
- qualifying ref: book_cleanersQualifying
- questions: 4 (which place, services needed, move-out timing, move-in timing)
- skip logic: move_out_timing shows if which_place = "move_out" or "both"; move_in_timing shows if which_place = "move_in" or "both"
- summary: "Here's what we've got" / closing / "Request Quotes"

### C3: SetupInternetFlow.swift
- taskTitle: "Schedule internet install"
- workflowId: "setup_internet"
- qualifying ref: setup_internetQualifying
- questions: 3 (usage, people count, contract preference)
- no skip logic
- summary: similar

### C4: SellItemsFlow.swift
- taskTitle: "Sell what you're not bringing"
- workflowId: "sell_items"
- qualifying ref: sell_itemsQualifying
- questions: 3 (item categories, estimated value, platforms)
- no skip logic

### C5: RemoveItemsFlow.swift
- taskTitle: "Schedule donation pickup"
- workflowId: "remove_items"
- qualifying ref: remove_itemsQualifying
- questions: 6 (removal route, item categories, condition, quantity, location, pickup preference)
- no skip logic

---

## TOTALS
- Pattern A (self-service): 13 tasks (12 standard + 1 special scanner)
- Pattern B (simple survey): 38 tasks
- Pattern C (complex survey): 5 tasks
- Already done: 3 (BookMovers, ManageBank, ReturnKeys)
- Remaining: 53 tasks
