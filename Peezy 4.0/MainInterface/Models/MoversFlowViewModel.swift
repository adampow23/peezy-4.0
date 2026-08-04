//
//  MoversFlowViewModel.swift
//  Peezy 4.0
//

import CoreLocation
import FirebaseFirestore
import Foundation
import Observation

struct MoversResearchGuidanceCopy: Equatable {
    let title: String
    let body: String
    let rangeLabel: String
    let researchPointer: String
}

enum MoversEstimateBoundaryReason: Equatable {
    case longDistance
    case physicalHours

    var copy: MoversResearchGuidanceCopy {
        switch self {
        case .longDistance:
            MoversResearchGuidanceCopy(
                title: "Long-distance mover costs have a wide range",
                body: "Route, shipment weight, dates, access, and service level can move the total substantially.",
                rangeLabel: "Wide — quote-dependent",
                researchPointer: "Compare at least three FMCSA-registered movers. Ask for a written binding or not-to-exceed estimate, every access or specialty fee, and what can change the total."
            )
        case .physicalHours:
            MoversResearchGuidanceCopy(
                title: "This move is beyond a standard local estimate",
                body: "A large load, complex access, or specialty handling makes the range wider than a standard local quote.",
                rangeLabel: "Wide — scope-dependent",
                researchPointer: "Compare at least three movers that can staff the load. Ask each one for its crew plan, a written range, included specialty handling, and what can change the total."
            )
        }
    }
}

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
    private(set) var isResearchGuidance = false
    private(set) var estimateBoundaryReason: MoversEstimateBoundaryReason?

    var bedroomsAnswer = "1 Bedroom"
    var destinationBedroomsAnswer = "1 Bedroom"
    var hasStorage = false
    var storageSize = "Small"
    var storageFullness = "1/2"
    var storageStopOnMovingDay = false
    var storageUnitAddress = ""
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
    private var baselineRefinementAnswers: [String: String] = [:]
    private var hasRefinementBaseline = false
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

    var totalCubicFeet: Double {
        scope?.cubicFeet ?? 0
    }

    var moveDistanceMiles: Double? {
        identity?.moveDistanceMiles
    }

    var homeSummary: String {
        bedroomsAnswer.isEmpty ? "Home details pending" : bedroomsAnswer
    }

    var accessSummary: String {
        "\(Self.shortAccess(originAccessAnswer)) at origin · \(Self.shortAccess(destinationAccessAnswer)) at destination"
    }

    var storageSummary: String? {
        guard hasStorage else { return nil }
        let stop = storageStopOnMovingDay ? " · moving-day stop" : ""
        return "\(storageSize) storage · \(storageFullness) full\(stop)"
    }

    var priceBasis: String {
        scope?.cubeSource == .inventoryScan ? "your scan" : "home details"
    }

    var researchGuidanceCopy: MoversResearchGuidanceCopy {
        (estimateBoundaryReason ?? .longDistance).copy
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
            baselineRefinementAnswers = refinementAnswers
            hasRefinementBaseline = true
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

    func captureDismissed() async {
        do {
            try await reloadInventory()
            if hasInventory {
                try await rebuildScope()
                transition(to: .scope)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    var flowProgressSnapshot: FlowProgressSnapshot {
        var recorded: [String: [String]] = hasRefinementBaseline
            ? refinementAnswers.filter { baselineRefinementAnswers[$0.key] != $0.value }
                .mapValues { [$0] }
            : [:]
        if !requestedArrivalWindow.isEmpty {
            recorded["requested_arrival_window"] = [requestedArrivalWindow]
        }
        if !notes.isEmpty {
            recorded["notes"] = [notes]
        }
        if let selectedQuote {
            recorded["selected_quote"] = [selectedQuote.id]
        }
        switch stage {
        case .comparison, .booking, .confirmation:
            recorded["quote_route"] = [isResearchGuidance ? "research_guidance" : "vendor"]
        default:
            break
        }
        if let estimateBoundaryReason {
            recorded["estimate_boundary_reason"] = [
                estimateBoundaryReason == .longDistance ? "long_distance" : "physical_hours"
            ]
        }
        return FlowProgressSnapshot(
            path: ["movers.\(stage.rawValue)"],
            answers: recorded
        )
    }

    func restoreFlowProgress(_ snapshot: FlowProgressSnapshot) async {
        let values = snapshot.answers.compactMapValues(\.first)
        bedroomsAnswer = values["bedrooms"] ?? bedroomsAnswer
        destinationBedroomsAnswer = values["destination_bedrooms"] ?? destinationBedroomsAnswer
        hasStorage = values["has_storage"].map { $0 == "true" } ?? hasStorage
        storageSize = values["storage_size"] ?? storageSize
        storageFullness = values["storage_fullness"] ?? storageFullness
        storageStopOnMovingDay = values["storage_stop"]
            .map { $0 == "true" } ?? storageStopOnMovingDay
        storageUnitAddress = values["storage_address"] ?? storageUnitAddress
        originAccessAnswer = values["origin_access"] ?? originAccessAnswer
        destinationAccessAnswer = values["destination_access"] ?? destinationAccessAnswer
        originLongCarry = values["origin_long_carry"].map { $0 == "true" } ?? originLongCarry
        destinationLongCarry = values["destination_long_carry"]
            .map { $0 == "true" } ?? destinationLongCarry
        if let packed = values["packed_status"], let restored = PackedStatus(rawValue: packed) {
            packedStatus = restored
        }
        coveragePreference = values["coverage"] ?? coveragePreference
        requestedArrivalWindow = values["requested_arrival_window"] ?? requestedArrivalWindow
        notes = values["notes"] ?? notes
        if values["quote_route"] == "research_guidance" {
            isResearchGuidance = true
            estimateBoundaryReason = values["estimate_boundary_reason"] == "physical_hours"
                ? .physicalHours
                : .longDistance
        }

        guard let rawStage = snapshot.path.last?.split(separator: ".").last,
              let rawValue = Int(rawStage),
              let restoredStage = MoversFlowStage(rawValue: rawValue),
              restoredStage != .loading,
              restoredStage != .failure
        else { return }

        if restoredStage.rawValue >= MoversFlowStage.scope.rawValue, scope == nil {
            do {
                try await rebuildScope()
            } catch {
                fail(error.localizedDescription)
                return
            }
        }

        switch restoredStage {
        case .comparison where isResearchGuidance:
            stage = .comparison
        case .comparison:
            await prepareComparisons()
        case .booking:
            guard await restoreSelectedQuote(id: values["selected_quote"]) else { return }
            stage = .booking
        case .confirmation where isResearchGuidance:
            stage = .comparison
        case .confirmation:
            guard await restoreSelectedQuote(id: values["selected_quote"]) else { return }
            stage = .confirmation
        default:
            stage = restoredStage
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

            if PricingEngine.quoteRoute(moveDistanceMiles: identity.moveDistanceMiles) != .instantComparison {
                routeToResearchGuidance(reason: .longDistance)
                return
            }

            let activeVendors = try await VendorStore().activeVendors(for: .movers)
            let largestAvailableCrewSize = activeVendors
                .compactMap { $0.rateCard.hourlyByCrew.largestAvailableCrewSize }
                .max()
            if PricingEngine.quoteRoute(
                scope: scope,
                largestAvailableCrewSize: largestAvailableCrewSize
            ) != .instantComparison {
                routeToResearchGuidance(reason: .physicalHours)
                return
            }

            isResearchGuidance = false
            estimateBoundaryReason = nil
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
        refinedAssessment["storageStopOnMovingDay"] = storageStopOnMovingDay ? "Yes" : "No"
        refinedAssessment["storageUnitAddress"] = storageUnitAddress
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
            storageContents: base.storageContents,
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
        storageStopOnMovingDay = (assessment["storageStopOnMovingDay"] as? String)?.lowercased() == "yes"
        storageUnitAddress = Self.nonempty(assessment["storageUnitAddress"] as? String) ?? ""
        originAccessAnswer = Self.normalizedAccess(assessment["currentFloorAccess"] as? String)
        destinationAccessAnswer = Self.normalizedAccess(assessment["newFloorAccess"] as? String)
    }

    private var refinementAnswers: [String: String] {
        [
            "bedrooms": bedroomsAnswer,
            "destination_bedrooms": destinationBedroomsAnswer,
            "has_storage": String(hasStorage),
            "storage_size": storageSize,
            "storage_fullness": storageFullness,
            "storage_stop": String(storageStopOnMovingDay),
            "storage_address": storageUnitAddress,
            "origin_access": originAccessAnswer,
            "destination_access": destinationAccessAnswer,
            "origin_long_carry": String(originLongCarry),
            "destination_long_carry": String(destinationLongCarry),
            "packed_status": packedStatus.rawValue,
            "coverage": coveragePreference
        ]
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

    private func routeToResearchGuidance(reason: MoversEstimateBoundaryReason) {
        isResearchGuidance = true
        estimateBoundaryReason = reason
        quotes = []
        selectedQuote = nil
        transition(to: .comparison)
    }

    private func restoreSelectedQuote(id selectedQuoteID: String?) async -> Bool {
        await prepareComparisons()
        guard stage == .comparison,
              let selectedQuoteID,
              let restoredQuote = quotes.first(where: { $0.id == selectedQuoteID })
        else { return false }
        selectedQuote = restoredQuote
        return true
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
