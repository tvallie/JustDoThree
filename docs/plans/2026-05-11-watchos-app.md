# watchOS Companion App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a watchOS app that mirrors today's three + work tasks, allows tap-to-complete, and accepts voice-add via existing Siri App Intents, syncing with the phone via WatchConnectivity.

**Architecture:** New `JustDoThreeWatch` watchOS target. Models, engines, intents, and the model-container helper move into a `JustDoThreeShared/` directory listed as `sources:` on both iOS and watchOS targets. A `WatchSync` module wraps `WCSession` with three message types: `TodaySnapshot` (phone→watch), `CompletionCommand` (watch→phone), and `IntentResult` (watch→phone). Phone remains the planner; watch is a satellite cache.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, WatchConnectivity, App Intents, XCTest, xcodegen.

**Reference:** Design doc at `docs/plans/2026-05-11-watchos-app-design.md`.

**Commit style:** Conventional Commits (`feat:`, `refactor:`, `test:`, etc.). NO `Co-Authored-By` trailer on any commit.

---

## Phase 1 — Refactor to shared sources

Move shared files into `JustDoThreeShared/`. No behavior changes. iOS app builds and tests pass identically before and after each task.

### Task 1: Create `JustDoThreeShared/` and move models

**Files:**
- Move: `JustDoThree/Models/JDTask.swift` → `JustDoThreeShared/Models/JDTask.swift`
- Move: `JustDoThree/Models/DailyPlan.swift` → `JustDoThreeShared/Models/DailyPlan.swift`
- Move: `JustDoThree/Models/RecurringRule.swift` → `JustDoThreeShared/Models/RecurringRule.swift`
- Move: `JustDoThree/Models/CompletionLog.swift` → `JustDoThreeShared/Models/CompletionLog.swift`
- Modify: `project.yml` (add `JustDoThreeShared` to `JustDoThree` target sources)

**Step 1:** `mkdir -p JustDoThreeShared/Models` then `git mv` each file.

**Step 2:** Edit `project.yml`. Under the `JustDoThree` target's `sources:` list, add a second entry:

```yaml
    sources:
      - path: JustDoThree
      - path: JustDoThreeShared
```

**Step 3:** Regenerate Xcode project:

```bash
xcodegen generate
```

**Step 4:** Build iOS target:

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

**Step 5:** Run tests:

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test 2>&1 | tail -20
```

Expected: All tests pass.

**Step 6:** Commit.

```bash
git add -A
git commit -m "refactor: move models into JustDoThreeShared for watch sharing"
```

### Task 2: Move engines (PlannerEngine, RolloverEngine)

**Files:**
- Move: `JustDoThree/Engines/PlannerEngine.swift` → `JustDoThreeShared/Engines/PlannerEngine.swift`
- Move: `JustDoThree/Engines/RolloverEngine.swift` → `JustDoThreeShared/Engines/RolloverEngine.swift`
- **Do NOT move** `JustDoThree/Engines/TaskOCREngine.swift` (depends on UIKit, stays iOS-only).

**Step 1:** `mkdir -p JustDoThreeShared/Engines` and `git mv` the two files.

**Step 2:** Regenerate, build, test as in Task 1 steps 3–5.

**Step 3:** Commit.

```bash
git add -A
git commit -m "refactor: move PlannerEngine and RolloverEngine into shared sources"
```

### Task 3: Move intents and JDTModelContainer

**Files:**
- Move: `JustDoThree/Intents/AddTaskIntent.swift` → `JustDoThreeShared/Intents/AddTaskIntent.swift`
- Move: `JustDoThree/Intents/AddWorkTaskIntent.swift` → `JustDoThreeShared/Intents/AddWorkTaskIntent.swift`
- Move: `JustDoThree/Intents/BacklogInsert.swift` → `JustDoThreeShared/Intents/BacklogInsert.swift`
- Move: `JustDoThree/Intents/JDTAppShortcuts.swift` → `JustDoThreeShared/Intents/JDTAppShortcuts.swift`
- Move: `JustDoThree/State/JDTModelContainer.swift` → `JustDoThreeShared/State/JDTModelContainer.swift`

**Step 1:** `mkdir -p JustDoThreeShared/Intents JustDoThreeShared/State` and `git mv` each file.

**Step 2:** Regenerate, build, test.

**Step 3:** Commit.

```bash
git add -A
git commit -m "refactor: move intents and model container into shared sources"
```

### Task 4: Parameterize `JDTModelContainer` for per-platform store

**Files:**
- Modify: `JustDoThreeShared/State/JDTModelContainer.swift`
- Modify: callers (`JustDoThreeApp.swift`, intent files) — usages of `JDTModelContainer.shared` should still work unchanged.

**Step 1:** Add a `shared(url:)` factory plus keep `.shared` as the iOS default. The watch target will call `shared(url:)` with a watch-specific URL later.

```swift
import Foundation
import SwiftData

enum JDTModelContainer {
    static let shared: ModelContainer = make(url: nil)

    static func make(url: URL?) -> ModelContainer {
        do {
            let config: ModelConfiguration
            if let url {
                config = ModelConfiguration(url: url)
            } else {
                config = ModelConfiguration()
            }
            return try ModelContainer(
                for: JDTask.self, DailyPlan.self, CompletionLog.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
```

**Step 2:** Build and run tests. Expected: still passing — iOS path unchanged.

**Step 3:** Commit.

```bash
git add -A
git commit -m "refactor: parameterize JDTModelContainer to accept custom store URL"
```

---

## Phase 2 — Watch target skeleton

### Task 5: Add `JustDoThreeWatch` target to `project.yml`

**Files:**
- Create: `JustDoThreeWatch/JustDoThreeWatchApp.swift` (minimal entry point)
- Create: `JustDoThreeWatch/RootView.swift` (placeholder text view)
- Create: `JustDoThreeWatch/Info.plist` (or use auto-generated)
- Modify: `project.yml`

**Step 1:** Create the watch target entry-point file:

```swift
// JustDoThreeWatch/JustDoThreeWatchApp.swift
import SwiftUI

@main
struct JustDoThreeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

```swift
// JustDoThreeWatch/RootView.swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Just Do Three")
    }
}
```

**Step 2:** Add the new target to `project.yml`:

```yaml
  JustDoThreeWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources:
      - path: JustDoThreeWatch
      - path: JustDoThreeShared
    info:
      path: JustDoThreeWatch/Info.plist
      properties:
        CFBundleDisplayName: Just Do Three
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        WKApplication: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.todd.justdothree.watchkitapp
        DEVELOPMENT_TEAM: 3ZAS78KQUH
        MARKETING_VERSION: "3"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.9"
        TARGETED_DEVICE_FAMILY: "4"
        INFOPLIST_FILE: JustDoThreeWatch/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        CODE_SIGN_STYLE: Automatic
        WATCHOS_DEPLOYMENT_TARGET: "10.0"
```

Also add a `scheme` for the watch target under `schemes:`.

Also modify the iOS target to declare a watch companion via the `dependencies:` mechanism (xcodegen): add `dependencies: - target: JustDoThreeWatch` under the `JustDoThree` target, with `embed: true` and `link: false` so the watch app embeds into the iOS app.

**Step 3:** Regenerate Xcode project.

**Step 4:** Build the watch scheme:

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThreeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`. If shared sources fail to compile on watchOS, fix them (most likely culprit: a stray `import UIKit` or `@Environment(\.scenePhase)` use).

**Step 5:** Build iOS scheme too — verify the embedding didn't break it.

**Step 6:** Commit.

```bash
git add -A
git commit -m "feat: add empty JustDoThreeWatch target embedded in iOS app"
```

### Task 6: Audit shared sources for watchOS compatibility

**Files:** any file under `JustDoThreeShared/` flagged by the build.

**Step 1:** From Task 5's build output, list compile errors. Likely categories:
- `import UIKit` in a shared file → conditional-compile out (`#if canImport(UIKit)`) or move the offending code back to iOS-only.
- `@available(iOS 17, *)` annotations without watchOS equivalent → add `, watchOS 10`.
- `EventKit` / `Speech` / `AVFoundation` usage → these don't belong in shared; move them.

**Step 2:** Fix each issue with the minimum change needed.

**Step 3:** Rebuild both schemes. Both must succeed.

**Step 4:** Run iOS tests — still passing.

**Step 5:** Commit.

```bash
git add -A
git commit -m "fix: make shared sources compile on watchOS"
```

---

## Phase 3 — Sync codec (TDD)

### Task 7: Define `TodaySnapshot`, `CompletionCommand`, `IntentResult` value types

**Files:**
- Create: `JustDoThreeShared/Sync/SyncMessages.swift`
- Create: `JustDoThreeTests/Sync/SyncMessagesTests.swift`
- Modify: `project.yml` (no changes needed if `JustDoThreeShared` already in sources)

**Step 1:** Write the failing tests first.

```swift
// JustDoThreeTests/Sync/SyncMessagesTests.swift
import XCTest
@testable import JustDoThree

final class SyncMessagesTests: XCTestCase {
    func test_todaySnapshot_encodes_and_decodes_roundtrip() throws {
        let snap = TodaySnapshot(
            schemaVersion: 1,
            planDate: Date(timeIntervalSince1970: 1_700_000_000),
            today: [.init(id: UUID(), title: "A", isCompleted: false, isStretch: false)],
            work: [.init(id: UUID(), title: "W", isCompleted: true, isStretch: false)],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(TodaySnapshot.self, from: data)
        XCTAssertEqual(snap, back)
    }

    func test_completionCommand_roundtrip() throws {
        let cmd = CompletionCommand(
            schemaVersion: 1,
            taskID: UUID(),
            action: .complete,
            issuedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let data = try JSONEncoder().encode(cmd)
        let back = try JSONDecoder().decode(CompletionCommand.self, from: data)
        XCTAssertEqual(cmd, back)
    }

    func test_intentResult_roundtrip() throws {
        let result = IntentResult(
            schemaVersion: 1,
            clientID: UUID(),
            list: .personalBacklog,
            title: "Pick up milk",
            createdAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let data = try JSONEncoder().encode(result)
        let back = try JSONDecoder().decode(IntentResult.self, from: data)
        XCTAssertEqual(result, back)
    }

    func test_decode_rejects_unknown_schema_version() {
        let json = #"{"schemaVersion": 99, "taskID": "\#(UUID().uuidString)", "action": "complete", "issuedAt": 0}"#
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try CompletionCommand.decodeCompatible(from: data))
    }
}
```

**Step 2:** Run tests to verify they fail (compile error: types not defined).

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test -only-testing:JustDoThreeTests/SyncMessagesTests 2>&1 | tail -20
```

Expected: build fails with "Cannot find 'TodaySnapshot' in scope".

**Step 3:** Implement.

```swift
// JustDoThreeShared/Sync/SyncMessages.swift
import Foundation

enum SyncSchema {
    static let current: Int = 1
}

struct TodaySnapshot: Codable, Equatable {
    struct Row: Codable, Equatable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        let isStretch: Bool
    }
    let schemaVersion: Int
    let planDate: Date
    let today: [Row]
    let work: [Row]
    let generatedAt: Date
}

struct CompletionCommand: Codable, Equatable {
    enum Action: String, Codable { case complete, uncomplete }
    let schemaVersion: Int
    let taskID: UUID
    let action: Action
    let issuedAt: Date

    static func decodeCompatible(from data: Data) throws -> CompletionCommand {
        let value = try JSONDecoder().decode(CompletionCommand.self, from: data)
        guard value.schemaVersion == SyncSchema.current else {
            throw SyncDecodeError.unsupportedSchemaVersion(value.schemaVersion)
        }
        return value
    }
}

struct IntentResult: Codable, Equatable {
    enum List: String, Codable { case personalBacklog, workBacklog }
    let schemaVersion: Int
    let clientID: UUID
    let list: List
    let title: String
    let createdAt: Date
}

enum SyncDecodeError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}
```

**Step 4:** Run tests — all pass.

**Step 5:** Commit.

```bash
git add -A
git commit -m "feat: add WatchConnectivity sync message types with schema versioning"
```

### Task 8: Add `decodeCompatible` to remaining sync types

**Files:**
- Modify: `JustDoThreeShared/Sync/SyncMessages.swift`
- Modify: `JustDoThreeTests/Sync/SyncMessagesTests.swift`

**Step 1:** Add failing tests for `TodaySnapshot.decodeCompatible` and `IntentResult.decodeCompatible` rejecting wrong schema versions.

**Step 2:** Run, verify they fail (method not defined).

**Step 3:** Implement the static methods identically to `CompletionCommand.decodeCompatible`.

**Step 4:** Tests pass.

**Step 5:** Commit.

```bash
git add -A
git commit -m "feat: add schema-version validation for snapshot and intent result decoding"
```

---

## Phase 4 — Phone-side sync handler (TDD)

### Task 9: `PhoneSyncHandler` — apply `CompletionCommand`

**Files:**
- Create: `JustDoThree/Sync/PhoneSyncHandler.swift` (iOS-only — owns the phone-side WCSession plumbing)
- Create: `JustDoThreeTests/Sync/PhoneSyncHandlerTests.swift`

The handler has two responsibilities tested here:
1. Apply an incoming `CompletionCommand` by calling `PlannerEngine.complete` / `uncomplete`.
2. Build a `TodaySnapshot` from the current store.

**Step 1:** Write failing tests. Use an in-memory `ModelContainer` and seed today's plan with two tasks.

```swift
final class PhoneSyncHandlerTests: XCTestCase {
    var container: ModelContainer!
    var handler: PhoneSyncHandler!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
        handler = PhoneSyncHandler(container: container)
    }

    func test_applyCompletionCommand_routes_through_PlannerEngine_complete() async throws {
        let task = JDTask(title: "Test")
        let plan = DailyPlan(date: Calendar.current.startOfDay(for: Date()))
        plan.taskIDs = [task.id]
        let ctx = ModelContext(container)
        ctx.insert(task)
        ctx.insert(plan)
        try ctx.save()

        let cmd = CompletionCommand(
            schemaVersion: 1, taskID: task.id, action: .complete,
            issuedAt: Date()
        )
        try await handler.apply(cmd)

        let updated = try ctx.fetch(FetchDescriptor<JDTask>()).first { $0.id == task.id }!
        XCTAssertTrue(updated.isCompleted)
        let updatedPlan = try ctx.fetch(FetchDescriptor<DailyPlan>()).first!
        XCTAssertTrue(updatedPlan.completedTaskIDs.contains(task.id))
    }

    func test_applyCompletionCommand_uncomplete_path() async throws {
        // ... mirror complete test but for uncomplete action
    }

    func test_buildSnapshot_returns_today_and_work_rows() async throws {
        // ... seed plan with stretch + work tasks, assert snapshot rows
    }
}
```

**Step 2:** Run tests, verify they fail to compile.

**Step 3:** Implement `PhoneSyncHandler`.

```swift
// JustDoThree/Sync/PhoneSyncHandler.swift
import Foundation
import SwiftData

@MainActor
final class PhoneSyncHandler {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func apply(_ cmd: CompletionCommand) throws {
        let ctx = ModelContext(container)
        guard let task = try ctx.fetch(FetchDescriptor<JDTask>(
            predicate: #Predicate { $0.id == cmd.taskID }
        )).first else { return }

        switch cmd.action {
        case .complete:   PlannerEngine.complete(task: task, in: ctx)
        case .uncomplete: PlannerEngine.uncomplete(task: task, in: ctx)
        }
        try ctx.save()
    }

    func buildSnapshot() throws -> TodaySnapshot {
        // Fetch today's plan, today tasks, work tasks; map to Rows.
        // Implementation reads existing AppState logic for "today + work" assembly.
        // ...
    }

    func apply(_ result: IntentResult) throws {
        // Insert into backlog with client-supplied UUID; dedupe.
        // ...
    }
}
```

Note: actual `PlannerEngine.complete` / `uncomplete` signatures — verify against [PlannerEngine.swift](JustDoThreeShared/Engines/PlannerEngine.swift) and adapt the call sites.

**Step 4:** Run tests, all pass.

**Step 5:** Commit.

```bash
git add -A
git commit -m "feat: add PhoneSyncHandler that applies completion commands via PlannerEngine"
```

### Task 10: `PhoneSyncHandler` — apply `IntentResult` with idempotency

**Files:**
- Modify: `JustDoThree/Sync/PhoneSyncHandler.swift`
- Modify: `JustDoThreeTests/Sync/PhoneSyncHandlerTests.swift`

**Step 1:** Failing tests:
- Applying an `IntentResult` inserts a `JDTask` at top of backlog matching the `list`.
- Applying the same `IntentResult` twice inserts only one task (dedupe by `clientID == JDTask.id`).

**Step 2:** Run, fail.

**Step 3:** Implement: insert via `BacklogInsert.insertAtTopOfBacklog` with `clientID` as the new task's `id`. Skip if a task with that `id` already exists.

**Step 4:** Tests pass.

**Step 5:** Commit.

```bash
git add -A
git commit -m "feat: apply intent results idempotently with client UUID dedupe"
```

### Task 11: Wire `PhoneSyncHandler` into a `WCSessionDelegate`

**Files:**
- Create: `JustDoThree/Sync/PhoneWCDelegate.swift`
- Modify: `JustDoThree/JustDoThreeApp.swift` (activate session on app launch)

**Step 1:** Implement `PhoneWCDelegate: NSObject, WCSessionDelegate`. On `didReceiveMessage` / `didReceiveUserInfo`, decode into `CompletionCommand` or `IntentResult`, hand to `PhoneSyncHandler`. On `didReceiveApplicationContext`, the phone doesn't currently expect one (snapshot flows phone→watch); log and ignore.

**Step 2:** Add a `pushSnapshot()` method that takes the snapshot, encodes to JSON, and calls `WCSession.default.updateApplicationContext`. Phone calls this whenever today's plan changes — observe via SwiftData `ModelContext.didSave` or by hooking into `AppState`.

**Step 3:** In `JustDoThreeApp.swift`, activate the session at startup:

```swift
init() {
    if WCSession.isSupported() {
        let delegate = PhoneWCDelegate.shared
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }
}
```

**Step 4:** Build iOS, run existing tests.

**Step 5:** Commit.

```bash
git add -A
git commit -m "feat: activate WCSession on phone and route messages to PhoneSyncHandler"
```

### Task 12: Push snapshot on plan changes

**Files:**
- Modify: `JustDoThree/State/AppState.swift` (or wherever plan mutations are centralized)
- Modify: `JustDoThree/Sync/PhoneWCDelegate.swift`

**Step 1:** Identify the choke point where plan / completion state changes (most likely in `AppState` or in views that call `PlannerEngine`). After each mutation, call `PhoneWCDelegate.shared.pushSnapshot(from:)`.

**Step 2:** Manual smoke test on iOS sim: confirm no regression in the iOS app.

**Step 3:** Commit.

```bash
git add -A
git commit -m "feat: push snapshot to watch on plan and completion mutations"
```

---

## Phase 5 — Watch-side sync + local store

### Task 13: Watch-local `JDTModelContainer` setup

**Files:**
- Modify: `JustDoThreeWatch/JustDoThreeWatchApp.swift`

**Step 1:** Configure the watch's model container with a URL in the watch app's documents directory.

```swift
@main
struct JustDoThreeWatchApp: App {
    let container: ModelContainer = {
        let url = URL.documentsDirectory.appending(path: "jdt-watch.store")
        return JDTModelContainer.make(url: url)
    }()
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}
```

**Step 2:** Build watch target.

**Step 3:** Commit.

```bash
git add -A
git commit -m "feat: configure watch SwiftData container in app documents directory"
```

### Task 14: `WatchSyncStore` — snapshot apply (TDD)

**Files:**
- Create: `JustDoThreeShared/Sync/WatchSyncStore.swift` (lives in shared so both targets reference it, but only the watch instantiates it)
- Create: `JustDoThreeTests/Sync/WatchSyncStoreTests.swift`

**Step 1:** Failing test: applying a `TodaySnapshot` to an empty container creates the plan + tasks matching the snapshot.

```swift
func test_applySnapshot_seeds_empty_store() async throws {
    let container = try ModelContainer(
        for: JDTask.self, DailyPlan.self, CompletionLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = WatchSyncStore(container: container)
    let snap = TodaySnapshot(
        schemaVersion: 1,
        planDate: Calendar.current.startOfDay(for: Date()),
        today: [.init(id: UUID(), title: "A", isCompleted: false, isStretch: false)],
        work: [.init(id: UUID(), title: "W", isCompleted: false, isStretch: false)],
        generatedAt: Date()
    )
    try store.apply(snap)

    let ctx = ModelContext(container)
    let tasks = try ctx.fetch(FetchDescriptor<JDTask>())
    XCTAssertEqual(tasks.count, 2)
}
```

Plus a second test: applying a newer snapshot replaces stale data (older `generatedAt` snapshots are ignored).

**Step 2:** Run, fail.

**Step 3:** Implement `WatchSyncStore.apply(_:)`. Strategy: wipe today's plan + referenced tasks, re-insert from snapshot. Track last-applied `generatedAt` in `UserDefaults` to ignore out-of-order deliveries.

**Step 4:** Tests pass.

**Step 5:** Commit.

```bash
git add -A
git commit -m "feat: add WatchSyncStore that applies snapshots to local SwiftData"
```

### Task 15: Watch `WCSessionDelegate`

**Files:**
- Create: `JustDoThreeWatch/Sync/WatchWCDelegate.swift`
- Modify: `JustDoThreeWatch/JustDoThreeWatchApp.swift`

**Step 1:** Implement delegate. On `didReceiveApplicationContext`, decode `TodaySnapshot` and apply via `WatchSyncStore`. Provide a `sendCompletion(_:)` method that calls `WCSession.default.sendMessage` (with `transferUserInfo` fallback).

**Step 2:** Activate the session in `JustDoThreeWatchApp.init()`.

**Step 3:** Build watch target.

**Step 4:** Commit.

```bash
git add -A
git commit -m "feat: activate WCSession on watch and apply incoming snapshots"
```

---

## Phase 6 — Watch UI

### Task 16: `TodayPage` view with tap-to-complete

**Files:**
- Create: `JustDoThreeWatch/Views/TodayPage.swift`
- Modify: `JustDoThreeWatch/RootView.swift` (use `TabView` of pages)

**Step 1:** Implement `TodayPage`: `@Query` for today's plan, render three rows + (if any) a "Stretch" section header and stretch rows. Each row is a button; tap toggles completion locally and fires `WatchWCDelegate.shared.sendCompletion(...)` plus `WKInterfaceDevice.current().play(.success)` on complete, `.click` on uncomplete.

**Step 2:** Empty state: if no plan for today, show "Open Just Do Three on iPhone."

**Step 3:** Build watch target. Run watch in simulator, verify list renders (you may need to seed local store manually for now).

**Step 4:** Commit.

```bash
git add -A
git commit -m "feat: add watch Today page with tap-to-complete and stretch section"
```

### Task 17: `WorkPage` view + `TabView` wiring

**Files:**
- Create: `JustDoThreeWatch/Views/WorkPage.swift`
- Modify: `JustDoThreeWatch/RootView.swift`

**Step 1:** Implement `WorkPage` mirroring `TodayPage` but querying work tasks. Same tap-to-complete behavior.

**Step 2:** In `RootView`, use:

```swift
TabView {
    TodayPage()
    WorkPage()
}
.tabViewStyle(.page)
```

**Step 3:** Build, verify both pages render and swipe works.

**Step 4:** Commit.

```bash
git add -A
git commit -m "feat: add watch Work page and TabView paging"
```

---

## Phase 7 — Intents on watch + snippet confirmation

### Task 18: Verify intents compile and register on watch

**Step 1:** Since `JustDoThreeShared/Intents/*` are already in the watch target via the shared sources, the App Intents should auto-register on first install. Build watch, install on simulator, open Shortcuts app on simulator (if possible) or attempt "Hey Siri, add task to Just Do Three" on a real paired watch.

**Step 2:** If the intent runs on watch, it writes via `JDTModelContainer.shared` — but the watch's container is created via `make(url:)` in `JustDoThreeWatchApp`, not `.shared`. Reconcile this: the intents need to use the same container the watch app uses.

**Fix:** Change the intents to look up the container from a singleton holder rather than `JDTModelContainer.shared` directly, and have the watch app populate that holder on launch. Same change on iOS uses `.shared`.

```swift
// JustDoThreeShared/State/JDTContainerProvider.swift
enum JDTContainerProvider {
    static var current: ModelContainer = JDTModelContainer.shared
}
```

Watch app sets `JDTContainerProvider.current = container` in its `init`.

**Step 3:** Build both targets, run iOS tests.

**Step 4:** Commit.

```bash
git add -A
git commit -m "refactor: route intents through JDTContainerProvider for per-platform store"
```

### Task 19: Intent posts `IntentResult` to phone after writing locally

**Files:**
- Modify: `JustDoThreeShared/Intents/AddTaskIntent.swift`
- Modify: `JustDoThreeShared/Intents/AddWorkTaskIntent.swift`

**Step 1:** After the existing write logic, emit an `IntentResult` to the WCSession. Wrap in `#if os(watchOS)` so the phone path is unchanged.

```swift
#if os(watchOS)
WatchWCDelegate.shared.sendIntentResult(
    IntentResult(
        schemaVersion: 1, clientID: newTask.id,
        list: .personalBacklog, title: title, createdAt: Date()
    )
)
#endif
```

**Step 2:** Build watch + iOS. Run iOS tests (`AddWorkTaskIntentTests`, `AddTaskIntentTests`) — must still pass.

**Step 3:** Commit.

```bash
git add -A
git commit -m "feat: forward watch-side intent results to phone via WCSession"
```

### Task 20: Snippet confirmation view

**Files:**
- Create: `JustDoThreeShared/Intents/AddedSnippetView.swift`
- Modify: both intent files to return the snippet.

**Step 1:** Implement a minimal SwiftUI view:

```swift
struct AddedSnippetView: View {
    let listLabel: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Added to \(listLabel)").font(.caption).foregroundStyle(.secondary)
            Text(title).font(.headline)
        }
        .padding()
    }
}
```

**Step 2:** In each intent's `perform()`, return:

```swift
return .result(
    dialog: "Added to backlog: \(title)",
    view: AddedSnippetView(listLabel: "backlog", title: title)
)
```

(Or `"work backlog"` for the work intent.)

**Step 3:** Build, run iOS tests — they may need updating if they assert on the return shape.

**Step 4:** Commit.

```bash
git add -A
git commit -m "feat: return snippet view confirming added task in Siri UI"
```

---

## Phase 8 — Verification

### Task 21: Manual end-to-end QA

Run through these scenarios on a real paired watch (simulator can do most but Siri intents work best on hardware):

1. **Glance:** open watch app with phone reachable — Today + Work populated within ~1s.
2. **Glance (no plan today):** delete today's plan on phone, open watch — "Open on iPhone" shown.
3. **Tap-complete on watch:** tap a Today row — haptic fires, row strikes through, phone reflects within ~1s.
4. **Tap-complete with phone unreachable:** disable phone Bluetooth, tap, re-enable — phone catches up.
5. **Voice-add backlog (phone reachable):** "Hey Siri, add a task to Just Do Three" → speak → snippet card shows "Added to backlog: …" → phone backlog has new top entry.
6. **Voice-add work (phone reachable):** "Hey Siri, add a work task to Just Do Three" → similar.
7. **Voice-add (phone unreachable):** disable Bluetooth, voice-add, re-enable — phone receives.
8. **Stretch task display:** add a stretch task on phone, snapshot pushes — watch shows divider + stretch row, tap-complete works.
9. **Recurring task completion:** complete a recurring task on watch — phone correctly handles recurrence rule (next instance not pre-completed).

**Step 1:** Walk through each scenario. Note any failures.

**Step 2:** File follow-up issues for anything not covered or broken. Fix only blocking bugs in this branch; defer polish.

**Step 3:** When all scenarios pass, the branch is ready to merge.

---

## Skills to reference during execution

- @superpowers:test-driven-development for all TDD tasks (codec, sync handler)
- @superpowers:systematic-debugging if any task hits unexpected failures
- @superpowers:verification-before-completion before claiming any task done
- @superpowers:finishing-a-development-branch when all phases complete
