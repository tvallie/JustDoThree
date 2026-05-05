# Siri Add-Task Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let the user say "Hey Siri, add a task to JustDoThree," speak a title, and have it appear at the top of the personal backlog with a spoken confirmation.

**Architecture:** A single in-process `AppIntent` (`AddTaskIntent`) opens the app's shared SwiftData `ModelContainer`, inserts a `JDTask(isWork: false)` at the top of the backlog, and returns a dialog. An `AppShortcutsProvider` registers fixed Siri phrases so it works zero-setup after install.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, App Intents (iOS 17), XCTest, xcodegen.

**Design doc:** [docs/plans/2026-05-05-siri-add-task-design.md](2026-05-05-siri-add-task-design.md)

**Conventions:**
- Project uses xcodegen — after creating any new source file, run `xcodegen generate` from the repo root so the Xcode project picks it up.
- Tests use XCTest. Tests for SwiftData live in `JustDoThreeTests/` and build an in-memory `ModelContainer` per test.
- Commits: short imperative subject, no Co-Authored-By trailer, no AI attribution.
- Build/test command: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`. If the user has a preferred simulator, use that; otherwise this default works.

---

### Task 1: Extract shared ModelContainer

**Why:** Both the app and the App Intent need to open the same SwiftData store. We extract the container so there's one source of truth for `[JDTask.self, DailyPlan.self, CompletionLog.self]`.

**Files:**
- Create: `JustDoThree/State/JDTModelContainer.swift`
- Modify: `JustDoThree/JustDoThreeApp.swift` (line 36 — replace `.modelContainer(for: [...])` with `.modelContainer(JDTModelContainer.shared)`)

**Step 1: Write `JDTModelContainer.swift`**

```swift
import Foundation
import SwiftData

/// Single shared SwiftData container used by the app scene and any AppIntents.
/// Keeping one container ensures app and Siri-invoked intents read/write the
/// same on-disk store with the same schema configuration.
enum JDTModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: JDTask.self, DailyPlan.self, CompletionLog.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
```

**Step 2: Update `JustDoThreeApp.swift`**

Replace line 36:
```swift
        .modelContainer(for: [JDTask.self, DailyPlan.self, CompletionLog.self])
```
with:
```swift
        .modelContainer(JDTModelContainer.shared)
```

**Step 3: Regenerate Xcode project**

Run: `xcodegen generate`
Expected: "Loaded project" + "Created project at JustDoThree.xcodeproj" — no errors.

**Step 4: Build to verify**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: BUILD SUCCEEDED.

**Step 5: Commit**

```bash
git add JustDoThree/State/JDTModelContainer.swift JustDoThree/JustDoThreeApp.swift JustDoThree.xcodeproj
git commit -m "refactor: extract shared SwiftData ModelContainer"
```

---

### Task 2: Failing test for AddTaskIntent — happy path

**Files:**
- Create: `JustDoThreeTests/AddTaskIntentTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import SwiftData
@testable import JustDoThree

final class AddTaskIntentTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
    }

    @MainActor
    func test_perform_addsTaskToPersonalBacklogAtTop() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Pre-existing items so we can prove the new task is at the top.
        let existing = JDTask(title: "old personal", sortOrder: 0, isWork: false)
        let work = JDTask(title: "work item", sortOrder: 0, isWork: true)
        context.insert(existing)
        context.insert(work)
        try context.save()

        var intent = AddTaskIntent()
        intent.title = "buy milk"

        _ = try await intent.perform(in: container)

        let all = try context.fetch(FetchDescriptor<JDTask>())
        let personal = all.filter { !$0.isWork }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(personal.count, 2)
        XCTAssertEqual(personal.first?.title, "buy milk")
        XCTAssertEqual(personal.first?.isWork, false)
        XCTAssertLessThan(personal.first!.sortOrder, existing.sortOrder)
        // Work backlog untouched.
        XCTAssertEqual(all.filter { $0.isWork }.count, 1)
    }
}
```

Note: this test calls `perform(in:)` — a test seam we'll add in the production code so the test injects its own in-memory container. Production callers (Siri) use the parameterless `perform()` which delegates to `perform(in: JDTModelContainer.shared)`.

**Step 2: Run test, expect failure**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test -only-testing:JustDoThreeTests/AddTaskIntentTests/test_perform_addsTaskToPersonalBacklogAtTop`
Expected: Compile error — `AddTaskIntent` does not exist.

**Step 3: Commit the failing test**

```bash
git add JustDoThreeTests/AddTaskIntentTests.swift
git commit -m "test: add failing test for AddTaskIntent happy path"
```

---

### Task 3: Implement AddTaskIntent (minimal — happy path only)

**Files:**
- Create: `JustDoThree/Intents/AddTaskIntent.swift`

**Step 1: Write minimal implementation**

```swift
import AppIntents
import SwiftData
import Foundation

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task to JustDoThree"
    static var description = IntentDescription(
        "Add a new task to your personal backlog in JustDoThree.",
        categoryName: "Tasks"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Task",
        description: "What you want to add to your backlog.",
        requestValueDialog: IntentDialog("What's the task?")
    )
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await perform(in: JDTModelContainer.shared)
    }

    /// Test seam: lets tests inject an in-memory container.
    @MainActor
    func perform(in container: ModelContainer) async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<JDTask>())
        let minOrder = existing.map(\.sortOrder).min() ?? 0
        let task = JDTask(title: trimmed, sortOrder: minOrder - 1, isWork: false)
        context.insert(task)
        try context.save()
        return .result(dialog: IntentDialog("Added '\(trimmed)' to your backlog."))
    }
}
```

**Step 2: Regenerate project & run test**

```bash
xcodegen generate
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test -only-testing:JustDoThreeTests/AddTaskIntentTests/test_perform_addsTaskToPersonalBacklogAtTop
```
Expected: Test PASSES.

**Step 3: Commit**

```bash
git add JustDoThree/Intents/AddTaskIntent.swift JustDoThree.xcodeproj
git commit -m "feat: add AddTaskIntent for Siri quick capture"
```

---

### Task 4: Failing test for empty title rejection

**Files:**
- Modify: `JustDoThreeTests/AddTaskIntentTests.swift`

**Step 1: Append test**

```swift
@MainActor
func test_perform_emptyTitle_throwsAndDoesNotInsert() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    var intent = AddTaskIntent()
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
```

**Step 2: Run, expect failure**

Run: `xcodebuild ... test -only-testing:JustDoThreeTests/AddTaskIntentTests/test_perform_emptyTitle_throwsAndDoesNotInsert`
Expected: FAIL — current implementation inserts a task with empty title.

**Step 3: Commit failing test**

```bash
git add JustDoThreeTests/AddTaskIntentTests.swift
git commit -m "test: add failing test for empty title rejection"
```

---

### Task 5: Reject empty titles

**Files:**
- Modify: `JustDoThree/Intents/AddTaskIntent.swift`

**Step 1: Add error type and guard**

At top of file, add:

```swift
enum AddTaskIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case emptyTitle

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyTitle: return "I didn't catch a task — try again."
        }
    }
}
```

In `perform(in:)`, after computing `trimmed`, before fetching:

```swift
guard !trimmed.isEmpty else { throw AddTaskIntentError.emptyTitle }
```

**Step 2: Run both tests**

Run: `xcodebuild ... test -only-testing:JustDoThreeTests/AddTaskIntentTests`
Expected: Both tests PASS.

**Step 3: Commit**

```bash
git add JustDoThree/Intents/AddTaskIntent.swift
git commit -m "feat: reject empty titles in AddTaskIntent"
```

---

### Task 6: Register App Shortcut phrases

**Why:** `AppShortcutsProvider` is what makes "Hey Siri, add a task to JustDoThree" work without the user creating a Shortcut by hand.

**Files:**
- Create: `JustDoThree/Intents/JDTAppShortcuts.swift`

**Step 1: Write the provider**

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
    }
}
```

Note: Apple requires every phrase to include `\(.applicationName)`. The system uses both the app's display name and any `INAlternativeAppNames` from Info.plist — JustDoThree's display name is "Just Do Three," so that's the phrase users will say. We can add alternative names in a follow-up if "JustDoThree" should also work.

**Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build
```
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add JustDoThree/Intents/JDTAppShortcuts.swift JustDoThree.xcodeproj
git commit -m "feat: register Siri phrases via AppShortcutsProvider"
```

---

### Task 7: Manual smoke test on a device or simulator

Not automated — record observations in the PR description.

1. Install build on a device or iOS 17 simulator with Siri enabled.
2. Say "Hey Siri, add a task to Just Do Three" (or trigger Siri and say it).
3. Siri prompts "What's the task?" — say "buy milk."
4. Siri responds "Added 'buy milk' to your backlog."
5. Open the app → Backlog tab → "buy milk" is at the top of the personal backlog.
6. Repeat with `activeContext` toggled to work — confirm the new task still goes to the personal backlog (not work).
7. Open the Shortcuts app → JustDoThree → "Add Task to JustDoThree" appears as a runnable action.

If anything fails, debug before merging. No commit for this step unless changes are needed.

---

## Out of Scope (explicitly deferred)

- Voice setting of due date, work/personal context, or list selection.
- A "move task from personal backlog to work backlog" action (mentioned by the user as a future feature).
- Adding `INAlternativeAppNames` so "JustDoThree" (one word) is recognized in addition to "Just Do Three."
