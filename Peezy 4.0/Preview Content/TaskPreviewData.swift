//
//  TaskPreviewData.swift
//  Peezy 4.0
//

import Foundation

#if DEBUG
enum TaskPreviewData {

    // MARK: - Shared Mock Objects

    static let sampleUserState = UserState(userId: "preview-user-123", name: "Alex")

    // MARK: - Task Cards from Catalog

    static let arrange_parking_newTask = PeezyCard(
        type: .task,
        title: "Reserve unloading parking",
        subtitle: "Reserve a truck-sized loading spot at your new building two weeks out. Most charge a deposit and require a Certificate of Insurance.",
        taskId: "ARRANGE_PARKING_NEW",
        workflowId: "arrange_parking_new",
        status: .inProgress,
        taskCategory: "moving",
        urgencyPercentage: 72,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask the building to cone off the spot the night before.",
        whyNeeded: "Without it, you'll be hauling boxes from wherever you can park.",
        estPeezy: "1 min"
    )

    static let arrange_parking_oldTask = PeezyCard(
        type: .task,
        title: "Reserve loading parking",
        subtitle: "Reserve a truck-sized loading spot at your current building two weeks out. Most charge a deposit and require a Certificate of Insurance.",
        taskId: "ARRANGE_PARKING_OLD",
        workflowId: "arrange_parking_old",
        status: .inProgress,
        taskCategory: "moving",
        urgencyPercentage: 73,
        actionType: "workflow",
        taskType: "survey",
        tips: "Reserve two adjacent spots — trucks need ramp clearance too.",
        whyNeeded: "Every block away adds 30+ minutes to your move — and your bill.",
        estPeezy: "1 min"
    )

    static let reserve_elevators_newTask = PeezyCard(
        type: .task,
        title: "Reserve unloading elevator",
        subtitle: "Lock in a service elevator window at your new building. Most allow 2-4 hours; overtime runs $100-200 per hour after.",
        taskId: "RESERVE_ELEVATORS_NEW",
        workflowId: "reserve_elevators_new",
        status: .inProgress,
        taskCategory: "moving",
        urgencyPercentage: 70,
        actionType: "workflow",
        taskType: "survey",
        tips: "Book the first morning slot — overtime starts at $100/hour.",
        whyNeeded: "Without a slot, you're competing with every other resident's groceries and laundry.",
        estPeezy: "1 min"
    )

    static let reserve_elevators_oldTask = PeezyCard(
        type: .task,
        title: "Reserve loading elevator",
        subtitle: "Lock in a service elevator window at your current building. Most allow 2-4 hours; overtime runs $100-200 per hour after.",
        taskId: "RESERVE_ELEVATORS_OLD",
        workflowId: "reserve_elevators_old",
        status: .inProgress,
        taskCategory: "moving",
        urgencyPercentage: 71,
        actionType: "workflow",
        taskType: "survey",
        tips: "Measure your couch against the elevator BEFORE move day.",
        whyNeeded: "Without one, you lose 10 minutes every time a neighbor calls it.",
        estPeezy: "1 min"
    )

    static let book_moversTask = PeezyCard(
        type: .task,
        title: "Book your movers",
        subtitle: "Get binding estimates from three USDOT-licensed movers. Book 8-12 weeks out for summer moves, 4-6 weeks off-season.",
        taskId: "BOOK_MOVERS",
        workflowId: "book_movers",
        status: .inProgress,
        taskCategory: "moving",
        urgencyPercentage: 94,
        actionType: "workflow",
        taskType: "survey",
        tips: "Get a binding estimate — federal law caps your final bill at 110%.",
        whyNeeded: "Booking late means leftover dates, leftover crews, and leftover quality.",
        estPeezy: "90 secs"
    )

    static let book_cleanersTask = PeezyCard(
        type: .task,
        title: "Book your cleaners",
        subtitle: "Schedule a move-out deep clean for the day after your movers finish. Get three quotes and confirm scope in writing.",
        taskId: "BOOK_CLEANERS",
        workflowId: "book_cleaners",
        status: .inProgress,
        taskCategory: "services",
        urgencyPercentage: 25,
        actionType: "workflow",
        taskType: "survey",
        tips: "Insist 'inside appliances' is in writing — most charge extra otherwise.",
        whyNeeded: "One missed area can cost you your entire security deposit.",
        estPeezy: "90 secs"
    )

    static let rent_truckTask = PeezyCard(
        type: .task,
        title: "Rent your moving truck",
        subtitle: "Compare U-Haul, Penske, and Budget on size, mileage, and total cost. Reserve 4-6 weeks out — earlier in summer.",
        taskId: "RENT_TRUCK",
        workflowId: "rent_truck",
        status: .inProgress,
        taskCategory: "moving",
        urgencyPercentage: 91,
        actionType: "workflow",
        taskType: "survey",
        tips: "Size up if borderline — one trip always beats two.",
        whyNeeded: "Late means the wrong size, wrong pickup location, or no truck at all.",
        estPeezy: "1 min"
    )

    static let setup_internetTask = PeezyCard(
        type: .task,
        title: "Schedule internet install",
        subtitle: "Order service 2-3 weeks ahead. Ask for self-install if your home is pre-wired — it saves $50-100 and a technician window.",
        taskId: "SETUP_INTERNET",
        workflowId: "setup_internet",
        status: .inProgress,
        taskCategory: "utilities",
        urgencyPercentage: 81,
        actionType: "workflow",
        taskType: "survey",
        tips: "Self-install saves $50-100 — confirm your address qualifies first.",
        whyNeeded: "Without it, you're tethering work calls to your phone for days.",
        estPeezy: "90 secs"
    )

    static let sell_itemsTask = PeezyCard(
        type: .task,
        title: "Sell what you're not bringing",
        subtitle: "List on Facebook Marketplace, OfferUp, or Craigslist 4+ weeks out. Drop the price 10-20% every three days until it sells.",
        taskId: "SELL_ITEMS",
        workflowId: "sell_items",
        status: .inProgress,
        taskCategory: "packing",
        urgencyPercentage: 75,
        actionType: "workflow",
        taskType: "survey",
        tips: "Post photos in natural daylight — listings sell twice as fast.",
        whyNeeded: "Every unsold item becomes a box you pay to move.",
        estPeezy: "90 secs"
    )

    static let remove_itemsTask = PeezyCard(
        type: .task,
        title: "Schedule donation pickup",
        subtitle: "Book a free pickup with Salvation Army or Habitat ReStore 3-4 weeks out — peak season wait times stretch to a month.",
        taskId: "REMOVE_ITEMS",
        workflowId: "remove_items",
        status: .inProgress,
        taskCategory: "packing",
        urgencyPercentage: 70,
        actionType: "workflow",
        taskType: "survey",
        tips: "Get an itemized receipt at pickup — it's a tax write-off.",
        whyNeeded: "Last-minute, you'll be hauling furniture to the curb yourself.",
        estPeezy: "90 secs"
    )

    static let manage_bankTask = PeezyCard(
        type: .task,
        title: "Handle your bank account",
        subtitle: "If your bank is national, just update your address. If regional, you may need to open a new account and reroute direct deposits.",
        taskId: "MANAGE_BANK",
        workflowId: "manage_bank",
        status: .inProgress,
        taskCategory: "finance",
        urgencyPercentage: 84,
        actionType: "workflow",
        taskType: "survey",
        tips: "Open the new account before closing the old — overlap protects autopay.",
        whyNeeded: "Outdated info triggers fraud alerts and frozen cards on day one.",
        estPeezy: "1 min"
    )

    static let manage_doctorTask = PeezyCard(
        type: .task,
        title: "Handle your primary doctor",
        subtitle: "Update your address if staying. If switching, request your full record through the patient portal — it's free and faster than fax.",
        taskId: "MANAGE_DOCTOR",
        workflowId: "manage_doctor",
        status: .inProgress,
        taskCategory: "health",
        urgencyPercentage: 68,
        actionType: "workflow",
        taskType: "survey",
        tips: "Download records from the portal yourself — providers have 30 days by law.",
        whyNeeded: "Without records, every new visit starts you over from zero.",
        estPeezy: "1 min"
    )

    static let manage_dentistTask = PeezyCard(
        type: .task,
        title: "Handle your dentist",
        subtitle: "Update your address if staying. If switching, request records and recent X-rays — most offices charge for paper copies but email is free.",
        taskId: "MANAGE_DENTIST",
        workflowId: "manage_dentist",
        status: .inProgress,
        taskCategory: "health",
        urgencyPercentage: 59,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask for digital X-ray transfer — most offices send them free.",
        whyNeeded: "Without X-rays, your new dentist will retake them at your cost.",
        estPeezy: "1 min"
    )

    static let manage_vetTask = PeezyCard(
        type: .task,
        title: "Handle your vet",
        subtitle: "Update your address if staying. If switching, request vaccination records, lab results, and any chronic-care notes for your new vet.",
        taskId: "MANAGE_VET",
        workflowId: "manage_vet",
        status: .inProgress,
        taskCategory: "pets",
        urgencyPercentage: 63,
        actionType: "workflow",
        taskType: "survey",
        tips: "Get the rabies certificate separately — boarding facilities require it on-site.",
        whyNeeded: "Without records, boarding kennels and ER vets may turn you away.",
        estPeezy: "1 min"
    )

    static let manage_gymTask = PeezyCard(
        type: .task,
        title: "Handle your gym membership",
        subtitle: "Most contracts let you cancel free if your new home is 25+ miles away. Bring written proof: lease, utility bill, or new license.",
        taskId: "MANAGE_GYM",
        workflowId: "manage_gym",
        status: .inProgress,
        taskCategory: "fitness",
        urgencyPercentage: 86,
        actionType: "workflow",
        taskType: "survey",
        tips: "Send cancellation by certified mail — verbal requests get 'lost.'",
        whyNeeded: "Otherwise, billing continues monthly until you formally cancel.",
        estPeezy: "1 min"
    )

    static let manage_yogaTask = PeezyCard(
        type: .task,
        title: "Handle your yoga membership",
        subtitle: "Most studios require 30-day written cancellation. Some chains transfer to a sister studio free if you stay in their network.",
        taskId: "MANAGE_YOGA",
        workflowId: "manage_yoga",
        status: .inProgress,
        taskCategory: "fitness",
        urgencyPercentage: 87,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask for written cancellation confirmation — 'requested' isn't 'confirmed.'",
        whyNeeded: "Skip this and auto-renewal bills you for two more months.",
        estPeezy: "1 min"
    )

    static let manage_spinTask = PeezyCard(
        type: .task,
        title: "Handle your cycling membership",
        subtitle: "Most studios require 30-day written cancellation. SoulCycle and similar chains may transfer free to any in-network location.",
        taskId: "MANAGE_SPIN",
        workflowId: "manage_spin",
        status: .inProgress,
        taskCategory: "fitness",
        urgencyPercentage: 82,
        actionType: "workflow",
        taskType: "survey",
        tips: "Cancel by email so you have a timestamped paper trail.",
        whyNeeded: "Otherwise, billing continues monthly until you formally cancel.",
        estPeezy: "1 min"
    )

    static let manage_massageTask = PeezyCard(
        type: .task,
        title: "Handle your spa membership",
        subtitle: "Massage Envy and most chains transfer to any location free. Local studios usually require 30-day written cancellation with proof of move.",
        taskId: "MANAGE_MASSAGE",
        workflowId: "manage_massage",
        status: .inProgress,
        taskCategory: "fitness",
        urgencyPercentage: 82,
        actionType: "workflow",
        taskType: "survey",
        tips: "Use every banked session before canceling — most don't refund.",
        whyNeeded: "Banked sessions usually expire fast once billing stops.",
        estPeezy: "1 min"
    )

    static let manage_golfTask = PeezyCard(
        type: .task,
        title: "Handle your club membership",
        subtitle: "Most clubs require formal resignation in writing with 30-90 days notice. Some refund equity, some don't — check your bylaws first.",
        taskId: "MANAGE_GOLF",
        workflowId: "manage_golf",
        status: .inProgress,
        taskCategory: "fitness",
        urgencyPercentage: 85,
        actionType: "workflow",
        taskType: "survey",
        tips: "Resign before the new fiscal year — dues bill upfront on day one.",
        whyNeeded: "Late resignation triggers full annual dues even after you've moved.",
        estPeezy: "1 min"
    )

    static let update_credit_cardTask = PeezyCard(
        type: .task,
        title: "Update credit card addresses",
        subtitle: "Log in and update billing addresses on every card. The address you file is what online checkout uses to authorize purchases.",
        taskId: "UPDATE_CREDIT_CARD",
        workflowId: "update_credit_card",
        status: .inProgress,
        taskCategory: "finance",
        urgencyPercentage: 62,
        actionType: "workflow",
        taskType: "survey",
        tips: "Set a temporary travel notice — out-of-state spending often triggers freezes.",
        whyNeeded: "Mismatched addresses get cards declined at checkout — even your own.",
        estPeezy: "30 secs"
    )

    static let update_investmentTask = PeezyCard(
        type: .task,
        title: "Update investment accounts",
        subtitle: "Update your address with every brokerage. Tax forms (1099s, K-1s) ship in January — wrong address means a delayed return.",
        taskId: "UPDATE_INVESTMENT",
        workflowId: "update_investment",
        status: .inProgress,
        taskCategory: "finance",
        urgencyPercentage: 61,
        actionType: "workflow",
        taskType: "survey",
        tips: "Switch statements to e-delivery — eliminates the address risk entirely.",
        whyNeeded: "Missing 1099s force tax-filing delays and IRS extension headaches.",
        estPeezy: "1 min"
    )

    static let update_student_loansTask = PeezyCard(
        type: .task,
        title: "Update student loan accounts",
        subtitle: "Update your address with every loan servicer. They mail repayment notices and 1098-E interest statements throughout the year.",
        taskId: "UPDATE_STUDENT_LOANS",
        workflowId: "update_student_loans",
        status: .inProgress,
        taskCategory: "finance",
        urgencyPercentage: 60,
        actionType: "workflow",
        taskType: "survey",
        tips: "Switch to paperless billing — eliminates address-based delivery failures.",
        whyNeeded: "A missed servicer notice can put you into delinquency status.",
        estPeezy: "1 min"
    )

    static let forward_mail_uspsTask = PeezyCard(
        type: .task,
        title: "Forward your mail",
        subtitle: "File a USPS change of address ($1.10 verification fee). First-class mail forwards free for 12 months from your start date.",
        taskId: "FORWARD_MAIL_USPS",
        workflowId: "forward_mail_usps",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 79,
        actionType: "workflow",
        taskType: "survey",
        tips: "Marketing mail and magazines don't forward — update senders directly.",
        whyNeeded: "Anything sent to your old address — bills, tax docs, checks — vanishes.",
        estPeezy: "30 secs"
    )

    static let schedule_time_off_workTask = PeezyCard(
        type: .task,
        title: "Request your time off",
        subtitle: "Request 2-3 days minimum: one for packing, moving day, and one to recover. Submit at least four weeks ahead.",
        taskId: "SCHEDULE_TIME_OFF_WORK",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 92,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Block the day after move day — unpacking always runs longer than expected.",
        whyNeeded: "Without time off, you'll be answering Slack with a couch on your back.",
        estPeezy: "30 secs"
    )

    static let update_employer_recordsTask = PeezyCard(
        type: .task,
        title: "Update employer records",
        subtitle: "Update your home address with HR. If you crossed state lines, also update your work-state W-4 — addresses and taxes are tracked separately.",
        taskId: "UPDATE_EMPLOYER_RECORDS",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 68,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Confirm payroll updated 'work state for taxes' — addresses don't sync.",
        whyNeeded: "Wrong state withholding turns next April into a W-2 nightmare.",
        estPeezy: "30 secs"
    )

    static let update_drivers_licenseTask = PeezyCard(
        type: .task,
        title: "Update your license address",
        subtitle: "Bring your current license and two proofs of new address to the DMV. Most states require updates within 30 days.",
        taskId: "UPDATE_DRIVERS_LICENSE",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 84,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Check your state — many let you update online without an appointment.",
        whyNeeded: "An outdated address can void traffic ticket service and jury duty notices.",
        estPeezy: "30 secs"
    )

    static let new_drivers_licenseTask = PeezyCard(
        type: .task,
        title: "Get your new state license",
        subtitle: "Surrender your old license at the new state's DMV. Bring proof of residency, your current license, and Social Security card.",
        taskId: "NEW_DRIVERS_LICENSE",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 84,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Request REAL ID — TSA needs a new one in your new state.",
        whyNeeded: "Driving past the deadline on an out-of-state license is a moving violation.",
        estPeezy: "30 secs"
    )

    static let register_vehicleTask = PeezyCard(
        type: .task,
        title: "Register your vehicles",
        subtitle: "Most states require registration within 30 days of moving. You'll need a new auto insurance policy that meets state minimums first.",
        taskId: "REGISTER_VEHICLE",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 82,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Update auto insurance first — DMV won't register without it.",
        whyNeeded: "Outdated tags risk tickets, towing, and insurance denial in a crash.",
        estPeezy: "30 secs"
    )

    static let photograph_rental_conditionTask = PeezyCard(
        type: .task,
        title: "Document the empty unit",
        subtitle: "After cleaning, take time-stamped photos and video of every wall, floor, fixture, and appliance — inside and out, every angle.",
        taskId: "PHOTOGRAPH_RENTAL_CONDITION",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 4,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Film a slow walkthrough video — judges weigh it heavier than photos.",
        whyNeeded: "Without photos, the landlord's word is the only evidence in deposit disputes.",
        estPeezy: "30 secs"
    )

    static let return_key_fobs_remotesTask = PeezyCard(
        type: .task,
        title: "Return all access devices",
        subtitle: "Hand-deliver every key, fob, garage remote, mailbox key, and parking tag — and get a written receipt listing exactly what you returned.",
        taskId: "RETURN_KEY_FOBS_REMOTES",
        status: .inProgress,
        taskCategory: "administrative",
        urgencyPercentage: 1,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Photograph everything you're returning the moment you hand it over.",
        whyNeeded: "A missing $5 fob can cost $200 in lock-change charges.",
        estPeezy: "30 secs"
    )

    static let cancel_utilitiesTask = PeezyCard(
        type: .task,
        title: "Cancel your utilities",
        subtitle: "Schedule shutoffs for electric, gas, water, sewer, and trash. Set the date for the day after you move out, not the day of.",
        taskId: "CANCEL_UTILITIES",
        workflowId: "cancel_utilities",
        status: .inProgress,
        taskCategory: "utilities",
        urgencyPercentage: 75,
        actionType: "workflow",
        taskType: "survey",
        tips: "Give them your forwarding address — credit refunds arrive by mail.",
        whyNeeded: "Utilities running in your name after move-out keep billing you.",
        estPeezy: "1 min"
    )

    static let setup_utilitiesTask = PeezyCard(
        type: .task,
        title: "Set up new utilities",
        subtitle: "Call electric, gas, water, and trash providers 2-3 weeks ahead. Schedule activation the day before you arrive — overlap beats outage.",
        taskId: "SETUP_UTILITIES",
        workflowId: "setup_utilities",
        status: .inProgress,
        taskCategory: "utilities",
        urgencyPercentage: 80,
        actionType: "workflow",
        taskType: "survey",
        tips: "Get a 'letter of credit' from your old utility — waives the deposit.",
        whyNeeded: "Arriving at a dark, waterless house ruins your first night.",
        estPeezy: "1 min"
    )

    static let transfer_utilitiesTask = PeezyCard(
        type: .task,
        title: "Transfer your utilities",
        subtitle: "Call each provider 1-2 weeks out. Schedule the new address active a day before, the old address shutoff a day after.",
        taskId: "TRANSFER_UTILITIES",
        workflowId: "transfer_utilities",
        status: .inProgress,
        taskCategory: "utilities",
        urgencyPercentage: 72,
        actionType: "workflow",
        taskType: "survey",
        tips: "Same provider = no new deposit, no credit check, no setup fee.",
        whyNeeded: "Without overlap, you'll lose water mid-clean or power mid-move.",
        estPeezy: "1 min"
    )

    static let begin_school_transferTask = PeezyCard(
        type: .task,
        title: "Notify the current school",
        subtitle: "Tell the school office in writing once your move is confirmed. Request transcripts, immunization records, and any IEP or 504 plans.",
        taskId: "BEGIN_SCHOOL_TRANSFER",
        workflowId: "begin_school_transfer",
        status: .inProgress,
        taskCategory: "children",
        urgencyPercentage: 82,
        actionType: "workflow",
        taskType: "survey",
        tips: "Get records emailed to you, not just the new school — backup matters.",
        whyNeeded: "Without records in hand, the new school may delay enrollment for weeks.",
        estPeezy: "30 secs"
    )

    static let new_school_enrollmentTask = PeezyCard(
        type: .task,
        title: "Enroll in the new school",
        subtitle: "Bring birth certificate, immunization records, last report card, and proof of residency. Most districts allow 30-day provisional enrollment if records are pending.",
        taskId: "NEW_SCHOOL_ENROLLMENT",
        workflowId: "new_school_enrollment",
        status: .inProgress,
        taskCategory: "children",
        urgencyPercentage: 90,
        actionType: "workflow",
        taskType: "survey",
        tips: "Request provisional enrollment if vaccine records are slow — schools must allow it.",
        whyNeeded: "One missing document can stall enrollment by weeks.",
        estPeezy: "30 secs"
    )

    static let coa_schoolsTask = PeezyCard(
        type: .task,
        title: "Update your child's school",
        subtitle: "Submit your new address with proof of residency. Update emergency contacts, transportation requests, and pickup authorizations the same day.",
        taskId: "COA_SCHOOLS",
        workflowId: "coa_schools",
        status: .inProgress,
        taskCategory: "children",
        urgencyPercentage: 90,
        actionType: "workflow",
        taskType: "survey",
        tips: "Bus zones change at the address level — confirm yours immediately.",
        whyNeeded: "An old address can drop your kid from the bus route overnight.",
        estPeezy: "30 secs"
    )

    static let setup_daycareTask = PeezyCard(
        type: .task,
        title: "Find your new daycare",
        subtitle: "Get on multiple waitlists immediately — infant care can take 12-24 months. Tour in person and ask about ratios, licensing, and turnover.",
        taskId: "SETUP_DAYCARE",
        workflowId: "setup_daycare",
        status: .inProgress,
        taskCategory: "children",
        urgencyPercentage: 88,
        actionType: "workflow",
        taskType: "survey",
        tips: "Send a handwritten thank-you after touring — directors remember you.",
        whyNeeded: "Waitlists can outlast your move date by a full year.",
        estPeezy: "1 min"
    )

    static let transfer_daycareTask = PeezyCard(
        type: .task,
        title: "Update your daycare",
        subtitle: "Email the director with your new address, updated emergency contacts, and any drop-off or pickup time changes.",
        taskId: "TRANSFER_DAYCARE",
        workflowId: "transfer_daycare",
        status: .inProgress,
        taskCategory: "children",
        urgencyPercentage: 75,
        actionType: "workflow",
        taskType: "survey",
        tips: "Update authorized pickup list in writing — verbal changes don't stick.",
        whyNeeded: "Outdated emergency contacts can block pickup if your child gets hurt.",
        estPeezy: "1 min"
    )

    static let transfer_pharmacy_recordsTask = PeezyCard(
        type: .task,
        title: "Transfer your pharmacy",
        subtitle: "Call the new pharmacy with your old pharmacy's name and number — they handle the transfer in minutes for chain stores.",
        taskId: "TRANSFER_PHARMACY_RECORDS",
        workflowId: "transfer_pharmacy_records",
        status: .inProgress,
        taskCategory: "health",
        urgencyPercentage: 55,
        actionType: "workflow",
        taskType: "survey",
        tips: "Controlled prescriptions don't transfer — get a new one from your doctor.",
        whyNeeded: "Running out mid-move means an urgent care visit just to refill.",
        estPeezy: "1 min"
    )

    static let transfer_specialists_recordsTask = PeezyCard(
        type: .task,
        title: "Transfer specialist records",
        subtitle: "List every specialist (cardiologist, derm, OB, etc.) and request records via the patient portal at least three weeks before moving.",
        taskId: "TRANSFER_SPECIALISTS_RECORDS",
        workflowId: "transfer_specialists_records",
        status: .inProgress,
        taskCategory: "health",
        urgencyPercentage: 69,
        actionType: "workflow",
        taskType: "survey",
        tips: "Have records emailed to you — fastest format, free, and you keep a copy.",
        whyNeeded: "Without specialist history, your new doctors restart workups from zero.",
        estPeezy: "1 min"
    )

    static let update_auto_insuranceTask = PeezyCard(
        type: .task,
        title: "Update your auto insurance",
        subtitle: "Notify your insurer with the new address before move day. Premiums shift by ZIP code — sometimes by hundreds per year.",
        taskId: "UPDATE_AUTO_INSURANCE",
        workflowId: "update_auto_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 82,
        actionType: "workflow",
        taskType: "survey",
        tips: "Get three new quotes the same day — ZIP changes are perfect leverage.",
        whyNeeded: "Wrong address on file can void your coverage in a claim.",
        estPeezy: "1 min"
    )

    static let cancel_condo_insuranceTask = PeezyCard(
        type: .task,
        title: "Cancel your condo insurance",
        subtitle: "Call your insurer with your move-out date. Schedule cancellation for the day after closing or possession transfer to avoid coverage gaps.",
        taskId: "CANCEL_CONDO_INSURANCE",
        workflowId: "cancel_condo_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 76,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask for a prorated refund — most insurers owe you for unused months.",
        whyNeeded: "Cancel too early and a last-day flood becomes your problem alone.",
        estPeezy: "1 min"
    )

    static let cancel_renters_insuranceTask = PeezyCard(
        type: .task,
        title: "Cancel your renter's insurance",
        subtitle: "Call your insurer to cancel — most do it online in 5 minutes. Schedule the end date for the day you hand back keys.",
        taskId: "CANCEL_RENTERS_INSURANCE",
        workflowId: "cancel_renters_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 77,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask for the unused premium back — you're owed a prorated refund.",
        whyNeeded: "Canceling before key return leaves your stuff uninsured during the last load.",
        estPeezy: "1 min"
    )

    static let setup_condo_insuranceTask = PeezyCard(
        type: .task,
        title: "Set up condo insurance",
        subtitle: "Get an HO6 policy effective on closing day. Read the HOA master policy first — it determines whether you need walls-in or full coverage.",
        taskId: "SETUP_CONDO_INSURANCE",
        workflowId: "setup_condo_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 76,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask the HOA which master policy type — bare walls, walls-in, or all-in.",
        whyNeeded: "The wrong HO6 leaves your floors and cabinets unprotected after a leak.",
        estPeezy: "1 min"
    )

    static let setup_homeowners_insuranceTask = PeezyCard(
        type: .task,
        title: "Set up homeowner's insurance",
        subtitle: "Lock in coverage 2-3 weeks before closing. Lenders require a paid first year and proof of binder before they'll fund the loan.",
        taskId: "SETUP_HOMEOWNERS_INSURANCE",
        workflowId: "setup_homeowners_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 77,
        actionType: "workflow",
        taskType: "survey",
        tips: "Quote at least three insurers — premiums vary 30%+ for identical coverage.",
        whyNeeded: "Without an active binder at closing, the deal stalls and your move with it.",
        estPeezy: "1 min"
    )

    static let setup_renters_insuranceTask = PeezyCard(
        type: .task,
        title: "Set up renter's insurance",
        subtitle: "Quote online with Lemonade, State Farm, or your auto insurer. Most policies run $15-30/month and bind in under ten minutes.",
        taskId: "SETUP_RENTERS_INSURANCE",
        workflowId: "setup_renters_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 77,
        actionType: "workflow",
        taskType: "survey",
        tips: "Bundle with auto insurance — usually saves 5-15% on both.",
        whyNeeded: "One pipe burst can wipe out your belongings without coverage.",
        estPeezy: "1 min"
    )

    static let transfer_condo_insuranceTask = PeezyCard(
        type: .task,
        title: "Transfer your condo insurance",
        subtitle: "Call your insurer 2-3 weeks ahead with the new address. Verify the new HOA master policy type — coverage needs may shift.",
        taskId: "TRANSFER_CONDO_INSURANCE",
        workflowId: "transfer_condo_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 76,
        actionType: "workflow",
        taskType: "survey",
        tips: "Different HOAs = different coverage needs — re-quote, don't just transfer.",
        whyNeeded: "An assumed transfer can leave gaps your old policy covered automatically.",
        estPeezy: "1 min"
    )

    static let transfer_homeowners_insuranceTask = PeezyCard(
        type: .task,
        title: "Transfer homeowner's insurance",
        subtitle: "Call your insurer 3-4 weeks before closing. Premiums shift with location, age, square footage, and roof — get a new quote either way.",
        taskId: "TRANSFER_HOMEOWNERS_INSURANCE",
        workflowId: "transfer_homeowners_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 77,
        actionType: "workflow",
        taskType: "survey",
        tips: "Re-quote three insurers — transfers rarely beat fresh-quote pricing.",
        whyNeeded: "A 'transfer' often hides a premium increase you'd catch by shopping.",
        estPeezy: "1 min"
    )

    static let transfer_renters_insuranceTask = PeezyCard(
        type: .task,
        title: "Transfer renter's insurance",
        subtitle: "Call your insurer with the new address 1-2 weeks ahead. Transferring keeps your claims-free discount and skips the new policy fee.",
        taskId: "TRANSFER_RENTERS_INSURANCE",
        workflowId: "transfer_renters_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 77,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask for the multi-year loyalty discount — most insurers don't volunteer it.",
        whyNeeded: "Restarting fresh resets discounts you've spent years earning.",
        estPeezy: "1 min"
    )

    static let buy_packing_suppliesTask = PeezyCard(
        type: .task,
        title: "Buy packing supplies",
        subtitle: "A one-bedroom needs roughly 30 small, 40 medium, and 20 large boxes, plus tape, paper, and markers. Budget $100-200 total.",
        taskId: "BUY_PACKING_SUPPLIES",
        status: .inProgress,
        taskCategory: "packing",
        urgencyPercentage: 85,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Liquor stores give away sturdy small boxes — perfect for books.",
        whyNeeded: "Running out mid-pack means a last-minute store run during peak chaos.",
        estPeezy: "30 secs"
    )

    static let buy_cleaning_suppliesTask = PeezyCard(
        type: .task,
        title: "Buy cleaning supplies",
        subtitle: "Pick up degreaser, glass cleaner, magic erasers, mop, broom, gloves, and microfiber cloths 3-5 days before move-out.",
        taskId: "BUY_CLEANING_SUPPLIES",
        status: .inProgress,
        taskCategory: "services",
        urgencyPercentage: 10,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Pack a 'last bag' with cleaning supplies — load it onto the truck last.",
        whyNeeded: "Once boxes are sealed, finding a sponge becomes a 30-minute hunt.",
        estPeezy: "30 secs"
    )

    static let scan_inventoryTask = PeezyCard(
        type: .task,
        title: "Scan your home",
        subtitle: "Pan your camera slowly across each room. Peezy's AI identifies furniture, appliances, and large items in about 20 seconds per room.",
        taskId: "SCAN_INVENTORY",
        status: .inProgress,
        taskCategory: "getting-started",
        urgencyPercentage: 99,
        selfServiceOnly: true,
        actionType: "in-app-inventory",
        taskType: "provide_info",
        tips: "Open closets and cabinets — Peezy catches what you'd forget to mention.",
        whyNeeded: "An accurate inventory unlocks precise quotes and protects you against damage claims.",
        estPeezy: "90 secs"
    )

    static let defrost_freezerTask = PeezyCard(
        type: .task,
        title: "Defrost your freezer",
        subtitle: "Empty the contents, unplug it, prop the doors open, and lay towels underneath. Plan 24-48 hours before move day.",
        taskId: "DEFROST_FREEZER",
        status: .inProgress,
        taskCategory: "packing",
        urgencyPercentage: 8,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "After moving, let it sit upright for 4 hours before plugging back in.",
        whyNeeded: "Movers won't load a wet or leaking fridge — full stop.",
        estPeezy: "30 secs"
    )

    static let diy_deep_cleaningTask = PeezyCard(
        type: .task,
        title: "Deep clean the place",
        subtitle: "Plan 6+ hours with two people. Hit appliances, baseboards, walls, windows, vents, and cabinets — landlords inspect every one.",
        taskId: "DIY_DEEP_CLEANING",
        status: .inProgress,
        taskCategory: "services",
        urgencyPercentage: 5,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Clean inside the oven and fridge first — they're the top deduction trigger.",
        whyNeeded: "One missed area can cost you hundreds in deposit deductions.",
        estPeezy: "30 secs"
    )

    static let diy_final_cleaningTask = PeezyCard(
        type: .task,
        title: "Do the final touch-up",
        subtitle: "After everything is out, walk every room, closet, and cabinet. Wipe baseboards, sweep floors, and confirm nothing is left behind.",
        taskId: "DIY_FINAL_CLEANING",
        status: .inProgress,
        taskCategory: "services",
        urgencyPercentage: 2,
        selfServiceOnly: true,
        actionType: "off-app",
        taskType: "provide_info",
        tips: "Bring a flashlight — corners and closets hide more than you think.",
        whyNeeded: "A forgotten item or dusty corner is exactly what landlords cite.",
        estPeezy: "30 secs"
    )

    static let cancel_homeowners_insuranceTask = PeezyCard(
        type: .task,
        title: "Cancel homeowner's insurance",
        subtitle: "Call your insurer once the sale closes. Set the cancellation date for the day after closing — never before.",
        taskId: "CANCEL_HOMEOWNERS_INSURANCE",
        workflowId: "cancel_homeowners_insurance",
        status: .inProgress,
        taskCategory: "insurance",
        urgencyPercentage: 76,
        actionType: "workflow",
        taskType: "survey",
        tips: "Ask for the prepaid premium refund — most owe you for unused months.",
        whyNeeded: "Canceling early voids coverage during the final walkthrough and key transfer.",
        estPeezy: "1 min"
    )

    // MARK: - Qualifying Data for All Workflows

    static let book_moversQualifying = WorkflowQualifying(
        workflowId: "book_movers",
        intro: WorkflowIntro(title: "Book your movers", subtitle: "We have a few questions to help us match you with the best movers for you."),
        questions: [
            WorkflowQuestion(id: "heavy_items", question: "Any heavy items making the move?", subtitle: nil, options: [QuestionOption(id: "piano", label: "Piano / Organ", icon: "pianokeys"), QuestionOption(id: "safe", label: "Gun Safe / Safe", icon: "lock.shield"), QuestionOption(id: "hot_tub", label: "Hot Tub / Spa", icon: "drop.fill"), QuestionOption(id: "pool_table", label: "Pool Table", icon: "circle.grid.3x3")], type: .multi_select),
            WorkflowQuestion(id: "specialty_items", question: "What about any items requiring a little extra care?", subtitle: nil, options: [QuestionOption(id: "art", label: "Art / Antiques", icon: "photo.artframe"), QuestionOption(id: "glass", label: "Large Mirrors / Glass", icon: "rectangle"), QuestionOption(id: "wine", label: "China / Dishware", icon: "wineglass")], type: .multi_select),
            WorkflowQuestion(id: "packing_help", question: "Interested in what packing help might cost?", subtitle: nil, options: [QuestionOption(id: "full", label: "Full service — pack everything", icon: "shippingbox.fill", exclusive: true), QuestionOption(id: "partial", label: "Just fragile / kitchen items", icon: "wineglass", exclusive: true)], type: .multi_select),
            WorkflowQuestion(id: "storage_needed", question: "Anything in storage that you'd like included in the quotes?", subtitle: nil, options: [QuestionOption(id: "yes", label: "Yes", icon: "hand.thumbsup.fill"), QuestionOption(id: "no", label: "No", icon: "hand.thumbsdown.fill")], type: .single_select),
            WorkflowQuestion(id: "storage_size", question: "What size unit is it?", subtitle: nil, options: [QuestionOption(id: "5x5", label: "Small (5×5)", icon: "shippingbox"), QuestionOption(id: "10x10", label: "Medium (10×10)", icon: "shippingbox.fill"), QuestionOption(id: "10x20", label: "Large (10×20)", icon: "archivebox.fill")], type: .single_select),
            WorkflowQuestion(id: "storage_fullness", question: "And about how full is the unit?", subtitle: nil, options: [QuestionOption(id: "quarter", label: "~¼", icon: "circle", fillPercent: 0.25), QuestionOption(id: "half", label: "~½", icon: "circle", fillPercent: 0.50), QuestionOption(id: "three_quarter", label: "~¾", icon: "circle", fillPercent: 0.75), QuestionOption(id: "full", label: "Full", icon: "circle", fillPercent: 1.0)], type: .single_select),
            WorkflowQuestion(id: "insurance_context", question: "Very important to understand", subtitle: "So, if your $1,000 TV weighs 50lbs, by law, you are only entitled to receive $30.", options: [], type: .single_select, buttonLabel: "I understand", cautionIcon: "exclamationmark.triangle.fill", boldPrefix: "By law, companies are required to provide basic coverage for your belongings, which covers $0.60 per pound for items damaged beyond repair."),
            WorkflowQuestion(id: "insurance_preference", question: "Based on what was just discussed, would you be interested in pricing for additional insurance?", subtitle: nil, options: [QuestionOption(id: "full_value", label: "Full Coverage — Full Replacement", icon: "shield.checkered"), QuestionOption(id: "supplemental", label: "Supplemental Partial Coverage", icon: "shield.lefthalf.filled")], type: .single_select, skipLabel: "No — free basic coverage")
        ],
        recap: WorkflowRecap(title: "That's it. We can take it from here.", closing: "This gives us what we need to get quotes from the top three companies that we believe will best assist you.", button: "Submit Request", subtext: "Typical response time: 2–3 days"),
        questionCount: 8
    )

    static let junk_removalQualifying = WorkflowQualifying(
        workflowId: "junk_removal",
        intro: WorkflowIntro(title: "Let's get rid of the stuff you don't need", subtitle: "A few questions to get you an accurate quote."),
        questions: [
            WorkflowQuestion(id: "volume", question: "How much stuff?", subtitle: nil, options: [QuestionOption(id: "few_items", label: "A Few Items", icon: "archivebox", subtitle: "Fits in a car"), QuestionOption(id: "partial", label: "Partial Truck", icon: "box.truck", subtitle: "Couch, mattress, some boxes"), QuestionOption(id: "full", label: "Full Truck", icon: "box.truck.fill", subtitle: "Garage cleanout, lots of stuff"), QuestionOption(id: "not_sure", label: "Not Sure", icon: "questionmark.circle.fill", subtitle: "Need an estimate")], type: .single_select),
            WorkflowQuestion(id: "item_types", question: "What kinds of items?", subtitle: nil, options: [QuestionOption(id: "furniture", label: "Furniture", icon: "sofa.fill"), QuestionOption(id: "appliances", label: "Appliances", icon: "refrigerator.fill"), QuestionOption(id: "mattress", label: "Mattress/Box Spring", icon: "bed.double.fill"), QuestionOption(id: "electronics", label: "Electronics", icon: "tv.fill"), QuestionOption(id: "yard", label: "Yard Waste", icon: "leaf.fill"), QuestionOption(id: "general", label: "General Junk", icon: "trash.fill")], type: .multi_select),
            WorkflowQuestion(id: "location", question: "Where is everything?", subtitle: nil, options: [QuestionOption(id: "curb", label: "At the Curb", icon: "road.lanes", subtitle: "Easy access"), QuestionOption(id: "garage", label: "Garage/Driveway", icon: "car.garage.fill"), QuestionOption(id: "inside", label: "Inside the Home", icon: "house.fill", subtitle: "They'll haul it out"), QuestionOption(id: "multiple", label: "Multiple Spots", icon: "arrow.triangle.branch")], type: .single_select),
            WorkflowQuestion(id: "timing", question: "When do you need pickup?", subtitle: nil, options: [QuestionOption(id: "asap", label: "ASAP", icon: "bolt.fill", subtitle: "Within 48 hours"), QuestionOption(id: "before_move", label: "Before Move Day", icon: "calendar", subtitle: "Coordinate with timeline"), QuestionOption(id: "flexible", label: "Flexible", icon: "clock.fill", subtitle: "Best price wins")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Here's what we're removing:", closing: "I'll get you quotes from haulers who can handle this. Usually within a few hours.", button: "Get Quotes"),
        questionCount: 4
    )

    static let book_cleanersQualifying = WorkflowQualifying(
        workflowId: "book_cleaners",
        intro: WorkflowIntro(title: "Let's find you the right cleaners", subtitle: "A couple quick questions to match you with the right service."),
        questions: [
            WorkflowQuestion(id: "which_place", question: "Which place needs cleaning?", subtitle: nil, options: [QuestionOption(id: "move_out", label: "Old place — move-out clean", icon: "door.left.hand.open"), QuestionOption(id: "move_in", label: "New place — move-in clean", icon: "door.right.hand.open"), QuestionOption(id: "both", label: "Both places", icon: "arrow.left.arrow.right")], type: .single_select),
            WorkflowQuestion(id: "services", question: "What services do you need?", subtitle: "Select all that apply.", options: [QuestionOption(id: "standard", label: "Standard clean", icon: "sparkles"), QuestionOption(id: "deep", label: "Deep clean (baseboards, inside appliances)", icon: "bubbles.and.sparkles"), QuestionOption(id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled"), QuestionOption(id: "windows", label: "Window cleaning", icon: "window.horizontal")], type: .multi_select),
            WorkflowQuestion(id: "move_out_timing", question: "When do you need the move-out clean?", subtitle: "Rough time preference.", options: [QuestionOption(id: "morning", label: "Morning", icon: "sunrise"), QuestionOption(id: "afternoon", label: "Afternoon", icon: "sun.max"), QuestionOption(id: "evening", label: "Evening", icon: "sunset"), QuestionOption(id: "flexible", label: "Flexible", icon: "clock")], type: .single_select),
            WorkflowQuestion(id: "move_in_timing", question: "When do you need the move-in clean?", subtitle: "Rough time preference.", options: [QuestionOption(id: "morning", label: "Morning", icon: "sunrise"), QuestionOption(id: "afternoon", label: "Afternoon", icon: "sun.max"), QuestionOption(id: "evening", label: "Evening", icon: "sunset"), QuestionOption(id: "flexible", label: "Flexible", icon: "clock")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Here's what we've got", closing: "We'll find cleaners who can handle everything you selected and get you quotes.", button: "Request Quotes"),
        questionCount: 4
    )

    static let remove_itemsQualifying = WorkflowQualifying(
        workflowId: "remove_items",
        intro: WorkflowIntro(title: "Let's figure out the best way to get rid of these items", subtitle: "A few questions to find the right option for you."),
        questions: [
            WorkflowQuestion(id: "removal_route", question: "What are you looking to do with these items?", subtitle: nil, options: [QuestionOption(id: "donate", label: "Donate them", icon: "heart"), QuestionOption(id: "haul_away", label: "Have them hauled away", icon: "truck.box"), QuestionOption(id: "not_sure", label: "Not sure — help me decide", icon: "questionmark.circle")], type: .single_select),
            WorkflowQuestion(id: "item_categories", question: "What types of items are we talking about?", subtitle: "Select all that apply.", options: [QuestionOption(id: "furniture", label: "Furniture", icon: "sofa"), QuestionOption(id: "appliances", label: "Appliances", icon: "refrigerator"), QuestionOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"), QuestionOption(id: "mattresses", label: "Mattresses", icon: "bed.double"), QuestionOption(id: "household", label: "Household / clothing", icon: "house"), QuestionOption(id: "outdoor", label: "Outdoor / debris", icon: "leaf")], type: .multi_select),
            WorkflowQuestion(id: "item_condition", question: "What condition are most of the items in?", subtitle: nil, options: [QuestionOption(id: "like_new", label: "Like new", icon: "star.fill"), QuestionOption(id: "gently_used", label: "Gently used", icon: "star.leadinghalf.filled"), QuestionOption(id: "worn", label: "Worn but functional", icon: "star"), QuestionOption(id: "needs_repair", label: "Needs repair", icon: "wrench")], type: .single_select),
            WorkflowQuestion(id: "quantity", question: "How much stuff are we talking about?", subtitle: nil, options: [QuestionOption(id: "few_small", label: "A few small items", icon: "bag"), QuestionOption(id: "several_large", label: "Several large items", icon: "shippingbox"), QuestionOption(id: "full_room", label: "A full room's worth", icon: "sofa.fill"), QuestionOption(id: "multiple_rooms", label: "Multiple rooms", icon: "building.2")], type: .single_select),
            WorkflowQuestion(id: "item_location", question: "Where are the items right now?", subtitle: nil, options: [QuestionOption(id: "ground_floor", label: "Inside home — ground floor", icon: "house"), QuestionOption(id: "upstairs", label: "Inside home — upstairs, basement, or attic", icon: "stairs"), QuestionOption(id: "garage", label: "Garage", icon: "car.garage"), QuestionOption(id: "curbside", label: "Curbside or driveway", icon: "road.lanes")], type: .single_select),
            WorkflowQuestion(id: "pickup_preference", question: "Can you drop items off, or do you need them picked up?", subtitle: nil, options: [QuestionOption(id: "need_pickup", label: "I need pickup", icon: "truck.box"), QuestionOption(id: "can_dropoff", label: "I can drop off", icon: "arrow.down.to.line"), QuestionOption(id: "either", label: "Either works", icon: "arrow.left.arrow.right")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Got it — I'll find the best option", closing: "Based on your answers, I'll match you with the right service to get these items taken care of.", button: "Find my options"),
        questionCount: 6
    )

    static let sell_itemsQualifying = WorkflowQualifying(
        workflowId: "sell_items",
        intro: WorkflowIntro(title: "Let's help you sell these items", subtitle: "A few questions so we can point you in the right direction."),
        questions: [
            WorkflowQuestion(id: "item_categories", question: "What are you looking to sell?", subtitle: "Select all that apply.", options: [QuestionOption(id: "furniture", label: "Furniture", icon: "sofa"), QuestionOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"), QuestionOption(id: "clothing", label: "Clothing", icon: "tshirt"), QuestionOption(id: "appliances", label: "Appliances", icon: "refrigerator"), QuestionOption(id: "collectibles", label: "Collectibles or valuables", icon: "tag"), QuestionOption(id: "other", label: "Other", icon: "shippingbox")], type: .multi_select),
            WorkflowQuestion(id: "estimated_value", question: "Roughly, what do you think everything is worth?", subtitle: nil, options: [QuestionOption(id: "under_500", label: "Under $500", icon: "dollarsign.circle"), QuestionOption(id: "500_2000", label: "$500 – $2,000", icon: "dollarsign.circle.fill"), QuestionOption(id: "2000_5000", label: "$2,000 – $5,000", icon: "banknote"), QuestionOption(id: "over_5000", label: "$5,000+", icon: "banknote.fill")], type: .single_select),
            WorkflowQuestion(id: "platforms", question: "Which platforms are you open to?", subtitle: "Select all you'd be willing to use.", options: [QuestionOption(id: "fb_marketplace", label: "Facebook Marketplace", icon: "storefront"), QuestionOption(id: "offerup", label: "OfferUp", icon: "tag"), QuestionOption(id: "craigslist", label: "Craigslist", icon: "list.bullet"), QuestionOption(id: "consignment", label: "Consignment store", icon: "building.columns"), QuestionOption(id: "any", label: "Any of them", icon: "checkmark.circle")], type: .multi_select)
        ],
        recap: WorkflowRecap(title: "Nice — let's get these sold", closing: "I'll put together a game plan based on what you're selling and where.", button: "Get my selling plan"),
        questionCount: 3
    )

    static let setup_internetQualifying = WorkflowQualifying(
        workflowId: "setup_internet",
        intro: WorkflowIntro(title: "Let's get you connected", subtitle: "A few questions to find the best internet options at your new place."),
        questions: [
            WorkflowQuestion(id: "usage", question: "Who's using the internet?", subtitle: "Select all that apply.", options: [QuestionOption(id: "work_from_home", label: "Work from home", icon: "laptopcomputer"), QuestionOption(id: "streaming", label: "Streaming (Netflix, YouTube)", icon: "play.tv.fill"), QuestionOption(id: "gaming", label: "Gaming", icon: "gamecontroller.fill"), QuestionOption(id: "smart_home", label: "Smart home devices", icon: "homekit"), QuestionOption(id: "basic", label: "Just browsing and email", icon: "globe")], type: .multi_select),
            WorkflowQuestion(id: "people_count", question: "How many people in the household?", subtitle: nil, options: [QuestionOption(id: "1_2", label: "1–2", icon: "person"), QuestionOption(id: "3_5", label: "3–5", icon: "person.2"), QuestionOption(id: "6_plus", label: "6+", icon: "person.3")], type: .single_select),
            WorkflowQuestion(id: "contract_preference", question: "Contract preference?", subtitle: nil, options: [QuestionOption(id: "month_to_month", label: "Month-to-month", icon: "calendar"), QuestionOption(id: "1_year", label: "1 year", icon: "calendar.badge.clock"), QuestionOption(id: "2_year", label: "2 year", icon: "calendar.badge.checkmark"), QuestionOption(id: "no_preference", label: "No preference", icon: "hand.thumbsup")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Here's what we've got", closing: "We'll match you with providers in your area and get you options. We'll reach out as soon as we have them.", button: "Request Quotes"),
        questionCount: 3
    )

    static let rent_truckQualifying = WorkflowQualifying(
        workflowId: "rent_truck",
        intro: WorkflowIntro(title: "Let's get you a truck", subtitle: "We'll use the details from your inventory to find the right size and best price."),
        questions: [
            WorkflowQuestion(id: "trip_type", question: "One-way or round-trip?", subtitle: "One-way = drop off at destination. Round-trip = return to pickup location.", options: [QuestionOption(id: "one_way", label: "One-way", icon: "arrow.right"), QuestionOption(id: "round_trip", label: "Round-trip", icon: "arrow.triangle.2.circlepath"), QuestionOption(id: "not_sure", label: "Not sure", icon: "questionmark.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Here's what we've got", closing: "We'll compare options from the major rental companies and get you the best deal. We'll reach out as soon as we have quotes.", button: "Request Quotes"),
        questionCount: 1
    )

    static let manage_bankQualifying = WorkflowQualifying(
        workflowId: "manage_bank",
        intro: WorkflowIntro(title: "Let's figure out what you need for your bank account.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your bank account?", subtitle: nil, options: [QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your current account, just update the address on file"), QuestionOption(id: "close_open_new", label: "Close & open new account", icon: "arrow.triangle.swap", subtitle: "Close this account and set up a new one near your new home"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_doctorQualifying = WorkflowQualifying(
        workflowId: "manage_doctor",
        intro: WorkflowIntro(title: "Let's figure out what you need for your primary care doctor.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do?", subtitle: nil, options: [QuestionOption(id: "transfer_records", label: "Transfer records to new doctor", icon: "doc.arrow.forward", subtitle: "Request records be sent to a new provider near your new home"), QuestionOption(id: "update_address", label: "Update address with current doctor", icon: "pencil.line", subtitle: "Keep your current doctor, just update your contact info"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_dentistQualifying = WorkflowQualifying(
        workflowId: "manage_dentist",
        intro: WorkflowIntro(title: "Let's figure out what you need for your dentist.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do?", subtitle: nil, options: [QuestionOption(id: "transfer_records", label: "Transfer records to new dentist", icon: "doc.arrow.forward", subtitle: "Request records and X-rays be sent to a new dentist"), QuestionOption(id: "update_address", label: "Update address with current dentist", icon: "pencil.line", subtitle: "Keep your current dentist, just update your contact info"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_vetQualifying = WorkflowQualifying(
        workflowId: "manage_vet",
        intro: WorkflowIntro(title: "Let's figure out what you need for your pet's vet care.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do?", subtitle: nil, options: [QuestionOption(id: "transfer_records", label: "Find new vet & transfer records", icon: "doc.arrow.forward", subtitle: "We'll help find a vet near your new home and transfer records"), QuestionOption(id: "update_address", label: "Update address with current vet", icon: "pencil.line", subtitle: "Keep your current vet, just update your contact info"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_gymQualifying = WorkflowQualifying(
        workflowId: "manage_gym",
        intro: WorkflowIntro(title: "Let's figure out what you need for your gym membership.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your membership?", subtitle: nil, options: [QuestionOption(id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home"), QuestionOption(id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership"), QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_yogaQualifying = WorkflowQualifying(
        workflowId: "manage_yoga",
        intro: WorkflowIntro(title: "Let's figure out what you need for your yoga or pilates membership.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your membership?", subtitle: nil, options: [QuestionOption(id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home"), QuestionOption(id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership"), QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_spinQualifying = WorkflowQualifying(
        workflowId: "manage_spin",
        intro: WorkflowIntro(title: "Let's figure out what you need for your spin or cycling membership.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your membership?", subtitle: nil, options: [QuestionOption(id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home"), QuestionOption(id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership"), QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_massageQualifying = WorkflowQualifying(
        workflowId: "manage_massage",
        intro: WorkflowIntro(title: "Let's figure out what you need for your massage or spa membership.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your membership?", subtitle: nil, options: [QuestionOption(id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home"), QuestionOption(id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership"), QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let manage_golfQualifying = WorkflowQualifying(
        workflowId: "manage_golf",
        intro: WorkflowIntro(title: "Let's figure out what you need for your golf or country club membership.", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your membership?", subtitle: nil, options: [QuestionOption(id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home"), QuestionOption(id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership"), QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let arrange_parking_newQualifying = WorkflowQualifying(
        workflowId: "arrange_parking_new",
        intro: WorkflowIntro(title: "Let's sort out parking for move-in day", subtitle: "We need to make sure the moving truck has a place to park at your new home."),
        questions: [
            WorkflowQuestion(id: "has_driveway", question: "Does your new place have a driveway or loading area?", subtitle: nil, options: [QuestionOption(id: "yes", label: "Yes, driveway or loading dock", icon: "car.fill", subtitle: "Truck can pull right up"), QuestionOption(id: "no", label: "No, street parking only", icon: "road.lanes", subtitle: "May need a permit"), QuestionOption(id: "not_sure", label: "Not sure", icon: "questionmark.circle", subtitle: "We'll plan for street parking")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Got your parking plan", closing: "We'll walk you through the next steps.", button: "Got it"),
        questionCount: 1
    )

    static let arrange_parking_oldQualifying = WorkflowQualifying(
        workflowId: "arrange_parking_old",
        intro: WorkflowIntro(title: "Let's sort out parking for move-out day", subtitle: "We need to make sure the moving truck has a place to park at your current building."),
        questions: [
            WorkflowQuestion(id: "has_driveway", question: "Does your current place have a driveway or loading area?", subtitle: nil, options: [QuestionOption(id: "yes", label: "Yes, driveway or loading dock", icon: "car.fill", subtitle: "Truck can pull right up"), QuestionOption(id: "no", label: "No, street parking only", icon: "road.lanes", subtitle: "May need a permit"), QuestionOption(id: "not_sure", label: "Not sure", icon: "questionmark.circle", subtitle: "We'll plan for street parking")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Got your parking plan", closing: "We'll walk you through the next steps.", button: "Got it"),
        questionCount: 1
    )

    static let reserve_elevators_newQualifying = WorkflowQualifying(
        workflowId: "reserve_elevators_new",
        intro: WorkflowIntro(title: "Let's reserve the elevator for move-in", subtitle: "We'll figure out when you need it and for how long based on your inventory."),
        questions: [
            WorkflowQuestion(id: "move_start_time", question: "What time are you planning to start your move?", subtitle: "This helps us calculate when you'll arrive at the new place.", options: [QuestionOption(id: "morning", label: "Morning", icon: "sunrise.fill", subtitle: "Before 10am"), QuestionOption(id: "midday", label: "Midday", icon: "sun.max.fill", subtitle: "10am – 1pm"), QuestionOption(id: "afternoon", label: "Afternoon", icon: "sunset.fill", subtitle: "After 1pm")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Elevator reservation plan ready", closing: "We'll calculate the time window you need based on your inventory.", button: "Got it"),
        questionCount: 1
    )

    static let reserve_elevators_oldQualifying = WorkflowQualifying(
        workflowId: "reserve_elevators_old",
        intro: WorkflowIntro(title: "Let's reserve the elevator for move-out", subtitle: "We'll figure out how long you need it based on your inventory."),
        questions: [
            WorkflowQuestion(id: "move_start_time", question: "What time are you planning to start your move?", subtitle: "This helps us calculate how long you'll need the elevator.", options: [QuestionOption(id: "morning", label: "Morning", icon: "sunrise.fill", subtitle: "Before 10am"), QuestionOption(id: "midday", label: "Midday", icon: "sun.max.fill", subtitle: "10am – 1pm"), QuestionOption(id: "afternoon", label: "Afternoon", icon: "sunset.fill", subtitle: "After 1pm")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Elevator reservation plan ready", closing: "We'll calculate the time window you need based on your inventory.", button: "Got it"),
        questionCount: 1
    )

    static let cancel_utilitiesQualifying = WorkflowQualifying(
        workflowId: "cancel_utilities",
        intro: WorkflowIntro(title: "Time to cancel utilities at your current place", subtitle: "We'll tell you exactly which providers to contact and when."),
        questions: [],
        recap: WorkflowRecap(title: "Here's your utility cancellation plan", closing: "Schedule disconnection for the day after your move so you have service through your last day. Most providers need 3-5 business days notice.", button: "Got it"),
        questionCount: 0
    )

    static let setup_utilitiesQualifying = WorkflowQualifying(
        workflowId: "setup_utilities",
        intro: WorkflowIntro(title: "Let's get utilities set up at your new place", subtitle: "We'll make sure everything is on when you arrive."),
        questions: [
            WorkflowQuestion(id: "internet_chosen", question: "Have you already chosen an internet provider?", subtitle: nil, options: [QuestionOption(id: "yes", label: "Yes, I know which one", icon: "checkmark.circle.fill", subtitle: "Just need setup steps"), QuestionOption(id: "no", label: "No, I need to pick one", icon: "magnifyingglass", subtitle: "Show me what's available"), QuestionOption(id: "building_provided", label: "My building has one option", icon: "building.2.fill", subtitle: "No choice to make")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Your utility setup plan", closing: "Priority order: Electric and gas first (1-3 day lead time), then internet (7-14 days for installation).", button: "Got it"),
        questionCount: 1
    )

    static let transfer_utilitiesQualifying = WorkflowQualifying(
        workflowId: "transfer_utilities",
        intro: WorkflowIntro(title: "Let's transfer your utilities", subtitle: "We'll check which providers serve both addresses so you can transfer instead of cancel and re-setup."),
        questions: [],
        recap: WorkflowRecap(title: "Your utility transfer plan", closing: "Do transfers 5-7 business days before your move date to avoid any gap in service.", button: "Got it"),
        questionCount: 0
    )

    static let forward_mail_uspsQualifying = WorkflowQualifying(
        workflowId: "forward_mail_usps",
        intro: WorkflowIntro(title: "Let's set up mail forwarding", subtitle: "This takes about 2 minutes and makes sure your mail follows you."),
        questions: [],
        recap: WorkflowRecap(title: "Here's how to forward your mail", closing: "Do this 1-2 weeks before your move. USPS needs 7-10 business days to fully activate forwarding. Forwarding lasts 12 months for first-class mail.", button: "Got it"),
        questionCount: 0
    )

    static let begin_school_transferQualifying = WorkflowQualifying(
        workflowId: "begin_school_transfer",
        intro: WorkflowIntro(title: "Let's start the school transfer", subtitle: "A couple quick questions so we can give you the right checklist."),
        questions: [
            WorkflowQuestion(id: "num_children", question: "How many children are transferring?", subtitle: nil, options: [QuestionOption(id: "1", label: "1 child", icon: "person.fill"), QuestionOption(id: "2", label: "2 children", icon: "person.2.fill"), QuestionOption(id: "3_plus", label: "3 or more", icon: "person.3.fill", subtitle: "We'll help you coordinate")], type: .single_select),
            WorkflowQuestion(id: "grade_levels", question: "What grade level(s)?", subtitle: "Select all that apply", options: [QuestionOption(id: "elementary", label: "Elementary (K-5)", icon: "book.fill", subtitle: "Report cards, immunizations"), QuestionOption(id: "middle", label: "Middle (6-8)", icon: "books.vertical.fill", subtitle: "Course placement records"), QuestionOption(id: "high", label: "High School (9-12)", icon: "graduationcap.fill", subtitle: "Transcripts, credits, AP records")], type: .multi_select)
        ],
        recap: WorkflowRecap(title: "Your school transfer checklist is ready", closing: "Start this process 2-3 weeks before your move. Schools typically take 5-10 business days to process records.", button: "Got it"),
        questionCount: 2
    )

    static let new_school_enrollmentQualifying = WorkflowQualifying(
        workflowId: "new_school_enrollment",
        intro: WorkflowIntro(title: "Let's enroll at the new school", subtitle: "We'll tell you which school you're zoned for and what you need to bring."),
        questions: [
            WorkflowQuestion(id: "num_children", question: "How many children are enrolling?", subtitle: nil, options: [QuestionOption(id: "1", label: "1 child", icon: "person.fill"), QuestionOption(id: "2", label: "2 children", icon: "person.2.fill", subtitle: "May be different schools"), QuestionOption(id: "3_plus", label: "3 or more", icon: "person.3.fill", subtitle: "We'll help coordinate")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Your enrollment plan is ready", closing: "Enroll as soon as you have proof of residency at the new address. Don't wait until move day.", button: "Got it"),
        questionCount: 1
    )

    static let coa_schoolsQualifying = WorkflowQualifying(
        workflowId: "coa_schools",
        intro: WorkflowIntro(title: "Update your address with the school", subtitle: "Since you're staying in the same district, this is a quick update."),
        questions: [],
        recap: WorkflowRecap(title: "Here's what to do", closing: "Contact the registrar with your new address and proof of residency. Also update emergency contacts, bus routes, and after-school programs.", button: "Got it"),
        questionCount: 0
    )

    static let setup_daycareQualifying = WorkflowQualifying(
        workflowId: "setup_daycare",
        intro: WorkflowIntro(title: "Let's find daycare near your new home", subtitle: "A couple questions so we can point you to the right options."),
        questions: [
            WorkflowQuestion(id: "child_age", question: "How old is your child?", subtitle: "Availability and waitlists vary significantly by age.", options: [QuestionOption(id: "infant", label: "Infant (0-12 mo)", icon: "figure.and.child.holdinghands", subtitle: "Longest waitlists"), QuestionOption(id: "toddler", label: "Toddler (1-3 yrs)", icon: "figure.child", subtitle: "Competitive but more options"), QuestionOption(id: "prek", label: "Pre-K (3-5 yrs)", icon: "book.and.wrench.fill", subtitle: "Check for free public pre-K")], type: .single_select),
            WorkflowQuestion(id: "care_type", question: "What type of care are you looking for?", subtitle: nil, options: [QuestionOption(id: "center", label: "Daycare center", icon: "building.2.fill", subtitle: "Licensed facility"), QuestionOption(id: "in_home", label: "In-home daycare", icon: "house.fill", subtitle: "Family daycare provider"), QuestionOption(id: "part_time", label: "Part-time or drop-in", icon: "clock.fill", subtitle: "Flexible schedule")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "Your daycare search plan", closing: "Contact 3-5 providers and get on waitlists now — it costs nothing and can take months. Start tours before or right after your move.", button: "Got it"),
        questionCount: 2
    )

    static let transfer_daycareQualifying = WorkflowQualifying(
        workflowId: "transfer_daycare",
        intro: WorkflowIntro(title: "Let's handle the daycare transition", subtitle: "We'll make sure there's no gap in care."),
        questions: [],
        recap: WorkflowRecap(title: "Your daycare transition plan", closing: "Give written notice to your current daycare ASAP — most require 2-4 weeks. Ask about prorated refunds and request immunization records and developmental assessments.", button: "Got it"),
        questionCount: 0
    )

    static let update_credit_cardQualifying = WorkflowQualifying(
        workflowId: "update_credit_card",
        intro: WorkflowIntro(title: "Let's handle your credit cards", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your credit card addresses?", subtitle: nil, options: [QuestionOption(id: "update_address", label: "Update my addresses", icon: "pencil.line", subtitle: "We'll walk you through each card"), QuestionOption(id: "help_me", label: "Help me update them", icon: "hands.sparkles.fill", subtitle: "We'll handle the research"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let update_investmentQualifying = WorkflowQualifying(
        workflowId: "update_investment",
        intro: WorkflowIntro(title: "Let's handle your investment accounts", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your investment accounts?", subtitle: nil, options: [QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep current accounts, update contact info"), QuestionOption(id: "help_transfer", label: "Help me transfer or consolidate", icon: "arrow.triangle.swap", subtitle: "We'll research options for you"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let update_student_loansQualifying = WorkflowQualifying(
        workflowId: "update_student_loans",
        intro: WorkflowIntro(title: "Let's handle your student loans", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do with your student loans?", subtitle: nil, options: [QuestionOption(id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Update with servicer and StudentAid.gov"), QuestionOption(id: "help_me", label: "Help me figure out what to do", icon: "questionmark.circle", subtitle: "We'll walk you through it"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let transfer_pharmacy_recordsQualifying = WorkflowQualifying(
        workflowId: "transfer_pharmacy_records",
        intro: WorkflowIntro(title: "Let's handle your pharmacy records", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do?", subtitle: nil, options: [QuestionOption(id: "transfer_records", label: "Transfer to a pharmacy near new home", icon: "doc.arrow.forward", subtitle: "We'll help coordinate the transfer"), QuestionOption(id: "update_address", label: "Update address with current pharmacy", icon: "pencil.line", subtitle: "Keep your current pharmacy"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let transfer_specialists_recordsQualifying = WorkflowQualifying(
        workflowId: "transfer_specialists_records",
        intro: WorkflowIntro(title: "Let's handle your specialist records", subtitle: nil),
        questions: [
            WorkflowQuestion(id: "action", question: "What would you like to do?", subtitle: nil, options: [QuestionOption(id: "transfer_records", label: "Transfer records to new specialist", icon: "doc.arrow.forward", subtitle: "We'll help coordinate the transfer"), QuestionOption(id: "update_address", label: "Update address with current specialist", icon: "pencil.line", subtitle: "Keep your current specialist"), QuestionOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll take it from here.", button: "Submit"),
        questionCount: 1
    )

    static let update_auto_insuranceQualifying = WorkflowQualifying(
        workflowId: "update_auto_insurance",
        intro: WorkflowIntro(title: "Update your auto insurance", subtitle: "Your garaging address affects your rates — let's get this updated."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help with this?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me update it", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "geico", label: "GEICO", icon: "shield.fill"), QuestionOption(id: "progressive", label: "Progressive", icon: "shield.fill"), QuestionOption(id: "allstate", label: "Allstate", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get this updated for you.", button: "Submit"),
        questionCount: 2
    )

    static let cancel_renters_insuranceQualifying = WorkflowQualifying(
        workflowId: "cancel_renters_insurance",
        intro: WorkflowIntro(title: "Cancel your renters insurance", subtitle: "We'll make sure you're covered through your last day."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help canceling?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "lemonade", label: "Lemonade", icon: "shield.fill"), QuestionOption(id: "progressive", label: "Progressive", icon: "shield.fill"), QuestionOption(id: "allstate", label: "Allstate", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get this canceled effective your move date.", button: "Submit"),
        questionCount: 2
    )

    static let setup_renters_insuranceQualifying = WorkflowQualifying(
        workflowId: "setup_renters_insurance",
        intro: WorkflowIntro(title: "Set up renters insurance at your new place", subtitle: "Most leases require it, and it protects your stuff."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help finding a policy?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, find me options", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll find you the best options and get you set up before move day.", button: "Submit"),
        questionCount: 1
    )

    static let transfer_renters_insuranceQualifying = WorkflowQualifying(
        workflowId: "transfer_renters_insurance",
        intro: WorkflowIntro(title: "Transfer your renters insurance", subtitle: "Update your existing policy to cover your new address."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help with this?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me transfer it", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "lemonade", label: "Lemonade", icon: "shield.fill"), QuestionOption(id: "progressive", label: "Progressive", icon: "shield.fill"), QuestionOption(id: "allstate", label: "Allstate", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get your policy transferred to the new address.", button: "Submit"),
        questionCount: 2
    )

    static let cancel_condo_insuranceQualifying = WorkflowQualifying(
        workflowId: "cancel_condo_insurance",
        intro: WorkflowIntro(title: "Cancel your condo insurance", subtitle: "Cancel effective your closing date, not your move-out date."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help canceling?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "nationwide", label: "Nationwide", icon: "shield.fill"), QuestionOption(id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get this canceled effective your closing date.", button: "Submit"),
        questionCount: 2
    )

    static let setup_condo_insuranceQualifying = WorkflowQualifying(
        workflowId: "setup_condo_insurance",
        intro: WorkflowIntro(title: "Set up condo insurance at your new place", subtitle: "Your HOA's master policy doesn't cover your unit's interior."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help finding a policy?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, find me options", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll find you the best options before closing.", button: "Submit"),
        questionCount: 1
    )

    static let transfer_condo_insuranceQualifying = WorkflowQualifying(
        workflowId: "transfer_condo_insurance",
        intro: WorkflowIntro(title: "Transfer your condo insurance", subtitle: "Move your policy from your old condo to the new one."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help with this?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me transfer it", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "nationwide", label: "Nationwide", icon: "shield.fill"), QuestionOption(id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get your policy transferred.", button: "Submit"),
        questionCount: 2
    )

    static let cancel_homeowners_insuranceQualifying = WorkflowQualifying(
        workflowId: "cancel_homeowners_insurance",
        intro: WorkflowIntro(title: "Cancel your homeowners insurance", subtitle: "Do not cancel before closing — you're liable until the deed transfers."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help canceling?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "nationwide", label: "Nationwide", icon: "shield.fill"), QuestionOption(id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill"), QuestionOption(id: "usaa", label: "USAA", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get this canceled effective your closing date.", button: "Submit"),
        questionCount: 2
    )

    static let setup_homeowners_insuranceQualifying = WorkflowQualifying(
        workflowId: "setup_homeowners_insurance",
        intro: WorkflowIntro(title: "Set up homeowners insurance", subtitle: "Your lender requires this before closing."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help finding a policy?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, find me options", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll find you the best options. Need this bound at least 1 week before closing.", button: "Submit"),
        questionCount: 1
    )

    static let transfer_homeowners_insuranceQualifying = WorkflowQualifying(
        workflowId: "transfer_homeowners_insurance",
        intro: WorkflowIntro(title: "Transfer your homeowners insurance", subtitle: "Move your coverage from your current home to the new one."),
        questions: [
            WorkflowQuestion(id: "help_preference", question: "Would you like help with this?", subtitle: nil, options: [QuestionOption(id: "help_me", label: "Yes, help me transfer it", icon: "hands.sparkles.fill"), QuestionOption(id: "self", label: "I'll handle it myself", icon: "person.fill")], type: .single_select),
            WorkflowQuestion(id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", options: [QuestionOption(id: "state_farm", label: "State Farm", icon: "shield.fill"), QuestionOption(id: "nationwide", label: "Nationwide", icon: "shield.fill"), QuestionOption(id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill"), QuestionOption(id: "usaa", label: "USAA", icon: "shield.fill"), QuestionOption(id: "other", label: "Other", icon: "ellipsis.circle")], type: .single_select)
        ],
        recap: WorkflowRecap(title: "We're on it", closing: "We'll reach out and get your policy transferred.", button: "Submit"),
        questionCount: 2
    )

    private static func qualifying(for workflowId: String?) -> WorkflowQualifying? {
        switch workflowId {
        case "book_movers": return book_moversQualifying
        case "junk_removal": return junk_removalQualifying
        case "book_cleaners": return book_cleanersQualifying
        case "remove_items": return remove_itemsQualifying
        case "sell_items": return sell_itemsQualifying
        case "setup_internet": return setup_internetQualifying
        case "rent_truck": return rent_truckQualifying
        case "manage_bank": return manage_bankQualifying
        case "manage_doctor": return manage_doctorQualifying
        case "manage_dentist": return manage_dentistQualifying
        case "manage_vet": return manage_vetQualifying
        case "manage_gym": return manage_gymQualifying
        case "manage_yoga": return manage_yogaQualifying
        case "manage_spin": return manage_spinQualifying
        case "manage_massage": return manage_massageQualifying
        case "manage_golf": return manage_golfQualifying
        case "arrange_parking_new": return arrange_parking_newQualifying
        case "arrange_parking_old": return arrange_parking_oldQualifying
        case "reserve_elevators_new": return reserve_elevators_newQualifying
        case "reserve_elevators_old": return reserve_elevators_oldQualifying
        case "cancel_utilities": return cancel_utilitiesQualifying
        case "setup_utilities": return setup_utilitiesQualifying
        case "transfer_utilities": return transfer_utilitiesQualifying
        case "forward_mail_usps": return forward_mail_uspsQualifying
        case "begin_school_transfer": return begin_school_transferQualifying
        case "new_school_enrollment": return new_school_enrollmentQualifying
        case "coa_schools": return coa_schoolsQualifying
        case "setup_daycare": return setup_daycareQualifying
        case "transfer_daycare": return transfer_daycareQualifying
        case "update_credit_card": return update_credit_cardQualifying
        case "update_investment": return update_investmentQualifying
        case "update_student_loans": return update_student_loansQualifying
        case "transfer_pharmacy_records": return transfer_pharmacy_recordsQualifying
        case "transfer_specialists_records": return transfer_specialists_recordsQualifying
        case "update_auto_insurance": return update_auto_insuranceQualifying
        case "cancel_renters_insurance": return cancel_renters_insuranceQualifying
        case "setup_renters_insurance": return setup_renters_insuranceQualifying
        case "transfer_renters_insurance": return transfer_renters_insuranceQualifying
        case "cancel_condo_insurance": return cancel_condo_insuranceQualifying
        case "setup_condo_insurance": return setup_condo_insuranceQualifying
        case "transfer_condo_insurance": return transfer_condo_insuranceQualifying
        case "cancel_homeowners_insurance": return cancel_homeowners_insuranceQualifying
        case "setup_homeowners_insurance": return setup_homeowners_insuranceQualifying
        case "transfer_homeowners_insurance": return transfer_homeowners_insuranceQualifying
        default: return nil
        }
    }

    // MARK: - Sequence Catalog for Sandbox

    static let allSequences: [(name: String, sequence: TaskCardSequence)] = [
        ("Getting Started: Scan your home", TaskCardSequenceBuilder.build(task: scan_inventoryTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: scan_inventoryTask.workflowId), userState: sampleUserState)),
        ("Moving: Book your movers", TaskCardSequenceBuilder.build(task: book_moversTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: book_moversTask.workflowId), userState: sampleUserState)),
        ("Moving: Rent your moving truck", TaskCardSequenceBuilder.build(task: rent_truckTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: rent_truckTask.workflowId), userState: sampleUserState)),
        ("Moving: Reserve loading parking", TaskCardSequenceBuilder.build(task: arrange_parking_oldTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: arrange_parking_oldTask.workflowId), userState: sampleUserState)),
        ("Moving: Reserve unloading parking", TaskCardSequenceBuilder.build(task: arrange_parking_newTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: arrange_parking_newTask.workflowId), userState: sampleUserState)),
        ("Moving: Reserve loading elevator", TaskCardSequenceBuilder.build(task: reserve_elevators_oldTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: reserve_elevators_oldTask.workflowId), userState: sampleUserState)),
        ("Moving: Reserve unloading elevator", TaskCardSequenceBuilder.build(task: reserve_elevators_newTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: reserve_elevators_newTask.workflowId), userState: sampleUserState)),
        ("Utilities: Schedule internet install", TaskCardSequenceBuilder.build(task: setup_internetTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: setup_internetTask.workflowId), userState: sampleUserState)),
        ("Utilities: Set up new utilities", TaskCardSequenceBuilder.build(task: setup_utilitiesTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: setup_utilitiesTask.workflowId), userState: sampleUserState)),
        ("Utilities: Cancel your utilities", TaskCardSequenceBuilder.build(task: cancel_utilitiesTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: cancel_utilitiesTask.workflowId), userState: sampleUserState)),
        ("Utilities: Transfer your utilities", TaskCardSequenceBuilder.build(task: transfer_utilitiesTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_utilitiesTask.workflowId), userState: sampleUserState)),
        ("Services: Book your cleaners", TaskCardSequenceBuilder.build(task: book_cleanersTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: book_cleanersTask.workflowId), userState: sampleUserState)),
        ("Services: Buy cleaning supplies", TaskCardSequenceBuilder.build(task: buy_cleaning_suppliesTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: buy_cleaning_suppliesTask.workflowId), userState: sampleUserState)),
        ("Services: Deep clean the place", TaskCardSequenceBuilder.build(task: diy_deep_cleaningTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: diy_deep_cleaningTask.workflowId), userState: sampleUserState)),
        ("Services: Do the final touch-up", TaskCardSequenceBuilder.build(task: diy_final_cleaningTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: diy_final_cleaningTask.workflowId), userState: sampleUserState)),
        ("Packing: Buy packing supplies", TaskCardSequenceBuilder.build(task: buy_packing_suppliesTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: buy_packing_suppliesTask.workflowId), userState: sampleUserState)),
        ("Packing: Sell what you're not bringing", TaskCardSequenceBuilder.build(task: sell_itemsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: sell_itemsTask.workflowId), userState: sampleUserState)),
        ("Packing: Schedule donation pickup", TaskCardSequenceBuilder.build(task: remove_itemsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: remove_itemsTask.workflowId), userState: sampleUserState)),
        ("Packing: Defrost your freezer", TaskCardSequenceBuilder.build(task: defrost_freezerTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: defrost_freezerTask.workflowId), userState: sampleUserState)),
        ("Administrative: Request your time off", TaskCardSequenceBuilder.build(task: schedule_time_off_workTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: schedule_time_off_workTask.workflowId), userState: sampleUserState)),
        ("Administrative: Update your license address", TaskCardSequenceBuilder.build(task: update_drivers_licenseTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: update_drivers_licenseTask.workflowId), userState: sampleUserState)),
        ("Administrative: Get your new state license", TaskCardSequenceBuilder.build(task: new_drivers_licenseTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: new_drivers_licenseTask.workflowId), userState: sampleUserState)),
        ("Administrative: Register your vehicles", TaskCardSequenceBuilder.build(task: register_vehicleTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: register_vehicleTask.workflowId), userState: sampleUserState)),
        ("Administrative: Forward your mail", TaskCardSequenceBuilder.build(task: forward_mail_uspsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: forward_mail_uspsTask.workflowId), userState: sampleUserState)),
        ("Administrative: Update employer records", TaskCardSequenceBuilder.build(task: update_employer_recordsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: update_employer_recordsTask.workflowId), userState: sampleUserState)),
        ("Administrative: Document the empty unit", TaskCardSequenceBuilder.build(task: photograph_rental_conditionTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: photograph_rental_conditionTask.workflowId), userState: sampleUserState)),
        ("Administrative: Return all access devices", TaskCardSequenceBuilder.build(task: return_key_fobs_remotesTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: return_key_fobs_remotesTask.workflowId), userState: sampleUserState)),
        ("Finance: Handle your bank account", TaskCardSequenceBuilder.build(task: manage_bankTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_bankTask.workflowId), userState: sampleUserState)),
        ("Finance: Update credit card addresses", TaskCardSequenceBuilder.build(task: update_credit_cardTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: update_credit_cardTask.workflowId), userState: sampleUserState)),
        ("Finance: Update investment accounts", TaskCardSequenceBuilder.build(task: update_investmentTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: update_investmentTask.workflowId), userState: sampleUserState)),
        ("Finance: Update student loan accounts", TaskCardSequenceBuilder.build(task: update_student_loansTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: update_student_loansTask.workflowId), userState: sampleUserState)),
        ("Health: Transfer specialist records", TaskCardSequenceBuilder.build(task: transfer_specialists_recordsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_specialists_recordsTask.workflowId), userState: sampleUserState)),
        ("Health: Handle your primary doctor", TaskCardSequenceBuilder.build(task: manage_doctorTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_doctorTask.workflowId), userState: sampleUserState)),
        ("Health: Handle your dentist", TaskCardSequenceBuilder.build(task: manage_dentistTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_dentistTask.workflowId), userState: sampleUserState)),
        ("Health: Transfer your pharmacy", TaskCardSequenceBuilder.build(task: transfer_pharmacy_recordsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_pharmacy_recordsTask.workflowId), userState: sampleUserState)),
        ("Pets: Handle your vet", TaskCardSequenceBuilder.build(task: manage_vetTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_vetTask.workflowId), userState: sampleUserState)),
        ("Fitness: Handle your yoga membership", TaskCardSequenceBuilder.build(task: manage_yogaTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_yogaTask.workflowId), userState: sampleUserState)),
        ("Fitness: Handle your gym membership", TaskCardSequenceBuilder.build(task: manage_gymTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_gymTask.workflowId), userState: sampleUserState)),
        ("Fitness: Handle your club membership", TaskCardSequenceBuilder.build(task: manage_golfTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_golfTask.workflowId), userState: sampleUserState)),
        ("Fitness: Handle your cycling membership", TaskCardSequenceBuilder.build(task: manage_spinTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_spinTask.workflowId), userState: sampleUserState)),
        ("Fitness: Handle your spa membership", TaskCardSequenceBuilder.build(task: manage_massageTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: manage_massageTask.workflowId), userState: sampleUserState)),
        ("Children: Enroll in the new school", TaskCardSequenceBuilder.build(task: new_school_enrollmentTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: new_school_enrollmentTask.workflowId), userState: sampleUserState)),
        ("Children: Update your child's school", TaskCardSequenceBuilder.build(task: coa_schoolsTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: coa_schoolsTask.workflowId), userState: sampleUserState)),
        ("Children: Find your new daycare", TaskCardSequenceBuilder.build(task: setup_daycareTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: setup_daycareTask.workflowId), userState: sampleUserState)),
        ("Children: Notify the current school", TaskCardSequenceBuilder.build(task: begin_school_transferTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: begin_school_transferTask.workflowId), userState: sampleUserState)),
        ("Children: Update your daycare", TaskCardSequenceBuilder.build(task: transfer_daycareTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_daycareTask.workflowId), userState: sampleUserState)),
        ("Insurance: Update your auto insurance", TaskCardSequenceBuilder.build(task: update_auto_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: update_auto_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Cancel your renter's insurance", TaskCardSequenceBuilder.build(task: cancel_renters_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: cancel_renters_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Set up homeowner's insurance", TaskCardSequenceBuilder.build(task: setup_homeowners_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: setup_homeowners_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Set up renter's insurance", TaskCardSequenceBuilder.build(task: setup_renters_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: setup_renters_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Transfer homeowner's insurance", TaskCardSequenceBuilder.build(task: transfer_homeowners_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_homeowners_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Transfer renter's insurance", TaskCardSequenceBuilder.build(task: transfer_renters_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_renters_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Cancel your condo insurance", TaskCardSequenceBuilder.build(task: cancel_condo_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: cancel_condo_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Set up condo insurance", TaskCardSequenceBuilder.build(task: setup_condo_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: setup_condo_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Transfer your condo insurance", TaskCardSequenceBuilder.build(task: transfer_condo_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: transfer_condo_insuranceTask.workflowId), userState: sampleUserState)),
        ("Insurance: Cancel homeowner's insurance", TaskCardSequenceBuilder.build(task: cancel_homeowners_insuranceTask, isSubscribed: true, completedTaskCount: 0, qualifying: qualifying(for: cancel_homeowners_insuranceTask.workflowId), userState: sampleUserState)),
    ]
}
#endif
