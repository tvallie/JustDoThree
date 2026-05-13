import SwiftUI
import SwiftData
import WatchKit

/// Watch page showing today's primary + stretch tasks for one context
/// (personal or work). Reads from the watch's local SwiftData store.
/// Tap toggles completion locally and forwards a CompletionCommand to
/// the phone.
struct DailyPlanPage: View {
    /// Personal (`false`) or work (`true`) context. Determines which plan
    /// to display and the navigation title.
    let isWork: Bool

    @Environment(\.modelContext) private var context
    @Query private var plans: [DailyPlan]
    @Query private var allTasks: [JDTask]

    private var todayPlan: DailyPlan? {
        let today = Date()
        return plans.first { $0.date.isSameDay(as: today) && $0.isWork == isWork }
    }

    private var navTitle: String { isWork ? "Work" : "Today" }

    var body: some View {
        if let plan = todayPlan,
           !(plan.taskIDs.isEmpty && plan.stretchTaskIDs.isEmpty) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.taskIDs, id: \.self) { id in
                        if let task = task(for: id) {
                            TaskRow(
                                title: task.title,
                                isCompleted: plan.completedTaskIDs.contains(id),
                                onTap: { toggle(task: task, plan: plan, isStretch: false) }
                            )
                        }
                    }
                    if !plan.stretchTaskIDs.isEmpty {
                        Text("Stretch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(plan.stretchTaskIDs, id: \.self) { id in
                            if let task = task(for: id) {
                                TaskRow(
                                    title: task.title,
                                    isCompleted: plan.completedStretchIDs.contains(id),
                                    onTap: { toggle(task: task, plan: plan, isStretch: true) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(navTitle)
        } else {
            EmptyStateView()
                .navigationTitle(navTitle)
        }
    }

    private func task(for id: UUID) -> JDTask? {
        allTasks.first { $0.id == id }
    }

    private func toggle(task: JDTask, plan: DailyPlan, isStretch: Bool) {
        let wasCompleted: Bool
        if isStretch {
            wasCompleted = plan.completedStretchIDs.contains(task.id)
        } else {
            wasCompleted = plan.completedTaskIDs.contains(task.id)
        }
        let willComplete = !wasCompleted

        // Optimistic local update so the UI reflects the tap immediately.
        if isStretch {
            if willComplete {
                if !plan.completedStretchIDs.contains(task.id) {
                    plan.completedStretchIDs.append(task.id)
                }
            } else {
                plan.completedStretchIDs.removeAll { $0 == task.id }
            }
        } else {
            if willComplete {
                if !plan.completedTaskIDs.contains(task.id) {
                    plan.completedTaskIDs.append(task.id)
                }
            } else {
                plan.completedTaskIDs.removeAll { $0 == task.id }
            }
        }
        task.isCompleted = willComplete
        try? context.save()

        WKInterfaceDevice.current().play(willComplete ? .success : .click)

        WatchWCDelegate.shared.send(completion: CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: task.id,
            action: willComplete ? .complete : .uncomplete,
            issuedAt: Date()
        ))
    }
}

private struct TaskRow: View {
    let title: String
    let isCompleted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? Color.accentColor : Color.secondary)
                Text(title)
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Just Do Three on iPhone")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
