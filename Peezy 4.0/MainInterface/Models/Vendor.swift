import Foundation
import FirebaseFirestore

/// Backend-owned service provider record. Phase A seeds movers; later verticals
/// reuse this rate-card envelope rather than introducing vertical-specific data.
struct Vendor: Codable, Equatable, Identifiable {
    enum Vertical: String, Codable, Equatable {
        case movers
    }

    let vendorId: String
    let name: String
    let vertical: Vertical
    let serviceRadius: VendorServiceRadius
    let rateCard: VendorRateCard
    let accountability: VendorAccountability
    let active: Bool

    var id: String { vendorId }
}

struct VendorServiceRadius: Codable, Equatable {
    let center: String
    let miles: Double
}

struct VendorRateCard: Codable, Equatable {
    let hourlyByCrew: CrewHourlyRates
    let tripChargeModel: VendorTripCharge
    let minimumHours: Double
    let clockPolicy: String
    let materials: VendorMaterials
    let valuationTiers: [VendorValuationTier]
    let surcharges: VendorSurcharges
    let specialtyFees: [String: Double]
    let blackoutDates: [String]
}

struct CrewHourlyRates: Codable, Equatable {
    let two: Double
    let three: Double
    let four: Double

    private enum CodingKeys: String, CodingKey {
        case two = "2"
        case three = "3"
        case four = "4"
    }

    func rate(for crewSize: Int) -> Double? {
        switch crewSize {
        case 2: two
        case 3: three
        case 4: four
        default: nil
        }
    }
}

struct VendorTripCharge: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case flat
    }

    let kind: Kind
    let amount: Double
}

struct VendorMaterials: Codable, Equatable {
    let included: Bool
    let boxBundle: Double
    let packingPaperBundle: Double
}

struct VendorValuationTier: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let coveragePerPound: Double
    let additionalCost: Double
}

struct VendorSurcharges: Codable, Equatable {
    let weekend: Double
    let monthEnd: Double
    let peakSeason: Double
}

struct VendorStrike: Codable, Equatable {
    enum Severity: String, Codable, Equatable {
        case high
        case dayOfPriceChange
    }

    enum Status: String, Codable, Equatable {
        case pendingReview
        case confirmed
        case dismissed
    }

    let date: Date
    let source: String
    let severity: Severity
    let status: Status
    let note: String
}

struct VendorAccountability: Codable, Equatable {
    let standardsVersion: String
    let strikes: [VendorStrike]

    init(standardsVersion: String, strikes: [VendorStrike]) {
        self.standardsVersion = standardsVersion
        self.strikes = strikes
    }

    private enum CodingKeys: String, CodingKey {
        case standardsVersion
        case strikes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standardsVersion = try container.decode(String.self, forKey: .standardsVersion)
        if let strikes = try? container.decode([VendorStrike].self, forKey: .strikes) {
            self.strikes = strikes
            return
        }

        let legacyCount = max(0, (try? container.decode(Int.self, forKey: .strikes)) ?? 0)
        strikes = (0..<legacyCount).map { index in
            VendorStrike(
                date: Date(timeIntervalSince1970: 0),
                source: "legacy-\(index + 1)",
                severity: .high,
                status: .confirmed,
                note: "Migrated from legacy strike count"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(standardsVersion, forKey: .standardsVersion)
        try container.encode(strikes, forKey: .strikes)
    }
}

/// Direct Firestore transport for backend-owned vendor rate cards. The active
/// query is mirrored by a defensive in-memory filter so inactive vendors never
/// reach comparison or booking code if a stale snapshot is returned.
struct VendorStore {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func activeVendors(for vertical: Vendor.Vertical) async throws -> [Vendor] {
        let snapshot = try await db.collection("vendors")
            .whereField("vertical", isEqualTo: vertical.rawValue)
            .whereField("active", isEqualTo: true)
            .getDocuments()
        let vendors = try snapshot.documents.map { try $0.data(as: Vendor.self) }
        return Self.active(vendors, for: vertical)
    }

    static func active(_ vendors: [Vendor], for vertical: Vendor.Vertical) -> [Vendor] {
        vendors
            .filter { $0.active && $0.vertical == vertical }
            .sorted { $0.vendorId < $1.vendorId }
    }
}
