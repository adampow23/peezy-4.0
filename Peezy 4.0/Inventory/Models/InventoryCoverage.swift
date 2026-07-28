import Foundation

enum CoverageRoomKind: String, Equatable {
    case livingRoom
    case kitchen
    case bathroom
    case bedroom
    case garage
    case basement
    case other
}

struct ExpectedCoverageRoom: Equatable, Identifiable {
    let id: String
    let kind: CoverageRoomKind
    let displayName: String
}

struct InventoryCoverageReport: Equatable {
    let scannedRoomNames: [String]
    let unresolvedRooms: [ExpectedCoverageRoom]

    var unresolvedRoomCount: Int { unresolvedRooms.count }
}

struct CoverageExpectationInputs: Equatable {
    let bedroomsAnswer: String
    let dwellingType: String
}

enum InventoryCoverage {
    static let confirmedMetadataKey = "coverageConfirmed"

    /// Product grouping built from the room labels standardized by RESO's
    /// ImageOf/RoomType vocabulary. Peezy intentionally collapses living-space
    /// variants into one expected "Living Room" slot and common capture labels
    /// into the other five coverage kinds.
    /// Source: https://dd.reso.org/DD1.7/Media/ImageOf/
    private static let synonymKinds: [String: CoverageRoomKind] = {
        var result: [String: CoverageRoomKind] = [:]

        func register(_ kind: CoverageRoomKind, _ labels: [String]) {
            for label in labels { result[label] = kind }
        }

        register(.livingRoom, [
            "living room", "family room", "den", "great room", "lounge",
            "sitting room", "recreation room", "rec room"
        ])
        register(.kitchen, ["kitchen", "kitchenette"])
        register(.bathroom, [
            "bathroom", "bath", "half bath", "powder room", "ensuite",
            "en suite", "primary bathroom", "master bathroom", "guest bathroom"
        ])
        register(.bedroom, [
            "bedroom", "primary bedroom", "master bedroom", "guest bedroom",
            "guest room", "nursery", "kids bedroom", "kid bedroom", "child bedroom"
        ])
        register(.garage, ["garage", "attached garage", "detached garage"])
        register(.basement, ["basement", "finished basement", "unfinished basement", "cellar"])
        return result
    }()

    static func expectedRooms(
        bedroomsAnswer: String,
        dwellingType: String
    ) -> [ExpectedCoverageRoom] {
        var rooms = [
            ExpectedCoverageRoom(id: "living-room", kind: .livingRoom, displayName: "Living Room"),
            ExpectedCoverageRoom(id: "kitchen", kind: .kitchen, displayName: "Kitchen"),
            ExpectedCoverageRoom(id: "bathroom", kind: .bathroom, displayName: "Bathroom")
        ]

        let bedroomCount = parsedBedroomCount(from: bedroomsAnswer)
        if bedroomCount > 0 {
            for index in 1...bedroomCount {
                let label = bedroomCount == 1 ? "Bedroom" : "Bedroom \(index)"
                rooms.append(ExpectedCoverageRoom(
                    id: "bedroom-\(index)",
                    kind: .bedroom,
                    displayName: label
                ))
            }
        }

        if normalizedLabel(dwellingType) == "house" {
            rooms.append(ExpectedCoverageRoom(id: "garage", kind: .garage, displayName: "Garage"))
            rooms.append(ExpectedCoverageRoom(id: "basement", kind: .basement, displayName: "Basement"))
        }
        return rooms
    }

    /// `userKnowledge` is the current per-field assessment projection. The
    /// auto-ID assessment collection is only a legacy fallback: when it has
    /// more than one document, there is no ordering contract and guessing a
    /// historical answer would be worse than leaving that expectation absent.
    static func expectationInputs(
        userKnowledgeData: [String: Any]?,
        legacyAssessmentDocuments: [[String: Any]]
    ) -> CoverageExpectationInputs {
        let entries = userKnowledgeData?["entries"] as? [String: Any]

        func currentValue(_ key: String) -> String? {
            guard let entry = entries?[key] as? [String: Any],
                  let value = entry["value"] as? String
            else { return nil }
            return nonempty(value)
        }

        let unambiguousLegacy = legacyAssessmentDocuments.count == 1
            ? legacyAssessmentDocuments[0]
            : [:]
        return CoverageExpectationInputs(
            bedroomsAnswer: currentValue("currentBedrooms")
                ?? nonempty(unambiguousLegacy["currentBedrooms"] as? String)
                ?? "",
            dwellingType: currentValue("currentDwellingType")
                ?? nonempty(unambiguousLegacy["currentDwellingType"] as? String)
                ?? ""
        )
    }

    static func normalizedKind(for roomName: String) -> CoverageRoomKind {
        let normalized = normalizedLabel(roomName)
        if let exact = synonymKinds[normalized] { return exact }

        let withoutNumbers = normalized
            .split(separator: " ")
            .filter { token in !token.allSatisfy(\.isNumber) && token != "#" }
            .joined(separator: " ")
        if let base = synonymKinds[withoutNumbers] { return base }

        if normalized.contains("bedroom") { return .bedroom }
        if normalized.contains("bathroom") { return .bathroom }
        if normalized.contains("garage") { return .garage }
        if normalized.contains("basement") { return .basement }
        return .other
    }

    static func report(
        expectedRooms: [ExpectedCoverageRoom],
        scannedRoomNames: [String],
        confirmedRoomIDs: Set<String>
    ) -> InventoryCoverageReport {
        var matchedIDs: Set<String> = []

        for scannedName in scannedRoomNames {
            let kind = normalizedKind(for: scannedName)
            guard kind != .other else { continue }

            let unmatched = expectedRooms.filter { room in
                room.kind == kind && !matchedIDs.contains(room.id)
            }
            guard !unmatched.isEmpty else { continue }

            if kind == .bedroom,
               let ordinal = bedroomOrdinal(from: scannedName) {
                if let exact = unmatched.first(where: { $0.id == "bedroom-\(ordinal)" }) {
                    matchedIDs.insert(exact.id)
                }
                // A duplicate or out-of-range numbered label is a scanned
                // extra. It must never consume a different expected bedroom.
                continue
            }

            // A later generic scan should fill an unresolved slot before a slot
            // the user already marked as empty.
            let match = unmatched.first(where: { !confirmedRoomIDs.contains($0.id) })
                ?? unmatched[0]
            matchedIDs.insert(match.id)
        }

        let validExpectedIDs = Set(expectedRooms.map(\.id))
        let effectiveConfirmedIDs = confirmedRoomIDs.intersection(validExpectedIDs)
        let unresolved = expectedRooms.filter {
            !matchedIDs.contains($0.id) && !effectiveConfirmedIDs.contains($0.id)
        }
        return InventoryCoverageReport(
            scannedRoomNames: scannedRoomNames,
            unresolvedRooms: unresolved
        )
    }

    static func metadata(confirmedRoomIDs: Set<String>) -> [String: Any] {
        [confirmedMetadataKey: confirmedRoomIDs.sorted()]
    }

    static func confirmedRoomIDs(fromMetadata metadata: [String: Any]) -> Set<String> {
        Set(metadata[confirmedMetadataKey] as? [String] ?? [])
    }

    private static func parsedBedroomCount(from answer: String) -> Int {
        guard let token = answer.split(whereSeparator: { !$0.isNumber }).first,
              let value = Int(token)
        else { return 0 }
        return max(value, 0)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bedroomOrdinal(from roomName: String) -> Int? {
        guard normalizedKind(for: roomName) == .bedroom,
              let token = roomName.split(whereSeparator: { !$0.isNumber }).first
        else { return nil }
        return Int(token)
    }

    private static func normalizedLabel(_ label: String) -> String {
        label
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
