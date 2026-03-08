import Foundation
import SwiftData

/// A task in the user's system. Lives in the backlog until scheduled or completed.
@Model
final class JDTask {
    var id: UUID
    var title: String
    var createdDate: Date
    /// Incremented each time this task is rolled over to a new day without completion.
    var rolloverCount: Int
    /// Sort position within the backlog (lower = higher priority).
    var sortOrder: Int
    /// True once the user marks this task permanently done.
    var isCompleted: Bool
    var completionDate: Date?
    /// JSON-encoded RecurringRule. Nil for non-recurring tasks (premium only).
    var recurringRuleData: Data?

    init(title: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.createdDate = Date()
        self.rolloverCount = 0
        self.sortOrder = sortOrder
        self.isCompleted = false
        self.completionDate = nil
        self.recurringRuleData = nil
    }

    var recurringRule: RecurringRule? {
        get {
            guard let data = recurringRuleData else { return nil }
            return try? JSONDecoder().decode(RecurringRule.self, from: data)
        }
        set {
            recurringRuleData = try? JSONEncoder().encode(newValue)
        }
    }
}
