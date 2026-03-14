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

    /// Transient cache so `recurringRule` doesn't allocate a JSONDecoder on every access.
    /// `nil` (outer) = not yet decoded; `.some(nil)` = decoded, no rule; `.some(rule)` = decoded rule.
    @Transient private var _cachedRule: RecurringRule?? = nil

    var recurringRule: RecurringRule? {
        get {
            if let cached = _cachedRule { return cached }
            let decoded = recurringRuleData.flatMap { try? JSONDecoder().decode(RecurringRule.self, from: $0) }
            _cachedRule = decoded
            return decoded
        }
        set {
            recurringRuleData = try? JSONEncoder().encode(newValue)
            _cachedRule = newValue
        }
    }
}
