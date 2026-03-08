import Foundation
import Observation
import StoreKit

@Observable
final class PremiumManager {

    static let productID = "com.todd.justdothree.premium"

    private let premiumKey = "jdt_isPremium"

    /// Whether the user owns premium. Stored property so @Observable tracks changes.
    var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: premiumKey) }
    }

    /// Localised price string fetched from App Store Connect (e.g. "$2.99", "€2,99").
    /// Empty until loadProducts() succeeds — UI should treat empty as "price loading".
    var displayPrice: String = ""

    /// Keeps the Transaction.updates listener alive for the app's lifetime.
    private var updatesTask: Task<Void, Never>?

    init() {
        self.isPremium = UserDefaults.standard.bool(forKey: premiumKey)
        updatesTask = Task { await self.listenForTransactionUpdates() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Product loading

    /// Fetches the premium product from App Store Connect and updates displayPrice.
    /// Call once at app launch — safe to call multiple times.
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            if let product = products.first {
                displayPrice = product.displayPrice
            }
        } catch {
            // Network unavailable or product not configured yet — keep fallback text.
        }
    }

    // MARK: - Access control

    func grantPremium() { isPremium = true }

    #if DEBUG
    /// Simulates a successful purchase without hitting StoreKit. DEBUG builds only.
    func simulatePurchase() { isPremium = true }
    /// Revokes premium to test non-premium state. DEBUG builds only.
    func revokePremium()    { isPremium = false }
    #endif

    // MARK: - StoreKit transactions

    /// Long-running listener for transactions that arrive outside the normal purchase flow
    /// (Ask to Buy approvals, interrupted purchases resuming, family sharing, etc.).
    /// Started in init() and kept alive for the app's lifetime.
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID {
                grantPremium()
                await transaction.finish()
            }
        }
    }

    /// Returns true only if the purchase completed and was verified.
    @discardableResult
    func purchase() async -> Bool {
        do {
            let products = try await Product.products(for: [Self.productID])
            guard let product = products.first else { return false }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    grantPremium()
                    await transaction.finish()
                    return true
                }
                return false
            default:
                return false
            }
        } catch {
            // Purchase cancelled or failed — no-op.
            return false
        }
    }

    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID {
                grantPremium()
                await transaction.finish()
            }
        }
    }
}
