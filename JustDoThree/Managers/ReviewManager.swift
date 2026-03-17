import Foundation
import StoreKit
import UIKit

/// Tracks usage milestones and requests an App Store review after the user
/// has been using the app for ≥10 days AND has completed all their primary
/// tasks on ≥5 separate days. Asks at most once per app version.
final class ReviewManager {
    static let shared = ReviewManager()
    private init() {}

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let firstLaunchDate    = "ReviewManager.firstLaunchDate"
        static let perfectDayCount    = "ReviewManager.perfectDayCount"
        static let lastPerfectDayDate = "ReviewManager.lastPerfectDayDate"
        static let lastReviewVersion  = "ReviewManager.lastReviewVersion"
    }

    // MARK: - Thresholds

    private let requiredPerfectDays = 5
    private let requiredDays        = 10

    // MARK: - Public API

    /// Call once at app launch. Records the date permanently; subsequent calls are no-ops.
    func recordFirstLaunchIfNeeded() {
        guard defaults.object(forKey: Keys.firstLaunchDate) == nil else { return }
        defaults.set(Date(), forKey: Keys.firstLaunchDate)
    }

    /// Call when the user finishes all their primary tasks for the day.
    /// Counts at most once per calendar day, then triggers the review prompt
    /// if all conditions are met.
    func recordPerfectDay() {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = defaults.object(forKey: Keys.lastPerfectDayDate) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return // already counted today
        }
        defaults.set(today, forKey: Keys.lastPerfectDayDate)
        let newCount = defaults.integer(forKey: Keys.perfectDayCount) + 1
        defaults.set(newCount, forKey: Keys.perfectDayCount)
        requestReviewIfEligible()
    }

    // MARK: - Private

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var daysSinceFirstLaunch: Int {
        guard let first = defaults.object(forKey: Keys.firstLaunchDate) as? Date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
    }

    private var alreadyRequestedThisVersion: Bool {
        defaults.string(forKey: Keys.lastReviewVersion) == currentVersion
    }

    private func requestReviewIfEligible() {
        guard !alreadyRequestedThisVersion else { return }
        guard daysSinceFirstLaunch >= requiredDays else { return }
        guard defaults.integer(forKey: Keys.perfectDayCount) >= requiredPerfectDays else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        SKStoreReviewController.requestReview(in: scene)
        defaults.set(currentVersion, forKey: Keys.lastReviewVersion)
    }
}
