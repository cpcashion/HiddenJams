//
//  SubscriptionManager.swift
//  HiddenJams
//
//  StoreKit 2 subscription. One product, which must exist in App Store
//  Connect (subscription group "Hidden Jams Pro") with this exact ID:
//    com.chris.GettingStarted.HiddenJams.unlimited.monthly  – $1.99/month
//  Local testing: HiddenJams.storekit (wired into the HiddenJams scheme).
//

import Foundation
import StoreKit
import Combine

enum SubscriptionProduct: String, CaseIterable {
    case monthly = "com.chris.GettingStarted.HiddenJams.unlimited.monthly"

    var displayName: String {
        switch self {
        case .monthly: return "Hidden Jams Unlimited"
        }
    }
}

enum SubscriptionError: Error, LocalizedError {
    case productNotFound
    case purchaseFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "Subscription product not found in the App Store."
        case .purchaseFailed(let msg): return msg
        case .cancelled: return "Purchase was cancelled."
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await refreshStatus() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Products

    func loadProducts() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let ids = Set(SubscriptionProduct.allCases.map(\.rawValue))
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
            if products.isEmpty {
                print("⚠️ No subscription products found — create them in App Store Connect.")
                lastError = "Couldn't load the subscription from the App Store. Please try again."
            }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshStatus()
        case .userCancelled:
            throw SubscriptionError.cancelled
        case .pending:
            throw SubscriptionError.purchaseFailed("Purchase is pending approval.")
        @unknown default:
            throw SubscriptionError.purchaseFailed("Unknown purchase result.")
        }
    }

    /// Restores purchases. Returns true if an active subscription was found.
    @discardableResult
    func restore() async -> Bool {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshStatus()
        return isPremium
    }

    // MARK: - Entitlement

    /// Source of truth: any active auto-renewable subscription transaction.
    func refreshStatus() async {
        var premium = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productType == .autoRenewable,
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() {
                premium = true
                break
            }
        }
        isPremium = premium
        UserProfileManager.shared.setSubscriptionTier(premium ? .premium : .free)
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await SubscriptionManager.shared.refreshStatus()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.purchaseFailed("Transaction could not be verified.")
        case .verified(let safe):
            return safe
        }
    }
}
