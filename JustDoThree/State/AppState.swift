import Foundation
import SwiftData
import Observation

/// Central in-memory UI state. Persisted data lives in SwiftData.
@MainActor
@Observable
final class AppState {

    // MARK: - Rollover sheet state

    var showRolloverSheet: Bool = false
    var rolloverItems: [RolloverItem] = []

    // MARK: - Settings

    var autoScheduleRecurring: Bool {
        get { UserDefaults.standard.bool(forKey: "jdt_autoScheduleRecurring") }
        set { UserDefaults.standard.set(newValue, forKey: "jdt_autoScheduleRecurring") }
    }

    // MARK: - Day transition

    /// Prevents duplicate rollover checks within a single app session day.
    private var lastCheckedDate: Date?

    /// Call on every app-active transition (foreground return, first launch).
    /// Creates today's plan if it doesn't exist, then surfaces any rollover items.
    func checkDayTransition(context: ModelContext) {
        let today = Date().startOfDay

        // Guard: already checked today in this session
        if let last = lastCheckedDate, last.isSameDay(as: today) { return }
        lastCheckedDate = today

        // Ensure today's plan exists
        let todayPlan = PlannerEngine.fetchOrCreateTodayPlan(context: context)

        // Auto-schedule recurring tasks if enabled
        if autoScheduleRecurring {
            PlannerEngine.autoScheduleRecurring(for: Date(), context: context)
        }

        // Guard: rollover already resolved today (persisted across sessions)
        let resolvedKey = "jdt_rolloverResolved"
        if let resolved = UserDefaults.standard.object(forKey: resolvedKey) as? Date,
           resolved.isSameDay(as: today) { return }

        // Find pending rollover tasks
        let pending = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
        if !pending.isEmpty {
            rolloverItems = pending
            showRolloverSheet = true
        } else {
            markRolloverResolved()
        }
    }

    /// Applies user's choices from the rollover sheet and dismisses it.
    func applyRolloverChoices(context: ModelContext) {
        guard let todayPlan = PlannerEngine.plan(for: Date(), context: context) else { return }
        RolloverEngine.applyChoices(rolloverItems, todayPlan: todayPlan, context: context)
        rolloverItems = []
        showRolloverSheet = false
        markRolloverResolved()
    }

    func dismissRolloverWithoutChanges() {
        rolloverItems = []
        showRolloverSheet = false
        markRolloverResolved()
    }

    private func markRolloverResolved() {
        UserDefaults.standard.set(Date(), forKey: "jdt_rolloverResolved")
    }
}
