import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(PremiumManager.self) private var premium
    @State private var showUpgrade = false

    var body: some View {
        NavigationStack {
            Group {
                if premium.isPremium {
                    WeekPlannerView()
                } else {
                    PremiumGateView(featureName: "7-Day Planning") {
                        showUpgrade = true
                    }
                    .frame(maxHeight: .infinity)
                }
            }
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
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheet()
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

    private var backlogTasks: [JDTask] {
        let scheduledIDs = Set(plans.flatMap { $0.taskIDs })
        return allTasks.filter { ($0.recurringRule != nil || !$0.isCompleted) && !scheduledIDs.contains($0.id) }
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

            // Selected day's tasks
            List {
                Section(header: Text(selectedDay.longDayString)) {
                    let plan = selectedPlan
                    if let plan {
                        ForEach(selectedPlanTasks) { task in
                            HStack {
                                Image(systemName: plan.completedTaskIDs.contains(task.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(plan.completedTaskIDs.contains(task.id) ? .green : .secondary)
                                Text(task.title)
                                    .strikethrough(plan.completedTaskIDs.contains(task.id))
                                    .foregroundStyle(plan.completedTaskIDs.contains(task.id) ? .secondary : .primary)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                let taskID = selectedPlanTasks[i].id
                                plan.taskIDs.removeAll { $0 == taskID }
                            }
                            try? modelContext.save()
                        }
                    }

                    if (selectedPlan?.taskIDs.count ?? 0) < 3 {
                        Button {
                            showBacklogPicker = true
                        } label: {
                            Label("Add task", systemImage: "plus")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                // Stretch goals — only shown if any exist for this day
                if !selectedPlanStretchTasks.isEmpty, let plan = selectedPlan {
                    Section {
                        ForEach(selectedPlanStretchTasks) { task in
                            let isComplete = plan.completedStretchIDs.contains(task.id)
                            HStack(spacing: 12) {
                                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isComplete ? .green : Color(.tertiaryLabel))
                                Text(task.title)
                                    .strikethrough(isComplete, color: .secondary)
                                    .foregroundStyle(isComplete ? .secondary : .primary)
                                Spacer()
                                if isComplete {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(
                                isComplete
                                    ? Color.accentColor.opacity(0.07)
                                    : Color(.secondarySystemGroupedBackground)
                            )
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Text("Stretch Goals")
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .sheet(isPresented: $showBacklogPicker) {
            BacklogPickerSheet(
                forDate: selectedDay,
                title: "Add to \(selectedDay.shortDayString)",
                onSelect: { task in
                    let plan = PlannerEngine.fetchOrCreatePlan(for: selectedDay, context: modelContext)
                    PlannerEngine.addToToday(task: task, plan: plan, context: modelContext)
                }
            )
        }
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
        .environment(PremiumManager())
        .modelContainer(previewContainer)
}
