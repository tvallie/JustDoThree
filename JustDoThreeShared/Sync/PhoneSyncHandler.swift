import Foundation
import SwiftData

/// Phone-side handler that turns sync messages from the watch into
/// SwiftData mutations. Routes completion commands through `PlannerEngine`
/// so recurring / stretch rules stay in one place.
@MainActor
final class PhoneSyncHandler {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Apply a CompletionCommand by finding the task, locating its plan
    /// (today's plan in personal or work context), and calling the
    /// appropriate PlannerEngine entry point. Unknown task IDs no-op.
    func apply(_ cmd: CompletionCommand) throws {
        let ctx = ModelContext(container)
        guard let task = try ctx.fetch(FetchDescriptor<JDTask>())
            .first(where: { $0.id == cmd.taskID })
        else { return }

        // Find the plan that references this task. Watch only ever issues
        // completion against today's plan(s), so prefer those, but fall back
        // to any plan that contains the task to handle clock-skew at the
        // day boundary.
        let plans = try ctx.fetch(FetchDescriptor<DailyPlan>())
        let owningPlan = plans.first(where: { plan in
            plan.taskIDs.contains(task.id) || plan.stretchTaskIDs.contains(task.id)
        })
        guard let plan = owningPlan else { return }

        let isStretch = plan.stretchTaskIDs.contains(task.id)

        switch cmd.action {
        case .complete:
            if isStretch {
                PlannerEngine.completeStretch(task: task, plan: plan, context: ctx)
            } else {
                PlannerEngine.complete(task: task, plan: plan, context: ctx)
            }
        case .uncomplete:
            PlannerEngine.uncomplete(task: task, plan: plan, context: ctx)
        }
    }

    /// Build a TodaySnapshot reflecting today's personal + work plans.
    /// Rows are ordered as the plan stores them (primary first, then stretch
    /// for the personal/today page). Returns empty arrays if no plan exists
    /// for today — the watch renders an "Open on iPhone" empty state in that
    /// case rather than guessing.
    func buildSnapshot() throws -> TodaySnapshot {
        let ctx = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())
        let allPlans = try ctx.fetch(FetchDescriptor<DailyPlan>())
        let allTasks = try ctx.fetch(FetchDescriptor<JDTask>())

        let personalPlan = allPlans.first { $0.date.isSameDay(as: today) && !$0.isWork }
        let workPlan     = allPlans.first { $0.date.isSameDay(as: today) &&  $0.isWork }

        let todayRows = (personalPlan.map { plan in
            rows(for: plan.taskIDs, completed: plan.completedTaskIDs,
                 isStretch: false, tasks: allTasks) +
            rows(for: plan.stretchTaskIDs, completed: plan.completedStretchIDs,
                 isStretch: true, tasks: allTasks)
        }) ?? []

        let workRows = (workPlan.map { plan in
            rows(for: plan.taskIDs, completed: plan.completedTaskIDs,
                 isStretch: false, tasks: allTasks) +
            rows(for: plan.stretchTaskIDs, completed: plan.completedStretchIDs,
                 isStretch: true, tasks: allTasks)
        }) ?? []

        return TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: todayRows,
            work: workRows,
            generatedAt: Date()
        )
    }

    private func rows(for ids: [UUID],
                      completed: [UUID],
                      isStretch: Bool,
                      tasks: [JDTask]) -> [TodaySnapshot.Row] {
        let completedSet = Set(completed)
        return ids.compactMap { id in
            guard let task = tasks.first(where: { $0.id == id }) else { return nil }
            return TodaySnapshot.Row(
                id: id,
                title: task.title,
                isCompleted: completedSet.contains(id),
                isStretch: isStretch
            )
        }
    }

    /// Apply a WatchIntentResult by inserting a new backlog task whose `id`
    /// matches the watch-supplied `clientID`. Idempotent: re-applying the
    /// same result is a no-op. Empty/whitespace titles are silently dropped.
    func apply(_ result: WatchIntentResult) throws {
        let ctx = ModelContext(container)
        let trimmed = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Dedupe — if a task with this clientID already exists, the previous
        // delivery already landed. Drop the duplicate.
        if try ctx.fetch(FetchDescriptor<JDTask>())
            .contains(where: { $0.id == result.clientID })
        {
            return
        }

        let isWork = (result.list == .workBacklog)
        let existing = try ctx.fetch(FetchDescriptor<JDTask>())
            .filter { $0.isWork == isWork }
        let minOrder = existing.map(\.sortOrder).min() ?? 0

        let task = JDTask(title: trimmed, sortOrder: minOrder - 1, isWork: isWork)
        // Override the autogenerated id so phone and watch share the same UUID
        // and future retries from the watch are no-ops via the dedupe check.
        task.id = result.clientID
        ctx.insert(task)
        try ctx.save()
    }
}
