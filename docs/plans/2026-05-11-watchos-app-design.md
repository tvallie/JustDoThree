# watchOS Companion App — Design

Date: 2026-05-11

## Summary

Add a watchOS app target that lets the user (a) glance at today's three plus
work tasks, (b) check items off with a tap, and (c) capture new backlog
items by voice via the existing Siri App Intents. The phone remains the
sole owner of daily planning, rollover, and the canonical SwiftData store;
the watch is a satellite that mirrors a small slice of state and syncs
edits back via WatchConnectivity.

## Goals

- Glanceable view of today's three + stretch tasks, tap-to-complete with
  strong haptic confirmation.
- Glanceable view of today's work tasks, tap-to-complete.
- Voice capture via existing `AddTaskIntent` and `AddWorkTaskIntent`,
  fronted by a Siri snippet card that confirms what was captured and where
  it went ("Added to backlog: …" / "Added to work backlog: …").
- No iCloud sign-in required; works offline as long as phone is in range.
- Zero impact on users who do not own an Apple Watch.

## Non-Goals

- Backlog browsing on the watch (personal or work backlog beyond items
  pulled into today).
- Editing task title, due date, recurrence, or order on the watch.
- Adding or removing items from today's three on the watch.
- Running the planner / rollover engine on the watch.
- Complications, Smart Stack widgets, or watchface integrations (deferred).
- CloudKit-backed sync; existing local SwiftData store stays unchanged.

## Architecture

### Targets

A new `JustDoThreeWatch` watchOS app target is added to `project.yml`.
A shared sources directory `JustDoThreeShared/` is created and added as a
source path on **both** the iOS and watchOS targets. The following existing
files move into `JustDoThreeShared/` so they compile into both targets:

- `Models/JDTask.swift`
- `Models/DailyPlan.swift`
- `Models/` supporting enums and value types referenced by the above
- `Engines/PlannerEngine.swift` (completion / uncompletion entry points)
- `Engines/` dependencies of PlannerEngine that do not import UIKit
- `State/JDTModelContainer.swift` (parameterized so each platform can pass
  its own store URL)
- `Intents/AddTaskIntent.swift`
- `Intents/AddWorkTaskIntent.swift`
- `Intents/BacklogInsert.swift`
- `Intents/JDTAppShortcuts.swift`

Anything that imports `UIKit`, depends on `EventKit` calendar/reminders, or
touches the camera/OCR stack stays in the iOS-only `JustDoThree/` sources
and does not move.

### Data ownership

The phone owns the canonical SwiftData store. The watch keeps its own local
SwiftData store containing only the slice it needs: today's `DailyPlan`,
the `JDTask` rows referenced by that plan (including stretch), and the
work tasks scheduled for today. The watch never builds a plan, never runs
rollover, never reads the backlog.

The watch's local store is treated as a write-through cache. The phone is
the source of truth; on disagreement, the phone wins.

### Sync layer (WatchConnectivity)

A new `WatchSync` module (in `JustDoThreeShared/`) wraps `WCSession`:

- **Phone → Watch (push)**: when today's plan, completion state, or work
  task list changes, the phone sends a `TodaySnapshot` message containing
  the minimal payload the watch UI needs (task IDs, titles, completion
  flags, plan ID, snapshot timestamp). Uses `updateApplicationContext` so
  only the latest snapshot is delivered if multiple updates queue up while
  the watch is asleep.

- **Watch → Phone (commands)**: when the user taps to complete or
  uncomplete on the watch, the watch sends a `CompletionCommand` message
  via `sendMessage` (with `transferUserInfo` fallback for offline). Phone
  applies the command via `PlannerEngine.complete(task:)` or
  `uncomplete(task:)`, then pushes a fresh `TodaySnapshot` back.

- **Watch → Phone (voice-add result)**: when an App Intent runs on the
  watch, after writing to the watch's local store, the watch sends an
  `IntentResult` message describing the new task (text, list,
  client-generated UUID). Phone deduplicates by UUID and inserts into its
  own backlog via the existing `insertAtTopOfBacklog` path.

All messages are versioned (`schemaVersion: Int`) so future schema changes
can be handled without crashing older paired devices.

### App Intents on watchOS

`AddTaskIntent` and `AddWorkTaskIntent` already exist and are
self-contained except for their use of `JDTModelContainer`. They will run
on whichever device Siri targets:

- **From watch (no nearby phone)**: intent runs on watch, writes to the
  watch's local store, queues an `IntentResult` for the phone (delivered
  next time phone is reachable). Snippet card shown on watch.
- **From watch (phone nearby)**: same as above; eventual consistency on
  the phone happens within seconds.
- **From phone**: unchanged from today.

The watch never displays the new task in its UI (backlog isn't shown on
watch), so the snippet card is the user's only confirmation. The snippet
view is a small SwiftUI view returned from `perform()` via
`IntentDialog(snippetView:)`, displaying "Added to backlog: <title>" or
"Added to work backlog: <title>".

### Watch UI

A single `WatchRootView` containing a two-page `TabView` with the dot
page-style indicator:

- **Page 1 — Today**: vertical list. Rows 1–3 are the daily three. If any
  stretch tasks exist, a "Stretch" section header follows, then stretch
  rows. Tapping a row toggles completion (strong `WKHapticType.success`
  on complete, lighter `.click` on uncomplete). Completed rows show
  strikethrough + dimmed.
- **Page 2 — Work**: vertical list of today's scheduled work tasks
  (whatever logic the phone uses to decide "today's work" — watch consumes
  the snapshot as-is). Same tap-to-complete behavior.

Empty state for either page: if the watch has no snapshot for today, both
pages show "Open Just Do Three on iPhone." The watch does not attempt to
build a plan from whatever data it has.

## Data Flow

### Cold start (watch app launch)

1. Watch opens local SwiftData store.
2. If a snapshot exists with `planDate == today`, render it immediately.
3. Watch requests fresh snapshot from phone via `WCSession`.
4. On reply, overwrite local store and re-render. If no plan exists for
   today on the phone either, render the "Open on iPhone" state.

### Tap to complete on watch

1. User taps row. Watch optimistically toggles UI + plays haptic.
2. Watch updates local `JDTask.isCompleted` and local plan's
   `completedTaskIDs`.
3. Watch sends `CompletionCommand(taskID, action: .complete)` to phone.
4. Phone applies via `PlannerEngine.complete(task:)`. This handles
   recurring rules and stretch promotion correctly.
5. Phone pushes refreshed `TodaySnapshot` to watch; watch reconciles
   (no-op if optimistic state already matches).

If phone is unreachable, the command is queued via `transferUserInfo` and
delivered when the watch next reaches the phone.

### Voice-add from watch

1. "Hey Siri, add task to Just Do Three" → Siri runs `AddTaskIntent` on
   watch.
2. Intent generates UUID, inserts `JDTask` into watch's local backlog
   shadow (or in-memory queue if we choose not to store backlog locally —
   see Open Questions).
3. Intent returns dialog + snippet card to Siri.
4. Watch posts `IntentResult` over `WCSession`.
5. Phone receives, inserts into canonical backlog using
   `insertAtTopOfBacklog` keyed on the watch-supplied UUID. Idempotent on
   retry.

## Error Handling

- **Phone unreachable**: snapshot may be stale. UI shows last known data
  with a small "syncing…" footer when a request is outstanding. Completion
  taps queue locally; commands deliver when reachable.
- **Schema mismatch** (newer watch, older phone or vice versa): receiving
  side drops the message and logs. Watch falls back to "Open on iPhone."
- **Plan missing for today on phone**: phone sends an explicit "no plan
  for today" snapshot rather than no message at all. Watch renders empty
  state.
- **Duplicate intent delivery**: phone deduplicates by client-supplied
  UUID before inserting.
- **WCSession not activated** (e.g., during very first launch): both sides
  retry activation on `sessionDidBecomeInactive` / `sessionDidDeactivate`.

## Testing

- Unit tests for the `WatchSync` codec (encode/decode `TodaySnapshot`,
  `CompletionCommand`, `IntentResult` round-trip, schema-version
  rejection).
- Unit tests for the phone-side handler: applying a `CompletionCommand`
  routes through `PlannerEngine.complete` (verify recurring-rule case is
  exercised). Applying an `IntentResult` is idempotent on duplicate UUID.
- Unit tests for the watch-side store reducer: snapshot apply replaces
  local plan + tasks, completion command produces correct optimistic UI.
- Manual: pair a watch to a development phone, exercise the four flows
  (glance, tap-complete, voice-add backlog, voice-add work) with phone
  reachable and unreachable.

The existing `PlannerEngine` test suite covers the completion logic the
watch ultimately drives, so we don't duplicate those tests at the
sync-layer level.

## Migration / Rollout

- No data migration. The phone's existing SwiftData store is untouched.
- The watch app ships in the same release as the iOS app and is installed
  via the standard "Install on Apple Watch" toggle in the Watch app on
  iPhone.
- First watch launch: empty local store, immediately requests snapshot
  from phone. No special first-run UI beyond the empty state.

## Open Questions

- **Local watch backlog storage**: should the watch persist its in-flight
  voice-add tasks to its local SwiftData store, or hold them in memory
  until WCSession confirms phone receipt? In-memory is simpler but loses
  the task if the user force-quits the watch app before the phone is
  reachable. Recommended: persist to local store, delete on confirmed
  phone insert.
- **Stretch task ordering on watch**: phone may have a custom ordering;
  watch will respect whatever order the snapshot delivers.
