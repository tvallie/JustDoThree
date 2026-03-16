# Debug: Seed History Data — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Seed History Data" debug button to SettingsView that populates all four HistoryView analytics cards with realistic test data in one tap.

**Architecture:** A new `seedHistoryData(context:)` method inside the existing `#if DEBUG` block in `AppState` creates 5 `JDTask` records (with rolloverCounts) and `CompletionLog` records for 14 past days. `SettingsView`'s existing Debug section gets one new button. No `DailyPlan` records needed — all four HistoryView cards query only `CompletionLog` or `JDTask`.

**Tech Stack:** SwiftUI, SwiftData, `@Observable` AppState, `ModelContext`

---

### Task 1: Add `seedHistoryData(context:)` to AppState

**Files:**
- Modify: `JustDoThree/State/AppState.swift` — inside the existing `#if DEBUG` block (after `previewRolloverSheet`)

**Step 1: Add the method**

Open `JustDoThree/State/AppState.swift`. Locate the `#if DEBUG` block (around line 82). After the closing `}` of `previewRolloverSheet`, add the following method before the `#endif`:

```swift
/// Seeds realistic history data for testing the HistoryView analytics cards.
/// Idempotent — skips seeding if 10 or more CompletionLog records already exist.
func seedHistoryData(context: ModelContext) {
    // Idempotency check
    let existingLogs = (try? context.fetch(FetchDescriptor<CompletionLog>())) ?? []
    guard existingLogs.count < 10 else { return }

    let cal = Calendar.current
    let today = Date().startOfDay

    // MARK: — Seed JDTasks (for Most Avoided card)
    let taskDefs: [(title: String, rolloverCount: Int)] = [
        ("Clean up dog poop in back yard", 4),
        ("Mow lawn", 3),
        ("Buy birthday gift for pet elephant", 2),
        ("Plant a tree", 1),
        ("Tell someone they are awesome", 0),
    ]

    var tasks: [JDTask] = []
    for (index, def) in taskDefs.enumerated() {
        let task = JDTask(title: def.title, sortOrder: index)
        task.rolloverCount = def.rolloverCount
        context.insert(task)
        tasks.append(task)
    }

    // MARK: — Seed CompletionLogs (for Stats, Perfect Days, Recent Completions cards)
    // 14 days back. Most days: 3 primary completions (perfect day).
    // Days 4 and 9 (0-indexed): only 2 completions — makes avg/day ~2.7.
    // Day 7: also add one stretch goal completion.

    let incompleteDays: Set<Int> = [4, 9]   // offsets that get only 2 completions
    let stretchDay: Int = 7                  // offset that also gets a stretch goal

    for offset in 1...14 {
        guard let planDate = cal.date(byAdding: .day, value: -offset, to: today) else { continue }

        let taskCount = incompleteDays.contains(offset) ? 2 : 3
        for slot in 0..<taskCount {
            let task = tasks[(offset + slot) % tasks.count]
            let log = CompletionLog(
                taskID: task.id,
                taskTitle: task.title,
                planDate: planDate,
                isStretchGoal: false
            )
            context.insert(log)
        }

        // Stretch goal on the designated day
        if offset == stretchDay {
            let stretchTask = tasks[(offset + 3) % tasks.count]
            let stretchLog = CompletionLog(
                taskID: stretchTask.id,
                taskTitle: stretchTask.title,
                planDate: planDate,
                isStretchGoal: true
            )
            context.insert(stretchLog)
        }
    }

    try? context.save()
}
```

**Step 2: Verify it compiles**

```bash
xcodebuild -scheme JustDoThree \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

**Step 3: Commit**

```bash
cd /Users/todd/CodingProjects/JustDoThree
git add JustDoThree/State/AppState.swift
git commit -m "Add seedHistoryData debug method to AppState"
```

---

### Task 2: Add the button to SettingsView

**Files:**
- Modify: `JustDoThree/Views/Settings/SettingsView.swift` — inside `#if DEBUG` Section("Debug")

**Step 1: Add the button**

Open `SettingsView.swift`. Find the `#if DEBUG` section (around line 97):

```swift
// DEBUG (remove before release)
#if DEBUG
Section("Debug") {
    Button("Preview Rollover Sheet") {
        appState.previewRolloverSheet(context: modelContext)
    }
}
#endif
```

Add one button after the existing one:

```swift
// DEBUG (remove before release)
#if DEBUG
Section("Debug") {
    Button("Preview Rollover Sheet") {
        appState.previewRolloverSheet(context: modelContext)
    }
    Button("Seed History Data") {
        appState.seedHistoryData(context: modelContext)
    }
}
#endif
```

**Step 2: Verify it compiles**

```bash
xcodebuild -scheme JustDoThree \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

**Step 3: Manual verification in simulator**

1. Launch the app in the iOS simulator
2. Go to Settings tab
3. Scroll to the **Debug** section — confirm "Seed History Data" button appears
4. Tap it
5. Navigate to the History tab — confirm all four cards are populated:
   - **Stats:** should show ~40 completed, 1 stretch goal, ~2.7 avg/day, 14 active days
   - **Perfect Days:** should show 12
   - **Most Avoided:** should list tasks with rollover counts (Clean up dog poop → 4, Mow lawn → 3, etc.)
   - **Recent Completions:** should list task titles with dates
6. Tap "Seed History Data" again — confirm nothing changes (idempotency check)

**Step 4: Commit**

```bash
git add JustDoThree/Views/Settings/SettingsView.swift
git commit -m "Add Seed History Data button to debug settings"
```
