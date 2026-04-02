import SwiftUI
import SwiftData

/// Modal sheet shown when the app opens on a new day and finds incomplete tasks
/// from a previous day. The user decides what to do with each one.
struct RolloverSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    private var todayPlan: DailyPlan? {
        plans.first { $0.date.isSameDay(as: Date()) }
    }

    private var todayTasks: [JDTask] {
        guard let plan = todayPlan else { return [] }
        return plan.taskIDs.compactMap { id in allTasks.first { $0.id == id } }
    }

    private var todaySlotsFree: Int {
        max(0, 3 - (todayPlan?.taskIDs.count ?? 0))
    }

    @State private var activeScheduleConflict: ScheduleConflict? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("A few things carried over")
                        .font(.headline)
                    Text("What would you like to do with these?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        // Bulk apply bar
                        ApplyToAllBar(slotsAvailable: todaySlotsFree) { choice in
                            applyToAll(choice)
                        }

                        Divider()
                            .padding(.horizontal, 20)

                        ForEach(Array(appState.rolloverItems.enumerated()), id: \.element.id) { index, item in
                            RolloverItemRow(
                                item: item,
                                slotsAvailable: todaySlotsFree,
                                todayTasks: todayTasks
                            ) { choice in
                                var updated = appState.rolloverItems
                                updated[index].choice = choice
                                updated[index].isIndividuallySet = true
                                appState.rolloverItems = updated
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)

                            if index < appState.rolloverItems.count - 1 {
                                Divider()
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Divider()

                // Footer
                VStack(spacing: 12) {
                    Button {
                        confirmChoices()
                    } label: {
                        Text("Confirm")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip for now") {
                        appState.dismissRolloverWithoutChanges()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Yesterday's Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .sheet(item: $activeScheduleConflict) { conflict in
                ScheduleOverflowResolutionSheet(conflict: conflict) { keptTaskIDs in
                    resolve(conflict: conflict, keeping: keptTaskIDs)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func applyToAll(_ choice: RolloverItem.Choice) {
        var updated = appState.rolloverItems
        var slotsRemaining = todaySlotsFree
        for i in updated.indices where !updated[i].isIndividuallySet {
            if case .addToToday = choice {
                if slotsRemaining > 0 {
                    updated[i].choice = .addToToday
                    slotsRemaining -= 1
                }
                // If no slots remain, leave this item's choice unchanged
            } else {
                updated[i].choice = choice
            }
        }
        appState.rolloverItems = updated
    }

    private func confirmChoices() {
        if let conflict = scheduleConflicts.first {
            if conflict.availableSlots <= 0 {
                resolve(conflict: conflict, keeping: [])
            } else {
                activeScheduleConflict = conflict
            }
            return
        }

        appState.applyRolloverChoices(context: modelContext)
    }

    private var scheduleConflicts: [ScheduleConflict] {
        let grouped = Dictionary(grouping: appState.rolloverItems) { item -> Date? in
            if case .scheduleFor(let date) = item.choice {
                return date.startOfDay
            }
            return nil
        }

        return grouped.compactMap { key, items -> ScheduleConflict? in
            guard let date = key else { return nil }
            let existingPlan = plans.first { $0.date.isSameDay(as: date) }
            let availableSlots = max(0, 3 - (existingPlan?.taskIDs.count ?? 0))
            guard items.count > availableSlots else { return nil }
            return ScheduleConflict(date: date, availableSlots: availableSlots, items: items.sorted { $0.task.sortOrder < $1.task.sortOrder })
        }
        .sorted { $0.date < $1.date }
    }

    private func resolve(conflict: ScheduleConflict, keeping keptTaskIDs: Set<UUID>) {
        var updated = appState.rolloverItems
        for index in updated.indices {
            guard case .scheduleFor(let date) = updated[index].choice,
                  date.isSameDay(as: conflict.date)
            else { continue }

            if keptTaskIDs.contains(updated[index].id) {
                updated[index].choice = .scheduleFor(conflict.date)
            } else {
                updated[index].choice = .backlog
            }
            updated[index].isIndividuallySet = true
        }

        appState.rolloverItems = updated
        activeScheduleConflict = nil
        confirmChoices()
    }
}

private struct ScheduleConflict: Identifiable {
    let date: Date
    let availableSlots: Int
    let items: [RolloverItem]

    var id: Date { date }
}

// MARK: - Apply to all bar

private struct ApplyToAllBar: View {
    let slotsAvailable: Int
    let onApply: (RolloverItem.Choice) -> Void
    @State private var showSchedulePicker = false

    private let choiceColumns = [
        GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apply to all unset")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: choiceColumns, alignment: .leading, spacing: 8) {
                    applyButton("Done", choice: .doneYesterday, icon: "checkmark")
                    applyButton("Today", choice: .addToToday, icon: "calendar",
                               disabled: slotsAvailable <= 0)
                    Button {
                        showSchedulePicker = true
                    } label: {
                        choiceLabel("Schedule", icon: "calendar.badge.plus")
                            .background(Color(.tertiarySystemFill))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    applyButton("Backlog", choice: .backlog, icon: "tray")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .sheet(isPresented: $showSchedulePicker) {
            DayPickerSheet { date in
                onApply(.scheduleFor(date))
                showSchedulePicker = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func applyButton(
        _ label: String,
        choice: RolloverItem.Choice,
        icon: String,
        disabled: Bool = false
    ) -> some View {
        Button {
            onApply(choice)
        } label: {
            choiceLabel(label, icon: icon)
                .background(Color(.tertiarySystemFill))
                .foregroundStyle(disabled ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func choiceLabel(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .clipShape(Capsule())
    }
}

// MARK: - Row

private struct RolloverItemRow: View {
    let item: RolloverItem
    let slotsAvailable: Int
    let todayTasks: [JDTask]
    let onChoiceChange: (RolloverItem.Choice) -> Void

    @State private var showSchedulePicker = false

    private let choiceColumns = [
        GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)
    ]

    // MARK: Helpers

    private var isTodaySelected: Bool {
        switch item.choice {
        case .addToToday, .addToTodayReplacing: return true
        default: return false
        }
    }

    private var isScheduleSelected: Bool {
        if case .scheduleFor = item.choice { return true }
        return false
    }

    private var scheduleButtonLabel: String {
        if case .scheduleFor(let date) = item.choice {
            return date.formatted(.dateTime.weekday(.abbreviated).day())
        }
        return "Schedule"
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Task title + lock indicator
            HStack {
                Text(item.task.title)
                    .font(.body)
                Spacer()
                if item.isIndividuallySet {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }

            // Choice buttons
            LazyVGrid(columns: choiceColumns, alignment: .leading, spacing: 8) {
                choiceButton("Done", icon: "checkmark",
                             isSelected: item.choice == .doneYesterday) {
                    onChoiceChange(.doneYesterday)
                }

                // Today
                Button {
                    onChoiceChange(.addToToday)
                } label: {
                    choiceLabel("Today", icon: "calendar")
                        .background(isTodaySelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(isTodaySelected ? .white : .primary)
                }
                .buttonStyle(.plain)

                // Schedule
                Button {
                    showSchedulePicker = true
                } label: {
                    choiceLabel(scheduleButtonLabel, icon: "calendar.badge.plus")
                        .background(isScheduleSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(isScheduleSelected ? .white : .primary)
                }
                .buttonStyle(.plain)

                choiceButton("Backlog", icon: "tray",
                             isSelected: item.choice == .backlog) {
                    onChoiceChange(.backlog)
                }
            }

            // Replace picker — expands when Today is selected but today is full
            if isTodaySelected && slotsAvailable <= 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today is full — pick a task to replace:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(todayTasks) { task in
                        let isPickedForReplace: Bool = {
                            if case .addToTodayReplacing(let id) = item.choice { return id == task.id }
                            return false
                        }()
                        Button {
                            onChoiceChange(.addToTodayReplacing(taskID: task.id))
                        } label: {
                            HStack {
                                Text(task.title)
                                    .font(.caption)
                                    .foregroundStyle(isPickedForReplace ? .white : .primary)
                                Spacer()
                                if isPickedForReplace {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isPickedForReplace ? Color.accentColor : Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Replaced task goes to backlog.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showSchedulePicker) {
            DayPickerSheet { date in
                onChoiceChange(.scheduleFor(date))
                showSchedulePicker = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func choiceButton(
        _ label: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            choiceLabel(label, icon: icon)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func choiceLabel(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .clipShape(Capsule())
    }
}

// MARK: - Day picker sheet

private struct DayPickerSheet: View {
    let onSelect: (Date) -> Void

    private var futureDays: [Date] {
        (1...7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date().startOfDay)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Schedule for...")
                .font(.headline)
                .padding(.top, 24)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: 12
            ) {
                ForEach(futureDays, id: \.self) { day in
                    Button {
                        onSelect(day)
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(day.formatted(.dateTime.day()))
                                .font(.callout.bold())
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 60, height: 52)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

private struct ScheduleOverflowResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let conflict: ScheduleConflict
    let onConfirm: (Set<UUID>) -> Void

    @State private var selectedTaskIDs: Set<UUID>

    init(conflict: ScheduleConflict, onConfirm: @escaping (Set<UUID>) -> Void) {
        self.conflict = conflict
        self.onConfirm = onConfirm
        let initiallySelected = Set(conflict.items.prefix(conflict.availableSlots).map(\.id))
        _selectedTaskIDs = State(initialValue: initiallySelected)
    }

    private var heading: String {
        if conflict.availableSlots <= 0 {
            return "No spots are open on \(conflict.date.shortDayString)."
        }
        return "Choose \(conflict.availableSlots) task\(conflict.availableSlots == 1 ? "" : "s") to keep on \(conflict.date.shortDayString)."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(heading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Any task you do not keep here will go to the backlog.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Rollover tasks") {
                    ForEach(conflict.items) { item in
                        Button {
                            toggleSelection(for: item.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.task.title)
                                        .foregroundStyle(.primary)
                                    if item.task.rolloverCount > 0 {
                                        Text("Rolled over \(item.task.rolloverCount)×")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedTaskIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedTaskIDs.contains(item.id) ? Color.accentColor : Color(.tertiaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(conflict.availableSlots <= 0)
                    }
                }
            }
            .navigationTitle("Schedule Overflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(conflict.availableSlots <= 0 ? "Send to Backlog" : "Confirm") {
                        onConfirm(selectedTaskIDs)
                        dismiss()
                    }
                    .disabled(conflict.availableSlots > 0 && selectedTaskIDs.count != conflict.availableSlots)
                }
            }
        }
    }

    private func toggleSelection(for taskID: UUID) {
        guard conflict.availableSlots > 0 else { return }

        if selectedTaskIDs.contains(taskID) {
            selectedTaskIDs.remove(taskID)
            return
        }

        guard selectedTaskIDs.count < conflict.availableSlots else { return }
        selectedTaskIDs.insert(taskID)
    }
}

#Preview {
    RolloverSheet()
        .environment(AppState())
        .modelContainer(previewContainer)
}
