import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(PremiumManager.self) private var premium

    @Query(sort: \CompletionLog.completionDate, order: .reverse)
    private var logs: [CompletionLog]

    @Query(sort: \JDTask.rolloverCount, order: .reverse)
    private var tasks: [JDTask]

    var body: some View {
        NavigationStack {
            analyticsContent
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

    // MARK: - Analytics

    private var analyticsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                StatsCardRow(logs: logs)
                PerfectDaysCard(logs: logs)
                MostAvoidedCard(tasks: tasks.filter { $0.rolloverCount > 0 })
                RecentCompletionsCard(logs: Array(logs.prefix(20)))
            }
            .padding()
        }
    }

    // MARK: - Grouping helper

    private var groupedLogs: [(date: Date, logs: [CompletionLog])] {
        let grouped = Dictionary(grouping: logs) { $0.planDate }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, logs: $0.value) }
    }
}

// MARK: - Analytics Cards

struct StatsCardRow: View {
    let logs: [CompletionLog]

    private var primaryLogs: [CompletionLog] { logs.filter { !$0.isStretchGoal } }
    private var stretchLogs: [CompletionLog] { logs.filter { $0.isStretchGoal } }
    private var daysWithCompletions: Int {
        Set(primaryLogs.map { $0.planDate }).count
    }
    private var avgPerDay: Double {
        guard daysWithCompletions > 0 else { return 0 }
        return Double(primaryLogs.count) / Double(daysWithCompletions)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "\(primaryLogs.count)", label: "Completed")
            StatTile(value: "\(stretchLogs.count)", label: "Stretch goals")
            StatTile(value: String(format: "%.1f", avgPerDay), label: "Avg / day")
            StatTile(value: "\(daysWithCompletions)", label: "Active days")
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PerfectDaysCard: View {
    let logs: [CompletionLog]

    // A "perfect day" = a day with at least 3 primary completions
    private var perfectDays: Int {
        let grouped = Dictionary(grouping: logs.filter { !$0.isStretchGoal }) { $0.planDate }
        return grouped.values.filter { $0.count >= 3 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perfect days")
                .font(.headline)
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                Text("\(perfectDays)")
                    .font(.largeTitle.bold())
                Text("days with all three done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MostAvoidedCard: View {
    let tasks: [JDTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most avoided")
                .font(.headline)

            if tasks.isEmpty {
                Text("No tasks have been rolled over yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks.prefix(5)) { task in
                    HStack {
                        Text(task.title)
                            .font(.subheadline)
                        Spacer()
                        Label("\(task.rolloverCount)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RecentCompletionsCard: View {
    let logs: [CompletionLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent completions")
                .font(.headline)

            ForEach(logs, id: \.taskID) { log in
                HStack {
                    Image(systemName: log.isStretchGoal ? "star.fill" : "checkmark.circle.fill")
                        .foregroundStyle(log.isStretchGoal ? .orange : .green)
                    Text(log.taskTitle)
                        .font(.subheadline)
                    Spacer()
                    Text(log.planDate.monthDayString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HistoryView()
        .environment(PremiumManager())
        .modelContainer(previewContainer)
}
