# Rollover Scheduling Design

## Goal

Give users full control over rolled-over tasks: add to today (with a bump-and-replace flow if today is full), schedule for a specific future date, or send to backlog — individually or in bulk.

## Background

The existing `RolloverSheet` shows one row per incomplete task from previous days. Each row has three choice buttons: **Done**, **Today**, **Backlog**. When today's 3 slots are already full, "Today" is simply disabled with no explanation and no alternative. There is no way to schedule a task for a future date, and no way to apply a choice to all tasks at once.

## Design

### Per-Task Choices (4 options)

| Choice | Behavior |
|--------|----------|
| **Done** | Mark completed on the original day (unchanged) |
| **Today** | Add to today's plan — triggers replace flow if today is full |
| **Schedule** | Opens a day-picker; button label updates to chosen date (e.g. "Thu Mar 27") |
| **Backlog** | Leave in backlog, no plan association (unchanged) |

### "Today" When Today Is Full

If today already has 3 tasks and the user taps **Today**:

- The row expands below the task title to show today's 3 scheduled tasks
- Each shows a **Replace** pill
- Tapping one selects it — that task will be removed from today and moved to the backlog
- The **Today** button stays highlighted to confirm the choice
- A note below the list reads: *"Replaced task goes to backlog."*

### "Schedule" Day Picker

- Tapping **Schedule** opens a compact bottom sheet
- Shows the next 7 days as day chips (same visual style as the Plan tab)
- Today is excluded (use **Today** button for that)
- Tapping a day dismisses the sheet and updates the row's button label to the short day name + date
- The `.scheduleFor(Date)` choice is stored on the item

### Bulk Apply ("Apply to all")

- A bar at the top of the task list (above the rows) with the same 4 buttons: Done / Today / Schedule / Backlog
- Tapping a bulk choice sets all **unset** tasks to that choice
- Tasks that have already been individually set are skipped (they have `isIndividuallySet = true`)
- Individually-set rows show a subtle lock indicator (e.g. a small filled dot or checkmark) so the user knows they're protected
- If bulk **Today** is tapped and today is full, any overflow tasks fall back to **Backlog** with an inline note explaining why
- If bulk **Schedule** is tapped, one date picker opens; the chosen date is applied to all unset tasks

### Interaction Order

Users can mix individual and bulk actions freely:
1. Set specific tasks individually first → those rows are locked
2. Tap "Apply to all" to handle remaining unset rows in one tap

Or reverse: set a bulk default first, then override individual rows.

## Data Model Changes

### `RolloverItem.Choice` enum — add two cases

```swift
case scheduleFor(Date)
case addToTodayReplacing(taskID: UUID)
```

### `RolloverItem` struct — add flag

```swift
var isIndividuallySet: Bool = false
```

### `RolloverEngine.applyChoices()` — handle new cases

- `.scheduleFor(date)`: call `PlannerEngine.fetchOrCreatePlan(for: date, context:)`, add task to that plan's `taskIDs` (if < 3 slots)
- `.addToTodayReplacing(taskID)`: remove the bumped task's ID from today's `taskIDs` (it remains a JDTask in the store — effectively back in backlog), then add rollover task to today's `taskIDs`

No new SwiftData models needed.

## Files to Touch

- `JustDoThree/Engines/RolloverEngine.swift` — new Choice cases, applyChoices logic
- `JustDoThree/Views/Rollover/RolloverSheet.swift` — bulk bar, Schedule button, today-full replace flow, lock indicator
- `JustDoThree/State/AppState.swift` — ensure rolloverItems array propagates `isIndividuallySet` updates correctly

## Out of Scope

- Scheduling stretch goals via rollover (primary tasks only)
- Recurring task special handling beyond what already exists
- Any changes to how rollover is triggered or detected
