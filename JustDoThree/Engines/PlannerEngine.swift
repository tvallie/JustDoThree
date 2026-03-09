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
        try? context.save()
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
        try? context.save()
        return true
    }

    static func removeFromToday(taskID: UUID, plan: DailyPlan, context: ModelContext) {
        plan.taskIDs.removeAll { $0 == taskID }
        plan.completedTaskIDs.removeAll { $0 == taskID }
        try? context.save()
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
        try? context.save()
    }

    static func uncomplete(task: JDTask, plan: DailyPlan, context: ModelContext) {
        plan.completedTaskIDs.removeAll { $0 == task.id }
        plan.completedStretchIDs.removeAll { $0 == task.id }
        task.isCompleted = false
        task.completionDate = nil
        // Remove matching completion log
        let logs = (try? context.fetch(FetchDescriptor<CompletionLog>())) ?? []
        if let log = logs.first(where: {
            $0.taskID == task.id && $0.planDate.isSameDay(as: plan.date)
        }) {
            context.delete(log)
        }
        try? context.save()
    }

    // MARK: - Stretch goals

    static func addStretch(task: JDTask, plan: DailyPlan, context: ModelContext) {
        guard !plan.stretchTaskIDs.contains(task.id),
              !task.isCompleted || task.recurringRule != nil
        else { return }
        plan.stretchTaskIDs.append(task.id)
        try? context.save()
    }

    static func removeStretch(taskID: UUID, plan: DailyPlan, context: ModelContext) {
        plan.stretchTaskIDs.removeAll { $0 == taskID }
        plan.completedStretchIDs.removeAll { $0 == taskID }
        try? context.save()
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
        try? context.save()
    }
}
