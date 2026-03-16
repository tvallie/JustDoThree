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

    var hasSeenOnboarding: Bool = UserDefaults.standard.bool(forKey: "jdt_hasSeenOnboarding") {
        didSet { UserDefaults.standard.set(hasSeenOnboarding, forKey: "jdt_hasSeenOnboarding") }
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
        let todayPlan = PlannerEngine.fetchOrCreateTodayPlan(context: context)
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

    #if DEBUG
    /// Forces the rollover sheet open for testing. Uses real pending items if any exist;
    /// otherwise seeds yesterday's plan with up to 2 backlog tasks to create test data.
    func previewRolloverSheet(context: ModelContext) {
        let todayPlan = PlannerEngine.fetchOrCreateTodayPlan(context: context)
        var items = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)

        if items.isEmpty {
            let allTasks = PlannerEngine.allTasks(context: context)
            let todayIDs = Set(todayPlan.taskIDs)
            let candidates = allTasks
                .filter { !$0.isCompleted && !todayIDs.contains($0.id) }
                .prefix(2)
            guard !candidates.isEmpty else { return }

            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            let yesterdayPlan = PlannerEngine.fetchOrCreatePlan(for: yesterday, context: context)
            for task in candidates where !yesterdayPlan.taskIDs.contains(task.id) {
                yesterdayPlan.taskIDs.append(task.id)
            }
            try? context.save()
            items = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
            guard !items.isEmpty else { return }
        }

        rolloverItems = items
        showRolloverSheet = true
    }

    /// Seeds realistic history data for testing the HistoryView analytics cards.
    /// Idempotent — skips seeding if 10 or more CompletionLog records already exist.
    func seedHistoryData(context: ModelContext) {
        // Idempotency check
        let existingLogs = (try? context.fetch(FetchDescriptor<CompletionLog>())) ?? []
        guard existingLogs.count < 10 else { return }

        let cal = Calendar.current
        let today = Date().startOfDay

        // MARK: — Seed JDTasks (for Most Avoided card)
        let taskDefs: [(title: String, rolloverCount: Int)] = [
            ("Clean up dog poop in back yard", 4),
            ("Mow lawn", 3),
            ("Buy birthday gift for pet elephant", 2),
            ("Plant a tree", 1),
            ("Tell someone they are awesome", 0),
        ]

        var tasks: [JDTask] = []
        for (index, def) in taskDefs.enumerated() {
            let task = JDTask(title: def.title, sortOrder: index)
            task.rolloverCount = def.rolloverCount
            context.insert(task)
            tasks.append(task)
        }

        // MARK: — Seed CompletionLogs (for Stats, Perfect Days, Recent Completions cards)
        // 14 days back. Most days: 3 primary completions (perfect day).
        // Days 4 and 9 (1-indexed offset): only 2 completions — makes avg/day ~2.7.
        // Day 7: also add one stretch goal completion.

        let incompleteDays: Set<Int> = [4, 9]
        let stretchDay: Int = 7

        for offset in 1...14 {
            guard let planDate = cal.date(byAdding: .day, value: -offset, to: today) else { continue }

            let taskCount = incompleteDays.contains(offset) ? 2 : 3
            for slot in 0..<taskCount {
                let task = tasks[(offset + slot) % tasks.count]
                let log = CompletionLog(
                    taskID: task.id,
                    taskTitle: task.title,
                    planDate: planDate,
                    isStretchGoal: false
                )
                context.insert(log)
            }

            if offset == stretchDay {
                let stretchTask = tasks[(offset + 3) % tasks.count]
                let stretchLog = CompletionLog(
                    taskID: stretchTask.id,
                    taskTitle: stretchTask.title,
                    planDate: planDate,
                    isStretchGoal: true
                )
                context.insert(stretchLog)
            }
        }

        try? context.save()
    }
    #endif
}
