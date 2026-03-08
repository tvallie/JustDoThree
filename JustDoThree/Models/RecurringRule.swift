import Foundation

/// Defines how a premium task recurs. Stored as JSON in JDTask.recurringRuleData.
struct RecurringRule: Codable, Hashable {
    enum Pattern: String, Codable {
        /// Repeats on a specific day of the week.
        case weekly
        /// Repeats on a specific day of the month.
        case monthly
    }

    var pattern: Pattern
    /// 1 = Sunday … 7 = Saturday. Used when pattern == .weekly.
    var weekday: Int?
    /// 1–31. Used when pattern == .monthly.
    var dayOfMonth: Int?

    static func weekly(weekday: Int) -> RecurringRule {
        RecurringRule(pattern: .weekly, weekday: weekday, dayOfMonth: nil)
    }

    static func monthly(dayOfMonth: Int) -> RecurringRule {
        RecurringRule(pattern: .monthly, weekday: nil, dayOfMonth: dayOfMonth)
    }
}
