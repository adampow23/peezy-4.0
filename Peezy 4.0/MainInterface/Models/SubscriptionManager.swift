//
//  SubscriptionManager.swift
//  Peezy
//
//  Manages all StoreKit 2 interactions: product fetching, purchasing,
//  entitlement tracking, and transaction listening.
//
//  Architecture:
//  - @MainActor singleton injected into SwiftUI via .environmentObject()
//  - Uses StoreKit 2 async/await API exclusively
//  - Listens for Transaction.updates on app launch for renewals/refunds
//  - Only calls Transaction.finish() after local state is updated
//

import Foundation
import SwiftUI
import Combine
import StoreKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SubscriptionManager()

    // MARK: - Product Identifiers

    enum ProductID: String, CaseIterable {
        /// The only product sold. Non-renewing subscription, 6-month access.
        case move = "peezy.plus.move"
        /// Legacy — no longer sold. Kept permanently so existing subscribers
        /// retain access (grandfathered). Do not remove.
        case weekly = "peezy.plus.weekly"
        case annual = "peezy.plus.annual"
    }

    /// Client-computed access term: StoreKit does not manage non-renewing duration.
    static let movePassTermMonths = 6

    // MARK: - Computed Subscription State

    var isSubscribed: Bool {
        subscriptionStatus.isActive
    }

    var isTrialActive: Bool {
        if case .trial = subscriptionStatus { return true }
        return false
    }

    // MARK: - Published State

    @Published var products: [Product] = []
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: PurchaseError? = nil
    @Published var isLoaded: Bool = false

    /// Whether the current Apple ID is eligible for the annual product's
    /// introductory free-trial offer. Refreshed after products load and
    /// after subscription status changes. Apple requires hiding free-trial
    /// copy from users who have already consumed the offer.
    @Published var isEligibleForAnnualTrial: Bool = false

    // MARK: - Subscription Status

    enum SubscriptionStatus: Equatable {
        case notSubscribed
        case trial(productId: String, expirationDate: Date)
        case subscribed(productId: String, expirationDate: Date)
        case expired
        case revoked

        var isActive: Bool {
            switch self {
            case .trial, .subscribed: return true
            default: return false
            }
        }
    }

    // MARK: - Purchase Result

    enum PurchaseResult {
        case success
        case cancelled
        case pending
        case failed(Error)
    }

    // MARK: - Purchase Error

    enum PurchaseError: LocalizedError {
        case productNotFound
        case purchaseFailed(underlying: Error)
        case purchaseCancelled
        case purchasePending
        case verificationFailed
        case networkError

        var errorDescription: String? {
            switch self {
            case .productNotFound: return "Subscription not available."
            case .purchaseFailed(let error): return error.localizedDescription
            case .purchaseCancelled: return nil
            case .purchasePending: return "Purchase pending approval."
            case .verificationFailed: return "Could not verify purchase."
            case .networkError: return "Network error. Please try again."
            }
        }
    }

    // MARK: - Private

    private var transactionListener: Task<Void, Error>?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var authRefreshTask: Task<Void, Never>?
    private var statusUpdateVersion: UInt = 0

    // MARK: - Init

    private init() {
        transactionListener = listenForTransactions()
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleAuthUserChange()
            }
        }

        Task {
            await loadProducts()
            await refreshTrialEligibility()
        }
    }

    deinit {
        transactionListener?.cancel()
        authRefreshTask?.cancel()
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            let productIDs = ProductID.allCases.map(\.rawValue)
            let storeProducts = try await Product.products(for: Set(productIDs))

            // Sort: Move Pass first (the only product currently sold).
            products = storeProducts.sorted { p1, _ in
                p1.id == ProductID.move.rawValue
            }

            isLoaded = true
        } catch {
            #if DEBUG
            print("Failed to load products: \(error)")
            #endif
            purchaseError = .networkError
        }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async -> PurchaseResult {
        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await updateSubscriptionStatus()
                    await refreshTrialEligibility()

                    // Give the entitlement write a short head start before the
                    // paywall reports success. A failed or timed-out sync stays
                    // non-fatal so local StoreKit entitlement remains enough.
                    await syncToServerBeforePurchaseSuccess(transaction: transaction)

                    await transaction.finish()
                    isPurchasing = false
                    return .success

                case .unverified(_, let error):
                    #if DEBUG
                    print("Transaction verification failed: \(error)")
                    #endif
                    purchaseError = .verificationFailed
                    isPurchasing = false
                    return .failed(error)
                }

            case .userCancelled:
                purchaseError = .purchaseCancelled
                isPurchasing = false
                return .cancelled

            case .pending:
                purchaseError = .purchasePending
                isPurchasing = false
                return .pending

            @unknown default:
                isPurchasing = false
                return .failed(PurchaseError.purchaseFailed(underlying: NSError(domain: "StoreKit", code: -1)))
            }
        } catch {
            purchaseError = .purchaseFailed(underlying: error)
            isPurchasing = false
            return .failed(error)
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        // Clear any stale error from a previous purchase attempt so the
        // settings restore success heuristic (purchaseError == nil) reads
        // the result of THIS restore call only.
        purchaseError = nil

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            await refreshTrialEligibility()
        } catch {
            #if DEBUG
            print("Restore failed: \(error)")
            #endif
            purchaseError = .purchaseFailed(underlying: error)
        }
    }

    // MARK: - Subscription Status

    private func handleAuthUserChange() {
        // Account boundaries must close the gate synchronously. The refresh
        // below may reopen it only from the new account's current entitlement.
        statusUpdateVersion &+= 1
        authRefreshTask?.cancel()
        subscriptionStatus = .notSubscribed

        authRefreshTask = Task { [weak self] in
            await self?.updateSubscriptionStatus()
        }
    }

    func updateSubscriptionStatus() async {
        statusUpdateVersion &+= 1
        let updateVersion = statusUpdateVersion
        let previousStatus = subscriptionStatus
        var resolvedStatus: SubscriptionStatus?

        func isCurrentUpdate() -> Bool {
            !Task.isCancelled && updateVersion == statusUpdateVersion
        }

        // Step 1: Preserve legacy auto-renewable access for grandfathered users.
        for await result in Transaction.currentEntitlements {
            guard isCurrentUpdate() else { return }
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productType == .autoRenewable else { continue }

            if transaction.revocationDate != nil {
                resolvedStatus = .revoked
                break
            }

            guard let expirationDate = transaction.expirationDate,
                  expirationDate > Date() else {
                continue
            }

            let isInTrial = transaction.offerType == .introductory

            if isInTrial {
                resolvedStatus = .trial(
                    productId: transaction.productID,
                    expirationDate: expirationDate
                )
            } else {
                resolvedStatus = .subscribed(
                    productId: transaction.productID,
                    expirationDate: expirationDate
                )
            }
            break
        }

        // Step 2: Finished non-renewing transactions are absent from
        // currentEntitlements, so inspect the latest Move Pass transaction.
        guard isCurrentUpdate() else { return }
        if resolvedStatus == nil,
           let result = await Transaction.latest(for: ProductID.move.rawValue),
           case .verified(let transaction) = result,
           transaction.revocationDate == nil,
           let expirationDate = movePassExpirationDate(for: transaction) {
            guard isCurrentUpdate() else { return }
            if expirationDate > Date() {
                resolvedStatus = .subscribed(
                    productId: transaction.productID,
                    expirationDate: expirationDate
                )
            } else {
                resolvedStatus = .expired
            }
        }

        // Step 3: Gift codes grant the same Move Pass entitlement through the
        // user document. Resolve the UID here at call time — never from an auth
        // callback capture — then reject the response if the account changes.
        if resolvedStatus == nil, let currentUID = Auth.auth().currentUser?.uid {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("users")
                    .document(currentUID)
                    .getDocument()

                guard isCurrentUpdate(), Auth.auth().currentUser?.uid == currentUID else { return }
                if let subscription = snapshot.data()?["subscription"] as? [String: Any],
                   subscription["source"] as? String == "giftCode",
                   let expirationDate = subscriptionExpirationDate(
                       from: subscription["expirationDate"]
                   ),
                   expirationDate > Date() {
                    resolvedStatus = .subscribed(
                        productId: ProductID.move.rawValue,
                        expirationDate: expirationDate
                    )
                }
            } catch {
                guard isCurrentUpdate() else { return }
                #if DEBUG
                print("Gift-code entitlement lookup failed: \(error)")
                #endif
                subscriptionStatus = .notSubscribed
                return
            }
        }

        guard isCurrentUpdate() else { return }
        if let resolvedStatus {
            subscriptionStatus = resolvedStatus
        } else {
            // Check if we were previously active → now expired
            switch previousStatus {
            case .trial, .subscribed:
                subscriptionStatus = .expired
            case .revoked:
                break // Keep revoked
            default:
                subscriptionStatus = .notSubscribed
            }
        }
    }

    // MARK: - Trial Eligibility

    /// Refreshes `isEligibleForAnnualTrial` from StoreKit. Apple requires
    /// hiding free-trial copy from users who are not eligible for the
    /// introductory offer (e.g., users who have previously subscribed in
    /// the same subscription group). Called after products load, after
    /// subscription status changes, and on demand from views.
    func refreshTrialEligibility() async {
        guard let annual = product(for: .annual) else {
            isEligibleForAnnualTrial = false
            return
        }
        let eligible = await annual.subscription?.isEligibleForIntroOffer ?? false
        isEligibleForAnnualTrial = eligible
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await self.updateSubscriptionStatus()
                await self.refreshTrialEligibility()
                await self.syncToServer(transaction: transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Helpers

    func product(for id: ProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func isEligibleForTrial(product: Product) async -> Bool {
        await product.subscription?.isEligibleForIntroOffer ?? false
    }

    private func movePassExpirationDate(for transaction: StoreKit.Transaction) -> Date? {
        guard transaction.productID == ProductID.move.rawValue else { return nil }
        return Calendar.current.date(
            byAdding: .month,
            value: Self.movePassTermMonths,
            to: transaction.purchaseDate
        )
    }

    private func subscriptionExpirationDate(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        guard let string = value as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    // MARK: - Server Sync

    private func syncToServerBeforePurchaseSuccess(
        transaction: StoreKit.Transaction
    ) async {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        let syncTask = Task {
            await syncToServer(transaction: transaction)
            continuation.yield()
            continuation.finish()
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            continuation.yield()
            continuation.finish()
        }

        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        syncTask.cancel()
        timeoutTask.cancel()
    }

    private func syncToServer(transaction: StoreKit.Transaction) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let expirationDate = transaction.expirationDate
            ?? movePassExpirationDate(for: transaction)

        let payload: [String: Any] = [
            "userId": uid,
            "productId": transaction.productID,
            "originalTransactionId": String(transaction.originalID),
            "transactionId": String(transaction.id),
            "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate),
            "expirationDate": expirationDate.map {
                ISO8601DateFormatter().string(from: $0)
            } ?? "",
            "environment": transaction.environment.rawValue,
            "isUpgraded": transaction.isUpgraded
        ]

        do {
            try await SubscriptionAPIClient.validateReceipt(payload: payload)
        } catch {
            #if DEBUG
            print("Server sync failed (non-fatal): \(error)")
            #endif
        }
    }
}
