import SwiftUI
import EventKit
import UIKit

/// Sheet that lets the user create an iPhone Calendar event or Reminder for a task.
/// Also adds the task to the in-app Plan when the chosen date is within 7 days
/// and the active-context plan has a free primary slot.
struct AddToCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    enum EntryType: String, CaseIterable, Identifiable {
        case event = "Event"
        case reminder = "Reminder"
        var id: String { rawValue }
    }

    let task: JDTask

    @State private var entryType: EntryType = .event
    @State private var date: Date
    @State private var isAllDay: Bool
    @State private var time: Date
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarID: String? = nil

    @State private var permissionState: PermissionState = .unknown
    @State private var errorMessage: String? = nil
    @State private var showSuccessAlert = false
    @State private var createdItemURL: URL? = nil

    private enum PermissionState { case unknown, granted, denied }

    init(task: JDTask) {
        self.task = task
        let initialDate = task.taskDate ?? Date()
        _date = State(initialValue: initialDate)
        _isAllDay = State(initialValue: task.taskDate != nil)
        let cal = Calendar.current
        let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: initialDate) ?? initialDate
        _time = State(initialValue: nineAM)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $entryType) {
                        ForEach(EntryType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: entryType) { _, _ in loadCalendars() }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    if entryType == .event {
                        Toggle("All-day", isOn: $isAllDay)
                        if !isAllDay {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    } else {
                        DatePicker("Due time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }

                if !availableCalendars.isEmpty {
                    Section(entryType == .event ? "Calendar" : "List") {
                        Picker(entryType == .event ? "Calendar" : "List", selection: $selectedCalendarID) {
                            ForEach(availableCalendars, id: \.calendarIdentifier) { c in
                                Text(c.title).tag(Optional(c.calendarIdentifier))
                            }
                        }
                    }
                }

                if permissionState == .denied {
                    Section {
                        Text("Permission denied. Enable access in Settings to continue.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to iPhone Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(permissionState == .denied || availableCalendars.isEmpty)
                }
            }
            .task { await ensurePermissionAndLoad() }
            .alert(
                "Couldn't Add",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                entryType == .event ? "Added to Calendar" : "Added to Reminders",
                isPresented: $showSuccessAlert
            ) {
                if let url = createdItemURL {
                    Button("Open") {
                        UIApplication.shared.open(url)
                        dismiss()
                    }
                }
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Permission + calendars

    private func ensurePermissionAndLoad() async {
        do {
            switch entryType {
            case .event:    try await CalendarService.requestEventAccess()
            case .reminder: try await CalendarService.requestReminderAccess()
            }
            permissionState = .granted
            loadCalendars()
        } catch {
            permissionState = .denied
        }
    }

    private func loadCalendars() {
        switch entryType {
        case .event:
            availableCalendars = CalendarService.availableEventCalendars()
            selectedCalendarID = CalendarService.defaultEventCalendar()?.calendarIdentifier
                ?? availableCalendars.first?.calendarIdentifier
        case .reminder:
            availableCalendars = CalendarService.availableReminderLists()
            selectedCalendarID = CalendarService.defaultReminderList()?.calendarIdentifier
                ?? availableCalendars.first?.calendarIdentifier
        }
        // Re-request permission for the second type if user toggles.
        if availableCalendars.isEmpty {
            Task { await ensurePermissionAndLoad() }
        }
    }

    // MARK: - Add

    private func add() async {
        guard let calendarID = selectedCalendarID,
              let calendar = availableCalendars.first(where: { $0.calendarIdentifier == calendarID })
        else { return }

        do {
            let identifier: String
            switch entryType {
            case .event:
                identifier = try CalendarService.createEvent(
                    title: task.title,
                    date: date,
                    isAllDay: isAllDay,
                    startTime: isAllDay ? nil : time,
                    durationMinutes: 30,
                    calendar: calendar
                )
                createdItemURL = URL(string: "x-apple-calevent://\(identifier)")
            case .reminder:
                let due = combinedDue(date: date, time: time)
                identifier = try CalendarService.createReminder(
                    title: task.title,
                    dueDate: due,
                    calendar: calendar
                )
                _ = identifier
                createdItemURL = URL(string: "x-apple-reminderkit://")
            }

            addToInAppPlanIfEligible(date: date)
            showSuccessAlert = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func combinedDue(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: date) ?? date
    }

    private func addToInAppPlanIfEligible(date: Date) {
        let today = Date().startOfDay
        let day = date.startOfDay
        let cal = Calendar.current
        let daysAhead = cal.dateComponents([.day], from: today, to: day).day ?? -1
        guard daysAhead >= 0, daysAhead < 7 else { return }
        let plan = PlannerEngine.fetchOrCreatePlan(
            for: day,
            isWork: appState.activeContext,
            context: modelContext
        )
        guard plan.taskIDs.count < 3, !plan.taskIDs.contains(task.id) else { return }
        PlannerEngine.addToToday(task: task, plan: plan, context: modelContext)
    }
}
