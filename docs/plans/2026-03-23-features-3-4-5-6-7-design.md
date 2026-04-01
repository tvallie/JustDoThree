# JustDoThree: Features 3, 4, 5, 6, 7 — Design Document
**Status: IN PROGRESS — brainstorming not yet complete**
**Date started: 2026-03-23**

---

## Features in Scope

- **Feature 3**: Home/Work context toggle
- **Feature 4**: Due dates per task
- **Feature 5**: Settings toggles for both features above
- **Feature 6**: Haptics + confetti when you finish your tasks for the day
- **Feature 7**: Finish reward (haptics/confetti/share) works for 1 or 2 tasks too, not just 3. Copy fix: "You finished your three." → dynamic based on count.

---

## Decisions Made

### Home/Work Feature

- **One shared backlog** — tasks tagged Home or Work, filterable when browsing and when adding
- **No "Both" / "Untagged"** — every task must be either Home or Work. Hard rule, no in-between.
- **Settings toggle** controls whether Work mode is on at all. When OFF, app works exactly as it does today.
- **Today tab**: segmented/toggle switcher — you see Home OR Work, never both at once (intentional — avoids overwhelm)
- **Backlog tab**: shows all tasks by default, can be filtered to Home or Work
- **Plan tab**: separate toggle — completely separate Home/Work views
- **History tab**: filter for Home, Work, or Both
- **Creating tasks from Today**: inherits the current active context (viewing Work → creates Work task)
- **Creating tasks from Backlog**: you explicitly choose Home or Work regardless of current filter
- **Migration when first enabling**: user is prompted to assign every existing task to Home or Work. No skipping. No unassigned state.
- **Turning Work mode OFF**: tasks silently retain their tags in case re-enabled later

### Data Model Architecture

**Option A selected**: Extend `DailyPlan` with Work-specific arrays.
- Existing `taskIDs`, `completedTaskIDs`, `stretchTaskIDs`, `completedStretchIDs` stay as-is → become the **Home** slots
- Add to `DailyPlan`: `workTaskIDs`, `completedWorkTaskIDs`, `stretchWorkTaskIDs`, `completedStretchWorkIDs`
- Add to `JDTask`: `context: TaskContext` enum (`.home` / `.work`)
- When Work mode is OFF: all existing code paths untouched

### Due Dates

- Settings toggle: "Due dates" (off by default)
- When ON: `AddTaskSheet` shows an optional due date field
- Due date shown in backlog **underneath the task title**, replacing the "created" date indicator when present
- Not required — tasks can still have no due date
- When due date setting is ON, a **sort preference** setting appears below the toggle:
  - **Manual order** (default — drag to reorder, same as now)
  - **By due date** (soonest first; undated tasks fall to bottom)
- When OFF: no due date field shown anywhere, backlog sort same as now

### Settings

Two new toggles in `SettingsView`:

1. **"Work & Home contexts"** toggle (off by default)
   - Enabling triggers migration flow for existing tasks
   - Disabling hides all context UI silently

2. **"Due dates"** toggle (off by default)
   - When ON: reveals "Backlog sort order" sub-setting (Manual / By due date)

Both stored as `@AppStorage` bools, same pattern as existing settings.

### Haptics + Confetti (Features 6 & 7)

- Triggers when `allPrimaryDone` becomes `true` (already fires on 1, 2, or 3 tasks)
- **Haptic**: `UINotificationFeedbackGenerator` success buzz on completion of last task
- **Confetti**: subtle shower contained within/around the celebration banner area
- **Copy fix**: "You finished your three." → dynamic:
  - 1 task: "You finished your one."
  - 2 tasks: "You finished your two."
  - 3 tasks: "You finished your three."

---

## Design Sections — Approval Status

| Section | Status |
|---------|--------|
| Settings layout | ✅ Approved |
| Home/Work tab behavior (Today, Backlog, Plan, History) | 🔲 Not yet presented |
| Migration flow | 🔲 Not yet presented |
| Due dates UI detail | 🔲 Not yet presented |
| Haptics + confetti detail | 🔲 Not yet presented |

---

## Next Steps (pick up here next session)

1. Present design for **Home/Work tab behavior** — Today switcher UI, Backlog filter, Plan toggle, History filter
2. Present **migration flow** design
3. Present **due dates** UI detail
4. Present **haptics + confetti** detail
5. Get full approval, then write implementation plan
