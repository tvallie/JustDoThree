import Foundation
import EventKit

/// Pure-logic wrapper around EKEventStore. No UI dependencies.
/// All methods are `@MainActor` because EKEventStore mutations should be serialized.
@MainActor
enum CalendarService {

    enum CalendarError: Error, LocalizedError {
        case permissionDenied
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permission denied. Enable access in Settings."
            case .saveFailed(let err):
                return "Couldn't save: \(err.localizedDescription)"
            }
        }
    }

    static let shared = EKEventStore()

    // MARK: - Permission

    static func requestEventAccess() async throws {
        let granted = try await shared.requestFullAccessToEvents()
        if !granted { throw CalendarError.permissionDenied }
    }

    static func requestReminderAccess() async throws {
        let granted = try await shared.requestFullAccessToReminders()
        if !granted { throw CalendarError.permissionDenied }
    }

    // MARK: - Calendars / Lists

    static func availableEventCalendars() -> [EKCalendar] {
        shared.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    static func availableReminderLists() -> [EKCalendar] {
        shared.calendars(for: .reminder).filter { $0.allowsContentModifications }
    }

    static func defaultEventCalendar() -> EKCalendar? {
        shared.defaultCalendarForNewEvents
    }

    static func defaultReminderList() -> EKCalendar? {
        shared.defaultCalendarForNewReminders()
    }

    // MARK: - Creation

    /// Creates an event. Returns the event identifier so callers can deep-link.
    static func createEvent(
        title: String,
        date: Date,
        isAllDay: Bool,
        startTime: Date?,
        durationMinutes: Int,
        calendar: EKCalendar
    ) throws -> String {
        let event = EKEvent(eventStore: shared)
        event.title = title
        event.calendar = calendar
        event.isAllDay = isAllDay

        if isAllDay {
            event.startDate = date.startOfDay
            event.endDate = date.startOfDay
        } else {
            let cal = Calendar.current
            let timeOnly = startTime ?? date
            let timeComps = cal.dateComponents([.hour, .minute], from: timeOnly)
            let start = cal.date(
                bySettingHour: timeComps.hour ?? 9,
                minute: timeComps.minute ?? 0,
                second: 0,
                of: date
            ) ?? date
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }

        do {
            try shared.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            throw CalendarError.saveFailed(error)
        }
    }

    /// Creates a reminder. Returns the reminder identifier.
    static func createReminder(
        title: String,
        dueDate: Date,
        calendar: EKCalendar
    ) throws -> String {
        let reminder = EKReminder(eventStore: shared)
        reminder.title = title
        reminder.calendar = calendar
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        reminder.dueDateComponents = comps

        do {
            try shared.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            throw CalendarError.saveFailed(error)
        }
    }
}
