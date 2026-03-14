import Foundation
import Observation

/// Stub — all features are free. isPremium is always true.
@Observable
final class PremiumManager {
    var isPremium: Bool = true
    var displayPrice: String = ""

    func loadProducts() async {}
    func purchase() async -> Bool { true }
    func restorePurchases() async {}

    #if DEBUG
    func simulatePurchase() {}
    func revokePremium() {}
    #endif
}
