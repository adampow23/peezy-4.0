import Foundation
import FirebaseFirestore

// MARK: - UserState
/// Complete user context sent to Peezy backend for personalized responses
struct UserState: Codable {
    // MARK: - Identity
    let userId: String
    var name: String
    
    // MARK: - Move Details
    var moveDate: Date?
    var moveDistance: MoveDistance?
    var originCity: String?
    var originState: String?
    var destinationCity: String?
    var destinationState: String?
    
    // MARK: - Property Info
    var originPropertyType: PropertyType?
    var originBedrooms: Int?
    var originOwnership: Ownership?
    var destinationPropertyType: PropertyType?
    var destinationBedrooms: Int?
    var destinationOwnership: Ownership?
    var destinationYearBuilt: Int?
    
    // MARK: - Household
    var hasKids: Bool = false
    var kidsAges: [Int]?
    var hasPets: Bool = false
    var petTypes: [String]?
    
    // MARK: - Special Items
    var largeItems: [String]?  // piano, pool table, safe, etc.
    var specialItems: [String]? // art, antiques, wine collection, etc.
    
    // MARK: - Budget & Preferences
    var budget: Budget?
    var helpLevel: HelpLevel?
    
    // MARK: - Task State
    var completedTasks: [String] = []
    var pendingTasks: [String] = []
    var deferredTasks: [String] = []  // Tasks user swiped "later" on
    
    // MARK: - Peezy Interaction State
    var heardAccountabilityPitch: Bool = false
    var vendorsContacted: [String] = []
    var vendorsBooked: [String] = []
    
    // MARK: - Timestamps
    var assessmentCompletedAt: Date?
    var lastInteractionAt: Date?
    
    // MARK: - Enums
    enum MoveDistance: String, Codable {
        case local = "local"
        case crossState = "cross_state"
        case crossCountry = "cross_country"
    }
    
    enum PropertyType: String, Codable {
        case apartment = "apartment"
        case condo = "condo"
        case house = "house"
        case townhouse = "townhouse"
        case studio = "studio"
        case other = "other"
    }
    
    enum Ownership: String, Codable {
        case rent = "rent"
        case own = "own"
    }
    
    enum Budget: String, Codable {
        case tight = "tight"
        case moderate = "moderate"
        case flexible = "flexible"
    }
    
    enum HelpLevel: String, Codable {
        case diy = "diy"              // I want to do it myself
        case someHelp = "some_help"   // Help with big stuff
        case fullService = "full_service" // Handle everything
    }
    
    // MARK: - Computed Properties
    
    var daysUntilMove: Int? {
        guard let moveDate = moveDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: DateProvider.shared.now, to: moveDate)
        return components.day
    }
    
    var urgencyLevel: UrgencyLevel {
        guard let days = daysUntilMove else { return .planning }
        switch days {
        case ..<0: return .past
        case 0: return .today
        case 1...3: return .critical
        case 4...7: return .urgent
        case 8...14: return .tight
        case 15...30: return .normal
        case 31...60: return .planning
        default: return .early
        }
    }
    
    enum UrgencyLevel: String {
        case past = "past"
        case today = "today"
        case critical = "critical"
        case urgent = "urgent"
        case tight = "tight"
        case normal = "normal"
        case planning = "planning"
        case early = "early"
    }
    
    var hasDateGap: Bool {
        // Would need lease end date to calculate - placeholder
        return false
    }
    
    var isLongDistance: Bool {
        moveDistance == .crossState || moveDistance == .crossCountry
    }
    
    var hasSpecialItems: Bool {
        !(largeItems?.isEmpty ?? true) || !(specialItems?.isEmpty ?? true)
    }
    
    // MARK: - Initializers
    
    init(userId: String, name: String) {
        self.userId = userId
        self.name = name
    }
    
    /// Create from assessment data dictionary (from AssessmentDataManager)
    /// Keys match what AssessmentDataManager.getAllAssessmentData() saves (camelCase)
    init(userId: String, from assessment: [String: Any]) {
        self.userId = userId

        // Name - AssessmentDataManager saves as "userName"
        self.name = assessment["userName"] as? String ?? ""

        // Move details
        if let date = assessment["moveDate"] as? Timestamp {
            self.moveDate = date.dateValue()
        } else if let date = assessment["moveDate"] as? Date {
            self.moveDate = date
        }

        // Move distance - AssessmentDataManager saves as "moveDistance"
        if let distance = assessment["moveDistance"] as? String {
            // Map assessment values to enum: "Local", "Cross-State", "Cross-Country"
            let normalized = distance.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
            self.moveDistance = MoveDistance(rawValue: normalized)
        }

        // Cities (not in current assessment, but keep for future)
        self.originCity = assessment["originCity"] as? String
        self.originState = assessment["originState"] as? String
        self.destinationCity = assessment["destinationCity"] as? String
        self.destinationState = assessment["destinationState"] as? String

        // Property info - AssessmentDataManager saves as "currentDwellingType" and "newDwellingType"
        if let type = assessment["currentDwellingType"] as? String {
            self.originPropertyType = PropertyType(rawValue: type.lowercased())
        }
        self.originBedrooms = assessment["originBedrooms"] as? Int

        // Ownership - AssessmentDataManager saves as "currentRentOrOwn" and "newRentOrOwn"
        if let ownership = assessment["currentRentOrOwn"] as? String {
            // Map "Renting" -> "rent", "Own" -> "own"
            let normalized = ownership.lowercased().hasPrefix("rent") ? "rent" : "own"
            self.originOwnership = Ownership(rawValue: normalized)
        }

        if let type = assessment["newDwellingType"] as? String {
            self.destinationPropertyType = PropertyType(rawValue: type.lowercased())
        }
        self.destinationBedrooms = assessment["destinationBedrooms"] as? Int

        if let ownership = assessment["newRentOrOwn"] as? String {
            let normalized = ownership.lowercased().hasPrefix("rent") ? "rent" : "own"
            self.destinationOwnership = Ownership(rawValue: normalized)
        }
        self.destinationYearBuilt = assessment["destinationYearBuilt"] as? Int

        // Household - AssessmentDataManager saves as "whosMoving"
        if let whosMoving = assessment["whosMoving"] as? String {
            // "Just me", "Me + Partner", "Family with kids", etc.
            self.hasKids = whosMoving.lowercased().contains("kid")
        }
        self.kidsAges = assessment["kidsAges"] as? [Int]

        // Pets - AssessmentDataManager saves as "hasVet"
        if let vet = assessment["hasVet"] as? String {
            self.hasPets = vet.lowercased() == "yes"
        }
        self.petTypes = assessment["petTypes"] as? [String]

        // Special items
        self.largeItems = assessment["largeItems"] as? [String]
        self.specialItems = assessment["specialItems"] as? [String]

        // Preferences
        if let budget = assessment["budget"] as? String {
            self.budget = Budget(rawValue: budget.lowercased())
        }

        // Help level - derived from hireMovers, hirePackers, hireCleaners
        let hireMovers = assessment["hireMovers"] as? String ?? ""
        let hirePackers = assessment["hirePackers"] as? String ?? ""
        if hireMovers.lowercased() == "yes" && hirePackers.lowercased() == "yes" {
            self.helpLevel = .fullService
        } else if hireMovers.lowercased() == "yes" {
            self.helpLevel = .someHelp
        } else {
            self.helpLevel = .diy
        }
    }
    
    // MARK: - Convert to Dictionary for Firebase
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "name": name,
            "heardAccountabilityPitch": heardAccountabilityPitch,
            "completedTasks": completedTasks,
            "pendingTasks": pendingTasks,
            "deferredTasks": deferredTasks,
            "vendorsContacted": vendorsContacted,
            "vendorsBooked": vendorsBooked
        ]
        
        // Optional values
        if let moveDate = moveDate {
            dict["moveDate"] = ISO8601DateFormatter().string(from: moveDate)
        }
        if let daysUntilMove = daysUntilMove {
            dict["daysUntilMove"] = daysUntilMove
        }
        if let moveDistance = moveDistance {
            dict["moveDistance"] = moveDistance.rawValue
        }
        if let originCity = originCity {
            dict["originCity"] = originCity
        }
        if let destinationCity = destinationCity {
            dict["destinationCity"] = destinationCity
        }
        if let originBedrooms = originBedrooms {
            dict["originBedrooms"] = originBedrooms
        }
        if let destinationBedrooms = destinationBedrooms {
            dict["destinationBedrooms"] = destinationBedrooms
        }
        if let originPropertyType = originPropertyType {
            dict["originPropertyType"] = originPropertyType.rawValue
        }
        if let destinationPropertyType = destinationPropertyType {
            dict["destinationPropertyType"] = destinationPropertyType.rawValue
        }
        if let originOwnership = originOwnership {
            dict["originOwnership"] = originOwnership.rawValue
        }
        if let destinationOwnership = destinationOwnership {
            dict["destinationOwnership"] = destinationOwnership.rawValue
        }
        if let destinationYearBuilt = destinationYearBuilt {
            dict["destinationYearBuilt"] = destinationYearBuilt
        }
        
        dict["hasKids"] = hasKids
        if let kidsAges = kidsAges {
            dict["kidsAges"] = kidsAges
        }
        dict["hasPets"] = hasPets
        if let petTypes = petTypes {
            dict["petTypes"] = petTypes
        }
        if let largeItems = largeItems {
            dict["largeItems"] = largeItems
        }
        if let specialItems = specialItems {
            dict["specialItems"] = specialItems
        }
        if let budget = budget {
            dict["budget"] = budget.rawValue
        }
        if let helpLevel = helpLevel {
            dict["helpLevel"] = helpLevel.rawValue
        }
        
        return dict
    }
}
