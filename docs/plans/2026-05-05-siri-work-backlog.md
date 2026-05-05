# Siri Work Backlog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a second Siri intent so "Hey Siri, add a work task to JustDoThree" inserts at the top of the work backlog, while existing personal-backlog phrases keep working unchanged.

**Architecture:** Extract the insert logic from `AddTaskIntent` into a free function `insertAtTopOfBacklog(title:isWork:in:)`. Add a parallel `AddWorkTaskIntent` that calls the helper with `isWork: true`. Register both intents in `JDTAppShortcuts` with distinct phrase sets. Sort-order computation is scoped to the matching backlog so each list maintains its own top.

**Tech Stack:** Swift 5.9, SwiftData, App Intents (iOS 17), XCTest, xcodegen.

**Design doc:** [docs/plans/2026-05-05-siri-work-backlog-design.md](2026-05-05-siri-work-backlog-design.md)

**Conventions:**
- Project uses xcodegen — after creating any new source file, run `xcodegen generate` so the Xcode project picks it up.
- Tests use XCTest with in-memory `ModelContainer` (see existing `AddTaskIntentTests` pattern).
- Commits: short imperative subject, no Co-Authored-By trailer.
- Build/test command: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' test`. (iPhone 15 simulator is not installed on this machine.)

---

### Task 1: Failing test for backlog-scoped sort order in personal path

**Why:** Before extracting the helper, lock down the existing behavior with a stronger test. The current `test_perform_addsTaskToPersonalBacklogAtTop` happens to pass with global-min-sortOrder logic because the seeded work and personal items both have sortOrder 0. We need a test that fails if sort order isn't scoped per backlog — otherwise the refactor in Task 2 has no safety net for the scope change.

**Files:**
- Modify: `JustDoThreeTests/AddTaskIntentTests.swift`

**Step 1: Append a new test method**

Add inside the existing `AddTaskIntentTests` class, after `test_perform_addsTaskToPersonalBacklogAtTop`:

```swift
@MainActor
func test_perform_personalSortOrder_scopedToPersonalBacklog() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    // Work backlog has a deeply-negative sortOrder; new personal task must
    // ignore it and only sort relative to other personal items.
    let work = JDTask(title: "deep work", sortOrder: -100, isWork: true)
    let personal = JDTask(title: "old personal", sortOrder: 5, isWork: false)
    context.insert(work)
    context.insert(personal)
    try context.save()

    var intent = AddTaskIntent()
    intent.title = "buy milk"
    _ = try await intent.perform(in: container)

    let all = try context.fetch(FetchDescriptor<JDTask>())
    let personalSorted = all.filter { !$0.isWork }.sorted { $0.sortOrder < $1.sortOrder }
    XCTAssertEqual(personalSorted.first?.title, "buy milk")
    // Should be 4 (one less than the existing personal min of 5), NOT -101.
    XCTAssertEqual(personalSorted.first?.sortOrder, 4)
}
```

**Step 2: Run, expect failure**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:JustDoThreeTests/AddTaskIntentTests/test_perform_personalSortOrder_scopedToPersonalBacklog`
Expected: FAIL — current implementation produces sortOrder -101 (one less than the global min of -100), not 4.

**Step 3: Commit failing test**

```bash
git add JustDoThreeTests/AddTaskIntentTests.swift
git commit -m "test: lock per-backlog sort-order scope for AddTaskIntent"
```

---

### Task 2: Extract `insertAtTopOfBacklog` helper, scoped per backlog

**Why:** Both intents need the same insert logic, and the per-backlog sort-order scope needs to land here. Extracting first means Task 4's new intent is a 5-line file.

**Files:**
- Create: `JustDoThree/Intents/BacklogInsert.swift`
- Modify: `JustDoThree/Intents/AddTaskIntent.swift`

**Step 1: Write the helper**

Create `JustDoThree/Intents/BacklogInsert.swift`:

```swift
import Foundation
import SwiftData

/// Trims `title`, validates it's non-empty, and inserts a new `JDTask` at the
/// top of the matching backlog (personal or work, per `isWork`).
///
/// "Top" means `min(sortOrder) - 1` filtered to the same `isWork` value, so
/// each backlog maintains its own ordering independent of the other.
///
/// Returns the trimmed title (for the caller's confirmation dialog).
/// Throws `AddTaskIntentError.emptyTitle` if `title` is empty after trimming.
@MainActor
func insertAtTopOfBacklog(title: String, isWork: Bool, in container: ModelContainer) throws -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AddTaskIntentError.emptyTitle }
    let context = ModelContext(container)
    let predicate = #Predicate<JDTask> { $0.isWork == isWork }
    let existing = try context.fetch(FetchDescriptor<JDTask>(predicate: predicate))
    let minOrder = existing.map(\.sortOrder).min() ?? 0
    let task = JDTask(title: trimmed, sortOrder: minOrder - 1, isWork: isWork)
    context.insert(task)
    try context.save()
    return trimmed
}
```

Note: the `#Predicate` captures `isWork` from the enclosing scope. SwiftData supports this in iOS 17+.

**Step 2: Simplify `AddTaskIntent.perform(in:)`**

Replace the body of `perform(in:)` in `JustDoThree/Intents/AddTaskIntent.swift` (lines 37-47) with:

```swift
    @MainActor
    func perform(in container: ModelContainer) async throws -> some IntentResult & ProvidesDialog {
        let trimmed = try insertAtTopOfBacklog(title: title, isWork: false, in: container)
        return .result(dialog: IntentDialog("Added '\(trimmed)' to your backlog."))
    }
```

**Step 3: Regenerate project**

Run: `xcodegen generate`
Expected: "Created project at JustDoThree.xcodeproj" — no errors.

**Step 4: Run all `AddTaskIntentTests`, expect all pass**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:JustDoThreeTests/AddTaskIntentTests`
Expected: All 3 tests PASS (the two original tests plus the per-backlog scope test from Task 1).

**Step 5: Commit**

```bash
git add JustDoThree/Intents/BacklogInsert.swift JustDoThree/Intents/AddTaskIntent.swift JustDoThree.xcodeproj
git commit -m "refactor: extract insertAtTopOfBacklog with per-list sort scope"
```

---

### Task 3: Failing tests for AddWorkTaskIntent

**Files:**
- Create: `JustDoThreeTests/AddWorkTaskIntentTests.swift`

**Step 1: Write the test file**

```swift
import XCTest
import SwiftData
@testable import JustDoThree

final class AddWorkTaskIntentTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
    }

    @MainActor
    func test_perform_addsTaskToWorkBacklogAtTop() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let personal = JDTask(title: "personal item", sortOrder: 0, isWork: false)
        let existingWork = JDTask(title: "old work", sortOrder: 0, isWork: true)
        context.insert(personal)
        context.insert(existingWork)
        try context.save()

        var intent = AddWorkTaskIntent()
        intent.title = "ship release"
        _ = try await intent.perform(in: container)

        let all = try context.fetch(FetchDescriptor<JDTask>())
        let work = all.filter { $0.isWork }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(work.count, 2)
        XCTAssertEqual(work.first?.title, "ship release")
        XCTAssertEqual(work.first?.isWork, true)
        XCTAssertLessThan(work.first!.sortOrder, existingWork.sortOrder)
        // Personal backlog untouched.
        XCTAssertEqual(all.filter { !$0.isWork }.count, 1)
    }

    @MainActor
    func test_perform_emptyTitle_throwsAndDoesNotInsert() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var intent = AddWorkTaskIntent()
        intent.title = "   "

        do {
            _ = try await intent.perform(in: container)
            XCTFail("Expected error for empty title")
        } catch {
            // expected
        }

        let all = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertTrue(all.isEmpty, "Should not insert a task for empty/whitespace title")
    }
}
```

**Step 2: Regenerate, run tests, expect compile failure**

```bash
xcodegen generate
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:JustDoThreeTests/AddWorkTaskIntentTests
```
Expected: Compile error — `AddWorkTaskIntent` does not exist.

**Step 3: Commit**

```bash
git add JustDoThreeTests/AddWorkTaskIntentTests.swift JustDoThree.xcodeproj
git commit -m "test: add failing tests for AddWorkTaskIntent"
```

---

### Task 4: Implement AddWorkTaskIntent

**Files:**
- Create: `JustDoThree/Intents/AddWorkTaskIntent.swift`

**Step 1: Write the intent**

```swift
import AppIntents
import SwiftData
import Foundation

struct AddWorkTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Work Task to JustDoThree"
    static var description = IntentDescription(
        "Add a new task to your work backlog in JustDoThree.",
        categoryName: "Tasks"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Task",
        description: "What you want to add to your work backlog.",
        requestValueDialog: IntentDialog("What's the work task?")
    )
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await perform(in: JDTModelContainer.shared)
    }

    /// Test seam: lets tests inject an in-memory container.
    @MainActor
    func perform(in container: ModelContainer) async throws -> some IntentResult & ProvidesDialog {
        let trimmed = try insertAtTopOfBacklog(title: title, isWork: true, in: container)
        return .result(dialog: IntentDialog("Added '\(trimmed)' to your work backlog."))
    }
}
```

**Step 2: Regenerate, run tests, expect pass**

```bash
xcodegen generate
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:JustDoThreeTests/AddWorkTaskIntentTests
```
Expected: Both tests PASS.

**Step 3: Commit**

```bash
git add JustDoThree/Intents/AddWorkTaskIntent.swift JustDoThree.xcodeproj
git commit -m "feat: add AddWorkTaskIntent for Siri work-backlog capture"
```

---

### Task 5: Register work-backlog phrases in JDTAppShortcuts

**Files:**
- Modify: `JustDoThree/Intents/JDTAppShortcuts.swift`

**Step 1: Add a second AppShortcut**

Replace the body of `appShortcuts` so it returns both shortcuts:

```swift
import AppIntents

struct JDTAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Add to \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddWorkTaskIntent(),
            phrases: [
                "Add a work task to \(.applicationName)",
                "Add work task to \(.applicationName)",
                "New work task in \(.applicationName)"
            ],
            shortTitle: "Add Work Task",
            systemImageName: "briefcase"
        )
    }
}
```

Note: `AppShortcutsProvider.appShortcuts` is an `@AppShortcutsBuilder` result builder — multiple `AppShortcut` literals back-to-back are valid (no comma, no array brackets).

**Step 2: Build to verify**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED.

**Step 3: Run the full intent test suite as a regression check**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:JustDoThreeTests/AddTaskIntentTests -only-testing:JustDoThreeTests/AddWorkTaskIntentTests`
Expected: All 5 tests PASS (3 personal + 2 work).

**Step 4: Commit**

```bash
git add JustDoThree/Intents/JDTAppShortcuts.swift
git commit -m "feat: register Siri phrases for work-backlog intent"
```

---

### Task 6: Manual smoke test

Not automated — record observations in the PR description (or commit notes).

1. Install build on a device or iOS 17+ simulator with Siri enabled.
2. Say "Hey Siri, add a work task to Just Do Three." Siri prompts "What's the work task?" — say "ship release."
3. Siri responds "Added 'ship release' to your work backlog."
4. Open the app → Backlog → toggle to Work → "ship release" is at the top.
5. Repeat with the existing personal phrase ("Add a task to Just Do Three" → "buy milk") and confirm it still lands at the top of the personal backlog.
6. Open the Shortcuts app → JustDoThree → both "Add Task to JustDoThree" and "Add Work Task to JustDoThree" appear as runnable actions.

If anything fails, debug before merging. No commit unless changes are needed.

---

## Out of Scope (explicitly deferred)

- "Add a personal task to JustDoThree" synonym phrases — bare "Add a task" already covers personal.
- Voice-driven move between backlogs.
- Disambiguation prompt when neither phrase matches well.
- Adding `INAlternativeAppNames` so "JustDoThree" (one word) is recognized as well as "Just Do Three."
