# Recurring Tasks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow premium users to mark backlog tasks as weekly or monthly recurring, so they automatically reset after completion and display their schedule in the backlog.

**Architecture:** The data model (`RecurringRule`, `JDTask.recurringRuleData`) is already scaffolded. Work is split across four areas: a display helper on `RecurringRule`, completion behavior in `PlannerEngine`, a premium-gated picker UI in `AddTaskSheet`, and a label in `BacklogRow`. Recurring tasks are never permanently completed — `isCompleted` stays `false`, but a `CompletionLog` is still inserted so all history metrics count correctly.

**Tech Stack:** Swift, SwiftUI, SwiftData. No test target exists — verification is done by building in Xcode (`⌘B`) and exercising via SwiftUI Previews or Simulator.

---

### Task 1: Add `displayString` to `RecurringRule`

**Files:**
- Modify: `JustDoThree/JustDoThree/Models/RecurringRule.swift`

**Step 1: Add the computed property**

Open `RecurringRule.swift`. After the `static func monthly(dayOfMonth:)` factory, add:

```swift
/// Human-readable schedule string, e.g. "every Monday" or "3rd of every month".
var displayString: String {
    switch pattern {
    case .weekly:
        let day = weekday ?? 1
        // Calendar weekday: 1 = Sunday, 2 = Monday … 7 = Saturday
        let symbols = Calendar.current.weekdaySymbols // ["Sunday", "Monday", …]
        let name = symbols[safe: day - 1] ?? "day \(day)"
        return "every \(name)"
    case .monthly:
        let d = dayOfMonth ?? 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let ordinal = formatter.string(from: NSNumber(value: d)) ?? "\(d)"
        return "\(ordinal) of every month"
    }
}
```

You also need to add a safe-subscript extension. Add this at the bottom of the file (outside the struct):

```swift
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

**Step 2: Verify it builds**

In Xcode, press `⌘B`. Expected: build succeeds with no errors.

**Step 3: Commit**

```bash
git add JustDoThree/JustDoThree/Models/RecurringRule.swift
git commit -m "feat: add RecurringRule.displayString helper"
```

---

### Task 2: Fix completion behavior in `PlannerEngine` for recurring tasks

**Files:**
- Modify: `JustDoThree/JustDoThree/Engines/PlannerEngine.swift`

**Context:** Currently `complete()` and `completeStretch()` always set `task.isCompleted = true`. For recurring tasks this must be skipped — the `CompletionLog` is still inserted (so history metrics count it), but the task must remain active in the backlog.

**Step 1: Update `complete()`**

Find the `complete(task:plan:context:)` function (around line 82). Replace the body with:

```swift
static func complete(task: JDTask, plan: DailyPlan, context: ModelContext) {
    guard !plan.completedTaskIDs.contains(task.id) else { return }
    plan.completedTaskIDs.append(task.id)
    let isStretch = plan.stretchTaskIDs.contains(task.id)
    let log = CompletionLog(taskID: task.id, taskTitle: task.title,
                             planDate: plan.date, isStretchGoal: isStretch)
    context.insert(log)
    // Recurring tasks reset immediately — do not mark permanently complete
    if task.recurringRule == nil {
        task.isCompleted = true
        task.completionDate = Date()
    }
    try? context.save()
}
```

**Step 2: Update `completeStretch()`**

Find `completeStretch(task:plan:context:)` (around line 125). Replace the body with:

```swift
static func completeStretch(task: JDTask, plan: DailyPlan, context: ModelContext) {
    guard plan.stretchTaskIDs.contains(task.id),
          !plan.completedStretchIDs.contains(task.id) else { return }
    plan.completedStretchIDs.append(task.id)
    let log = CompletionLog(taskID: task.id, taskTitle: task.title,
                             planDate: plan.date, isStretchGoal: true)
    context.insert(log)
    // Recurring tasks reset immediately — do not mark permanently complete
    if task.recurringRule == nil {
        task.isCompleted = true
        task.completionDate = Date()
    }
    try? context.save()
}
```

**Step 3: Verify it builds**

Press `⌘B`. Expected: build succeeds.

**Step 4: Commit**

```bash
git add JustDoThree/JustDoThree/Engines/PlannerEngine.swift
git commit -m "feat: skip permanent completion for recurring tasks"
```

---

### Task 3: Add recurrence UI to `AddTaskSheet`

**Files:**
- Modify: `JustDoThree/JustDoThree/Views/Shared/AddTaskSheet.swift`

**Context:** `AddTaskSheet` is used both for creating new tasks and editing existing ones. The recurrence section must only appear for premium users. Free users see a locked row matching the existing "Import tasks" premium badge pattern. The sheet detent must grow when recurrence is active.

**Step 1: Add state variables**

In `AddTaskSheet`, find the existing `@State` block (around line 17). Add three new state vars directly below `@State private var showUpgrade`:

```swift
@State private var recurringPattern: RecurringRule.Pattern? = nil
@State private var recurringWeekday: Int = 2   // Monday (Calendar weekday 2)
@State private var recurringDayOfMonth: Int = 1
```

**Step 2: Populate state from existing task**

In the `.onAppear` block (line 31), add recurrence loading after `title = existing.title`:

```swift
if let rule = existing.recurringRule {
    recurringPattern = rule.pattern
    if let wd = rule.weekday { recurringWeekday = wd }
    if let d = rule.dayOfMonth { recurringDayOfMonth = d }
}
```

**Step 3: Add the recurrence section to the Form**

In the `Form` body, after the existing file-import section (after the closing `}` of the `if !isEditing` block, around line 73), add a new section visible for both creating and editing:

```swift
// Recurrence section
if premium.isPremium {
    Section {
        Picker("Repeat", selection: $recurringPattern) {
            Text("None").tag(Optional<RecurringRule.Pattern>.none)
            Text("Weekly").tag(Optional(RecurringRule.Pattern.weekly))
            Text("Monthly").tag(Optional(RecurringRule.Pattern.monthly))
        }

        if recurringPattern == .weekly {
            Picker("Day", selection: $recurringWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                }
            }
        }

        if recurringPattern == .monthly {
            Picker("Day of month", selection: $recurringDayOfMonth) {
                ForEach(1...31, id: \.self) { day in
                    let formatter = NumberFormatter()
                    let _ = { formatter.numberStyle = .ordinal }()
                    Text(formatter.string(from: NSNumber(value: day)) ?? "\(day)").tag(day)
                }
            }
        }
    } header: {
        Text("Recurrence")
    } footer: {
        Text("Premium feature. Recurring tasks reset after completion.")
    }
} else {
    Section {
        Button {
            showUpgrade = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Recurring tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Premium")
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.teal.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}
```

**Step 4: Save the recurring rule in `save()`**

Find the `save()` function (around line 98). After `guard !trimmedTitle.isEmpty` and before `if let task = existingTask`, add a helper that builds the rule:

```swift
private var builtRecurringRule: RecurringRule? {
    switch recurringPattern {
    case .weekly:  return .weekly(weekday: recurringWeekday)
    case .monthly: return .monthly(dayOfMonth: recurringDayOfMonth)
    case .none:    return nil
    }
}
```

Then in `save()`, apply it for both the edit and create paths:

```swift
private func save() {
    guard !trimmedTitle.isEmpty else { return }
    if let task = existingTask {
        task.title = trimmedTitle
        task.recurringRule = builtRecurringRule
        try? modelContext.save()
    } else {
        let nextOrder = (allTasks.map(\.sortOrder).max() ?? -1) + 1
        let task = JDTask(title: trimmedTitle, sortOrder: nextOrder)
        task.recurringRule = builtRecurringRule
        modelContext.insert(task)
        try? modelContext.save()
        onCreated?(task)
    }
    dismiss()
}
```

**Step 5: Update the sheet detent**

Find `.presentationDetents(...)` (line 87). Replace it with a dynamic detent based on whether recurrence is active:

```swift
.presentationDetents(recurringPattern != nil ? [.medium] : [.height(isEditing ? 200 : 340)])
```

Note: height increases from 265 → 340 for create mode to accommodate the recurrence locked row for free users. Premium users with active recurrence get `.medium`.

**Step 6: Verify it builds and previews**

Press `⌘B`. Open the `AddTaskSheet` preview canvas. Verify the form renders without errors.

**Step 7: Commit**

```bash
git add JustDoThree/JustDoThree/Views/Shared/AddTaskSheet.swift
git commit -m "feat: add premium recurring rule picker to AddTaskSheet"
```

---

### Task 4: Show recurring label in `BacklogRow`

**Files:**
- Modify: `JustDoThree/JustDoThree/Views/Backlog/BacklogView.swift`

**Context:** `BacklogRow` currently shows `createdDate` and optionally a rollover count in a subtitle `HStack`. Add a third item for the recurring label when `task.recurringRule != nil`.

**Step 1: Add recurring label to the subtitle HStack**

Find the `HStack(spacing: 8)` inside `BacklogRow` (around line 241). It currently contains two items. Add a third after the rollover label:

```swift
if let rule = task.recurringRule {
    Label("recurring · \(rule.displayString)", systemImage: "repeat")
        .font(.caption)
        .foregroundStyle(.teal)
}
```

The full `HStack` should now look like:

```swift
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
    if let rule = task.recurringRule {
        Label("recurring · \(rule.displayString)", systemImage: "repeat")
            .font(.caption)
            .foregroundStyle(.teal)
    }
}
```

**Step 2: Verify it builds**

Press `⌘B`. Open the `BacklogView` preview canvas. Verify the row renders.

**Step 3: Commit**

```bash
git add JustDoThree/JustDoThree/Views/Backlog/BacklogView.swift
git commit -m "feat: show recurring label in BacklogRow"
```

---

### Task 5: Smoke test end-to-end in Simulator

**Steps:**
1. Run the app in Simulator (`⌘R`)
2. Open Backlog → tap `+` → verify the "Recurring tasks" locked row appears (free user)
3. Toggle premium in `SettingsView` (or via `PremiumManager` in preview) if a dev toggle exists
4. Open Backlog → tap `+` → set a task to "Weekly, Monday" → tap Add
5. Verify the new task appears in the backlog with `"recurring · every Monday"` label in teal
6. Open Today → add the recurring task → complete it
7. Verify: checkmark shows in Today, task still appears in Backlog (not filtered out), History shows the completion
8. Repeat steps 5–7 for a monthly task (e.g. "Monthly, 15th")

---
