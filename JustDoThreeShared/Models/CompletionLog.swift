import Foundation
import SwiftData

/// Immutable record created when a task is marked complete.
/// Stores a title snapshot so history remains accurate even if the task is renamed.
/// Deleted when the user "un-completes" a task for that day.
@Model
final class CompletionLog {
    var taskID: UUID
    /// Snapshot of task.title at the moment of completion.
    var taskTitle: String
    /// The calendar day this completion is attributed to (midnight local time).
    var planDate: Date
    /// Exact moment the user tapped the checkmark.
    var completionDate: Date
    var isStretchGoal: Bool

    init(taskID: UUID, taskTitle: String, planDate: Date, isStretchGoal: Bool = false) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.planDate = Calendar.current.startOfDay(for: planDate)
        self.completionDate = Date()
        self.isStretchGoal = isStretchGoal
    }
}
