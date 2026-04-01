import Foundation
import SwiftData

/// Pure logic layer for DailyPlan operations. No UI dependencies.
enum PlannerEngine {

    // MARK: - Plan fetching

    /// Returns today's DailyPlan, creating it if it doesn't exist yet.
    @discardableResult
    static func fetchOrCreateTodayPlan(context: ModelContext) -> DailyPlan {
        fetchOrCreatePlan(for: Date(), context: context)
    }

    @discardableResult
    static func fetchOrCreatePlan(for date: Date, context: ModelContext) -> DailyPlan {
        let all = allPlans(context: context)
        if let existing = all.first(where: { $0.date.isSameDay(as: date) }) {
            return existing
        }
        let plan = DailyPlan(date: date)
        context.insert(plan)
        save(context: context)
        return plan
    }

    static func allPlans(context: ModelContext) -> [DailyPlan] {
        let descriptor = FetchDescriptor<DailyPlan>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func plan(for date: Date, context: ModelContext) -> DailyPlan? {
        allPlans(context: context).first { $0.date.isSameDay(as: date) }
    }

    /// Most recent plan BEFORE today that has at least one task.
    static func mostRecentPreviousPlan(context: ModelContext) -> DailyPlan? {
        let today = Date().startOfDay
        return allPlans(context: context)
            .filter { $0.date < today && !$0.taskIDs.isEmpty }
            .max(by: { $0.date < $1.date })
    }

    // MARK: - Task operations

    static func allTasks(context: ModelContext) -> [JDTask] {
        let descriptor = FetchDescriptor<JDTask>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func task(id: UUID, context: ModelContext) -> JDTask? {
        allTasks(context: context).first { $0.id == id }
    }

    static func topInsertionStartOrder(existingTasks: [JDTask], count: Int) -> Int {
        let minimum = existingTasks.map(\.sortOrder).min() ?? 0
        return minimum - max(1, count)
    }

    // MARK: - Today task management

    /// Adds a task to a plan. Returns false if the plan is full, task is already there,
    /// or the task is completed and non-recurring.
    @discardableResult
    static func addToToday(task: JDTask, plan: DailyPlan, context: ModelContext) -> Bool {
        guard plan.taskIDs.count < 3,
              !plan.taskIDs.contains(task.id),
              !task.isCompleted || task.recurringRule != nil
        else { return false }
        plan.taskIDs.append(task.id)
        save(context: context)
        return true
    }

    static func removeFromToday(taskID: UUID, plan: DailyPlan, context: ModelContext) {
        let removedWasCompleted = plan.completedTaskIDs.contains(taskID)
        let wasFullyComplete = plan.taskIDs.count == 3 && plan.isAllPrimaryComplete

        plan.taskIDs.removeAll { $0 == taskID }
        plan.completedTaskIDs.removeAll { $0 == taskID }
        if removedWasCompleted && wasFullyComplete {
            promoteFirstStretchGoalIfNeeded(in: plan)
        }
        save(context: context)
    }

    // MARK: - Completion

    static func complete(task: JDTask, plan: DailyPlan, context: ModelContext) {
        guard !plan.completedTaskIDs.contains(task.id) else { return }
        plan.completedTaskIDs.append(task.id)
        let isStretch = plan.stretchTaskIDs.contains(task.id)
        let log = CompletionLog(taskID: task.id, taskTitle: task.title,
                                 planDate: plan.date, isStretchGoal: isStretch)
        context.insert(log)
        // Recurring tasks reset immediately — do not mark permanently complete
        if task.recurringRule == nil {
            task.isCompleted = true
            task.completionDate = Date()
        }
        save(context: context)
    }

    static func uncomplete(task: JDTask, plan: DailyPlan, context: ModelContext) {
        plan.completedTaskIDs.removeAll { $0 == task.id }
        plan.completedStretchIDs.removeAll { $0 == task.id }
        if task.recurringRule == nil {
            task.isCompleted = false
            task.completionDate = nil
        }
        // Remove matching completion log
        let logs = (try? context.fetch(FetchDescriptor<CompletionLog>())) ?? []
        if let log = logs.first(where: {
            $0.taskID == task.id && $0.planDate.isSameDay(as: plan.date)
        }) {
            context.delete(log)
        }
        save(context: context)
    }

    // MARK: - Stretch goals

    static func addStretch(task: JDTask, plan: DailyPlan, context: ModelContext) {
        guard !plan.stretchTaskIDs.contains(task.id),
              !task.isCompleted || task.recurringRule != nil
        else { return }
        plan.stretchTaskIDs.append(task.id)
        save(context: context)
    }

    static func removeStretch(taskID: UUID, plan: DailyPlan, context: ModelContext) {
        plan.stretchTaskIDs.removeAll { $0 == taskID }
        plan.completedStretchIDs.removeAll { $0 == taskID }
        save(context: context)
    }

    // MARK: - Recurring auto-schedule

    /// Adds any recurring tasks whose rule matches the given date into that day's plan.
    /// Respects the 3-task primary limit. Safe to call multiple times (idempotent).
    static func autoScheduleRecurring(for date: Date, context: ModelContext) {
        let plan = fetchOrCreatePlan(for: date, context: context)
        let tasks = allTasks(context: context)
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let dayOfMonth = cal.component(.day, from: date)

        var changed = false
        for task in tasks {
            guard let rule = task.recurringRule else { continue }
            guard plan.taskIDs.count < 3 else { break }
            guard !plan.taskIDs.contains(task.id) else { continue }

            let matches: Bool
            switch rule.pattern {
            case .weekly:  matches = rule.weekday == weekday
            case .monthly: matches = rule.dayOfMonth == dayOfMonth
            }
            guard matches else { continue }
            plan.taskIDs.append(task.id)
            changed = true
        }
        if changed { save(context: context) }
    }

    static func completeStretch(task: JDTask, plan: DailyPlan, context: ModelContext) {
        guard plan.stretchTaskIDs.contains(task.id),
              !plan.completedStretchIDs.contains(task.id) else { return }
        plan.completedStretchIDs.append(task.id)
        let log = CompletionLog(taskID: task.id, taskTitle: task.title,
                                 planDate: plan.date, isStretchGoal: true)
        context.insert(log)
        // Recurring tasks reset immediately — do not mark permanently complete
        if task.recurringRule == nil {
            task.isCompleted = true
            task.completionDate = Date()
        }
        save(context: context)
    }

    // MARK: - Save helper

    private static func promoteFirstStretchGoalIfNeeded(in plan: DailyPlan) {
        guard let promotedID = plan.stretchTaskIDs.first,
              !plan.taskIDs.contains(promotedID),
              plan.taskIDs.count < 3
        else { return }

        plan.stretchTaskIDs.removeAll { $0 == promotedID }
        plan.taskIDs.append(promotedID)

        if plan.completedStretchIDs.contains(promotedID) {
            plan.completedStretchIDs.removeAll { $0 == promotedID }
            if !plan.completedTaskIDs.contains(promotedID) {
                plan.completedTaskIDs.append(promotedID)
            }
        }
    }

    private static func save(context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[PlannerEngine] SwiftData save failed: \(error)")
            #endif
        }
    }
}
