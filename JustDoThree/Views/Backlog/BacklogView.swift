import SwiftUI
import SwiftData

struct BacklogView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]

    @State private var showAddSheet = false
    @State private var editingTask: JDTask? = nil
    @State private var showDeleteConfirm: JDTask? = nil

    private var todayTaskIDs: Set<UUID> {
        let plan = plans.first { $0.date.isSameDay(as: Date()) }
        return Set((plan?.taskIDs ?? []) + (plan?.stretchTaskIDs ?? []))
    }

    private var backlogTasks: [JDTask] {
        allTasks.filter { !$0.isCompleted && !todayTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if backlogTasks.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "Your backlog is clear",
                        message: "Add tasks here to pick from them each day.",
                        actionTitle: "Add a Task",
                        action: { showAddSheet = true }
                    )
                } else {
                    List {
                        ForEach(backlogTasks) { task in
                            BacklogRow(
                                task: task,
                                onEdit: { editingTask = task },
                                onDelete: { showDeleteConfirm = task }
                            )
                            // Suppress the system delete circles — we have our own button
                            .deleteDisabled(true)
                        }
                        .onMove(perform: move)
                    }
                    .listStyle(.plain)
                    // Always in edit mode so drag handles are live without tapping EditButton
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Backlog")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet()
        }
        .sheet(item: $editingTask) { task in
            AddTaskSheet(existingTask: task)
        }
        .confirmationDialog(
            "Delete \"\(showDeleteConfirm?.title ?? "")\"?",
            isPresented: Binding(
                get: { showDeleteConfirm != nil },
                set: { if !$0 { showDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                if let task = showDeleteConfirm { delete(task) }
            }
            Button("Cancel", role: .cancel) { showDeleteConfirm = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = backlogTasks
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, task) in reordered.enumerated() { task.sortOrder = i }
        try? modelContext.save()
    }

    private func delete(_ task: JDTask) {
        modelContext.delete(task)
        try? modelContext.save()
        showDeleteConfirm = nil
    }
}

// MARK: - BacklogRow

struct BacklogRow: View {
    let task: JDTask
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tap the text area to edit
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text(task.createdDate.monthDayString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if task.rolloverCount > 0 {
                            Label("\(task.rolloverCount) rollover\(task.rolloverCount == 1 ? "" : "s")",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Visible delete button — tap to confirm delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.6))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    BacklogView()
        .modelContainer(previewContainer)
}
