import Foundation

// Standalone executable tests for the pure coverage model. Run with:
// swiftc InventoryCoverage.swift Tests/CoverageCheckTests.swift -o /tmp/peezy_coverage_tests && /tmp/peezy_coverage_tests

@main
struct CoverageCheckTests {
    static func main() {
        var failures: [String] = []
        var checksRun = 0

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checksRun += 1
            if condition() {
                print("PASS  \(name)")
            } else {
                failures.append(name)
                print("FAIL  \(name)")
            }
        }

        let house = InventoryCoverage.expectedRooms(
            bedroomsAnswer: "3 Bedrooms",
            dwellingType: "House"
        )
        check(
            house.map(\.displayName) == [
                "Living Room", "Kitchen", "Bathroom",
                "Bedroom 1", "Bedroom 2", "Bedroom 3",
                "Garage", "Basement"
            ],
            "house expectation includes standard rooms, numbered bedrooms, garage, and basement"
        )

        for dwelling in ["Apartment", "Condo", "Townhome"] {
            let rooms = InventoryCoverage.expectedRooms(
                bedroomsAnswer: "2 Bedrooms",
                dwellingType: dwelling
            )
            check(!rooms.contains { $0.id == "garage" || $0.id == "basement" },
                  "\(dwelling) excludes garage and basement")
        }
        let missingBedroomAnswer = InventoryCoverage.expectedRooms(
            bedroomsAnswer: "",
            dwellingType: "Apartment"
        )
        check(missingBedroomAnswer.map(\.displayName) == ["Living Room", "Kitchen", "Bathroom"],
              "absent assessment bedroom count contributes zero bedroom expectations")

        let currentInputs = InventoryCoverage.expectationInputs(
            userKnowledgeData: [
                "entries": [
                    "currentBedrooms": ["value": "3 Bedrooms"],
                    "currentDwellingType": ["value": "House"]
                ]
            ],
            legacyAssessmentDocuments: [
                ["currentBedrooms": "1 Bedroom", "currentDwellingType": "Apartment"],
                ["currentBedrooms": "2 Bedrooms", "currentDwellingType": "Condo"]
            ]
        )
        check(
            currentInputs == CoverageExpectationInputs(
                bedroomsAnswer: "3 Bedrooms",
                dwellingType: "House"
            ),
            "current userKnowledge values win over ambiguous historical assessments"
        )
        let ambiguousLegacyInputs = InventoryCoverage.expectationInputs(
            userKnowledgeData: nil,
            legacyAssessmentDocuments: [
                ["currentBedrooms": "1 Bedroom", "currentDwellingType": "Apartment"],
                ["currentBedrooms": "2 Bedrooms", "currentDwellingType": "House"]
            ]
        )
        check(
            ambiguousLegacyInputs == CoverageExpectationInputs(
                bedroomsAnswer: "",
                dwellingType: ""
            ),
            "multiple legacy assessments never select an arbitrary historical answer"
        )
        let singleLegacyInputs = InventoryCoverage.expectationInputs(
            userKnowledgeData: nil,
            legacyAssessmentDocuments: [
                ["currentBedrooms": "2 Bedrooms", "currentDwellingType": "Townhome"]
            ]
        )
        check(
            singleLegacyInputs == CoverageExpectationInputs(
                bedroomsAnswer: "2 Bedrooms",
                dwellingType: "Townhome"
            ),
            "one legacy assessment remains a safe compatibility fallback"
        )

        let livingSynonyms = ["Living Room", "family room", "DEN", "Great Room"]
        for synonym in livingSynonyms {
            check(
                InventoryCoverage.normalizedKind(for: synonym) == .livingRoom,
                "\(synonym) normalizes to living room"
            )
        }
        check(InventoryCoverage.normalizedKind(for: "Primary Bedroom") == .bedroom,
              "primary bedroom normalizes to bedroom")
        check(InventoryCoverage.normalizedKind(for: "Powder Room") == .bathroom,
              "powder room normalizes to bathroom")
        check(InventoryCoverage.normalizedKind(for: "Kitchenette") == .kitchen,
              "kitchenette normalizes to kitchen")
        check(InventoryCoverage.normalizedKind(for: "Cellar") == .basement,
              "cellar normalizes to basement")
        check(InventoryCoverage.normalizedKind(for: "Attached Garage") == .garage,
              "attached garage normalizes to garage")

        let initial = InventoryCoverage.report(
            expectedRooms: house,
            scannedRoomNames: ["Family Room", "Kitchen", "Primary Bedroom", "Office"],
            confirmedRoomIDs: []
        )
        check(initial.scannedRoomNames == ["Family Room", "Kitchen", "Primary Bedroom", "Office"],
              "scanned extras remain in the scanned list")
        check(initial.unresolvedRooms.map(\.displayName) == [
            "Bathroom", "Bedroom 2", "Bedroom 3", "Garage", "Basement"
        ], "missing bedrooms are numbered and expected rooms stay unresolved")

        let duplicateOrdinal = InventoryCoverage.report(
            expectedRooms: house,
            scannedRoomNames: ["Bedroom 2", "Bedroom 2"],
            confirmedRoomIDs: []
        )
        check(
            duplicateOrdinal.unresolvedRooms
                .filter { $0.kind == .bedroom }
                .map(\.displayName) == ["Bedroom 1", "Bedroom 3"],
            "a duplicate numbered bedroom stays an extra instead of consuming another bedroom"
        )
        let outOfRangeOrdinal = InventoryCoverage.report(
            expectedRooms: house,
            scannedRoomNames: ["Bedroom 4"],
            confirmedRoomIDs: []
        )
        check(
            outOfRangeOrdinal.unresolvedRooms
                .filter { $0.kind == .bedroom }
                .map(\.displayName) == ["Bedroom 1", "Bedroom 2", "Bedroom 3"],
            "an out-of-range numbered bedroom stays an extra"
        )

        let clipTarget = initial.unresolvedRooms.first { $0.id == "bedroom-2" }!
        let afterClip = InventoryCoverage.report(
            expectedRooms: house,
            scannedRoomNames: ["Family Room", "Kitchen", "Primary Bedroom", "Office", clipTarget.displayName],
            confirmedRoomIDs: []
        )
        check(!afterClip.unresolvedRooms.contains { $0.id == clipTarget.id },
              "completed Add a clip scan resolves its expected room")

        let confirmed = InventoryCoverage.confirmedRoomIDs(
            fromMetadata: InventoryCoverage.metadata(
                confirmedRoomIDs: ["basement", "garage"]
            )
        )
        check(confirmed == Set(["basement", "garage"]),
              "Nothing there confirmation round-trips through metadata")
        let afterNothingThere = InventoryCoverage.report(
            expectedRooms: house,
            scannedRoomNames: initial.scannedRoomNames,
            confirmedRoomIDs: confirmed
        )
        check(!afterNothingThere.unresolvedRooms.contains { $0.id == "basement" || $0.id == "garage" },
              "confirmed rooms resolve without a scan")

        if failures.isEmpty {
            print("\nCoverageCheckTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nCoverageCheckTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }
}
