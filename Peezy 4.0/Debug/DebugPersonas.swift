#if DEBUG
import Foundation

/// Pre-defined user personas for testing different scenarios.
enum DebugPersona: String, CaseIterable, Identifiable {
    case firstTimeLocalRenter = "First-Time Local Renter"
    case crossCountryFamily = "Cross-Country Family"
    case firstTimeHomebuyer = "First-Time Homebuyer"
    case downsizingSenior = "Downsizing Senior"
    case urgentLocalMove = "Urgent Local Move"
    case fixerUpperBuyer = "Fixer-Upper Buyer"

    var id: String { rawValue }

    /// Returns a UserState configured for this persona.
    /// - Parameter baseDate: Reference date for calculating move date (defaults to now)
    /// - Returns: A fully configured UserState
    func createUserState(baseDate: Date = DateProvider.shared.now) -> UserState {
        switch self {
        case .firstTimeLocalRenter:
            var state = UserState(userId: "debug-first-time-local", name: "Alex (Test)")
            state.moveDate = Calendar.current.date(byAdding: .day, value: 42, to: baseDate)
            state.moveDistance = .local
            state.originCity = "Kansas City"
            state.originState = "MO"
            state.destinationCity = "Kansas City"
            state.destinationState = "MO"
            state.originPropertyType = .apartment
            state.originBedrooms = 1
            state.originOwnership = .rent
            state.destinationPropertyType = .apartment
            state.destinationBedrooms = 2
            state.destinationOwnership = .rent
            state.hasKids = false
            state.hasPets = false
            state.budget = .tight
            state.helpLevel = .someHelp
            state.assessmentCompletedAt = baseDate
            state.lastInteractionAt = baseDate
            return state

        case .crossCountryFamily:
            var state = UserState(userId: "debug-cross-country-family", name: "Jordan (Test)")
            state.moveDate = Calendar.current.date(byAdding: .day, value: 56, to: baseDate)
            state.moveDistance = .crossCountry
            state.originCity = "Kansas City"
            state.originState = "MO"
            state.destinationCity = "Seattle"
            state.destinationState = "WA"
            state.originPropertyType = .house
            state.originBedrooms = 3
            state.originOwnership = .rent
            state.destinationPropertyType = .house
            state.destinationBedrooms = 4
            state.destinationOwnership = .rent
            state.hasKids = true
            state.kidsAges = [8, 11]
            state.hasPets = true
            state.petTypes = ["dog"]
            state.largeItems = ["sectional sofa", "king bed"]
            state.budget = .moderate
            state.helpLevel = .fullService
            state.assessmentCompletedAt = baseDate
            state.lastInteractionAt = baseDate
            return state

        case .firstTimeHomebuyer:
            var state = UserState(userId: "debug-first-homebuyer", name: "Taylor (Test)")
            state.moveDate = Calendar.current.date(byAdding: .day, value: 28, to: baseDate)
            state.moveDistance = .local
            state.originCity = "Kansas City"
            state.originState = "MO"
            state.destinationCity = "Overland Park"
            state.destinationState = "KS"
            state.originPropertyType = .apartment
            state.originBedrooms = 2
            state.originOwnership = .rent
            state.destinationPropertyType = .house
            state.destinationBedrooms = 3
            state.destinationOwnership = .own
            state.destinationYearBuilt = 1985
            state.hasKids = false
            state.hasPets = false
            state.budget = .moderate
            state.helpLevel = .someHelp
            state.assessmentCompletedAt = baseDate
            state.lastInteractionAt = baseDate
            return state

        case .downsizingSenior:
            var state = UserState(userId: "debug-downsizing-senior", name: "Margaret (Test)")
            state.moveDate = Calendar.current.date(byAdding: .day, value: 70, to: baseDate)
            state.moveDistance = .local
            state.originCity = "Kansas City"
            state.originState = "MO"
            state.destinationCity = "Kansas City"
            state.destinationState = "MO"
            state.originPropertyType = .house
            state.originBedrooms = 4
            state.originOwnership = .own
            state.destinationPropertyType = .apartment
            state.destinationBedrooms = 2
            state.destinationOwnership = .rent
            state.hasKids = false
            state.hasPets = false
            state.largeItems = ["grandfather clock"]
            state.specialItems = ["piano", "antiques", "china collection"]
            state.budget = .flexible
            state.helpLevel = .fullService
            state.assessmentCompletedAt = baseDate
            state.lastInteractionAt = baseDate
            return state

        case .urgentLocalMove:
            var state = UserState(userId: "debug-urgent-local", name: "Chris (Test)")
            state.moveDate = Calendar.current.date(byAdding: .day, value: 10, to: baseDate)
            state.moveDistance = .local
            state.originCity = "Kansas City"
            state.originState = "MO"
            state.destinationCity = "Kansas City"
            state.destinationState = "MO"
            state.originPropertyType = .apartment
            state.originBedrooms = 1
            state.originOwnership = .rent
            state.destinationPropertyType = .apartment
            state.destinationBedrooms = 1
            state.destinationOwnership = .rent
            state.hasKids = false
            state.hasPets = true
            state.petTypes = ["cat"]
            state.budget = .tight
            state.helpLevel = .diy
            state.assessmentCompletedAt = baseDate
            state.lastInteractionAt = baseDate
            return state

        case .fixerUpperBuyer:
            var state = UserState(userId: "debug-fixer-upper", name: "Sam (Test)")
            state.moveDate = Calendar.current.date(byAdding: .day, value: 42, to: baseDate)
            state.moveDistance = .local
            state.originCity = "Kansas City"
            state.originState = "MO"
            state.destinationCity = "Independence"
            state.destinationState = "MO"
            state.originPropertyType = .apartment
            state.originBedrooms = 1
            state.originOwnership = .rent
            state.destinationPropertyType = .house
            state.destinationBedrooms = 3
            state.destinationOwnership = .own
            state.destinationYearBuilt = 1962
            state.hasKids = false
            state.hasPets = false
            state.budget = .tight
            state.helpLevel = .diy
            state.assessmentCompletedAt = baseDate
            state.lastInteractionAt = baseDate
            return state
        }
    }

    /// Short description for UI display
    var summary: String {
        switch self {
        case .firstTimeLocalRenter:
            return "Local rent->rent, no pets/kids, tight budget, 6 weeks"
        case .crossCountryFamily:
            return "Cross-country rent->rent, dog + 2 kids, 8 weeks"
        case .firstTimeHomebuyer:
            return "Local rent->own, 1985 house, 4 weeks"
        case .downsizingSenior:
            return "Local own->rent, piano + antiques, 10 weeks"
        case .urgentLocalMove:
            return "Local rent->rent, cat, tight budget, 10 DAYS"
        case .fixerUpperBuyer:
            return "Local rent->own, 1962 house, tight budget, 6 weeks"
        }
    }
}
#endif
