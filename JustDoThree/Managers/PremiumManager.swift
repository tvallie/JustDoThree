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

    init() {
        self.isPremium = UserDefaults.standard.bool(forKey: premiumKey)
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

    func purchase() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            guard let product = products.first else { return }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified = verification { grantPremium() }
            default:
                break
            }
        } catch {
            // Purchase cancelled or failed — no-op.
        }
    }

    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID {
                grantPremium()
            }
        }
    }
}
