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

    /// Human-readable schedule string, e.g. "every Monday" or "3rd of every month".
    var displayString: String {
        switch pattern {
        case .weekly:
            let day = max(1, min(7, weekday ?? 1))
            // Calendar weekday: 1 = Sunday, 2 = Monday … 7 = Saturday
            let symbols = Calendar.current.weekdaySymbols // ["Sunday", "Monday", …]
            let name = symbols[safe: day - 1] ?? "day \(day)"
            return "every \(name)"
        case .monthly:
            let d = dayOfMonth ?? 1
            let ordinal = ordinalFormatter.string(from: NSNumber(value: d)) ?? "\(d)"
            return "\(ordinal) of every month"
        }
    }
}

private let ordinalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return f
}()

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
