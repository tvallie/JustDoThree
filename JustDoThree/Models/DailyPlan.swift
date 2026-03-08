import Foundation
import SwiftData

/// Represents the user's chosen tasks for one calendar day.
/// Stores UUIDs (not relationships) to stay CloudKit-compatible.
@Model
final class DailyPlan {
    /// Normalized to midnight local time for the given calendar day.
    var date: Date
    /// Ordered list of task IDs for today's three (max 3).
    var taskIDs: [UUID]
    /// Subset of taskIDs marked complete on this day.
    var completedTaskIDs: [UUID]
    /// Stretch goal task IDs — shown after all primary tasks are done.
    var stretchTaskIDs: [UUID]
    /// Subset of stretchTaskIDs that the user completed.
    var completedStretchIDs: [UUID]

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.taskIDs = []
        self.completedTaskIDs = []
        self.stretchTaskIDs = []
        self.completedStretchIDs = []
    }

    var isAllPrimaryComplete: Bool {
        !taskIDs.isEmpty && taskIDs.allSatisfy { completedTaskIDs.contains($0) }
    }

    var primaryCompletedCount: Int {
        completedTaskIDs.filter { taskIDs.contains($0) }.count
    }
}
