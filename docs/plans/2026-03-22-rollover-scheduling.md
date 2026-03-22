# Rollover Scheduling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give users full control over rolled-over tasks: schedule for today (with bump-and-replace when full), schedule for a future date, or send to backlog — individually per task or all at once via a bulk bar.

**Architecture:** Extend the `RolloverItem.Choice` enum with two new cases (`.scheduleFor(Date)` and `.addToTodayReplacing(taskID:)`), update `RolloverEngine.applyChoices()` to handle them, then rewrite `RolloverSheet.swift` with a bulk-apply bar at the top, a day-picker sheet for scheduling, and an inline replace-picker expansion when today is already full. No new SwiftData models needed.

**Tech Stack:** SwiftUI, SwiftData, `@Observable` AppState, `@Query`, `PlannerEngine`

---

## Key Files

- `JustDoThree/Engines/RolloverEngine.swift` — `RolloverItem` struct + `RolloverEngine.applyChoices()`
- `JustDoThree/Views/Rollover/RolloverSheet.swift` — full UI rewrite
- `JustDoThree/State/AppState.swift` — no changes needed; `applyRolloverChoices` already calls `fetchOrCreateTodayPlan`

## Build Verification Command

```bash
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

---

## Task 1: Extend RolloverItem data model

**Files:**
- Modify: `JustDoThree/Engines/RolloverEngine.swift` lines 1–16 (the `RolloverItem` struct and `Choice` enum)

### Context

`RolloverItem` is a plain Swift struct. `Choice` is a nested enum with three cases. We need to:
1. Add two new cases with associated values: `.scheduleFor(Date)` and `.addToTodayReplacing(taskID: UUID)`
2. Add `Equatable` conformance so we can use `==` in view code
3. Add `isIndividuallySet: Bool = false` — tracks whether the user has manually chosen this item (so bulk-apply skips it)
4. Change the default choice from `.addToToday` to `.backlog` (safer default; bulk-apply bar makes it easy to change all at once)

### Step 1: Replace the RolloverItem struct (lines 1–16 of RolloverEngine.swift)

Replace the entire struct block with:

```swift
/// Represents one task surfaced during rollover, with the user's pending choice.
struct RolloverItem: Identifiable {
    enum Choice: Equatable {
        case doneYesterday              // mark complete for the previous day
        case addToToday                 // move into today's plan (only if a slot is free)
        case addToTodayReplacing(taskID: UUID) // replace an existing today-task (it goes to backlog)
        case scheduleFor(Date)          // add to a specific future day's plan
        case backlog                    // leave in backlog (increment rolloverCount)
    }

    let id: UUID              // matches task.id
    let task: JDTask
    let fromPlan: DailyPlan
    var choice: Choice = .backlog
    var isIndividuallySet: Bool = false
}
```

### Step 2: Build to confirm it compiles

```bash
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

(The existing `choiceButton` in `RolloverSheet.swift` uses `item.choice == choice` — this will still compile once `Equatable` is added. The new cases won't be pattern-matched until later tasks.)

### Step 3: Commit

```bash
git add JustDoThree/Engines/RolloverEngine.swift
git commit -m "feat: extend RolloverItem.Choice with scheduleFor and addToTodayReplacing cases"
```

---

## Task 2: Update RolloverEngine.applyChoices()

**Files:**
- Modify: `JustDoThree/Engines/RolloverEngine.swift` lines 58–93 (the `applyChoices` method)

### Context

The switch statement inside `applyChoices` needs two new cases:
- `.addToTodayReplacing(taskID:)` — removes the bumped task's ID from `todayPlan.taskIDs` (the task stays in SwiftData, effectively back in backlog), then appends the rollover task's ID to today.
- `.scheduleFor(date)` — fetches or creates the plan for that date using `PlannerEngine.fetchOrCreatePlan(for:context:)`, then appends if under the 3-slot cap.

`PlannerEngine.fetchOrCreatePlan(for:context:)` is the same method used in `PlanView.swift` — it already exists.

### Step 1: Replace the switch body in applyChoices

The full updated `applyChoices` method:

```swift
/// Applies user's rollover choices: completes, schedules, or returns each task to backlog.
static func applyChoices(
    _ items: [RolloverItem],
    todayPlan: DailyPlan,
    context: ModelContext
) {
    for item in items {
        switch item.choice {
        case .doneYesterday:
            if !item.fromPlan.completedTaskIDs.contains(item.task.id) {
                item.fromPlan.completedTaskIDs.append(item.task.id)
            }
            let log = CompletionLog(
                taskID: item.task.id,
                taskTitle: item.task.title,
                planDate: item.fromPlan.date
            )
            context.insert(log)
            // Recurring tasks reset immediately — do not mark permanently complete
            if item.task.recurringRule == nil {
                item.task.isCompleted = true
                item.task.completionDate = Date()
            }

        case .addToToday:
            if todayPlan.taskIDs.count < 3,
               !todayPlan.taskIDs.contains(item.task.id) {
                todayPlan.taskIDs.append(item.task.id)
            }
            item.task.rolloverCount += 1

        case .addToTodayReplacing(let bumpedID):
            // Remove the bumped task from today (it stays in the task store — backlog)
            todayPlan.taskIDs.removeAll { $0 == bumpedID }
            // Add the rollover task
            if !todayPlan.taskIDs.contains(item.task.id) {
                todayPlan.taskIDs.append(item.task.id)
            }
            item.task.rolloverCount += 1

        case .scheduleFor(let date):
            let plan = PlannerEngine.fetchOrCreatePlan(for: date, context: context)
            if plan.taskIDs.count < 3, !plan.taskIDs.contains(item.task.id) {
                plan.taskIDs.append(item.task.id)
            }
            item.task.rolloverCount += 1

        case .backlog:
            item.task.rolloverCount += 1
        }
    }
    save(context: context)
}
```

### Step 2: Build

```bash
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add JustDoThree/Engines/RolloverEngine.swift
git commit -m "feat: handle scheduleFor and addToTodayReplacing in RolloverEngine.applyChoices"
```

---

## Task 3: Add DayPickerSheet subview

**Files:**
- Modify: `JustDoThree/Views/Rollover/RolloverSheet.swift` — add new private struct at the bottom (before `#Preview`)

### Context

`DayPickerSheet` is a small bottom sheet showing the next 7 days (starting tomorrow, so today is excluded — use the Today button for today). It uses the same day-chip visual style as `PlanView`'s `DayChip`. When the user taps a day, it calls `onSelect(date)` and the caller dismisses the sheet.

### Step 1: Add DayPickerSheet before the #Preview block

```swift
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
```

### Step 2: Build

```bash
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add JustDoThree/Views/Rollover/RolloverSheet.swift
git commit -m "feat: add DayPickerSheet for rollover scheduling"
```

---

## Task 4: Rewrite RolloverItemRow

**Files:**
- Modify: `JustDoThree/Views/Rollover/RolloverSheet.swift` — replace the `RolloverItemRow` struct (currently lines 85–122)

### Context

The row now shows 4 choice buttons: **Done / Today / Schedule / Backlog**.

**Today button behavior:**
- If `slotsAvailable > 0`: tapping sets choice to `.addToToday` immediately.
- If `slotsAvailable <= 0`: tapping sets choice to `.addToToday` (expanding the replace picker) but the choice stays incomplete until the user also taps a task to replace.
- When `isTodaySelected && slotsAvailable <= 0`, an inline replace-picker expands below the buttons showing each of today's tasks as tappable pills. Tapping one sets choice to `.addToTodayReplacing(taskID:)`.

**Schedule button behavior:**
- Tapping opens `DayPickerSheet` via a `@State private var showSchedulePicker`.
- When a date is selected, the button label changes to `"Thu 27"` style (weekday abbreviated + day number).

**Lock indicator:**
- When `item.isIndividuallySet == true`, a small filled `Circle()` in `Color.accentColor` appears to the right of the task title. This tells the user this row won't be affected by "Apply to all."

**New signature:** The row now takes `todayTasks: [JDTask]` so it can render the replace picker.

### Step 1: Replace the RolloverItemRow struct

```swift
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
```

### Step 2: Build

```bash
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

There will be a compile error because `RolloverSheet` is still passing the old `slotsAvailable:` parameter without `todayTasks:`. That's fine — it will be fixed in Task 5.

### Step 3: Commit after Task 5 fixes the build (do NOT commit a broken build)

Wait for Task 5 before committing.

---

## Task 5: Rewrite RolloverSheet body + add ApplyToAllBar

**Files:**
- Modify: `JustDoThree/Views/Rollover/RolloverSheet.swift` — replace `RolloverSheet` struct (lines 6–81) and add `ApplyToAllBar` private struct

### Context

Two changes to `RolloverSheet`:
1. Add `@Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]` so we can look up today's task objects by UUID for the replace picker.
2. Add computed properties: `todayPlan`, `todayTasks`, `todaySlotsFree`.
3. Add `applyToAll(_ choice:)` function that sets all non-individually-set items to the given choice.
4. Insert `ApplyToAllBar` above the task rows in the `ScrollView`.
5. Pass `todayTasks` to each `RolloverItemRow`.
6. Update each row's `onChoiceChange` closure to also set `isIndividuallySet = true`.

`ApplyToAllBar` is a new private struct with the same 4 buttons (Done/Today/Schedule/Backlog). Today is disabled when `slotsAvailable <= 0`. Schedule opens its own `DayPickerSheet`.

### Step 1: Replace RolloverSheet struct

```swift
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
        3 - (todayPlan?.taskIDs.count ?? 0)
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
        for i in updated.indices where !updated[i].isIndividuallySet {
            updated[i].choice = choice
        }
        appState.rolloverItems = updated
    }
}
```

### Step 2: Add ApplyToAllBar private struct (after the closing brace of RolloverSheet, before RolloverItemRow)

```swift
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
```

### Step 3: Build

```bash
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit Tasks 4 and 5 together

```bash
git add JustDoThree/Views/Rollover/RolloverSheet.swift
git commit -m "feat: rewrite RolloverSheet with 4-choice rows, bulk apply bar, today-full replace picker, and day scheduling"
```

---

## Final state of RolloverSheet.swift

For reference, the complete file after all changes should contain these sections in order:

1. `RolloverSheet` struct (with `@Query allTasks`, `applyToAll`, etc.)
2. `ApplyToAllBar` private struct
3. `RolloverItemRow` private struct
4. `DayPickerSheet` private struct
5. `#Preview`

## Manual Test Checklist

After build succeeds, use the debug `previewRolloverSheet` method (already hooked up in the app's debug menu or Settings tab) to trigger the sheet and verify:

- [ ] "Apply to all → Backlog" sets all rows to Backlog
- [ ] Tapping a row's "Done" locks it (blue dot appears); subsequent "Apply to all → Backlog" skips that row
- [ ] "Apply to all → Today" is disabled when today has 3 tasks
- [ ] Tapping "Schedule" on a row opens the day picker; selecting a day updates the button label
- [ ] "Apply to all → Schedule" opens one day picker; date applies to all unset rows
- [ ] Tapping "Today" when today has 3 tasks expands the replace picker; tapping a task to replace highlights it
- [ ] Tapping "Confirm" with `.addToTodayReplacing` removes the bumped task from today and adds the rollover task
- [ ] Tapping "Confirm" with `.scheduleFor(date)` adds the task to that day's plan (check Plan tab)
