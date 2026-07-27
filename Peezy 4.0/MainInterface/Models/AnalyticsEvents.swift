import FirebaseAnalytics
import Foundation
import StoreKit

enum AnalyticsEvents {
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
        Analytics.setUserProperty(
            hasSubscription ? "true" : "false",
            forName: "has_subscription"
        )
    }

    private static func log(_ name: Name, _ parameters: [String: Any]? = nil) {
        Analytics.logEvent(name.rawValue, parameters: parameters)

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
