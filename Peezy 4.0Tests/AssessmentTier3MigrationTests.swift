import Testing
@testable import Peezy_4_0

struct AssessmentTier3MigrationTests {
    @MainActor
    @Test func assessmentExcludesMoverRefinementInputs() {
        let data = AssessmentDataManager()
        data.userName = "Test User"
        data.currentDwellingType = "Apartment"
        data.newDwellingType = "Condo"
        data.anyKids = "Yes"
        data.hireMovers = "No"
        data.hasDeclutter = "Yes"
        data.currentBedrooms = "3 Bedrooms"
        data.newBedrooms = "4 Bedrooms"
        data.hasStorage = "Yes"
        data.storageSize = "Large"
        data.storageFullness = "Full"

        let coordinator = AssessmentCoordinator(dataManager: data)
        let steps = coordinator.sequence.compactMap(\.inputStep)
        let migratedSteps: Set<AssessmentInputStep> = [
            .currentBedrooms,
            .newBedrooms,
            .hasStorage,
            .storageSize,
            .storageFullness
        ]

        #expect(steps.count == 26)
        #expect(migratedSteps.isDisjoint(with: steps))
        #expect(steps.contains(.currentFloorAccess))
        #expect(steps.contains(.newFloorAccess))
        #expect(steps.contains(.hasVehicles))
        #expect(steps.contains(.moveDateType))
    }
}
