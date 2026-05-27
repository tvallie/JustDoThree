import XCTest
import SwiftData
@testable import JustDoThree

@MainActor
final class RolloverEngineTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    // MARK: - Helpers

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date().startOfDay)!
    }

    private func insertTask(_ title: String, isWork: Bool = false) -> JDTask {
        let task = JDTask(title: title, isWork: isWork)
        context.insert(task)
        return task
    }

    private func insertPlan(daysAgo: Int, taskIDs: [UUID], isWork: Bool = false) -> DailyPlan {
        let plan = DailyPlan(date: day(-daysAgo), isWork: isWork)
        plan.taskIDs = taskIDs
        context.insert(plan)
        return plan
    }

    // MARK: - Backlog choice

    func test_backlog_choice_removes_task_from_every_previous_plan_in_same_mode() throws {
        // Task appears in 3 prior days (already-accumulated rollovers from before fix).
        let task = insertTask("Sticky")
        let oldest = insertPlan(daysAgo: 3, taskIDs: [task.id])
        let middle = insertPlan(daysAgo: 2, taskIDs: [task.id])
        let newest = insertPlan(daysAgo: 1, taskIDs: [task.id])
        let todayPlan = insertPlan(daysAgo: 0, taskIDs: [])
        try context.save()

        let items = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
        XCTAssertEqual(items.count, 1, "should dedupe to a single item")

        var resolved = items
        resolved[0].choice = .backlog
        RolloverEngine.applyChoices(resolved, todayPlan: todayPlan, context: context)

        XCTAssertFalse(oldest.taskIDs.contains(task.id), "task should be gone from oldest plan")
        XCTAssertFalse(middle.taskIDs.contains(task.id), "task should be gone from middle plan")
        XCTAssertFalse(newest.taskIDs.contains(task.id), "task should be gone from newest plan")

        // Next-day rollover (simulate by re-running detection) must not resurface it.
        let nextItems = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
        XCTAssertTrue(nextItems.isEmpty, "task should never resurface after one Backlog choice")
    }

    func test_backlog_choice_does_not_affect_other_mode_plans() throws {
        // Same UUID listed in a personal plan and a work plan (shouldn't happen, but be defensive).
        let task = insertTask("Personal task", isWork: false)
        let personalOld = insertPlan(daysAgo: 1, taskIDs: [task.id], isWork: false)
        let workOld = insertPlan(daysAgo: 1, taskIDs: [task.id], isWork: true)
        let todayPersonal = insertPlan(daysAgo: 0, taskIDs: [], isWork: false)
        try context.save()

        let items = RolloverEngine.findPendingItems(todayPlan: todayPersonal, context: context)
        var resolved = items
        for i in resolved.indices { resolved[i].choice = .backlog }
        RolloverEngine.applyChoices(resolved, todayPlan: todayPersonal, context: context)

        XCTAssertFalse(personalOld.taskIDs.contains(task.id))
        XCTAssertTrue(workOld.taskIDs.contains(task.id), "work plan must be untouched by personal backlog action")
    }

    // MARK: - Mode filtering

    func test_findPendingItems_excludes_tasks_with_wrong_isWork() throws {
        // A personal plan ends up holding a work task's ID (e.g. legacy / sync bug).
        let workTask = insertTask("Work-only", isWork: true)
        let personalTask = insertTask("Personal-only", isWork: false)
        _ = insertPlan(daysAgo: 1, taskIDs: [workTask.id, personalTask.id], isWork: false)
        let todayPersonal = insertPlan(daysAgo: 0, taskIDs: [], isWork: false)
        try context.save()

        let items = RolloverEngine.findPendingItems(todayPlan: todayPersonal, context: context)
        let titles = items.map(\.task.title)
        XCTAssertEqual(titles, ["Personal-only"],
                       "work tasks must not surface in a personal rollover sheet")
    }

    // MARK: - Schedule choice

    func test_scheduleFor_removes_task_from_previous_plans() throws {
        let task = insertTask("Reschedule me")
        let oldA = insertPlan(daysAgo: 2, taskIDs: [task.id])
        let oldB = insertPlan(daysAgo: 1, taskIDs: [task.id])
        let todayPlan = insertPlan(daysAgo: 0, taskIDs: [])
        try context.save()

        let items = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
        var resolved = items
        resolved[0].choice = .scheduleFor(day(2))
        RolloverEngine.applyChoices(resolved, todayPlan: todayPlan, context: context)

        XCTAssertFalse(oldA.taskIDs.contains(task.id))
        XCTAssertFalse(oldB.taskIDs.contains(task.id))

        let nextItems = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
        XCTAssertTrue(nextItems.isEmpty, "task should not resurface after being scheduled forward")
    }
}
