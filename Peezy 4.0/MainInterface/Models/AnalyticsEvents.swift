import FirebaseAnalytics
import Foundation
import StoreKit

enum AnalyticsEvents {
    /// S4 (C2.2 telemetry barrier): once the client telemetry purge runs, no further event or user property leaves
    /// this process; only a fresh process collects again. Lock-guarded so any actor may close it.
    final class CollectionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var suspended = false
        var isSuspended: Bool { lock.withLock { suspended } }
        func suspend() { lock.withLock { suspended = true } }
        /// Admission and the synchronous SDK invocation under one critical section: a call admitted before `suspend()`
        /// completes before the barrier begins, and nothing is admitted afterwards (no check/use window).
        @discardableResult
        func admit(_ body: () -> Void) -> Bool {
            lock.withLock {
                guard !suspended else { return false }
                body()
                return true
            }
        }
    }

    nonisolated(unsafe) static let collection = CollectionGate()

    static func suspend() { collection.suspend() }
    static var isSuspended: Bool { collection.isSuspended }

    enum PaywallTrigger: String {
        case postAssessment = "post_assessment"
        case book
        case kit
        case concierge
    }

    private enum Name: String, CaseIterable {
        case explainerComplete = "explainer_complete"
        case assessmentStart = "assessment_start"
        case assessmentComplete = "assessment_complete"
        case doseFirstComplete = "dose_first_complete"
        case doseDayComplete = "dose_day_complete"
        case scanComplete = "scan_complete"
        case packingPlanCreated = "packing_plan_created"
        case paywallView = "paywall_view"
        case paywallConvert = "paywall_convert"
        case bookingSubmit = "booking_submit"
        case kitOfferView = "kit_offer_view"
        case kitOrder = "kit_order"
        case checkinComplete = "checkin_complete"
    }

    private enum Parameter {
        static let questionCount = "questionCount"
        static let dayNumber = "dayNumber"
        static let itemCount = "itemCount"
        static let cubicFeet = "cubicFeet"
        static let trigger = "trigger"
        static let productId = "productId"
        static let vertical = "vertical"
        static let isQuoteRequest = "isQuoteRequest"
        static let itemTotal = "itemTotal"
        static let flagged = "flagged"
    }

    static func explainerCompleted() {
        log(.explainerComplete)
    }

    static func assessmentStarted() {
        log(.assessmentStart)
    }

    static func assessmentCompleted(questionCount: Int) {
        log(.assessmentComplete, [Parameter.questionCount: questionCount])
    }

    static func firstDoseCompleted() {
        log(.doseFirstComplete)
    }

    static func dayDoseCompleted(dayNumber: Int) {
        log(.doseDayComplete, [Parameter.dayNumber: dayNumber])
    }

    static func scanCompleted(itemCount: Int, cubicFeet: Double) {
        log(.scanComplete, [
            Parameter.itemCount: itemCount,
            Parameter.cubicFeet: cubicFeet
        ])
    }

    static func packingPlanCreated() {
        log(.packingPlanCreated)
    }

    static func paywallViewed(trigger: PaywallTrigger) {
        log(.paywallView, [Parameter.trigger: trigger.rawValue])
    }

    static func paywallConverted(trigger: PaywallTrigger, productId: String) {
        log(.paywallConvert, [
            Parameter.trigger: trigger.rawValue,
            Parameter.productId: productId
        ])
    }

    static func recordNewPaywallConversion(
        trigger: PaywallTrigger,
        presentedAt: Date
    ) async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  transaction.purchaseDate >= presentedAt else { continue }
            paywallConverted(trigger: trigger, productId: transaction.productID)
            return
        }
    }

    static func bookingSubmitted(vertical: String, isQuoteRequest: Bool) {
        log(.bookingSubmit, [
            Parameter.vertical: vertical,
            Parameter.isQuoteRequest: isQuoteRequest
        ])
    }

    static func kitOfferViewed(itemTotal: Int) {
        log(.kitOfferView, [Parameter.itemTotal: itemTotal])
    }

    static func kitOrdered(itemTotal: Int) {
        log(.kitOrder, [Parameter.itemTotal: itemTotal])
    }

    static func checkinCompleted(flagged: Bool) {
        log(.checkinComplete, [Parameter.flagged: flagged])
    }

    static func setHasSubscription(_ hasSubscription: Bool) {
        collection.admit {
            Analytics.setUserProperty(
                hasSubscription ? "true" : "false",
                forName: "has_subscription"
            )
        }
    }

    /// Only the fixed parameter keys with scalar values reach the SDK: no UID, path, payload, or error text (C3 sink rule).
    static func sanitized(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters else { return nil }
        let allowed: Set<String> = [Parameter.questionCount, Parameter.dayNumber, Parameter.itemCount, Parameter.cubicFeet, Parameter.trigger, Parameter.productId, Parameter.vertical, Parameter.isQuoteRequest, Parameter.itemTotal, Parameter.flagged]
        return parameters.filter { key, value in allowed.contains(key) && (value is Int || value is Double || value is Bool || value is String) }
    }

    private static func log(_ name: Name, _ parameters: [String: Any]? = nil) {
        guard collection.admit({ Analytics.logEvent(name.rawValue, parameters: sanitized(parameters)) }) else { return }

        #if DEBUG
        let details = parameters?
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ") ?? ""
        let suffix = details.isEmpty ? "" : " \(details)"
        NSLog("[PeezyAnalytics] \(name.rawValue)\(suffix)")
        #endif
    }
}
