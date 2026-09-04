import Foundation
import FirebaseFirestore

struct ISPPlan: Identifiable, Equatable {
    static let affiliatePending = "#AFFILIATE_PENDING"

    let id: String
    let provider: String
    let tier: String
    let speed: String
    let price: String
    let promo: String
    let contract: String
    let why: String
    let providerURL: URL
    let affiliateURL: String
    let sourceURL: URL
    let researchedAt: String
    let curationNote: String
    let sortOrder: Int

    var preferredURL: URL {
        guard affiliateURL != Self.affiliatePending,
              let affiliate = URL(string: affiliateURL),
              affiliate.scheme?.lowercased() == "https" else {
            return providerURL
        }
        return affiliate
    }

    var comparisonModel: ComparisonCardModel {
        ComparisonCardModel(
            id: id,
            providerName: provider,
            priceRange: price,
            durationAndTeam: speed,
            arrivalWindow: promo,
            insuranceTier: contract,
            why: why,
            priceBasis: "Provider confirms address availability and final terms",
            detailNotes: [tier]
        )
    }

    init(document: QueryDocumentSnapshot) throws {
        let data = document.data()
        func requiredString(_ key: String) throws -> String {
            guard let value = data[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ISPPlanError.invalidDocument(document.documentID, key)
            }
            return value
        }

        let planID = try requiredString("planId")
        let providerURLString = try requiredString("providerURL")
        let sourceURLString = try requiredString("sourceURL")
        guard document.documentID == planID,
              let providerURL = URL(string: providerURLString),
              providerURL.scheme?.lowercased() == "https",
              let sourceURL = URL(string: sourceURLString),
              sourceURL.scheme?.lowercased() == "https",
              let sortOrder = (data["sortOrder"] as? NSNumber)?.intValue else {
            throw ISPPlanError.invalidDocument(document.documentID, "identity/URL/sortOrder")
        }

        let affiliateURL = try requiredString("affiliateURL")
        if affiliateURL != Self.affiliatePending {
            guard let parsed = URL(string: affiliateURL), parsed.scheme?.lowercased() == "https" else {
                throw ISPPlanError.invalidDocument(document.documentID, "affiliateURL")
            }
        }

        self.id = planID
        self.provider = try requiredString("provider")
        self.tier = try requiredString("tier")
        self.speed = try requiredString("speed")
        self.price = try requiredString("price")
        self.promo = try requiredString("promo")
        self.contract = try requiredString("contract")
        self.why = try requiredString("why")
        self.providerURL = providerURL
        self.affiliateURL = affiliateURL
        self.sourceURL = sourceURL
        self.researchedAt = try requiredString("researchedAt")
        self.curationNote = try requiredString("curationNote")
        self.sortOrder = sortOrder
    }
}

enum ISPPlanError: LocalizedError {
    case invalidDocument(String, String)
    case noPlans

    var errorDescription: String? {
        switch self {
        case .invalidDocument(let documentID, let field):
            "ISP plan \(documentID) has an invalid \(field) field."
        case .noPlans:
            "No internet plans are available right now."
        }
    }
}

struct ISPPlanService {
    func fetchPlans() async throws -> [ISPPlan] {
        let snapshot = try await FirestoreRuntime.provider.acquire().firestore
            .collection("ispPlans")
            .getDocuments()
        let plans = try snapshot.documents.map(ISPPlan.init(document:))
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !plans.isEmpty else { throw ISPPlanError.noPlans }
        return plans
    }
}
