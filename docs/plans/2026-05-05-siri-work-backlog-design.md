# Siri Work Backlog — Design

**Goal:** Let the user say "Hey Siri, add a work task to JustDoThree" and have the spoken title appear at the top of the **work** backlog, while the existing "Add a task to JustDoThree" continues to add to the **personal** backlog.

**Background:** The initial Siri add-task feature ([2026-05-05-siri-add-task-design.md](2026-05-05-siri-add-task-design.md)) hardcoded `isWork: false` and explicitly deferred voice selection of the destination list. This adds the work-backlog variant.

## Approach

Two separate `AppIntent`s sharing a small insert helper, registered as two `AppShortcut` entries with distinct phrase sets. Personal stays the default — the existing phrases are unchanged, so existing usage keeps working without retraining.

Rejected alternative: a single intent with a Personal/Work enum parameter and phrase substitution (`"Add a \(\.$list) task..."`). Siri's parsing of single-word enum values out of speech is unreliable, and two intents make each phrase set independently testable.

## Components

**New**
- `JustDoThree/Intents/AddWorkTaskIntent.swift` — mirrors `AddTaskIntent`. Inserts with `isWork: true`. Dialog: "Added 'X' to your work backlog."
- `JustDoThree/Intents/BacklogInsert.swift` — a single free function:
  ```swift
  @MainActor
  func insertAtTopOfBacklog(title: String, isWork: Bool, in container: ModelContainer) throws -> String
  ```
  Trims, throws `AddTaskIntentError.emptyTitle` for empty, computes `minSortOrder - 1` scoped to the matching backlog, inserts, saves, returns the trimmed title for the dialog.

**Modified**
- `JustDoThree/Intents/AddTaskIntent.swift` — `perform(in:)` body becomes a one-line call to `insertAtTopOfBacklog(..., isWork: false, ...)`.
- `JustDoThree/Intents/JDTAppShortcuts.swift` — adds a second `AppShortcut` for `AddWorkTaskIntent` with phrases:
  - `"Add a work task to \(.applicationName)"`
  - `"Add work task to \(.applicationName)"`
  - `"New work task in \(.applicationName)"`

**Sort-order scope:** the helper computes `min(sortOrder)` filtered to the matching `isWork` value, so a new work task lands at the top of the work backlog regardless of personal-backlog sort orders (and vice versa).

## Tests

`JustDoThreeTests/AddWorkTaskIntentTests.swift`:
- `test_perform_addsTaskToWorkBacklogAtTop` — seed one personal and one work item, run intent, assert: new task is at top of work backlog by sortOrder, has `isWork == true`, personal backlog count unchanged.
- `test_perform_emptyTitle_throwsAndDoesNotInsert` — same shape as personal version.

Existing `AddTaskIntentTests` continue to pass unchanged (personal path is untouched behaviorally).

## Out of Scope

- "Personal task" synonym phrases ("Add a personal task to JustDoThree"). The bare "Add a task" already covers personal; can add later if Siri ambiguity surfaces.
- Moving an existing task between backlogs by voice.
- Disambiguation prompts ("work or personal?") when neither phrase is matched.
