import SwiftUI
import SwiftData

struct PlanView: View {
    var body: some View {
        NavigationStack {
            WeekPlannerView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            AppLogoView(size: 26)
                            Text("Just Do Three")
                                .font(.headline)
                        }
                    }
                }
        }
    }
}

// MARK: - Week planner (premium)

struct WeekPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    @State private var selectedDay: Date = Date().startOfDay
    @State private var showBacklogPicker = false
    @State private var addingStretch = false
    @State private var taskToRemove: UUID? = nil
    @State private var taskToRemoveIsStretch = false
    @State private var showDeleteConfirm = false
    @State private var showEditSheet: JDTask? = nil
    @AppStorage("jdt_autoScheduleRecurring") private var autoScheduleRecurring = false

    private var upcomingDays: [Date] {
        (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date().startOfDay)
        }
    }

    private var selectedPlan: DailyPlan? {
        plans.first { $0.date.isSameDay(as: selectedDay) }
    }

    private var selectedPlanTasks: [JDTask] {
        guard let plan = selectedPlan else { return [] }
        return plan.taskIDs.compactMap { id in allTasks.first { $0.id == id } }
    }

    private var selectedPlanStretchTasks: [JDTask] {
        guard let plan = selectedPlan else { return [] }
        return plan.stretchTaskIDs.compactMap { id in allTasks.first { $0.id == id } }
    }

    private var slotsUsed: Int { selectedPlanTasks.count }
    private var slotsLeft: Int { max(0, 3 - slotsUsed) }
    private var primaryTasksComplete: Bool {
        guard let plan = selectedPlan else { return false }
        return selectedPlanTasks.count == 3
            && selectedPlanTasks.allSatisfy { plan.completedTaskIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day selector strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(upcomingDays, id: \.self) { day in
                        DayChip(date: day, isSelected: day.isSameDay(as: selectedDay)) {
                            selectedDay = day
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemBackground))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    primaryTaskSection
                    if primaryTasksComplete {
                        stretchSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showBacklogPicker) {
            BacklogPickerSheet(
                forDate: selectedDay,
                title: addingStretch ? "Add a Stretch Goal" : "Add to \(selectedDay.shortDayString)",
                onSelect: { task in
                    let plan = PlannerEngine.fetchOrCreatePlan(for: selectedDay, context: modelContext)
                    if addingStretch {
                        PlannerEngine.addStretch(task: task, plan: plan, context: modelContext)
                    } else {
                        PlannerEngine.addToToday(task: task, plan: plan, context: modelContext)
                    }
                }
            )
        }
        .sheet(item: $showEditSheet) { task in
            AddTaskSheet(existingTask: task)
        }
        .confirmationDialog(
            taskToRemoveIsStretch
                ? "Remove this stretch goal from \(selectedDay.shortDayString)?"
                : "Remove this task from \(selectedDay.shortDayString)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            if taskToRemoveIsStretch {
                Button("Remove stretch goal", role: .destructive) {
                    if let id = taskToRemove { removeStretch(id) }
                }
            } else {
                Button("Leave the slot open", role: .destructive) {
                    if let id = taskToRemove { removeFromPlan(id) }
                }
                Button("Choose from backlog instead") {
                    if let id = taskToRemove { removeFromPlan(id) }
                    addingStretch = false
                    showBacklogPicker = true
                }
            }
            Button("Cancel", role: .cancel) { clearPendingRemoval() }
        }
        .onAppear {
            if autoScheduleRecurring {
                for day in upcomingDays {
                    PlannerEngine.autoScheduleRecurring(for: day, context: modelContext)
                }
            }
        }
        .onChange(of: selectedDay) { _, day in
            if autoScheduleRecurring {
                PlannerEngine.autoScheduleRecurring(for: day, context: modelContext)
            }
        }
        .onChange(of: autoScheduleRecurring) { _, enabled in
            if enabled {
                for day in upcomingDays {
                    PlannerEngine.autoScheduleRecurring(for: day, context: modelContext)
                }
            }
        }
    }

    // MARK: - Subviews

    private var primaryTaskSection: some View {
        VStack(spacing: 10) {
            if selectedPlanTasks.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing planned yet",
                    message: "Choose up to three tasks to focus on \(selectedDay.isSameDay(as: Date()) ? "today" : selectedDay.shortDayString)."
                )
            } else {
                ForEach(selectedPlanTasks) { task in
                    let isComplete = selectedPlan?.completedTaskIDs.contains(task.id) ?? false
                    TaskCard(
                        task: task,
                        isCompleted: isComplete,
                        onToggle: { isComplete ? uncomplete(task) : complete(task) },
                        onDelete: {
                            taskToRemove = task.id
                            taskToRemoveIsStretch = false
                            showDeleteConfirm = true
                        },
                        onEdit: { showEditSheet = task },
                        removeActionTitle: "Remove from Plan",
                        onReplace: {
                            removeFromPlan(task.id)
                            addingStretch = false
                            showBacklogPicker = true
                        }
                    )
                }
            }

            if slotsLeft > 0 {
                Button {
                    addingStretch = false
                    showBacklogPicker = true
                } label: {
                    Label("Add a task", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var stretchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stretch goals")
                    .font(.headline)
                Spacer()
                Button {
                    addingStretch = true
                    showBacklogPicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                }
            }

            ForEach(selectedPlanStretchTasks) { task in
                let isComplete = selectedPlan?.completedStretchIDs.contains(task.id) ?? false
                TaskCard(
                    task: task,
                    isCompleted: isComplete,
                    isStretch: true,
                    onToggle: {
                        if isComplete { uncompleteStretch(task) } else { completeStretch(task) }
                    },
                    onDelete: {
                        taskToRemove = task.id
                        taskToRemoveIsStretch = true
                        showDeleteConfirm = true
                    },
                    onEdit: { showEditSheet = task },
                    removeActionTitle: "Remove stretch goal"
                )
            }
        }
    }

    // MARK: - Actions

    private func removeFromPlan(_ id: UUID) {
        guard let plan = selectedPlan else { return }
        PlannerEngine.removeFromToday(taskID: id, plan: plan, context: modelContext)
        clearPendingRemoval()
    }

    private func removeStretch(_ id: UUID) {
        guard let plan = selectedPlan else { return }
        PlannerEngine.removeStretch(taskID: id, plan: plan, context: modelContext)
        clearPendingRemoval()
    }

    private func clearPendingRemoval() {
        taskToRemove = nil
        taskToRemoveIsStretch = false
    }

    private func complete(_ task: JDTask) {
        guard let plan = selectedPlan else { return }
        PlannerEngine.complete(task: task, plan: plan, context: modelContext)
    }

    private func uncomplete(_ task: JDTask) {
        guard let plan = selectedPlan else { return }
        PlannerEngine.uncomplete(task: task, plan: plan, context: modelContext)
    }

    private func completeStretch(_ task: JDTask) {
        guard let plan = selectedPlan else { return }
        PlannerEngine.completeStretch(task: task, plan: plan, context: modelContext)
    }

    private func uncompleteStretch(_ task: JDTask) {
        guard let plan = selectedPlan else { return }
        PlannerEngine.uncomplete(task: task, plan: plan, context: modelContext)
    }
}

struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let onTap: () -> Void

    private var isToday: Bool { date.isSameDay(as: Date()) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.callout.bold())
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: 48, height: 52)
            .background(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemFill)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlanView()
        .modelContainer(previewContainer)
}
