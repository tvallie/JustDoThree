# CSV Export Design

**Date:** 2026-05-03
**Feature:** Export backlog tasks to CSV from Settings

---

## Goal

Let users export their task list to a CSV file, with control over which context (Personal, Work, or Both) and which optional columns (Date, Context, Recurring) are included. Accessible from a new "Data" section in Settings.

---

## Architecture

No new service or engine. All logic lives in a new `ExportTasksSheet` view:

1. Fetch all `JDTask` records via `@Query`
2. Filter by selected context
3. Build CSV string in-memory
4. Write to a temp file
5. Present via SwiftUI `ShareLink`

---

## Entry Point

Add a "Data" section to `SettingsView` with a single button: **"Export Tasks"**. Tapping presents `ExportTasksSheet` as a sheet.

---

## ExportTasksSheet UI

**Presentation:** `.presentationDetents([.medium])`

**Controls:**

- **Context picker** (segmented): Personal / Work / Both
  - Hidden (and fixed to Personal) if `appState.workModeEnabled` is `false`
- **Column toggles:**
  - Include Date (default: on)
  - Include Context (default: on) — only shown when context picker is set to Both
  - Include Recurring (default: on)
- **ShareLink button:** "Export CSV" — generates file on tap

---

## CSV Format

**Filename:** `jdt-tasks-YYYY-MM-DD.csv`

**Header row:** Only columns the user selected, e.g.:
```
Title,Date,Context,Recurring
```

**Data rows:** One per task. Values containing commas are double-quoted.

| Column | Format | Example |
|--------|--------|---------|
| Title | Plain string, quoted if needed | `"Fix the bug"` |
| Date | `YYYY-MM-DD` or empty | `2026-05-10` |
| Context | `Personal` or `Work` | `Work` |
| Recurring | Human-readable or empty | `Weekly (Monday)` |

**Recurring format mapping:**
- `.weekly(weekday:)` → `Weekly (Monday)` (using `Calendar.weekdaySymbols`)
- `.monthly(dayOfMonth:)` → `Monthly (15th)` (using ordinal formatter)

---

## Work Mode Behavior

- Work Mode disabled: no context picker; export always uses Personal tasks only
- Work Mode enabled: segmented picker visible; defaults to Both

---

## Data flow

```
SettingsView
  └─ sheet → ExportTasksSheet
               ├─ @Query all JDTasks
               ├─ filter by context selection
               ├─ build CSV string
               ├─ write to FileManager.default.temporaryDirectory
               └─ ShareLink → iOS share sheet
```

---

## Out of scope

- Rollover count column
- Import from CSV (separate feature)
- Completion history export
