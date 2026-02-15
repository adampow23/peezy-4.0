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

@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SubscriptionManager()

    // MARK: - Product Identifiers

    enum ProductID: String, CaseIterable {
        case monthly = "peezy.monthly"
        case yearly = "peezy.yearly"
    }

    // MARK: - Published State

    @Published var products: [Product] = []
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: PurchaseError? = nil
    @Published var isLoaded: Bool = false

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

    // MARK: - Init

    private init() {
        transactionListener = listenForTransactions()

        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            let productIDs = ProductID.allCases.map(\.rawValue)
            let storeProducts = try await Product.products(for: Set(productIDs))

            // Sort: yearly first (highlighted plan)
            products = storeProducts.sorted { p1, _ in
                p1.id == ProductID.yearly.rawValue
            }

            isLoaded = true
        } catch {
            print("Failed to load products: \(error)")
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

                    // Fire-and-forget server sync
                    Task { await syncToServer(transaction: transaction) }

                    await transaction.finish()
                    isPurchasing = false
                    return .success

                case .unverified(_, let error):
                    print("Transaction verification failed: \(error)")
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
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            print("Restore failed: \(error)")
            purchaseError = .purchaseFailed(underlying: error)
        }
    }

    // MARK: - Subscription Status

    func updateSubscriptionStatus() async {
        var foundActive = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productType == .autoRenewable else { continue }

            if transaction.revocationDate != nil {
                subscriptionStatus = .revoked
                foundActive = true
                break
            }

            guard let expirationDate = transaction.expirationDate,
                  expirationDate > Date() else {
                continue
            }

            let isInTrial = transaction.offerType == .introductory

            if isInTrial {
                subscriptionStatus = .trial(
                    productId: transaction.productID,
                    expirationDate: expirationDate
                )
            } else {
                subscriptionStatus = .subscribed(
                    productId: transaction.productID,
                    expirationDate: expirationDate
                )
            }
            foundActive = true
            break
        }

        if !foundActive {
            // Check if we were previously active → now expired
            switch subscriptionStatus {
            case .trial, .subscribed:
                subscriptionStatus = .expired
            case .revoked:
                break // Keep revoked
            default:
                subscriptionStatus = .notSubscribed
            }
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await self.updateSubscriptionStatus()
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

    // MARK: - Server Sync

    private func syncToServer(transaction: StoreKit.Transaction) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let payload: [String: Any] = [
            "userId": uid,
            "productId": transaction.productID,
            "originalTransactionId": String(transaction.originalID),
            "transactionId": String(transaction.id),
            "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate),
            "expirationDate": transaction.expirationDate.map {
                ISO8601DateFormatter().string(from: $0)
            } ?? "",
            "environment": transaction.environment.rawValue,
            "isUpgraded": transaction.isUpgraded
        ]

        do {
            try await SubscriptionAPIClient.validateReceipt(payload: payload)
        } catch {
            print("Server sync failed (non-fatal): \(error)")
        }
    }
}
