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

    /// DEBUG only — remove before App Store submission.
    func simulatePurchase() { isPremium = true }
    func revokePremium()    { isPremium = false }

    // MARK: - StoreKit transactions
    //
    // Setup checklist:
    // 1. File > New > StoreKit Configuration File in Xcode
    // 2. Add a Non-Consumable product with ID "com.todd.justdothree.premium"
    // 3. Replace the purchase/restore bodies below with StoreKit 2 calls
    // 4. On .verified transaction, call grantPremium()

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
