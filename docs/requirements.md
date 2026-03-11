# Just Do Three — Current Requirements
**Version:** 1.1 (build 2)
**Last updated:** 2026-03-11
**Platform:** iPhone (iOS, SwiftUI + SwiftData)

---

## Overview

Just Do Three is a focused daily productivity app. Each day the user picks exactly three tasks to complete. Nothing more. The constraint is the feature.

---

## App Structure

Five-tab navigation (TabView):

| Tab | Icon | Description |
|-----|------|-------------|
| Today | checkmark.circle | Main daily view |
| Backlog | tray | Task library |
| History | clock | Completion log & analytics |
| Plan | calendar | 7-day planner (Premium) |
| Settings | gearshape | Preferences & account |

---

## Data Models

### JDTask
Lives in the backlog until scheduled or completed.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| title | String | Task name |
| createdDate | Date | When task was created |
| rolloverCount | Int | Times deferred to a new day without completion |
| sortOrder | Int | Manual position in backlog (lower = higher priority) |
| isCompleted | Bool | True once permanently marked done |
| completionDate | Date? | When task was permanently completed |
| recurringRuleData | Data? | JSON-encoded RecurringRule (Premium only, nil for standard tasks) |

### DailyPlan
Represents the user's chosen tasks for one calendar day.

| Field | Type | Description |
|-------|------|-------------|
| date | Date | Normalized to midnight local time |
| taskIDs | [UUID] | Ordered list of up to 3 primary task IDs |
| completedTaskIDs | [UUID] | Subset of taskIDs marked complete |
| stretchTaskIDs | [UUID] | Stretch goal task IDs (shown after primaries complete) |
| completedStretchIDs | [UUID] | Subset of stretchTaskIDs marked complete |

### CompletionLog
Immutable record created when a task is marked complete. Preserves task title as a snapshot.

| Field | Type | Description |
|-------|------|-------------|
| taskID | UUID | Reference to the original task |
| taskTitle | String | Title snapshot at time of completion |
| planDate | Date | Calendar day this completion is attributed to |
| completionDate | Date | Exact moment the checkmark was tapped |
| isStretchGoal | Bool | Whether this was a stretch goal completion |

### RecurringRule
Defines how a Premium task recurs. Stored as JSON inside `JDTask.recurringRuleData`.

| Field | Type | Description |
|-------|------|-------------|
| pattern | .weekly / .monthly | Recurrence frequency |
| weekday | Int? (1–7) | 1=Sunday…7=Saturday. Used for weekly rules. |
| dayOfMonth | Int? (1–31) | Day number. Used for monthly rules. |

**Display strings:** `"every Monday"` / `"3rd of every month"`

---

## Tiers

### Free
- Today tab (full access)
- Backlog tab (full access)
- History tab (completed task list only, grouped by day)
- Create and manage tasks
- Manual rollover sheet
- Notifications

### Premium (one-time in-app purchase)
Everything in Free, plus:
- **7-Day Planning** — Plan tab (schedule tasks up to 7 days ahead)
- **Analytics** — Full History dashboard (stats, perfect days, most avoided, recent completions)
- **Recurring Tasks** — Weekly or monthly repeating tasks
- **Auto-schedule Recurring** — Setting to auto-add recurring tasks to their scheduled day
- **Import Tasks** — Bulk import from .txt or .csv file
- **Stretch Goals** — Bonus tasks shown after all three primary tasks are complete

---

## Feature Specifications

### Today Tab

**Primary Tasks**
- Displays up to 3 tasks for the current calendar day
- Each task shows a circle/checkmark toggle
- Tapping a task completes it; tapping again un-completes it
- Completed tasks show with strikethrough
- Tasks can be removed from today (swipe or button)
- Task title can be edited inline via sheet

**Adding Tasks to Today**
- "Add task" button opens BacklogPickerSheet
- Shows available backlog tasks not already scheduled today
- Tapping a task adds it to today (if slots < 3)
- "Plan tomorrow" button opens BacklogPickerSheet for the next day (Premium only)

**Stretch Goals**
- Shown only after all 3 primary tasks are marked complete
- User can add stretch tasks from backlog
- Stretch completions are tracked separately in CompletionLog (`isStretchGoal: true`)
- Completing a stretch goal does not permanently complete the task (same as recurring behavior — actually only non-recurring stretch goals are permanently completed)

**Rollover (Day Transition)**
- Triggered on first app-active event each calendar day
- Finds all tasks from previous days that are incomplete and not already in today's plan
- Presents RolloverSheet modal (non-dismissible)
- Each item offers three choices:
  - **Done** — Marks complete for the previous day, creates CompletionLog
  - **Today** — Adds to today's plan (disabled if today already has 3 tasks), increments rolloverCount
  - **Backlog** — Returns to backlog, increments rolloverCount
- "Skip for now" dismisses without applying any changes
- Rollover is resolved once per day (stored in UserDefaults `jdt_rolloverResolved`)

### Backlog Tab

- Lists all incomplete, unscheduled tasks sorted by `sortOrder`
- Recurring tasks always appear (they never permanently complete)
- **Create task** — AddTaskSheet (title + optional recurrence for Premium)
- **Edit task** — Edit title and recurrence rule via AddTaskSheet
- **Delete task** — Swipe to delete with confirmation
- **Reorder** — Drag to reorder, updates `sortOrder`
- **Mark complete** — Permanently completes a non-recurring task

### History Tab

**Free users**
- Completed task list grouped by day (newest first)
- Each row shows task title + icon (checkmark for primary, star for stretch)
- PremiumGateView banner at bottom prompting upgrade

**Premium users (Analytics Dashboard)**
- **Stats row** (4 tiles): Total completed · Stretch goals · Avg/day · Active days
- **Perfect Days card**: Count of days where 3+ primary tasks were completed
- **Most Avoided card**: Top 5 tasks by rolloverCount (tasks never rolled over are excluded)
- **Recent Completions card**: Last 20 completions with date and stretch indicator

### Plan Tab (Premium only)

- Gate: Non-premium users see PremiumGateView
- Horizontal scrollable day-selector strip for today + next 6 days
- Selected day shows its task list (with completion state, read-only)
- Swipe to remove a task from a future day's plan
- "Add task" opens BacklogPickerSheet for the selected day
- Stretch goals shown if any exist for the selected day
- Auto-schedule recurring tasks runs on appear and when selected day changes (if setting enabled)

### Settings Tab

**Reminders**
- Morning reminder toggle (default off, default time 8:00 AM)
  - Body: "What are your three today?"
- Evening check-in toggle (default off, default time 7:00 PM)
  - Body: "Did you finish your three?"
- Time picker shown inline when toggle is on
- Requests notification authorization on first enable
- Both are daily repeating UNCalendarNotificationTrigger

**Premium**
- Non-premium: Shows upgrade CTA with one-time price and feature list + "Unlock" button
- Non-premium: "Restore purchase" button
- Premium: Shows "Just Do Three Premium — unlocked" confirmation in green

**Premium Features** (shown only to Premium users)
- **Auto-schedule recurring tasks** toggle
  - When on: recurring tasks are automatically added to their scheduled day's plan on app launch and day change
  - Stored in UserDefaults `jdt_autoScheduleRecurring`

**About**
- App version (from CFBundleShortVersionString)
- Privacy Policy (in-app NavigationLink)
- Terms of Use (in-app NavigationLink)
- Copyright footer with current year

---

## Task Operations Summary

| Operation | Free | Premium |
|-----------|------|---------|
| Create task | ✓ | ✓ |
| Edit task title | ✓ | ✓ |
| Delete task | ✓ | ✓ |
| Reorder backlog | ✓ | ✓ |
| Add to today (max 3) | ✓ | ✓ |
| Remove from today | ✓ | ✓ |
| Complete / uncomplete | ✓ | ✓ |
| Manual rollover sheet | ✓ | ✓ |
| Notifications | ✓ | ✓ |
| Stretch goals | ✓ | ✓ |
| Recurring tasks | — | ✓ |
| Import from .txt/.csv | — | ✓ |
| 7-day planning | — | ✓ |
| Analytics dashboard | — | ✓ |
| Auto-schedule recurring | — | ✓ |

---

## Recurring Task Behavior

- Setting a recurrence rule is Premium-only (locked row with "Premium" badge shown to free users)
- **Completion behavior:** Completing a recurring task logs a CompletionLog but does NOT set `isCompleted = true` or `completionDate`. The task resets immediately and stays in the backlog.
- **Un-complete:** No-op on the task itself (was never permanently completed); removes the CompletionLog entry for that day.
- **Auto-schedule:** When enabled, `PlannerEngine.autoScheduleRecurring()` adds matching recurring tasks to the plan on their scheduled day. Idempotent — safe to call multiple times. Respects the 3-task primary limit.
- **Backlog display:** Recurring tasks always appear in backlog regardless of completion history.

---

## Storage & Architecture

| Layer | Technology |
|-------|-----------|
| Persistent data | SwiftData (JDTask, DailyPlan, CompletionLog) |
| Settings/preferences | UserDefaults |
| App state / UI state | AppState (@Observable, @MainActor) |
| Premium state | PremiumManager (@Observable, StoreKit 2) |
| Notifications | NotificationManager (UNUserNotificationCenter) |
| CloudKit compatibility | UUID-based references (no SwiftData relationships) |

**UserDefaults keys:**
- `jdt_isPremium` — premium unlock state
- `jdt_rolloverResolved` — date rollover was last resolved (prevents repeat on same day)
- `jdt_autoScheduleRecurring` — auto-schedule toggle state
- `jdt_morningEnabled` / `jdt_eveningEnabled` — notification toggles
- `jdt_morningHour` / `jdt_morningMinute` — morning time (default 8:00)
- `jdt_eveningHour` / `jdt_eveningMinute` — evening time (default 19:00)

---

## Business Rules

1. A DailyPlan holds a maximum of **3 primary tasks**.
2. A task cannot be added to today's plan if it is permanently completed (unless it is recurring).
3. A recurring task is never permanently completed — each completion logs only a CompletionLog.
4. Rollover is processed once per calendar day. Dismissing it ("Skip for now") also marks it resolved for that day.
5. Rolling a task over (either to Today or Backlog via rollover) increments `rolloverCount`.
6. `CompletionLog` stores a title snapshot — history remains accurate even if a task is renamed.
7. Deleting a CompletionLog entry (via uncomplete) is the only way to remove a completion record.
8. The Plan tab shows today + next 6 days (7 days total).
9. BacklogPickerSheet excludes tasks already scheduled on any day for non-recurring tasks; for recurring tasks it only excludes those already scheduled on the selected day.
