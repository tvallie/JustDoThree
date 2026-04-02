import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    @State private var showBacklogPicker = false
    @State private var showTomorrowPicker = false
    @State private var showBrag = false
    @State private var addingStretch = false
    @State private var taskToDelete: UUID? = nil
    @State private var showDeleteConfirm = false
    @State private var showEditSheet: JDTask? = nil
    @State private var showConfetti = false
    @State private var confettiBurstID = UUID()
    @State private var celebrationCount = 0
    @AppStorage("jdt_autoScheduleRecurring") private var autoScheduleRecurring = false

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

    private var completedTaskTitles: [String] {
        guard let plan = todayPlan else { return [] }
        return todayTasks.filter { plan.completedTaskIDs.contains($0.id) }.map(\.title)
    }

    private var completedStretchTitles: [String] {
        guard let plan = todayPlan else { return [] }
        return stretchTasks.filter { plan.completedStretchIDs.contains($0.id) }.map(\.title)
    }

    private var slotsUsed: Int { todayTasks.count }
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
            .overlay(alignment: .top) {
                if showConfetti {
                    CelebrationConfettiView()
                        .id(confettiBurstID)
                        .frame(height: 260)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .sensoryFeedback(.success, trigger: celebrationCount)
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
        .sheet(isPresented: $showBrag) {
            BragSheet(
                date: Date(),
                completedTasks: completedTaskTitles,
                completedStretches: completedStretchTitles
            )
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
        .onChange(of: autoScheduleRecurring) { _, enabled in
            if enabled {
                PlannerEngine.autoScheduleRecurring(for: Date(), context: modelContext)
            }
        }
        .onChange(of: allPrimaryDone) { _, newValue in
            guard newValue else { return }
            ReviewManager.shared.recordPerfectDay()
            triggerCelebration()
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
                    message: "Choose up to three tasks to focus on today."
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

    private var celebrationBanner: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("Nice work.")
                    .font(.title3.bold())
                Text("You finished your three.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                showBrag = true
            } label: {
                Label("Share your win", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
            }

            if stretchTasks.isEmpty {
                Text("Want to keep going? Add a bonus task from your backlog or get a head start on tomorrow.")
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
    }

    // MARK: - Actions

    private func addToToday(_ task: JDTask) {
        let plan = todayPlan ?? PlannerEngine.fetchOrCreateTodayPlan(context: modelContext)
        // Remove any IDs that no longer correspond to a real task (defensive cleanup)
        let validIDs = Set(allTasks.map(\.id))
        plan.taskIDs.removeAll { !validIDs.contains($0) }
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

    private func triggerCelebration() {
        confettiBurstID = UUID()
        celebrationCount += 1
        withAnimation(.easeOut(duration: 0.2)) {
            showConfetti = true
        }

        let burstID = confettiBurstID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard burstID == confettiBurstID else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showConfetti = false
            }
        }
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
    var removeActionTitle: String = "Remove from Today"
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

            if task.recurringRule != nil {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.teal)
            }

            // ··· action menu — always visible
            Menu {
                Button("Edit", systemImage: "pencil") { onEdit() }
                if let onReplace, !isCompleted {
                    Button("Replace Task", systemImage: "arrow.left.arrow.right") { onReplace() }
                }
                Divider()
                Button(removeActionTitle, systemImage: "xmark", role: .destructive) { onDelete() }
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

private struct CelebrationConfettiView: View {
    private let pieces = CelebrationConfettiPiece.sampleBurst
    @State private var animateBurst = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: piece.cornerRadius, style: .continuous)
                        .fill(piece.color.gradient)
                        .frame(width: piece.size.width, height: piece.size.height)
                        .rotationEffect(.degrees(animateBurst ? piece.endRotation : piece.startRotation))
                        .position(
                            x: proxy.size.width * (animateBurst ? piece.endX : piece.startX),
                            y: animateBurst ? piece.endY : -24
                        )
                        .opacity(animateBurst ? 0 : 1)
                        .animation(
                            .timingCurve(0.2, 0.8, 0.2, 1, duration: piece.duration)
                                .delay(piece.delay),
                            value: animateBurst
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                animateBurst = false
                DispatchQueue.main.async {
                    animateBurst = true
                }
            }
        }
    }
}

private struct CelebrationConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let size: CGSize
    let startX: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let startRotation: Double
    let endRotation: Double
    let delay: Double
    let duration: Double
    let cornerRadius: CGFloat

    static let sampleBurst: [CelebrationConfettiPiece] = [
        .init(id: 0, color: .pink, size: CGSize(width: 10, height: 18), startX: 0.18, endX: 0.06, endY: 200, startRotation: -10, endRotation: 220, delay: 0.00, duration: 1.20, cornerRadius: 4),
        .init(id: 1, color: .orange, size: CGSize(width: 12, height: 16), startX: 0.24, endX: 0.18, endY: 228, startRotation: 12, endRotation: -180, delay: 0.04, duration: 1.05, cornerRadius: 5),
        .init(id: 2, color: .yellow, size: CGSize(width: 9, height: 20), startX: 0.31, endX: 0.28, endY: 212, startRotation: -22, endRotation: 260, delay: 0.08, duration: 1.18, cornerRadius: 4),
        .init(id: 3, color: .green, size: CGSize(width: 11, height: 14), startX: 0.38, endX: 0.36, endY: 236, startRotation: 20, endRotation: -210, delay: 0.02, duration: 1.26, cornerRadius: 5),
        .init(id: 4, color: .mint, size: CGSize(width: 8, height: 18), startX: 0.46, endX: 0.41, endY: 190, startRotation: -12, endRotation: 170, delay: 0.00, duration: 0.98, cornerRadius: 4),
        .init(id: 5, color: .teal, size: CGSize(width: 10, height: 10), startX: 0.52, endX: 0.55, endY: 220, startRotation: 0, endRotation: 360, delay: 0.06, duration: 1.12, cornerRadius: 10),
        .init(id: 6, color: .cyan, size: CGSize(width: 9, height: 18), startX: 0.58, endX: 0.63, endY: 210, startRotation: 18, endRotation: -190, delay: 0.01, duration: 1.04, cornerRadius: 4),
        .init(id: 7, color: .blue, size: CGSize(width: 11, height: 16), startX: 0.64, endX: 0.73, endY: 235, startRotation: -18, endRotation: 240, delay: 0.09, duration: 1.22, cornerRadius: 5),
        .init(id: 8, color: .indigo, size: CGSize(width: 10, height: 18), startX: 0.70, endX: 0.82, endY: 205, startRotation: 10, endRotation: -220, delay: 0.03, duration: 1.08, cornerRadius: 4),
        .init(id: 9, color: .purple, size: CGSize(width: 12, height: 12), startX: 0.78, endX: 0.92, endY: 198, startRotation: -8, endRotation: 190, delay: 0.07, duration: 1.16, cornerRadius: 6),
        .init(id: 10, color: .red, size: CGSize(width: 8, height: 16), startX: 0.43, endX: 0.22, endY: 248, startRotation: -30, endRotation: 310, delay: 0.12, duration: 1.30, cornerRadius: 4),
        .init(id: 11, color: .accentColor, size: CGSize(width: 10, height: 14), startX: 0.57, endX: 0.79, endY: 244, startRotation: 24, endRotation: -260, delay: 0.11, duration: 1.28, cornerRadius: 4),
    ]
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
        let startOrder = PlannerEngine.topInsertionStartOrder(existingTasks: allTasks, count: 1)
        let task = JDTask(title: trimmed, sortOrder: startOrder)
        modelContext.insert(task)
        try? modelContext.save()
        onSelect(task)
        dismiss()
    }
}

// MARK: - TomorrowPickerSheet

/// Lets users pull a task from tomorrow's plan into today as a stretch goal.
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
        .modelContainer(previewContainer)
}
