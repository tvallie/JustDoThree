# Siri "Add Task to JustDoThree" — Design

Date: 2026-05-05

## Summary

Add a Siri voice-capture flow so the user can say "Hey Siri, add a task to
JustDoThree," speak a title, and have the task appear at the top of the
personal backlog. Hands-free, no app launch.

## Goals

- Zero-setup Siri invocation immediately after install.
- One spoken title in, one task in the personal backlog out.
- Confirmation dialog spoken by Siri; app stays closed.

## Non-Goals

- Setting due dates, work/personal context, or list selection by voice.
- Editing or completing tasks via Siri.
- Cross-process / widget / extension storage concerns.

## Architecture

A single `AppIntent` (`AddTaskIntent`) lives in the main app target and runs
in-process. It opens the same SwiftData `ModelContainer` the app uses,
inserts a new `JDTask` into the personal backlog, and returns a spoken
confirmation. An `AppShortcutsProvider` registers fixed phrases so Siri
picks them up immediately after install; the same intent is automatically
discoverable in the Shortcuts app for power users.

iOS 17 deployment target — App Intents and `AppShortcutsProvider` are fully
available. No extension target needed.

## Components

New files:

- `JustDoThree/Intents/AddTaskIntent.swift` — the `AppIntent` with one
  `@Parameter` (task title, requested by Siri if not given).
- `JustDoThree/Intents/JDTAppShortcuts.swift` — `AppShortcutsProvider`
  declaring the invocation phrases ("Add a task to JustDoThree", "Add to
  JustDoThree").

Refactor:

- Extract the app's `ModelContainer` construction into a shared
  `JDTModelContainer.shared` so both `JustDoThreeApp` and `AddTaskIntent`
  use the same SQLite store and configuration.

## Data Flow

1. User says "Hey Siri, add a task to JustDoThree."
2. Siri matches the App Shortcut phrase and invokes `AddTaskIntent`.
3. Siri prompts "What's the task?" via `@Parameter(requestValueDialog:)`.
4. User speaks the title.
5. `perform()` opens the shared `ModelContainer`, computes a `sortOrder`
   smaller than all existing personal-backlog tasks, inserts a new
   `JDTask(title:, sortOrder:, isWork: false)`, saves.
6. Returns `.result(dialog: "Added '\(title)' to your backlog.")`.

Siri-captured tasks always go to the **personal** backlog (`isWork: false`)
regardless of the app's current `activeContext`. A future feature will let
the user move a task from the personal backlog to the work backlog.

## Error Handling

- Empty or whitespace-only title: throw an `AppIntent` error with dialog
  "I didn't catch a task — try again." Siri will re-prompt.
- Duplicate title in backlog: still add. Mirrors `AddTaskSheet` behavior.
- SwiftData save failure: catch and return dialog "Sorry, I couldn't save
  that to JustDoThree." No retry.

## Sort Order

Insert at the top of the personal backlog (smallest `sortOrder` minus one),
so the just-captured item is the first thing the user sees when they next
open the app.

## Testing

Unit tests (`JustDoThreeTests/AddTaskIntentTests.swift`) using an in-memory
`ModelContainer`:

- Adds a `JDTask` with the given title, `isWork == false`, at the top.
- Empty/whitespace title throws and does not insert.
- Existing personal-backlog items keep their order; new task's `sortOrder`
  is less than all of them.
- Existing work-backlog items are untouched.

Manual smoke test on a device:

- "Hey Siri, add a task to JustDoThree" → "What's the task?" → speak title
  → spoken confirmation → open app, task is at top of personal backlog.
- Same flow invoked from the Shortcuts app.

No XCUITest coverage of the Siri flow itself.
