//
//  MoversFlowViewModel.swift
//  Peezy 4.0
//

import CoreLocation
import FirebaseFirestore
import Foundation
import Observation

@MainActor
@Observable
final class MoversFlowViewModel {
    private(set) var stage: MoversFlowStage = .loading
    private(set) var identity: PeezyIdentity?
    private(set) var scope: MoveScope?
    private(set) var quotes: [MoversVendorQuote] = []
    private(set) var selectedQuote: MoversVendorQuote?
    private(set) var errorMessage: String?
    private(set) var isSubmitting = false
    private(set) var hasInventory = false
    private(set) var isQuoteRequest = false

    var bedroomsAnswer = "1 Bedroom"
    var destinationBedroomsAnswer = "1 Bedroom"
    var hasStorage = false
    var storageSize = "Small"
    var storageFullness = "1/2"
    var originAccessAnswer = "Unknown"
    var destinationAccessAnswer = "Unknown"
    var originLongCarry = false
    var destinationLongCarry = false
    var packedStatus: PackedStatus = .unknown
    var coveragePreference = "standard"
    var requestedArrivalWindow = ""
    var notes = ""

    private var userId = ""
    private var taskId = ""
    private var inventoryItems: [InventoryItem] = []
    private var unresolvedUnseenRoomCount = 0
    private var assessment: [String: Any] = [:]
    private let actionService = TaskActionService()

    var canCompare: Bool {
        let window = requestedArrivalWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        let storageComplete = !hasStorage || (!storageSize.isEmpty && !storageFullness.isEmpty)
        let fallbackComplete = hasInventory || (!bedroomsAnswer.isEmpty && !destinationBedroomsAnswer.isEmpty)
        return !window.isEmpty && storageComplete && fallbackComplete
    }

    var cubeSummary: String {
        guard let scope else { return "Calculating scope" }
        return "~\(Int(scope.cubicFeet.rounded())) cu ft"
    }

    var homeSummary: String {
        bedroomsAnswer.isEmpty ? "Home details pending" : bedroomsAnswer
    }

    var accessSummary: String {
        "\(Self.shortAccess(originAccessAnswer)) at origin · \(Self.shortAccess(destinationAccessAnswer)) at destination"
    }

    var storageSummary: String? {
        guard hasStorage else { return nil }
        return "\(storageSize) storage · \(storageFullness) full"
    }

    var priceBasis: String {
        scope?.cubeSource == .inventoryScan ? "your scan" : "home details"
    }

    func prepare(userId: String, taskId: String) async {
        self.userId = userId
        self.taskId = taskId
        errorMessage = nil

        guard !userId.isEmpty else {
            fail("Sign in again to continue booking your movers.")
            return
        }

        identity = await IdentityService.shared.loadOrMigrate(userId: userId)
        guard identity != nil else {
            fail("Your move details are missing. Add both addresses in Settings, then try again.")
            return
        }

        do {
            assessment = try await loadAssessment(userId: userId)
            hydrateRefinementInputs()
            try await reloadInventory()
            if hasInventory {
                try await rebuildScope()
                transition(to: .scope)
            } else {
                transition(to: .capture)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func captureFinished() async {
        do {
            try await reloadInventory()
            guard hasInventory else {
                fail("The scan finished without any move items. Try the scan again or use home details.")
                return
            }
            try await rebuildScope()
            transition(to: .scope)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func useHomeDetailsInstead() async {
        do {
            inventoryItems = []
            unresolvedUnseenRoomCount = 0
            hasInventory = false
            try await rebuildScope()
            transition(to: .scope)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func showCapture() {
        transition(to: .capture)
    }

    func showRefinement() {
        transition(to: .refinement)
    }

    func prepareComparisons() async {
        guard canCompare else { return }
        do {
            try await rebuildScope()
            guard let scope, let identity else { throw FlowError.missingScope }

            if PricingEngine.quoteRoute(moveDistanceMiles: identity.moveDistanceMiles) == .conciergeQuote {
                isQuoteRequest = true
                quotes = []
                selectedQuote = nil
                transition(to: .comparison)
                return
            }

            isQuoteRequest = false

            let activeVendors = try await VendorStore().activeVendors(for: .movers)
            let eligibleVendors = try await vendorsWithinRadius(activeVendors, identity: identity)
            let prepared = eligibleVendors.compactMap { vendor -> MoversVendorQuote? in
                guard let estimate = PricingEngine.estimate(
                    scope: scope,
                    rateCard: PricingRateCard(vendorRateCard: vendor.rateCard)
                ), let tier = valuationTier(for: vendor)
                else { return nil }
                return MoversVendorQuote(vendor: vendor, estimate: estimate, valuationTier: tier)
            }
            quotes = prepared.sorted {
                if $0.estimate.range.low == $1.estimate.range.low {
                    return $0.vendor.name < $1.vendor.name
                }
                return $0.estimate.range.low < $1.estimate.range.low
            }
            guard !quotes.isEmpty else { throw FlowError.noEligibleVendors }
            transition(to: .comparison)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func select(_ quote: MoversVendorQuote) {
        selectedQuote = quote
    }

    func showBooking() {
        guard selectedQuote != nil else { return }
        transition(to: .booking)
    }

    func submitBooking() async {
        guard !isSubmitting,
              let identity,
              let scope,
              let selectedQuote
        else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let payload = MoversBookingPayload(
            identity: identity,
            scope: scope,
            quote: selectedQuote,
            quoteRequest: false,
            requestedArrivalWindow: requestedArrivalWindow.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var workflowAnswers = WorkflowAnswers(workflowId: "book_movers")
        workflowAnswers.answers = payload.workflowAnswers()

        do {
            let response = try await WorkflowService().submitAnswers(
                workflowId: "book_movers",
                answers: workflowAnswers,
                userId: userId
            )
            guard response.success else { throw FlowError.submissionRejected }
            transition(to: .confirmation)
        } catch {
            errorMessage = "We couldn't send the booking request. Nothing was booked—please try again. \(error.localizedDescription)"
        }
    }

    func submitQuoteRequest() async {
        guard !isSubmitting,
              isQuoteRequest,
              let identity,
              let scope
        else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let payload = MoversBookingPayload(
            identity: identity,
            scope: scope,
            quote: nil,
            quoteRequest: true,
            requestedArrivalWindow: requestedArrivalWindow.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var workflowAnswers = WorkflowAnswers(workflowId: "book_movers")
        workflowAnswers.answers = payload.workflowAnswers()

        do {
            let response = try await WorkflowService().submitAnswers(
                workflowId: "book_movers",
                answers: workflowAnswers,
                userId: userId
            )
            guard response.success else { throw FlowError.submissionRejected }
            transition(to: .confirmation)
        } catch {
            errorMessage = "We couldn't send the quote request. Nothing was submitted—please try again. \(error.localizedDescription)"
        }
    }

    func goBack() {
        switch stage {
        case .scope: transition(to: .capture)
        case .refinement: transition(to: .scope)
        case .comparison: transition(to: .refinement)
        case .booking: transition(to: .comparison)
        default: break
        }
    }

    func retry() async {
        await prepare(userId: userId, taskId: taskId)
    }

    func markComplete() {
        transition(to: .confirmation, persistedStage: .complete)
    }

    private func reloadInventory() async throws {
        let manager = InventorySessionManager()
        await manager.loadExistingInventory()
        inventoryItems = manager.allItems
        unresolvedUnseenRoomCount = manager.coverageReport.unresolvedRoomCount
        hasInventory = inventoryItems.contains(where: \.shouldMove)
    }

    private func rebuildScope() async throws {
        guard let identity else { throw FlowError.missingIdentity }
        var refinedAssessment = assessment
        refinedAssessment["currentBedrooms"] = bedroomsAnswer
        refinedAssessment["newBedrooms"] = destinationBedroomsAnswer
        refinedAssessment["hasStorage"] = hasStorage ? "Yes" : "No"
        refinedAssessment["storageSize"] = storageSize
        refinedAssessment["storageFullness"] = storageFullness
        refinedAssessment["currentFloorAccess"] = originAccessAnswer == "Unknown" ? "" : originAccessAnswer
        refinedAssessment["newFloorAccess"] = destinationAccessAnswer == "Unknown" ? "" : destinationAccessAnswer

        let base = await MoveScopeFactory.makeScope(
            inventoryItems: inventoryItems,
            assessment: refinedAssessment,
            identity: identity,
            packedStatus: packedStatus,
            unresolvedUnseenRoomCount: unresolvedUnseenRoomCount
        )
        scope = MoveScope(
            cubicFeet: base.cubicFeet,
            driveMinutes: base.driveMinutes,
            originAccess: MoveAccess(
                route: base.originAccess.route,
                elevatorReserved: base.originAccess.elevatorReserved,
                longCarry: originLongCarry
            ),
            destAccess: MoveAccess(
                route: base.destAccess.route,
                elevatorReserved: base.destAccess.elevatorReserved,
                longCarry: destinationLongCarry
            ),
            packedStatus: base.packedStatus,
            specialtyItems: base.specialtyItems,
            storageStop: base.storageStop,
            serviceDate: base.serviceDate,
            cubeSource: base.cubeSource,
            unresolvedUnseenRoomCount: base.unresolvedUnseenRoomCount
        )
    }

    private func hydrateRefinementInputs() {
        bedroomsAnswer = Self.nonempty(assessment["currentBedrooms"] as? String) ?? "1 Bedroom"
        destinationBedroomsAnswer = Self.nonempty(assessment["newBedrooms"] as? String) ?? "1 Bedroom"
        hasStorage = (assessment["hasStorage"] as? String)?.lowercased() == "yes"
        storageSize = Self.normalizedStorageSize(assessment["storageSize"] as? String)
        storageFullness = Self.normalizedStorageFullness(assessment["storageFullness"] as? String)
        originAccessAnswer = Self.normalizedAccess(assessment["currentFloorAccess"] as? String)
        destinationAccessAnswer = Self.normalizedAccess(assessment["newFloorAccess"] as? String)
    }

    private func loadAssessment(userId: String) async throws -> [String: Any] {
        let snapshot = try await Firestore.firestore().collection("users").document(userId)
            .collection("user_assessments").limit(to: 1).getDocuments()
        return snapshot.documents.first?.data() ?? [:]
    }

    private func vendorsWithinRadius(_ vendors: [Vendor], identity: PeezyIdentity) async throws -> [Vendor] {
        guard let origin = identity.currentAddress,
              !origin.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw FlowError.missingOrigin }

        let geocoder = CLGeocoder()
        guard let originLocation = try await geocoder.geocodeAddressString(origin.raw).first?.location else {
            throw FlowError.locationUnavailable
        }

        var result: [Vendor] = []
        for vendor in vendors {
            guard let centerLocation = try await geocoder
                .geocodeAddressString(vendor.serviceRadius.center).first?.location
            else { continue }
            let miles = originLocation.distance(from: centerLocation) / 1_609.344
            if miles <= vendor.serviceRadius.miles { result.append(vendor) }
        }
        return result
    }

    private func valuationTier(for vendor: Vendor) -> VendorValuationTier? {
        vendor.rateCard.valuationTiers.first(where: { $0.id == coveragePreference })
            ?? vendor.rateCard.valuationTiers.first
    }

    private func transition(to next: MoversFlowStage, persistedStage: TaskStage? = nil) {
        stage = next
        guard !taskId.isEmpty,
              let taskStage = persistedStage ?? next.persistedTaskStage
        else { return }
        let id = taskId
        Task { await actionService.setStage(taskId: id, stage: taskStage) }
    }

    private func fail(_ message: String) {
        errorMessage = message
        stage = .failure
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func normalizedStorageSize(_ value: String?) -> String {
        switch value?.lowercased() {
        case "medium", "10x10": "Medium"
        case "large", "10x20": "Large"
        default: "Small"
        }
    }

    private static func normalizedStorageFullness(_ value: String?) -> String {
        switch value?.lowercased() {
        case "1/4", "quarter": "1/4"
        case "3/4", "three_quarter": "3/4"
        case "full": "Full"
        default: "1/2"
        }
    }

    private static func normalizedAccess(_ value: String?) -> String {
        switch value?.lowercased() {
        case "ground floor": "Ground Floor"
        case "stairs": "Stairs"
        case "elevator": "Elevator"
        case "reserved elevator": "Reserved Elevator"
        default: "Unknown"
        }
    }

    private static func shortAccess(_ value: String) -> String {
        value == "Unknown" ? "access TBD" : value.lowercased()
    }

    private enum FlowError: LocalizedError {
        case missingIdentity
        case missingScope
        case missingOrigin
        case locationUnavailable
        case noEligibleVendors
        case submissionRejected

        var errorDescription: String? {
            switch self {
            case .missingIdentity: "Your identity details could not be loaded."
            case .missingScope: "Your move scope could not be calculated."
            case .missingOrigin: "Add your current address before comparing movers."
            case .locationUnavailable: "We couldn't verify which movers serve your current address."
            case .noEligibleVendors: "No active movers currently cover this address."
            case .submissionRejected: "The booking service did not accept the request."
            }
        }
    }
}
