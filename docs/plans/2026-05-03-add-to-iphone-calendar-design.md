# Add to iPhone Calendar — Design Doc

**Date:** 2026-05-03
**Status:** Approved
**Scope:** Let users add a JDT task to the iOS Calendar (as an Event) or Reminders (as a Reminder), and — when the chosen date falls within the 7-day Plan look-forward — also add it to the in-app Plan.

---

## Goal

Give users a one-tap path from a JDT task to an iOS Calendar event or Reminder, without taking on sync complexity.

## Triggers

- **AddTaskSheet** (edit mode only) — a row labeled **"Add to iPhone Calendar"** near the existing date field. Hidden when creating a new task.
- **Today's TaskCard `···` menu** — a menu item **"Add to iPhone Calendar"** between Edit and Replace.

## Flow

1. Tap "Add to iPhone Calendar" → presents `AddToCalendarSheet`.
2. Sheet contains:
   - **Type** segmented control: `Event | Reminder`
   - **Date** picker — prefilled from `task.taskDate` if set, else today.
   - **All-day toggle** (Event only) — defaults ON if `taskDate` was set, OFF otherwise.
   - **Time** picker (Event only) — hidden when all-day. Default duration 30 min.
   - **Calendar / List** picker — defaults to system default for the chosen type.
   - Primary **Add** button.
3. On Add:
   - Request EventKit permission (`requestFullAccessToEvents` or `requestFullAccessToReminders`) if not yet granted.
   - Create the `EKEvent` or `EKReminder` and save via `EKEventStore`.
   - If the chosen date is within the next 7 days AND the active-context plan for that date has a free primary slot, call `PlannerEngine.fetchOrCreatePlan(for:isWork:context:)` and `PlannerEngine.addToToday`. The active context is `appState.activeContext`.
   - Show a confirmation alert: **"Added to [Calendar/Reminders]."** with two buttons:
     - **Open** — deep-link to the iOS app:
       - Event: `x-apple-calevent://` with the event identifier.
       - Reminder: opens the Reminders app (no per-item URL).
     - **Done** — dismiss.
4. If permission is denied, alert the user with a "Settings" button that opens the app's settings via `UIApplication.openSettingsURLString`.

## Plumbing

- **New file** `JustDoThree/Services/CalendarService.swift` — async wrappers around `EKEventStore` for: permission request, event creation, reminder creation, default-calendar lookup, default-list lookup. No UI imports.
- **New file** `JustDoThree/Views/Shared/AddToCalendarSheet.swift` — the sheet UI.
- **Info.plist additions** (also in `project.yml`):
  - `NSCalendarsFullAccessUsageDescription` — "Just Do Three needs calendar access to add tasks as calendar events."
  - `NSRemindersFullAccessUsageDescription` — "Just Do Three needs reminders access to add tasks as reminders."
- **No model changes.** No EventKit ID stored on `JDTask` (fire-and-forget).

## Out of Scope (YAGNI)

- No two-way sync. Renaming or deleting a JDT task does not touch the iOS event/reminder.
- No "in calendar" badge on tasks.
- No alarm/reminder offsets — users tweak in Calendar/Reminders app.
- No recurring rule mapping — JDT recurrence ≠ EventKit recurrence semantics.
- No multi-task batch export.

## Edge Cases

- **Permission denied** — Alert with Settings deep-link. No partial creation.
- **Date beyond 7 days** — Skip in-app Plan add silently. Only the device calendar/reminder is created.
- **Plan slot full** — Skip in-app Plan add silently. The device entry still gets created.
- **Title empty** — AddTaskSheet already blocks save with empty title, so by definition the task has a title before reaching this flow.
- **Permission grant on iOS 17+ vs earlier** — Use `requestFullAccessToEvents` / `requestFullAccessToReminders` (iOS 17+); deployment target is iOS 17 per Info.plist, so no fallback path needed.

## Open Questions

None — design approved.
