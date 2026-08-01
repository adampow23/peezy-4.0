import SwiftUI
import UIKit
import LucideIcons

enum AssessmentChapter: String, CaseIterable {
    case move
    case homes
    case people
    case accounts

    var title: String {
        switch self {
        case .move: "Your move"
        case .homes: "Your homes"
        case .people: "Your people"
        case .accounts: "Your accounts"
        }
    }

    var accent: Color {
        switch self {
        case .move: PeezyTheme.Colors.accentBlue
        case .homes: PeezyTheme.Colors.supportPurple
        case .people: PeezyTheme.Colors.emotionalRed
        case .accounts: PeezyTheme.Colors.successGreen
        }
    }
}

struct AssessmentChapterProgress {
    let chapter: AssessmentChapter
    let position: Int
    let total: Int

    var fraction: Double {
        min(max(Double(position) / Double(max(total, 1)), 0), 1)
    }
}

/// The single source of truth for assessment and FlowEngine question icons.
/// Values are Lucide asset IDs from the pinned LucideIcons package.
enum PeezyQuestionVisuals {
    static let questionIcons: [String: String] = [
        "assessment.userName": "badge",
        "assessment.moveDate": "calendar-days",
        "assessment.moveDateType": "calendar-range",
        "assessment.currentRentOrOwn": "key-round",
        "assessment.currentDwellingType": "house",
        "assessment.currentAddress": "map-pin",
        "assessment.currentFloorAccess": "building-2",
        "assessment.currentBedrooms": "bed-double",
        "assessment.currentSquareFootage": "ruler",
        "assessment.currentFinishedSqFt": "ruler",
        "assessment.newRentOrOwn": "key-round",
        "assessment.newDwellingType": "house-plus",
        "assessment.newAddress": "map-pinned",
        "assessment.newFloorAccess": "building-2",
        "assessment.newBedrooms": "bed-double",
        "assessment.newSquareFootage": "ruler",
        "assessment.newFinishedSqFt": "ruler",
        "assessment.hasStorage": "warehouse",
        "assessment.storageSize": "boxes",
        "assessment.storageFullness": "gauge",
        "assessment.anyKids": "users-round",
        "assessment.childrenInSchool": "graduation-cap",
        "assessment.childrenInDaycare": "blocks",
        "assessment.hasVet": "paw-print",
        "assessment.hasVehicles": "car-front",
        "assessment.servicesIntro": "hand-helping",
        "assessment.hireMovers": "truck",
        "assessment.truckRental": "key-round",
        "assessment.hasDeclutter": "package-open",
        "assessment.wantToSell": "tag",
        "assessment.hireCleaners": "sparkles",
        "assessment.addressChangeIntro": "map-pinned",
        "assessment.financialInstitutions": "landmark",
        "assessment.healthcareProviders": "stethoscope",
        "assessment.fitnessWellness": "dumbbell",
        "assessment.howHeard": "message-circle-question-mark",

        "flow.setup_utilities.handling": "plug-zap",
        "flow.cancel_utilities.handling": "plug-zap",
        "flow.transfer_utilities.handling": "plug-zap",
        "flow.manage_vet.handling_update": "paw-print",
        "flow.manage_vet.handling_cancel": "file-heart",
        "flow.manage_vet.handling_find": "search",
        "flow.transfer_pharmacy_records.handling_update": "pill-bottle",
        "flow.transfer_pharmacy_records.handling_cancel": "file-heart",
        "flow.transfer_pharmacy_records.handling_find": "search",
        "flow.reserve_access_old.handling": "building-2",
        "flow.reserve_access_new.handling": "building-2",
        "flow.medical_records.handling": "file-heart",
        "flow.financial_accounts.handling": "wallet-cards",
        "flow.memberships.handling": "badge",
        "flow.storage_unit.handling": "warehouse"
    ]

    /// Concrete option nouns only. Abstract yes/no, date, flexibility, and
    /// quantity choices intentionally have no entry and therefore no icon.
    static let optionIcons: [String: String] = [
        "Rent": "key-round",
        "Own": "house",
        "Renting": "key-round",
        "Buying": "house",
        "House": "house",
        "Apartment": "building-2",
        "Condo": "building",
        "Townhouse": "house-plus",
        "Ground Floor": "door-open",
        "Stairs": "between-vertical-start",
        "Elevator": "panel-top",
        "Reserved Elevator": "calendar-check",
        "Bank / Credit Union": "landmark",
        "Credit Card": "credit-card",
        "Investment Account": "chart-no-axes-combined",
        "Student Loans": "graduation-cap",
        "Doctor": "stethoscope",
        "Dentist": "smile-plus",
        "Specialists": "cross",
        "Pharmacy": "pill-bottle",
        "Gym / CrossFit": "dumbbell",
        "Yoga / Pilates": "person-standing",
        "Spin / Cycling": "bike",
        "Massage / Spa": "sparkles",
        "Country Club / Golf": "club",
        "Friend or Family": "users-round",
        "Social Media": "share-2",
        "Google Search": "search",
        "Real Estate Agent": "handshake",
        "Moving Company": "truck",
        "Other": "circle-ellipsis"
    ]

    static func assessmentIcon(for step: AssessmentInputStep) -> String {
        questionIcons["assessment.\(step.rawValue)"] ?? "circle-question-mark"
    }

    static func flowIcon(workflowID: String, stepID: String) -> String {
        questionIcons["flow.\(workflowID).\(stepID)"] ?? "circle-question-mark"
    }

    static func optionIcon(for label: String) -> String? {
        optionIcons[label]
    }

    static func chapter(for step: AssessmentInputStep) -> AssessmentChapter {
        switch step {
        case .userName, .moveDate, .moveDateType:
            .move
        case .currentRentOrOwn, .currentDwellingType, .currentAddress,
             .currentFloorAccess, .currentBedrooms, .currentSquareFootage,
             .currentFinishedSqFt, .newRentOrOwn, .newDwellingType, .newAddress,
             .newFloorAccess, .newBedrooms, .newSquareFootage, .newFinishedSqFt,
             .hasStorage, .storageSize, .storageFullness:
            .homes
        case .anyKids, .childrenInSchool, .childrenInDaycare, .hasVet,
             .hasVehicles, .servicesIntro, .hireMovers, .truckRental,
             .hasDeclutter, .wantToSell, .hireCleaners:
            .people
        case .addressChangeIntro, .financialInstitutions, .healthcareProviders,
             .fitnessWellness, .howHeard:
            .accounts
        }
    }
}

struct PeezyLucideIcon: View {
    let id: String
    var size: CGFloat
    var color: Color

    var body: some View {
        Group {
            if let image = UIImage(lucideId: id) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
