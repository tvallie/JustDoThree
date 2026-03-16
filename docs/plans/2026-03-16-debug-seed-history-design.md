# Debug: Seed History Data

**Date:** 2026-03-16
**Status:** Approved

## Goal

Add a "Seed History Data" button to the existing `#if DEBUG` section in `SettingsView` that populates all four HistoryView analytics cards with realistic test data in one tap.

## Cards Targeted

| Card | Data Required |
|------|--------------|
| Stats (completed, avg/day, active days, stretch goals) | `CompletionLog` entries |
| Perfect Days | Days with ≥ 3 primary `CompletionLog` entries |
| Most Avoided | `JDTask` entries with `rolloverCount > 0` |
| Recent Completions | `CompletionLog` entries |

## Design

### `AppState` — `seedHistoryData(context:)` (`#if DEBUG`)

**Idempotency:** If `CompletionLog` count ≥ 10, return early. Safe to tap multiple times.

**JDTasks seeded (5):**

| Title | rolloverCount |
|-------|--------------|
| Clean up dog poop in back yard | 4 |
| Mow lawn | 3 |
| Buy birthday gift for pet elephant | 2 |
| Plant a tree | 1 |
| Tell someone they are awesome | 0 |

**DailyPlans + CompletionLogs — 14 past days:**

- Most days: 3 primary completions (perfect days) using a rotating mix of the 5 tasks
- 2 days: only 2 completions (makes avg/day realistically ~2.7)
- 1 day: includes a stretch goal completion
- Each `DailyPlan` has `taskIDs` and `completedTaskIDs` set consistently with its `CompletionLog` entries

### `SettingsView` — Debug Section

Add a second button below "Preview Rollover Sheet":

```swift
Button("Seed History Data") {
    appState.seedHistoryData(context: modelContext)
}
```

## Files Changed

- `JustDoThree/State/AppState.swift` — add `seedHistoryData(context:)` in `#if DEBUG` block
- `JustDoThree/Views/Settings/SettingsView.swift` — add button to Debug section
