# Recurring Tasks Design

**Date:** 2026-03-09
**Feature:** Weekly & monthly recurring tasks in backlog
**Status:** Approved

## Overview

Allow premium users to mark backlog tasks as recurring (weekly on a specific weekday, or monthly on a specific day of the month). Recurring tasks are never permanently completed — each completion is logged for history but the task immediately resets and remains visible in the backlog.

## Decisions

- **Reset behavior:** Immediate. Completing a recurring task logs the completion but does not set `isCompleted = true`. The task stays in the backlog.
- **Premium gating:** Yes. Setting a recurring rule is premium-only. Free users see a locked row with a "Premium" badge.

## Data Layer

No model changes required. `RecurringRule` and `JDTask.recurringRuleData` are already in place.

Add `displayString: String` computed property to `RecurringRule`:
- Weekly → `"every Monday"` (using weekday name)
- Monthly → `"3rd of every month"` (using ordinal day number)

## Completion Behavior (`PlannerEngine`)

In `complete()` and `completeStretch()`, add a recurring task check:
- Add task to `plan.completedTaskIDs` ✓ (checkmark shows in Today view)
- Insert `CompletionLog` ✓ (counts toward all history metrics)
- Skip `task.isCompleted = true` and `task.completionDate` (task stays active in backlog)

`uncomplete()` requires no changes — `isCompleted` was never set so the existing resets are no-ops.

History metrics are unaffected: all stats (`StatsCardRow`, `PerfectDaysCard`, `RecentCompletionsCard`) read from `CompletionLog`, not `task.isCompleted`. "Most avoided" reads `task.rolloverCount`, which still increments normally when a recurring task is deferred.

## `AddTaskSheet` UI

Add a "Recurrence" section to the Form below the title field.

**Premium users:**
- `Picker` for frequency: None / Weekly / Monthly
- When Weekly: second `Picker` for day of week (Sunday–Saturday)
- When Monthly: second `Picker` for day of month (1–31)
- Sheet detent expands to `.medium` when recurrence is not `.none`

**Free users:**
- Locked row matching the existing "Import tasks" premium badge pattern (same icon, "Premium" capsule badge)

## `BacklogRow` UI

Add a recurring label to the existing subtitle `HStack` (alongside created date and rollover count).

- Icon: `repeat` SF Symbol
- Text: `"recurring · every Monday"` or `"recurring · 3rd of every month"` (uses `RecurringRule.displayString`)
- Color: teal (matches premium badge used elsewhere)
- Only shown when `task.recurringRule != nil`
