# JDT at Work Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add opt-in work/personal context separation — separate backlogs, daily plans, and 3-task limits — controlled by a Settings toggle and a `Personal | Work` segmented picker in Today, Backlog, and Plan tabs.

**Architecture:** Add `isWork: Bool = false` to `JDTask` and `DailyPlan`. `AppState` gains two UserDefaults-backed properties: `workModeEnabled` (feature gate) and `activeContext` (last-used context). `PlannerEngine` and `RolloverEngine` gain `isWork` parameters so each context runs independently. All three main views show a shared `WorkContextPicker` in their toolbar when work mode is on; the picker is invisible when off.

**Tech Stack:** Swift, SwiftUI, SwiftData, UserDefaults (`@AppStorage` pattern already used throughout)

**Design doc:** `docs/plans/2026-05-01-jdt-at-work-design.md`

---

### Task 1: Add `isWork` to JDTask

**Files:**
- Modify: `JustDoThree/Models/JDTask.swift`

**Step 1: Add the property**

In `JDTask`, add after `var recurringRuleData: Data?`:

```swift
/// True for work-context tasks; false (default) for personal tasks.
var isWork: Bool = false
```

SwiftData handles the migration automatically — existing tasks get `false`.

**Step 2: Update the initialiser to accept context**

Change `init(title:sortOrder:)`:

```swift
init(title: String, sortOrder: Int = 0, isWork: Bool = false) {
    self.id = UUID()
    self.title = title
    self.createdDate = Date()
    self.taskDate = nil
    self.rolloverCount = 0
    self.sortOrder = sortOrder
    self.isWork = isWork
    self.isCompleted = false
    self.completionDate = nil
    self.recurringRuleData = nil
}
```

**Step 3: Commit**

```bash
git add JustDoThree/Models/JDTask.swift
git commit -m "feat: add isWork flag to JDTask"
```

---

### Task 2: Add `isWork` to DailyPlan

**Files:**
- Modify: `JustDoThree/Models/DailyPlan.swift`

**Step 1: Add the property**

After `var completedStretchIDs: [UUID]`:

```swift
/// True for work-context plans; false (default) for personal plans.
var isWork: Bool = false
```

**Step 2: Update the initialiser**

```swift
init(date: Date, isWork: Bool = false) {
    self.date = Calendar.current.startOfDay(for: date)
    self.isWork = isWork
    self.taskIDs = []
    self.completedTaskIDs = []
    self.stretchTaskIDs = []
    self.completedStretchIDs = []
}
```

**Step 3: Commit**

```bash
git add JustDoThree/Models/DailyPlan.swift
git commit -m "feat: add isWork flag to DailyPlan"
```

---

### Task 3: Extend AppState with work mode + per-context rollover

**Files:**
- Modify: `JustDoThree/State/AppState.swift`

**Step 1: Add work mode properties to the Settings section**

After the existing `hasSeenOnboarding` property:

```swift
var workModeEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "jdt_workModeEnabled") }
    set {
        UserDefaults.standard.set(newValue, forKey: "jdt_workModeEnabled")
        if !newValue { activeContext = false } // reset to personal when disabled
    }
}

/// false = Personal, true = Work. Persisted so last context is restored on relaunch.
var activeContext: Bool {
    get { UserDefaults.standard.bool(forKey: "jdt_activeContext") }
    set { UserDefaults.standard.set(newValue, forKey: "jdt_activeContext") }
}
```

**Step 2: Replace `checkDayTransition` with per-context version**

Replace the entire `checkDayTransition` method:

```swift
func checkDayTransition(context: ModelContext) {
    let today = Date().startOfDay
    if let last = lastCheckedDate, last.isSameDay(as: today) { return }
    lastCheckedDate = today

    PlannerEngine.fetchOrCreateTodayPlan(isWork: false, context: context)
    if workModeEnabled {
        PlannerEngine.fetchOrCreateTodayPlan(isWork: true, context: context)
    }

    if autoScheduleRecurring {
        PlannerEngine.autoScheduleRecurring(for: Date(), isWork: false, context: context)
        if workModeEnabled {
            PlannerEngine.autoScheduleRecurring(for: Date(), isWork: true, context: context)
        }
    }

    // Personal rollover always checked on app open
    checkContextRollover(isWork: false, context: context)
}

/// Called on app open for personal, and on first work-context switch of the day.
func checkContextRollover(isWork: Bool, context: ModelContext) {
    let today = Date().startOfDay
    let resolvedKey = isWork ? "jdt_rolloverResolved_work" : "jdt_rolloverResolved_personal"
    if let resolved = UserDefaults.standard.object(forKey: resolvedKey) as? Date,
       resolved.isSameDay(as: today) { return }

    let todayPlan = PlannerEngine.fetchOrCreateTodayPlan(isWork: isWork, context: context)
    let pending = RolloverEngine.findPendingItems(todayPlan: todayPlan, context: context)
    if !pending.isEmpty {
        rolloverItems = pending
        showRolloverSheet = true
    } else {
        markRolloverResolved(isWork: isWork)
    }
}
```

**Step 3: Update `applyRolloverChoices` to derive context from items**

```swift
func applyRolloverChoices(context: ModelContext) {
    let isWork = rolloverItems.first?.fromPlan.isWork ?? false
    let todayPlan = PlannerEngine.fetchOrCreateTodayPlan(isWork: isWork, context: context)
    RolloverEngine.applyChoices(rolloverItems, todayPlan: todayPlan, context: context)
    rolloverItems = []
    showRolloverSheet = false
    markRolloverResolved(isWork: isWork)
}
```

**Step 4: Update `dismissRolloverWithoutChanges`**

```swift
func dismissRolloverWithoutChanges() {
    let isWork = rolloverItems.first?.fromPlan.isWork ?? false
    rolloverItems = []
    showRolloverSheet = false
    markRolloverResolved(isWork: isWork)
}
```

**Step 5: Update `markRolloverResolved` to accept context**

```swift
private func markRolloverResolved(isWork: Bool = false) {
    let key = isWork ? "jdt_rolloverResolved_work" : "jdt_rolloverResolved_personal"
    UserDefaults.standard.set(Date(), forKey: key)
}
```

**Step 6: Remove old `markRolloverResolved()` call and old key**

Delete the old `markRolloverResolved()` method (it took no parameters — replaced above).

**Step 7: Commit**

```bash
git add JustDoThree/State/AppState.swift
git commit -m "feat: add workModeEnabled, activeContext, per-context rollover to AppState"
```

---

### Task 4: Update PlannerEngine for context-awareness

**Files:**
- Modify: `JustDoThree/Engines/PlannerEngine.swift`

**Step 1: Update `fetchOrCreateTodayPlan`**

```swift
@discardableResult
static func fetchOrCreateTodayPlan(isWork: Bool = false, context: ModelContext) -> DailyPlan {
    fetchOrCreatePlan(for: Date(), isWork: isWork, context: context)
}
```

**Step 2: Update `fetchOrCreatePlan`**

```swift
@discardableResult
static func fetchOrCreatePlan(for date: Date, isWork: Bool = false, context: ModelContext) -> DailyPlan {
    let all = allPlans(context: context)
    if let existing = all.first(where: { $0.date.isSameDay(as: date) && $0.isWork == isWork }) {
        return existing
    }
    let plan = DailyPlan(date: date, isWork: isWork)
    context.insert(plan)
    save(context: context)
    return plan
}
```

**Step 3: Update `plan(for:context:)`**

```swift
static func plan(for date: Date, isWork: Bool = false, context: ModelContext) -> DailyPlan? {
    allPlans(context: context).first { $0.date.isSameDay(as: date) && $0.isWork == isWork }
}
```

**Step 4: Update `mostRecentPreviousPlan`**

```swift
static func mostRecentPreviousPlan(isWork: Bool = false, context: ModelContext) -> DailyPlan? {
    let today = Date().startOfDay
    return allPlans(context: context)
        .filter { $0.date < today && !$0.taskIDs.isEmpty && $0.isWork == isWork }
        .max(by: { $0.date < $1.date })
}
```

**Step 5: Update `autoScheduleRecurring`**

```swift
static func autoScheduleRecurring(for date: Date, isWork: Bool = false, context: ModelContext) {
    let plan = fetchOrCreatePlan(for: date, isWork: isWork, context: context)
    let tasks = allTasks(context: context).filter { $0.isWork == isWork }
    let cal = Calendar.current
    let weekday = cal.component(.weekday, from: date)
    let dayOfMonth = cal.component(.day, from: date)

    var changed = false
    for task in tasks {
        guard let rule = task.recurringRule else { continue }
        guard plan.taskIDs.count < 3 else { break }
        guard !plan.taskIDs.contains(task.id) else { continue }

        let matches: Bool
        switch rule.pattern {
        case .weekly:  matches = rule.weekday == weekday
        case .monthly: matches = rule.dayOfMonth == dayOfMonth
        }
        guard matches else { continue }
        plan.taskIDs.append(task.id)
        changed = true
    }
    if changed { save(context: context) }
}
```

**Step 6: Commit**

```bash
git add JustDoThree/Engines/PlannerEngine.swift
git commit -m "feat: add isWork parameter to PlannerEngine plan-fetch and auto-schedule"
```

---

### Task 5: Update RolloverEngine for context-awareness

**Files:**
- Modify: `JustDoThree/Engines/RolloverEngine.swift`

**Step 1: Filter previous plans by context in `findPendingItems`**

In `findPendingItems`, change the `previousPlans` filter:

```swift
let previousPlans = allPlans
    .filter { $0.date < today && !$0.taskIDs.isEmpty && $0.isWork == todayPlan.isWork }
    .sorted { $0.date > $1.date }
```

**Step 2: Pass context into `fetchOrCreatePlan` in `applyChoices`**

In the `.scheduleFor(let date)` case:

```swift
case .scheduleFor(let date):
    let plan = PlannerEngine.fetchOrCreatePlan(
        for: date,
        isWork: item.fromPlan.isWork,
        context: context
    )
    if plan.taskIDs.count < 3, !plan.taskIDs.contains(item.task.id) {
        plan.taskIDs.append(item.task.id)
    }
    item.task.rolloverCount += 1
```

**Step 3: Commit**

```bash
git add JustDoThree/Engines/RolloverEngine.swift
git commit -m "feat: scope RolloverEngine to active context"
```

---

### Task 6: Add JDT at Work toggle in SettingsView

**Files:**
- Modify: `JustDoThree/Views/Settings/SettingsView.swift`

**Step 1: Add AppStorage binding**

In the `SettingsView` property list, add after `@AppStorage("jdt_enableTaskDates")`:

```swift
@AppStorage("jdt_workModeEnabled") private var workModeEnabled = false
```

**Step 2: Add toggle row in the Features section**

Add after the `enableTaskDates` toggle row, before the closing `}` of the Features `Section`:

```swift
Toggle(isOn: $workModeEnabled) {
    VStack(alignment: .leading, spacing: 2) {
        Text("JDT at Work")
        Text("Separate your work and personal tasks with independent daily plans.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**Step 3: Commit**

```bash
git add JustDoThree/Views/Settings/SettingsView.swift
git commit -m "feat: add JDT at Work toggle to Settings"
```

---

### Task 7: Create WorkContextPicker shared component

**Files:**
- Create: `JustDoThree/Views/Shared/WorkContextPicker.swift`

**Step 1: Create the file**

```swift
import SwiftUI

/// A `Personal | Work` segmented picker placed in the nav bar principal slot.
/// Invisible when `workModeEnabled` is false — callers can render it unconditionally.
struct WorkContextPicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.workModeEnabled {
            Picker(
                "Context",
                selection: Binding(
                    get: { appState.activeContext },
                    set: { appState.activeContext = $0 }
                )
            ) {
                Text("Personal").tag(false)
                Text("Work").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }
}
```

**Step 2: Add file to Xcode project**

Open `project.yml` (or the Xcode project) and add `WorkContextPicker.swift` to the Shared group, mirroring how `CameraPickerView.swift` was added.

**Step 3: Commit**

```bash
git add JustDoThree/Views/Shared/WorkContextPicker.swift JustDoThree.xcodeproj/project.pbxproj
git commit -m "feat: add WorkContextPicker segmented control component"
```

---

### Task 8: Update TodayView

**Files:**
- Modify: `JustDoThree/Views/Today/TodayView.swift`

**Step 1: Update `todayPlan` computed property**

```swift
private var todayPlan: DailyPlan? {
    plans.first { $0.date.isSameDay(as: Date()) && $0.isWork == appState.activeContext }
}
```

**Step 2: Update `backlogTasks` to filter by context**

```swift
private var backlogTasks: [JDTask] {
    let excludeIDs = Set((todayPlan?.taskIDs ?? []) + (todayPlan?.stretchTaskIDs ?? []))
    return allTasks.filter { task in
        task.isWork == appState.activeContext &&
        !excludeIDs.contains(task.id) &&
        (!task.isCompleted || task.recurringRule != nil)
    }
}
```

**Step 3: Replace toolbar principal with WorkContextPicker**

Replace the existing `toolbar` property:

```swift
@ToolbarContentBuilder
private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .principal) {
        if appState.workModeEnabled {
            WorkContextPicker()
        } else {
            HStack(spacing: 6) {
                AppLogoView(size: 26)
                Text("Just Do Three")
                    .font(.headline)
            }
        }
    }
}
```

**Step 4: Trigger work rollover on context switch**

Add a new `.onChange` modifier after the existing `.onChange(of: scenePhase)` block (around line 148):

```swift
.onChange(of: appState.activeContext) { _, isWork in
    if isWork {
        appState.checkContextRollover(isWork: true, context: modelContext)
    }
}
```

**Step 5: Update `addToToday` to target correct plan**

```swift
private func addToToday(_ task: JDTask) {
    let plan = todayPlan ?? PlannerEngine.fetchOrCreateTodayPlan(
        isWork: appState.activeContext,
        context: modelContext
    )
    let validIDs = Set(allTasks.map(\.id))
    plan.taskIDs.removeAll { !validIDs.contains($0) }
    PlannerEngine.addToToday(task: task, plan: plan, context: modelContext)
}
```

**Step 6: Update `autoScheduleRecurring` onChange**

```swift
.onChange(of: autoScheduleRecurring) { _, enabled in
    if enabled {
        PlannerEngine.autoScheduleRecurring(for: Date(), isWork: false, context: modelContext)
        if appState.workModeEnabled {
            PlannerEngine.autoScheduleRecurring(for: Date(), isWork: true, context: modelContext)
        }
    }
}
```

**Step 7: Commit**

```bash
git add JustDoThree/Views/Today/TodayView.swift
git commit -m "feat: wire TodayView to active work context"
```

---

### Task 9: Update BacklogPickerSheet and TomorrowPickerSheet

Both live in `TodayView.swift`.

**Files:**
- Modify: `JustDoThree/Views/Today/TodayView.swift`

**Step 1: Add AppState to BacklogPickerSheet**

Add to `BacklogPickerSheet`'s property list:

```swift
@Environment(AppState.self) private var appState
```

**Step 2: Filter `inTargetPlanItems` by context**

```swift
private var inTargetPlanItems: [JDTask] {
    guard let plan = plans.first(where: {
        $0.date.isSameDay(as: forDate) && $0.isWork == appState.activeContext
    }) else { return [] }
    let ids = Set(plan.taskIDs + plan.stretchTaskIDs)
    return allTasks.filter { ids.contains($0.id) }
}
```

**Step 3: Filter `backlogTasks` by context**

```swift
private var backlogTasks: [JDTask] {
    let busy = inTargetPlanIDs.union(scheduledElsewhereIDs)
    return allTasks.filter { task in
        task.isWork == appState.activeContext &&
        !busy.contains(task.id) &&
        (!task.isCompleted || task.recurringRule != nil)
    }
}
```

**Step 4: Tag new tasks in `createAndAdd`**

```swift
private func createAndAdd() {
    guard !trimmed.isEmpty else { return }
    let startOrder = PlannerEngine.topInsertionStartOrder(existingTasks: allTasks, count: 1)
    let task = JDTask(title: trimmed, sortOrder: startOrder, isWork: appState.activeContext)
    modelContext.insert(task)
    try? modelContext.save()
    onSelect(task)
    dismiss()
}
```

**Step 5: Add AppState to TomorrowPickerSheet**

```swift
@Environment(AppState.self) private var appState
```

**Step 6: Filter `tomorrowTasks` by context**

```swift
private var tomorrowTasks: [JDTask] {
    guard let plan = plans.first(where: {
        $0.date.isSameDay(as: tomorrow) && $0.isWork == appState.activeContext
    }) else { return [] }
    return plan.taskIDs.compactMap { id -> JDTask? in
        guard let task = allTasks.first(where: { $0.id == id }) else { return nil }
        guard !todayExcludedIDs.contains(id) else { return nil }
        guard !task.isCompleted || task.recurringRule != nil else { return nil }
        return task
    }
}
```

**Step 7: Commit**

```bash
git add JustDoThree/Views/Today/TodayView.swift
git commit -m "feat: scope BacklogPickerSheet and TomorrowPickerSheet to active context"
```

---

### Task 10: Update BacklogView

**Files:**
- Modify: `JustDoThree/Views/Backlog/BacklogView.swift`

**Step 1: Add AppState environment**

Add to BacklogView's property list:

```swift
@Environment(AppState.self) private var appState
```

**Step 2: Filter `backlogTasks` by context**

```swift
private var backlogTasks: [JDTask] {
    allTasks.filter {
        $0.isWork == appState.activeContext &&
        ($0.recurringRule != nil || !$0.isCompleted) &&
        !todayTaskIDs.contains($0.id)
    }
}
```

**Step 3: Also filter `todayTaskIDs` by context**

```swift
private var todayTaskIDs: Set<UUID> {
    let plan = plans.first {
        $0.date.isSameDay(as: Date()) && $0.isWork == appState.activeContext
    }
    return Set((plan?.taskIDs ?? []) + (plan?.stretchTaskIDs ?? []))
}
```

**Step 4: Add WorkContextPicker to toolbar**

Find the `.toolbar` modifier in BacklogView and add a `.principal` item. The existing toolbar likely has a title — replace or add:

```swift
ToolbarItem(placement: .principal) {
    if appState.workModeEnabled {
        WorkContextPicker()
    }
}
```

If there is no existing `.principal` item, add it to the existing toolbar block. If the navigationTitle is set as `.inline`, it coexists with the principal item — remove the `navigationTitle` or keep it as the fallback when work mode is off.

**Step 5: Update PasteTasksSheet calls to carry context**

`PasteTasksSheet` is shown via `showPasteSheet`. No parameter change needed here — `PasteTasksSheet` will read `AppState` directly (Task 12).

**Step 6: Commit**

```bash
git add JustDoThree/Views/Backlog/BacklogView.swift
git commit -m "feat: scope BacklogView to active work context"
```

---

### Task 11: Update PlanView / WeekPlannerView

**Files:**
- Modify: `JustDoThree/Views/Plan/PlanView.swift`

**Step 1: Add AppState to WeekPlannerView**

```swift
@Environment(AppState.self) private var appState
```

**Step 2: Filter `selectedPlan` by context**

```swift
private var selectedPlan: DailyPlan? {
    plans.first { $0.date.isSameDay(as: selectedDay) && $0.isWork == appState.activeContext }
}
```

**Step 3: Add WorkContextPicker to PlanView toolbar**

In `PlanView.body`, the toolbar has a `.principal` item (logo + "Just Do Three"). Replace it:

```swift
ToolbarItem(placement: .principal) {
    if appState.workModeEnabled {
        WorkContextPicker()
    } else {
        HStack(spacing: 6) {
            AppLogoView(size: 26)
            Text("Just Do Three")
                .font(.headline)
        }
    }
}
```

**Step 4: Scope the backlog picker in WeekPlannerView**

Find where `WeekPlannerView` calls `PlannerEngine.fetchOrCreatePlan(for:context:)` when adding tasks via its `BacklogPickerSheet`. Update any such calls to pass `isWork: appState.activeContext`. Also ensure its `BacklogPickerSheet` uses `forDate:` — the context filter in `BacklogPickerSheet` (Task 9) will handle the rest since `BacklogPickerSheet` reads `appState.activeContext`.

**Step 5: Commit**

```bash
git add JustDoThree/Views/Plan/PlanView.swift
git commit -m "feat: scope WeekPlannerView to active work context"
```

---

### Task 12: Update AddTaskSheet and PasteTasksSheet to tag isWork

**Files:**
- Modify: `JustDoThree/Views/Shared/AddTaskSheet.swift`
- Modify: `JustDoThree/Views/Backlog/PasteTasksSheet.swift`

**Step 1: Add AppState to AddTaskSheet**

```swift
@Environment(AppState.self) private var appState
```

**Step 2: Tag new task with active context in `save()`**

In `AddTaskSheet.save()`, when creating a new task:

```swift
} else {
    let startOrder = PlannerEngine.topInsertionStartOrder(existingTasks: allTasks, count: 1)
    let task = JDTask(title: trimmedTitle, sortOrder: startOrder, isWork: appState.activeContext)
    task.recurringRule = builtRecurringRule
    task.taskDate = normalizedTaskDate
    modelContext.insert(task)
    try? modelContext.save()
    onCreated?(task)
}
```

**Step 3: Add AppState to PasteTasksSheet**

```swift
@Environment(AppState.self) private var appState
```

**Step 4: Tag tasks in `importLines()`**

```swift
modelContext.insert(JDTask(title: title, sortOrder: startSortOrder + imported, isWork: appState.activeContext))
```

**Step 5: Also update ImportInstructionsSheet inside AddTaskSheet**

`ImportInstructionsSheet` also creates tasks via its `handleImport` method. Add `@Environment(AppState.self) private var appState` to `ImportInstructionsSheet` and update its task creation:

```swift
modelContext.insert(JDTask(title: title, sortOrder: startSortOrder + imported, isWork: appState.activeContext))
```

**Step 6: Commit**

```bash
git add JustDoThree/Views/Shared/AddTaskSheet.swift JustDoThree/Views/Backlog/PasteTasksSheet.swift
git commit -m "feat: tag new tasks with active context in AddTaskSheet and PasteTasksSheet"
```

---

### Task 13: Add WorkContextPicker.swift to Xcode project file

**Files:**
- Modify: `JustDoThree.xcodeproj/project.pbxproj`

**Step 1: Run xcodegen to regenerate project**

If the project uses `project.yml`:

```bash
cd /Users/todd/CodingProjects/JustDoThree
xcodegen generate
```

If not using xcodegen, open Xcode and drag `WorkContextPicker.swift` into the Shared group manually, then verify the build succeeds.

**Step 2: Build verify**

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit if project file changed**

```bash
git add JustDoThree.xcodeproj/project.pbxproj project.yml
git commit -m "chore: add WorkContextPicker to Xcode project"
```

---

### Task 14: Smoke test + final commit

**Step 1: Manual checks**

- Settings → JDT at Work off → no picker visible in any tab ✓
- Settings → JDT at Work on → `Personal | Work` picker appears in Today, Backlog, Plan ✓
- Add a task in Personal context → `isWork = false` ✓
- Switch to Work → picker flips → backlog shows empty / work tasks only ✓
- Add a task in Work context → `isWork = true` ✓
- Today: Personal plan and Work plan have independent 3-task limits ✓
- Turn feature off → app looks exactly as before ✓
- Relaunch → last-used context is restored ✓

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat: JDT at Work — work/personal context separation"
```
