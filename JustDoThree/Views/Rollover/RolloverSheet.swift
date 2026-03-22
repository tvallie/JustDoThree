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
                        appState.applyRolloverChoices(context: modelContext)
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
}

// MARK: - Apply to all bar

private struct ApplyToAllBar: View {
    let slotsAvailable: Int
    let onApply: (RolloverItem.Choice) -> Void
    @State private var showSchedulePicker = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apply to all unset")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    applyButton("Done", choice: .doneYesterday, icon: "checkmark")
                    applyButton("Today", choice: .addToToday, icon: "calendar",
                               disabled: slotsAvailable <= 0)
                    Button {
                        showSchedulePicker = true
                    } label: {
                        Label("Schedule", systemImage: "calendar.badge.plus")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill))
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
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
            Label(label, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .foregroundStyle(disabled ? .secondary : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Row

private struct RolloverItemRow: View {
    let item: RolloverItem
    let slotsAvailable: Int
    let todayTasks: [JDTask]
    let onChoiceChange: (RolloverItem.Choice) -> Void

    @State private var showSchedulePicker = false

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
            HStack(spacing: 8) {
                choiceButton("Done", icon: "checkmark",
                             isSelected: item.choice == .doneYesterday) {
                    onChoiceChange(.doneYesterday)
                }

                // Today
                Button {
                    onChoiceChange(.addToToday)
                } label: {
                    Label("Today", systemImage: "calendar")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isTodaySelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(isTodaySelected ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Schedule
                Button {
                    showSchedulePicker = true
                } label: {
                    Label(scheduleButtonLabel, systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isScheduleSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(isScheduleSelected ? .white : .primary)
                        .clipShape(Capsule())
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
            Label(label, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

#Preview {
    RolloverSheet()
        .environment(AppState())
        .modelContainer(previewContainer)
}
