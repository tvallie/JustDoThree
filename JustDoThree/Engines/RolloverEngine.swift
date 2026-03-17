import Foundation
import SwiftData

/// Represents one task surfaced during rollover, with the user's pending choice.
struct RolloverItem: Identifiable {
    enum Choice {
        case doneYesterday  // mark complete for the previous day
        case addToToday     // move into today's plan
        case backlog        // leave in backlog (increment rolloverCount)
    }

    let id: UUID              // matches task.id
    let task: JDTask
    let fromPlan: DailyPlan
    var choice: Choice = .addToToday
}

/// Pure logic for detecting and resolving day-rollover.
enum RolloverEngine {

    // MARK: - Detection

    /// Finds tasks from previous days that are incomplete and not yet in today's plan.
    static func findPendingItems(
        todayPlan: DailyPlan,
        context: ModelContext
    ) -> [RolloverItem] {
        let today = Date().startOfDay
        let allPlans = PlannerEngine.allPlans(context: context)
        let allTasks = PlannerEngine.allTasks(context: context)

        let previousPlans = allPlans
            .filter { $0.date < today && !$0.taskIDs.isEmpty }
            .sorted { $0.date > $1.date } // newest first for dedup

        var seen = Set<UUID>()
        var items: [RolloverItem] = []

        for plan in previousPlans {
            let incompleteIDs = plan.taskIDs.filter { !plan.completedTaskIDs.contains($0) }
            for taskID in incompleteIDs {
                guard !seen.contains(taskID) else { continue }
                seen.insert(taskID)
                guard
                    let task = allTasks.first(where: { $0.id == taskID }),
                    !task.isCompleted,
                    !todayPlan.taskIDs.contains(taskID)
                else { continue }
                items.append(RolloverItem(id: taskID, task: task, fromPlan: plan))
            }
        }
        return items
    }

    // MARK: - Resolution

    /// Applies user's rollover choices: completes, schedules, or returns each task to backlog.
    static func applyChoices(
        _ items: [RolloverItem],
        todayPlan: DailyPlan,
        context: ModelContext
    ) {
        for item in items {
            switch item.choice {
            case .doneYesterday:
                if !item.fromPlan.completedTaskIDs.contains(item.task.id) {
                    item.fromPlan.completedTaskIDs.append(item.task.id)
                }
                let log = CompletionLog(
                    taskID: item.task.id,
                    taskTitle: item.task.title,
                    planDate: item.fromPlan.date
                )
                context.insert(log)
                // Recurring tasks reset immediately — do not mark permanently complete
                if item.task.recurringRule == nil {
                    item.task.isCompleted = true
                    item.task.completionDate = Date()
                }

            case .addToToday:
                if todayPlan.taskIDs.count < 3,
                   !todayPlan.taskIDs.contains(item.task.id) {
                    todayPlan.taskIDs.append(item.task.id)
                }
                item.task.rolloverCount += 1

            case .backlog:
                item.task.rolloverCount += 1
            }
        }
        save(context: context)
    }

    // MARK: - Save helper

    private static func save(context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[RolloverEngine] SwiftData save failed: \(error)")
            #endif
        }
    }
}
