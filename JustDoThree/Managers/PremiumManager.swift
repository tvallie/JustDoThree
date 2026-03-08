import Foundation
import Observation

/// Manages premium access state.
/// v1: Uses UserDefaults as backing store. Replace the purchase/restore
/// bodies with real StoreKit 2 transactions before shipping.
@Observable
final class PremiumManager {

    private let premiumKey = "jdt_isPremium"

    // Stored property so @Observable tracks changes and updates the UI.
    // didSet keeps UserDefaults in sync so state survives restarts.
    var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: premiumKey) }
    }

    init() {
        self.isPremium = UserDefaults.standard.bool(forKey: "jdt_isPremium")
    }

    /// Call this from your StoreKit purchase result handler.
    func grantPremium() {
        isPremium = true
    }

    /// Revoke premium (for DEBUG testing only).
    func revokePremium() {
        isPremium = false
    }

    /// Simulates a successful purchase. Remove before App Store submission.
    func simulatePurchase() {
        isPremium = true
    }

    // MARK: - StoreKit stubs (replace with real implementation)
    //
    // To wire up real purchases:
    // 1. Create a StoreKit Configuration file in Xcode (File > New > StoreKit Config)
    // 2. Add a Non-Consumable product with ID "com.todd.justdothree.premium"
    // 3. Replace the bodies below with StoreKit 2 Product.purchase() calls
    // 4. On .verified transaction, call grantPremium()

    func purchase() async {
        // TODO: implement StoreKit 2 purchase
        simulatePurchase()
    }

    func restorePurchases() async {
        // TODO: implement StoreKit 2 restore (iterate Transaction.currentEntitlements)
    }
}
