import Foundation

extension Date {
    /// Returns midnight (00:00:00) of this date in the current calendar.
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Returns true if self and other fall on the same calendar day.
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Returns true if self is strictly before the start of today.
    var isBeforeToday: Bool {
        startOfDay < Date().startOfDay
    }

    /// E.g. "Wednesday, March 7"
    var longDayString: String {
        formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// E.g. "Wed, Mar 7"
    var shortDayString: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// E.g. "Mar 7"
    var monthDayString: String {
        formatted(.dateTime.month(.abbreviated).day())
    }

    /// E.g. "Mar 7" or "Mar 7, 2027" when outside the current year.
    var backlogTaskDateString: String {
        let currentYear = Calendar.current.component(.year, from: Date())
        let dateYear = Calendar.current.component(.year, from: self)

        if dateYear == currentYear {
            return formatted(.dateTime.month(.abbreviated).day())
        }

        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}

extension Calendar {
    /// Returns every date from startDate up to (but not including) endDate, stepping by 1 day.
    func dates(from startDate: Date, through endDate: Date) -> [Date] {
        var dates: [Date] = []
        var current = startDate.startOfDay
        let end = endDate.startOfDay
        while current <= end {
            dates.append(current)
            current = date(byAdding: .day, value: 1, to: current) ?? current
        }
        return dates
    }
}
