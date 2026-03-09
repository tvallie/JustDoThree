import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(PremiumManager.self) private var premium
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    @State private var showBacklogPicker = false
    @State private var showTomorrowPicker = false
    @State private var addingStretch = false
    @State private var taskToDelete: UUID? = nil
    @State private var showDeleteConfirm = false
    @State private var showEditSheet: JDTask? = nil

    // MARK: - Computed

    private var todayPlan: DailyPlan? {
        plans.first { $0.date.isSameDay(as: Date()) }
    }

    private var todayTasks: [JDTask] {
        guard let plan = todayPlan else { return [] }
        return plan.taskIDs.compactMap { id in allTasks.first { $0.id == id } }
    }

    private var stretchTasks: [JDTask] {
        guard let plan = todayPlan else { return [] }
        return plan.stretchTaskIDs.compactMap { id in allTasks.first { $0.id == id } }
    }

    private var backlogTasks: [JDTask] {
        let excludeIDs = Set((todayPlan?.taskIDs ?? []) + (todayPlan?.stretchTaskIDs ?? []))
        return allTasks.filter { task in
            !excludeIDs.contains(task.id) && (!task.isCompleted || task.recurringRule != nil)
        }
    }

    private var allPrimaryDone: Bool {
        todayPlan?.isAllPrimaryComplete ?? false
    }

    private var slotsUsed: Int { todayPlan?.taskIDs.count ?? 0 }
    private var slotsLeft: Int { max(0, 3 - slotsUsed) }

    // MARK: - Body

    var body: some View {
        @Bindable var state = appState
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    dateHeader
                    progressPips
                    primaryTaskList
                    if allPrimaryDone && slotsUsed > 0 {
                        celebrationBanner
                        stretchSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showBacklogPicker) {
            BacklogPickerSheet(
                title: addingStretch ? "Add a Stretch Goal" : "Add to Today",
                onSelect: { task in
                    if addingStretch {
                        addStretch(task)
                    } else {
                        addToToday(task)
                    }
                }
            )
        }
        .sheet(item: $showEditSheet) { task in
            AddTaskSheet(existingTask: task)
        }
        .sheet(isPresented: $showTomorrowPicker) {
            TomorrowPickerSheet(onSelect: addStretch)
        }
        .sheet(isPresented: $state.showRolloverSheet) {
            RolloverSheet()
        }
        .confirmationDialog(
            "Remove this task from today?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave the slot open", role: .destructive) {
                if let id = taskToDelete { removeFromToday(id) }
            }
            Button("Choose from backlog instead") {
                if let id = taskToDelete { removeFromToday(id) }
                addingStretch = false
                showBacklogPicker = true
            }
            Button("Cancel", role: .cancel) { taskToDelete = nil }
        }
        .onAppear {
            appState.checkDayTransition(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.checkDayTransition(context: modelContext)
            }
        }
    }

    // MARK: - Subviews

    private var dateHeader: some View {
        Text(Date().longDayString)
            .font(.title2.weight(.semibold))
    }

    private var progressPips: some View {
        HStack(spacing: 10) {
            let done = todayPlan?.primaryCompletedCount ?? 0
            let total = slotsUsed
            ForEach(0..<3) { i in
                Circle()
                    .fill(pipColor(index: i, done: done, total: total))
                    .frame(width: 10, height: 10)
                    .animation(.easeInOut(duration: 0.2), value: done)
            }
            Text(progressLabel(done: done, total: total))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func pipColor(index: Int, done: Int, total: Int) -> Color {
        if index < done { return .accentColor }
        if index < total { return Color(.tertiarySystemFill) }
        return Color(.quaternarySystemFill)
    }

    private func progressLabel(done: Int, total: Int) -> String {
        if total == 0 { return "No tasks yet" }
        if done == total { return "All done" }
        return "\(done) of \(total)"
    }

    private var primaryTaskList: some View {
        VStack(spacing: 10) {
            if todayTasks.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Pick your three",
                    message: "Choose up to three tasks to focus on today.",
                    actionTitle: "Add from Backlog",
                    action: { addingStretch = false; showBacklogPicker = true }
                )
            } else {
                ForEach(todayTasks) { task in
                    let isComplete = todayPlan?.completedTaskIDs.contains(task.id) ?? false
                    TaskCard(
                        task: task,
                        isCompleted: isComplete,
                        onToggle: { isComplete ? uncomplete(task) : complete(task) },
                        onDelete: { taskToDelete = task.id; showDeleteConfirm = true },
                        onEdit: { showEditSheet = task },
                        onReplace: {
                            removeFromToday(task.id)
                            addingStretch = false
                            showBacklogPicker = true
                        }
                    )
                }

                if slotsLeft > 0 && !allPrimaryDone {
                    Button {
                        addingStretch = false
                        showBacklogPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("Add a task")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var celebrationBanner: some View {
        VStack(spacing: 8) {
            Text("Nice work.")
                .font(.title3.bold())
            Text("You finished your three.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var stretchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stretch goals")
                    .font(.headline)
                Spacer()
                if premium.isPremium {
                    // Premium: choose source — backlog or tomorrow's plan
                    Menu {
                        Button("From Backlog", systemImage: "tray") {
                            addingStretch = true
                            showBacklogPicker = true
                        }
                        Button("From Tomorrow's Plan", systemImage: "calendar") {
                            showTomorrowPicker = true
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline)
                    }
                } else if !backlogTasks.isEmpty {
                    Button {
                        addingStretch = true
                        showBacklogPicker = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline)
                    }
                }
            }

            if stretchTasks.isEmpty {
                Text(premium.isPremium
                     ? "Want to keep going? Add a bonus task from your backlog or get a head start on tomorrow."
                     : "Want to keep going? Pick a bonus task from your backlog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stretchTasks) { task in
                    let isComplete = todayPlan?.completedStretchIDs.contains(task.id) ?? false
                    TaskCard(
                        task: task,
                        isCompleted: isComplete,
                        isStretch: true,
                        onToggle: {
                            if isComplete { uncompleteStretch(task) } else { completeStretch(task) }
                        },
                        onDelete: {
                            if let plan = todayPlan {
                                PlannerEngine.removeStretch(taskID: task.id, plan: plan, context: modelContext)
                            }
                        },
                        onEdit: { showEditSheet = task }
                    )
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                AppLogoView(size: 26)
                Text("Just Do Three")
                    .font(.headline)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if slotsLeft > 0 && !allPrimaryDone {
                Button {
                    addingStretch = false
                    showBacklogPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Actions

    private func addToToday(_ task: JDTask) {
        let plan = todayPlan ?? PlannerEngine.fetchOrCreateTodayPlan(context: modelContext)
        PlannerEngine.addToToday(task: task, plan: plan, context: modelContext)
    }

    private func removeFromToday(_ id: UUID) {
        guard let plan = todayPlan else { return }
        PlannerEngine.removeFromToday(taskID: id, plan: plan, context: modelContext)
        taskToDelete = nil
    }

    private func complete(_ task: JDTask) {
        guard let plan = todayPlan else { return }
        PlannerEngine.complete(task: task, plan: plan, context: modelContext)
    }

    private func uncomplete(_ task: JDTask) {
        guard let plan = todayPlan else { return }
        PlannerEngine.uncomplete(task: task, plan: plan, context: modelContext)
    }

    private func addStretch(_ task: JDTask) {
        guard let plan = todayPlan else { return }
        PlannerEngine.addStretch(task: task, plan: plan, context: modelContext)
    }

    private func completeStretch(_ task: JDTask) {
        guard let plan = todayPlan else { return }
        PlannerEngine.completeStretch(task: task, plan: plan, context: modelContext)
    }

    private func uncompleteStretch(_ task: JDTask) {
        guard let plan = todayPlan else { return }
        PlannerEngine.uncomplete(task: task, plan: plan, context: modelContext)
    }
}

// MARK: - TaskCard

struct TaskCard: View {
    let task: JDTask
    let isCompleted: Bool
    var isStretch: Bool = false
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    /// Provide this to show a "Replace Task" option in the menu (today primary tasks only).
    var onReplace: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Completion circle
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCompleted ? .green : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)

            // Tap title to edit
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(isCompleted, color: .secondary)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if task.rolloverCount > 0 {
                        Text("Rolled over \(task.rolloverCount)×")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            // ··· action menu — always visible
            Menu {
                Button("Edit", systemImage: "pencil") { onEdit() }
                if let onReplace, !isCompleted {
                    Button("Replace Task", systemImage: "arrow.left.arrow.right") { onReplace() }
                }
                Divider()
                Button("Remove from Today", systemImage: "xmark", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - BacklogPickerSheet

struct BacklogPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]

    /// Which day this picker is adding tasks to (defaults to today).
    var forDate: Date = Date()
    var title: String = "Add to Today"
    let onSelect: (JDTask) -> Void

    @State private var newTaskTitle = ""
    @FocusState private var fieldFocused: Bool

    // MARK: - Derived sets

    /// Tasks already in the target day's plan — shown disabled, not selectable.
    private var inTargetPlanItems: [JDTask] {
        guard let plan = plans.first(where: { $0.date.isSameDay(as: forDate) }) else { return [] }
        let ids = Set(plan.taskIDs + plan.stretchTaskIDs)
        return allTasks.filter { ids.contains($0.id) }
    }

    private var inTargetPlanIDs: Set<UUID> {
        Set(inTargetPlanItems.map { $0.id })
    }

    /// Tasks scheduled on any OTHER day — shown disabled with the day name.
    private var scheduledElsewhere: [(task: JDTask, dayLabel: String)] {
        allTasks.compactMap { task -> (JDTask, String)? in
            guard !task.isCompleted || task.recurringRule != nil else { return nil }
            guard !inTargetPlanIDs.contains(task.id) else { return nil }
            let today = Date().startOfDay
            for plan in plans where !plan.date.isSameDay(as: forDate) && plan.date >= today {
                if plan.taskIDs.contains(task.id) || plan.stretchTaskIDs.contains(task.id) {
                    let label = plan.date.isSameDay(as: Date()) ? "Today" : plan.date.shortDayString
                    return (task, label)
                }
            }
            return nil
        }
    }

    private var scheduledElsewhereIDs: Set<UUID> {
        Set(scheduledElsewhere.map { $0.task.id })
    }

    // MARK: - Available backlog

    /// Tasks free to be scheduled — not already in any plan, not completed (unless recurring).
    private var backlogTasks: [JDTask] {
        let busy = inTargetPlanIDs.union(scheduledElsewhereIDs)
        return allTasks.filter { task in
            !busy.contains(task.id) && (!task.isCompleted || task.recurringRule != nil)
        }
    }

    /// Backlog filtered by the user's search text.
    private var filteredTasks: [JDTask] {
        let q = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return backlogTasks }
        return backlogTasks.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var trimmed: String { newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var targetDayLabel: String {
        forDate.isSameDay(as: Date()) ? "today's plan" : "this day's plan"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // ── Always-visible new-task row ──
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)

                        TextField("Type a new task…", text: $newTaskTitle)
                            .submitLabel(.done)
                            .focused($fieldFocused)
                            .onSubmit { createAndAdd() }

                        if !trimmed.isEmpty {
                            Button("Add") { createAndAdd() }
                                .bold()
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── Available backlog picks ──
                if filteredTasks.isEmpty && trimmed.isEmpty {
                    Section {
                        Label("Your backlog is empty — type above to create your first task.",
                              systemImage: "tray")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                } else if !filteredTasks.isEmpty {
                    Section("From backlog") {
                        ForEach(filteredTasks) { task in
                            Button {
                                onSelect(task)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                    if task.rolloverCount > 0 {
                                        Text("Rolled over \(task.rolloverCount)×")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Already in this day's plan (disabled) ──
                if !inTargetPlanItems.isEmpty {
                    Section("Already in \(targetDayLabel)") {
                        ForEach(inTargetPlanItems) { task in
                            HStack {
                                Text(task.title)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // ── Scheduled on a different day (disabled) ──
                if !scheduledElsewhere.isEmpty {
                    Section("Scheduled on another day") {
                        ForEach(scheduledElsewhere, id: \.task.id) { item in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task.title)
                                        .foregroundStyle(.secondary)
                                    Text("Planned for \(item.dayLabel)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if backlogTasks.isEmpty { fieldFocused = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func createAndAdd() {
        guard !trimmed.isEmpty else { return }
        let nextOrder = (allTasks.map(\.sortOrder).max() ?? -1) + 1
        let task = JDTask(title: trimmed, sortOrder: nextOrder)
        modelContext.insert(task)
        try? modelContext.save()
        onSelect(task)
        dismiss()
    }
}

// MARK: - TomorrowPickerSheet

/// Lets a premium user pull a task from tomorrow's plan into today as a stretch goal.
/// The task is removed from tomorrow's plan when added to today.
struct TomorrowPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]

    let onSelect: (JDTask) -> Void

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private var todayExcludedIDs: Set<UUID> {
        let plan = plans.first { $0.date.isSameDay(as: Date()) }
        return Set((plan?.taskIDs ?? []) + (plan?.stretchTaskIDs ?? []))
    }

    /// Tasks in tomorrow's plan that aren't already in today's list and aren't completed.
    private var tomorrowTasks: [JDTask] {
        guard let plan = plans.first(where: { $0.date.isSameDay(as: tomorrow) }) else { return [] }
        return plan.taskIDs.compactMap { id -> JDTask? in
            guard let task = allTasks.first(where: { $0.id == id }) else { return nil }
            guard !todayExcludedIDs.contains(id) else { return nil }
            guard !task.isCompleted || task.recurringRule != nil else { return nil }
            return task
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tomorrowTasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Nothing on tomorrow's plan")
                            .font(.headline)
                        Text("Plan your next day in the week view to see tasks here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(tomorrowTasks) { task in
                                Button {
                                    if let tomorrowPlan = plans.first(where: { $0.date.isSameDay(as: tomorrow) }) {
                                        PlannerEngine.removeFromToday(taskID: task.id, plan: tomorrowPlan, context: modelContext)
                                    }
                                    onSelect(task)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .foregroundStyle(.primary)
                                        if task.rolloverCount > 0 {
                                            Text("Rolled over \(task.rolloverCount)×")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Tomorrow's plan")
                        } footer: {
                            Text("The task will move to today and be removed from tomorrow's plan.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("From Tomorrow's Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    TodayView()
        .environment(AppState())
        .environment(PremiumManager())
        .modelContainer(previewContainer)
}
