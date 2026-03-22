import SwiftUI
import SwiftData

/// Modal sheet shown when the app opens on a new day and finds incomplete tasks
/// from a previous day. The user decides what to do with each one.
struct RolloverSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]

    private var todaySlotsFree: Int {
        let plan = plans.first { $0.date.isSameDay(as: Date()) }
        return 3 - (plan?.taskIDs.count ?? 0)
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

                // Item rows — ScrollView avoids all List hit-testing issues
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.rolloverItems.enumerated()), id: \.element.id) { index, item in
                            RolloverItemRow(item: item, slotsAvailable: todaySlotsFree) { choice in
                                var updated = appState.rolloverItems
                                updated[index].choice = choice
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
}

// MARK: - Row

private struct RolloverItemRow: View {
    let item: RolloverItem
    let slotsAvailable: Int
    let onChoiceChange: (RolloverItem.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.task.title)
                .font(.body)

            HStack(spacing: 8) {
                choiceButton("Done", choice: .doneYesterday, icon: "checkmark")
                choiceButton("Today", choice: .addToToday, icon: "calendar",
                             disabled: item.choice != .addToToday && slotsAvailable <= 0)
                choiceButton("Backlog", choice: .backlog, icon: "tray")
            }
        }
    }

    private func choiceButton(
        _ label: String, choice: RolloverItem.Choice,
        icon: String, disabled: Bool = false
    ) -> some View {
        Button {
            onChoiceChange(choice)
        } label: {
            Label(label, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(item.choice == choice ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(item.choice == choice ? .white : (disabled ? .secondary : .primary))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
